import SwiftUI

struct UserGroup: Identifiable {
    var id: String { username }
    var username: String
    var processes: [MachProcess]
    
    var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }
    var memory: UInt64 { processes.reduce(0) { $0 + $1.memory } }
    var diskRate: Double { processes.reduce(0) { $0 + $1.diskReadRate + $1.diskWriteRate } }
    var netRate: Double { processes.reduce(0) { $0 + $1.networkRxRate + $1.networkTxRate } }
}

struct UsersView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var expandedUsers: Set<String> = []
    @State private var selectedPID: pid_t?
    @State private var selectedUser: String?
    @State private var confirmKillPID: pid_t?
    @State private var confirmKillName: String = ""

    private var tc: Color { cs == .dark ? .white : .black }
    private var bg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F4F4F4") }
    private var accent: Color { Color(hex: "0078D7") }

    private var userGroups: [UserGroup] {
        let grouped = Dictionary(grouping: monitor.processes) { $0.username }
        return grouped.map { (key, value) in
            UserGroup(username: key, processes: value.sorted { $0.cpu > $1.cpu })
        }.sorted { $0.cpu > $1.cpu }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Users").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(userGroups.count) active users").font(.system(size: 11)).foregroundColor(.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            // Table headers and List inside horizontal ScrollView for small screen responsiveness
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("User").font(.system(size: 11, weight: .medium)).foregroundColor(.gray).frame(minWidth: 220, alignment: .leading).padding(.leading, 24)
                        Text("CPU").font(.system(size: 11, weight: .medium)).foregroundColor(.gray).frame(width: 70, alignment: .trailing)
                        Text("Memory").font(.system(size: 11, weight: .medium)).foregroundColor(.gray).frame(width: 80, alignment: .trailing)
                        Text("Disk").font(.system(size: 11, weight: .medium)).foregroundColor(.gray).frame(width: 80, alignment: .trailing)
                        Text("Network").font(.system(size: 11, weight: .medium)).foregroundColor(.gray).frame(width: 80, alignment: .trailing)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color.gray.opacity(0.06))
                    .frame(width: 554)

                    Divider()

                    // Flat list that renders users and conditionally inserts child rows
                    List {
                        ForEach(userGroups) { grp in
                            // Render User Row
                            HStack(spacing: 0) {
                                Button(action: {
                                    if expandedUsers.contains(grp.username) {
                                        expandedUsers.remove(grp.username)
                                    } else {
                                        expandedUsers.insert(grp.username)
                                    }
                                }) {
                                    Image(systemName: expandedUsers.contains(grp.username) ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.gray)
                                        .frame(width: 16)
                                }
                                .buttonStyle(.plain)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "person.circle.fill").foregroundColor(.blue).font(.system(size: 12))
                                    Text("\(grp.username) (\(grp.processes.count))").font(.system(size: 12, weight: .semibold))
                                }
                                .frame(minWidth: 204, alignment: .leading)
                                
                                Text(String(format: "%.1f%%", grp.cpu))
                                    .font(.system(size: 12))
                                    .frame(width: 70, alignment: .trailing)
                                    .background(heatmapColor(val: grp.cpu, maxVal: 100))
                                
                                Text(ByteCountFormatter.string(fromByteCount: Int64(grp.memory), countStyle: .memory))
                                    .font(.system(size: 12))
                                    .frame(width: 80, alignment: .trailing)
                                    .background(heatmapColor(val: Double(grp.memory), maxVal: Double(monitor.memory.total)))
                                
                                Text(bytesPerSec(grp.diskRate))
                                    .font(.system(size: 12))
                                    .frame(width: 80, alignment: .trailing)
                                    .background(heatmapColor(val: grp.diskRate, maxVal: 50 * 1024 * 1024))
                                
                                Text(bytesPerSec(grp.netRate))
                                    .font(.system(size: 12))
                                    .frame(width: 80, alignment: .trailing)
                                    .background(heatmapColor(val: grp.netRate, maxVal: 10 * 1024 * 1024))
                                
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedUser = grp.username
                                selectedPID = nil
                            }
                            .background(selectedUser == grp.username && selectedPID == nil ? accent.opacity(0.15) : Color.clear)
                            
                            // Render User Processes if expanded
                            if expandedUsers.contains(grp.username) {
                                ForEach(grp.processes) { proc in
                                    HStack(spacing: 0) {
                                        Spacer().frame(width: 24)
                                        HStack(spacing: 6) {
                                            Image(systemName: "doc.text").font(.system(size: 10)).foregroundColor(.gray)
                                            Text(proc.name).font(.system(size: 11))
                                            Text("(\(proc.pid))").font(.system(size: 9)).foregroundColor(.gray).monospacedDigit()
                                        }
                                        .frame(minWidth: 196, alignment: .leading)
                                        
                                        Text(String(format: "%.1f%%", proc.cpu))
                                            .font(.system(size: 11))
                                            .frame(width: 70, alignment: .trailing)
                                            .background(heatmapColor(val: proc.cpu, maxVal: 100))
                                        
                                        Text(ByteCountFormatter.string(fromByteCount: Int64(proc.memory), countStyle: .memory))
                                            .font(.system(size: 11))
                                            .frame(width: 80, alignment: .trailing)
                                            .background(heatmapColor(val: Double(proc.memory), maxVal: Double(monitor.memory.total)))
                                        
                                        Text(bytesPerSec(proc.diskReadRate + proc.diskWriteRate))
                                            .font(.system(size: 11))
                                            .frame(width: 80, alignment: .trailing)
                                            .background(heatmapColor(val: proc.diskReadRate + proc.diskWriteRate, maxVal: 50 * 1024 * 1024))
                                        
                                        Text(bytesPerSec(proc.networkRxRate + proc.networkTxRate))
                                            .font(.system(size: 11))
                                            .frame(width: 80, alignment: .trailing)
                                            .background(heatmapColor(val: proc.networkRxRate + proc.networkTxRate, maxVal: 10 * 1024 * 1024))
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPID = proc.pid
                                        selectedUser = nil
                                    }
                                    .background(selectedPID == proc.pid ? accent.opacity(0.15) : Color.clear)
                                    .contextMenu {
                                        Button("End Task") { confirmKillPID = proc.pid; confirmKillName = proc.name }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: 554)
                }
                .frame(width: 554)
            }

            // Footer
            HStack {
                Spacer()
                Button("End Task") {
                    if let pid = selectedPID, let proc = monitor.processes.first(where: { $0.pid == pid }) {
                        confirmKillPID = pid
                        confirmKillName = proc.name
                    }
                }
                .font(.system(size: 12))
                .disabled(selectedPID == nil)
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(bg)
        .alert("End Task", isPresented: Binding(get: { confirmKillPID != nil }, set: { if !$0 { confirmKillPID = nil } })) {
            Button("End task", role: .destructive) {
                if let p = confirmKillPID { kill(p, SIGKILL) }
                confirmKillPID = nil
                if selectedPID == confirmKillPID { selectedPID = nil }
            }
            Button("Cancel", role: .cancel) { confirmKillPID = nil }
        } message: {
            Text("Do you want to end \"\(confirmKillName)\"? Ending this process will close all associated windows and force the application to quit.")
        }
    }

    private func heatmapColor(val: Double, maxVal: Double) -> Color {
        guard val > 0 else { return Color.clear }
        let ratio = min(val / maxVal, 1.0)
        return Color(hex: "FF7000").opacity(0.05 + ratio * 0.4)
    }
}
