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
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color.white }
    private var accent: Color { Color(hex: "0078D7") }

    private var userGroups: [UserGroup] {
        let grouped = Dictionary(grouping: monitor.processes) { $0.username }
        return grouped.map { (key, value) in
            UserGroup(username: key, processes: value.sorted { $0.cpu > $1.cpu })
        }.sorted { $0.cpu > $1.cpu }
    }

    var body: some View {
        VStack(spacing: 0) {
            
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill").foregroundColor(accent).font(.system(size: 13))
                    Text("Active Users (\(userGroups.count))").font(.system(size: 11, weight: .bold))
                }

                Spacer()

                Button("End task") {
                    if let pid = selectedPID, let proc = monitor.processes.first(where: { $0.pid == pid }) {
                        confirmKillPID = pid
                        confirmKillName = proc.name
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(selectedPID != nil ? (cs == .dark ? Color(hex: "C42B1C") : Color(hex: "FDF3F2")) : (cs == .dark ? Color(hex: "3A3A3A") : Color(hex: "FFFFFF")))
                .foregroundColor(selectedPID != nil ? (cs == .dark ? .white : Color(hex: "C42B1C")) : .gray)
                .border(selectedPID != nil ? (cs == .dark ? Color.clear : Color(hex: "F8C0BC")) : Color.gray.opacity(0.3), width: 0.5)
                .cornerRadius(3)
                .disabled(selectedPID == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cs == .dark ? Color(hex: "252525") : Color(hex: "F9F9F9"))

            
            HStack(spacing: 0) {
                Text("User").font(.system(size: 11, weight: .semibold)).foregroundColor(tc).frame(minWidth: 220, alignment: .leading).padding(.leading, 24)
                Text("CPU").font(.system(size: 11, weight: .semibold)).foregroundColor(tc).frame(width: 80, alignment: .trailing)
                Text("Memory").font(.system(size: 11, weight: .semibold)).foregroundColor(tc).frame(width: 85, alignment: .trailing)
                Text("Disk").font(.system(size: 11, weight: .semibold)).foregroundColor(tc).frame(width: 80, alignment: .trailing)
                Text("Network").font(.system(size: 11, weight: .semibold)).foregroundColor(tc).frame(width: 80, alignment: .trailing)
                Spacer()
            }
            .frame(height: 32)
            .background(cs == .dark ? Color(hex: "232323") : Color(hex: "EDEDED"))

            Divider()

            
            List {
                ForEach(userGroups) { grp in
                    
                    HStack(spacing: 0) {
                        Button(action: {
                            if expandedUsers.contains(grp.username) {
                                expandedUsers.remove(grp.username)
                            } else {
                                expandedUsers.insert(grp.username)
                            }
                        }) {
                            Image(systemName: expandedUsers.contains(grp.username) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                                .frame(width: 16)
                        }
                        .buttonStyle(.plain)
                        .help(expandedUsers.contains(grp.username) ? "Collapse" : "Expand")
                        
                        HStack(spacing: 6) {
                            Image(systemName: "person.circle.fill").foregroundColor(accent).font(.system(size: 12))
                            Text("\(grp.username) (\(grp.processes.count))").font(.system(size: 12, weight: .semibold))
                        }
                        .frame(minWidth: 204, alignment: .leading)
                        
                        Text(String(format: "%.1f%%", grp.cpu))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                            .padding(.trailing, 4)
                            .frame(maxHeight: .infinity)
                            .background(heatmapBg(val: grp.cpu, maxVal: 100))
                        
                        Text(formatWinMem(grp.memory))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .frame(width: 85, alignment: .trailing)
                            .padding(.trailing, 4)
                            .frame(maxHeight: .infinity)
                            .background(heatmapBg(val: Double(grp.memory), maxVal: Double(monitor.memory.total)))
                        
                        Text(bytesPerSec(grp.diskRate))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                            .padding(.trailing, 4)
                            .frame(maxHeight: .infinity)
                            .background(heatmapBg(val: grp.diskRate, maxVal: 50 * 1024 * 1024))
                        
                        Text(bytesPerSec(grp.netRate))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                            .padding(.trailing, 4)
                            .frame(maxHeight: .infinity)
                            .background(heatmapBg(val: grp.netRate, maxVal: 10 * 1024 * 1024))
                        
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .frame(height: 28)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedUser = grp.username
                        selectedPID = nil
                    }
                    .background(selectedUser == grp.username && selectedPID == nil ? accent.opacity(0.18) : Color.clear)
                    .overlay(alignment: .leading) {
                        if selectedUser == grp.username && selectedPID == nil {
                            Rectangle().fill(accent).frame(width: 3.5)
                        }
                    }
                    
                    
                    if expandedUsers.contains(grp.username) {
                        ForEach(grp.processes) { proc in
                            HStack(spacing: 0) {
                                Spacer().frame(width: 24)
                                HStack(spacing: 6) {
                                    AppIconView(processName: proc.name)
                                        .frame(width: 14, height: 14)
                                    Text(proc.name).font(.system(size: 11))
                                    Text("(\(proc.pid))").font(.system(size: 11)).foregroundColor(.gray).monospacedDigit()
                                }
                                .frame(minWidth: 196, alignment: .leading)
                                
                                Text(String(format: "%.1f%%", proc.cpu))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)
                                    .padding(.trailing, 4)
                                    .frame(maxHeight: .infinity)
                                    .background(heatmapBg(val: proc.cpu, maxVal: 100))
                                
                                Text(formatWinMem(proc.memory))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .frame(width: 85, alignment: .trailing)
                                    .padding(.trailing, 4)
                                    .frame(maxHeight: .infinity)
                                    .background(heatmapBg(val: Double(proc.memory), maxVal: Double(monitor.memory.total)))
                                
                                Text(bytesPerSec(proc.diskReadRate + proc.diskWriteRate))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)
                                    .padding(.trailing, 4)
                                    .frame(maxHeight: .infinity)
                                    .background(heatmapBg(val: proc.diskReadRate + proc.diskWriteRate, maxVal: 50 * 1024 * 1024))
                                
                                Text(bytesPerSec(proc.networkRxRate + proc.networkTxRate))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .frame(width: 80, alignment: .trailing)
                                    .padding(.trailing, 4)
                                    .frame(maxHeight: .infinity)
                                    .background(heatmapBg(val: proc.networkRxRate + proc.networkTxRate, maxVal: 10 * 1024 * 1024))
                                
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .frame(height: 26)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPID = proc.pid
                                selectedUser = nil
                            }
                            .background(selectedPID == proc.pid ? accent.opacity(0.18) : Color.clear)
                            .overlay(alignment: .leading) {
                                if selectedPID == proc.pid {
                                    Rectangle().fill(accent).frame(width: 3.5)
                                }
                            }
                            .contextMenu {
                                Button("End Task") { confirmKillPID = proc.pid; confirmKillName = proc.name }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(cardBg)
        .alert("End Task", isPresented: Binding(get: { confirmKillPID != nil }, set: { if !$0 { confirmKillPID = nil } })) {
            Button("End task", role: .destructive) {
                if let p = confirmKillPID {
                    if let err = monitor.endProcess(pid: p, name: confirmKillName) {
                        monitor.actionError = err
                    }
                    if selectedPID == p { selectedPID = nil }
                }
                confirmKillPID = nil
                confirmKillName = ""
            }
            Button("Cancel", role: .cancel) { confirmKillPID = nil }
        } message: {
            Text("Do you want to end \"\(confirmKillName)\"? Ending this process will close all associated windows and force the application to quit.")
        }
    }

    private func heatmapBg(val: Double, maxVal: Double) -> Color {
        guard val > 0.05 else { return Color.clear }
        let ratio = min(val / maxVal, 1.0)
        if cs == .dark {
            return Color(hex: "D46B08").opacity(0.12 + ratio * 0.45)
        } else {
            return Color(hex: "FFE58F").opacity(0.25 + ratio * 0.55)
        }
    }
}
