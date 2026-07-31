import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Binding var isPresented: Bool
    @Binding var selectedTab: AppTab
    @Binding var selectedPID: pid_t?
    @State private var query = ""
    @Environment(\.colorScheme) var cs

    private var tc: Color { cs == .dark ? .white : .black }
    private var cardBg: Color { cs == .dark ? Color(hex: "252525") : Color.white }

    private var filteredProcesses: [MachProcess] {
        guard !query.isEmpty else { return Array(monitor.processes.prefix(10)) }
        return monitor.processes.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            "\($0.pid)".contains(query) ||
            $0.tabName.localizedCaseInsensitiveContains(query)
        }.prefix(12).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                TextField("Type a command, process name, or PID...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("ESC to exit")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                    .foregroundColor(.gray)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    if query.isEmpty {
                        Group {
                            actionRow(title: "Go to Processes View", icon: "square.grid.2x2") { selectedTab = .processes; isPresented = false }
                            actionRow(title: "Go to Performance Dashboard", icon: "chart.bar.fill") { selectedTab = .performance; isPresented = false }
                            actionRow(title: "Go to Startup Apps", icon: "bolt.fill") { selectedTab = .startup; isPresented = false }
                            actionRow(title: "Go to Users & Sessions", icon: "person.2.fill") { selectedTab = .users; isPresented = false }
                            actionRow(title: "Go to Services Manager", icon: "gearshape.2.fill") { selectedTab = .services; isPresented = false }
                            actionRow(title: "Go to Insights & Diagnostics", icon: "sparkles") { selectedTab = .insights; isPresented = false }
                        }
                        Divider().padding(.vertical, 4)
                    }

                    ForEach(filteredProcesses) { proc in
                        HStack(spacing: 8) {
                            AppIconView(processName: proc.name)
                                .frame(width: 16, height: 16)
                            Text(proc.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(tc)
                            if !proc.tabName.isEmpty {
                                Text("[\(proc.tabName)]")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text("PID \(proc.pid)")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundColor(.gray)
                            Text(String(format: "%.1f%% CPU", proc.cpu))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "0078D7"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPID = proc.pid
                            selectedTab = .processes
                            isPresented = false
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 520)
        .background(cardBg)
        .cornerRadius(10)
        .shadow(radius: 20)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .onExitCommand {
            isPresented = false
        }
    }

    private func actionRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "0078D7"))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(tc)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
