import SwiftUI
import Darwin

struct ProcessNode: Identifiable {
    var id: pid_t { process.pid }
    var process: MachProcess
    var children: [MachProcess]
    
    var totalCPU: Double
    var totalMemory: UInt64
    var totalDisk: Double
    var totalNetwork: Double
}

struct ProcessView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @Binding var searchText: String
    
    @State private var sortColumn = SortColumn.cpu
    @State private var sortAsc = false
    @Binding var selectedPID: pid_t?
    @State private var expandedPIDs: Set<pid_t> = []
    @State private var confirmKillPID: pid_t?
    @State private var confirmKillName: String = ""

    enum SortColumn { case name, cpu, memory, disk, network, pid }

    private var tc: Color { cs == .dark ? .white : .black }
    private var bg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F4F4F4") }
    private var accent: Color { Color(hex: "0078D7") }

    private var groupedNodes: [ProcessNode] {
        let list = monitor.processes
        let filtered = searchText.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        
        let pidMap = Dictionary(uniqueKeysWithValues: list.map { ($0.pid, $0) })
        
        var childrenMap: [pid_t: [MachProcess]] = [:]
        for proc in list {
            if proc.ppid > 1 && pidMap[proc.ppid] != nil {
                childrenMap[proc.ppid, default: []].append(proc)
            }
        }
        
        var topLevelNodes: [ProcessNode] = []
        for proc in filtered {
            let isChild = proc.ppid > 1 && pidMap[proc.ppid] != nil
            if !isChild {
                let children = childrenMap[proc.pid] ?? []
                
                let totalCPU = proc.cpu + children.reduce(0) { $0 + $1.cpu }
                let totalMemory = proc.memory + children.reduce(0) { $0 + $1.memory }
                let totalDisk = (proc.diskReadRate + proc.diskWriteRate) + children.reduce(0) { $0 + ($1.diskReadRate + $1.diskWriteRate) }
                let totalNetwork = (proc.networkRxRate + proc.networkTxRate) + children.reduce(0) { $0 + ($1.networkRxRate + $1.networkTxRate) }
                
                topLevelNodes.append(ProcessNode(
                    process: proc,
                    children: children.sorted { $0.cpu > $1.cpu },
                    totalCPU: totalCPU,
                    totalMemory: totalMemory,
                    totalDisk: totalDisk,
                    totalNetwork: totalNetwork
                ))
            }
        }
        
        return topLevelNodes.sorted { (node1, node2) -> Bool in
            switch sortColumn {
            case .name:
                return sortAsc ? node1.process.name.lowercased() < node2.process.name.lowercased() : node1.process.name.lowercased() > node2.process.name.lowercased()
            case .cpu:
                return sortAsc ? node1.totalCPU < node2.totalCPU : node1.totalCPU > node2.totalCPU
            case .memory:
                return sortAsc ? node1.totalMemory < node2.totalMemory : node1.totalMemory > node2.totalMemory
            case .disk:
                return sortAsc ? node1.totalDisk < node2.totalDisk : node1.totalDisk > node2.totalDisk
            case .network:
                return sortAsc ? node1.totalNetwork < node2.totalNetwork : node1.totalNetwork > node2.totalNetwork
            case .pid:
                return sortAsc ? node1.process.pid < node2.process.pid : node1.process.pid > node2.process.pid
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action & Search bar at the top of Processes tab
            HStack(spacing: 12) {
                // Search box
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    TextField("Filter processes by name", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(cs == .dark ? .white : .black)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: 220, height: 22)
                .background(cs == .dark ? Color(hex: "333333") : Color.white)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                )
                
                Spacer()
                
                Button("End task") {
                    if let p = selectedPID {
                        kill(p, SIGKILL)
                        selectedPID = nil
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(selectedPID != nil ? (cs == .dark ? Color(hex: "C42B1C") : Color(hex: "FDF3F2")) : (cs == .dark ? Color(hex: "3A3A3A") : Color(hex: "FFFFFF")))
                .foregroundColor(selectedPID != nil ? (cs == .dark ? .white : Color(hex: "C42B1C")) : .gray)
                .border(selectedPID != nil ? (cs == .dark ? Color.clear : Color(hex: "F8C0BC")) : Color.gray.opacity(0.3), width: 0.5)
                .disabled(selectedPID == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cs == .dark ? Color(hex: "252525") : Color(hex: "F9F9F9"))
            
            // Shaded Column Headers displaying live utilization totals
            HStack(spacing: 0) {
                Button(action: { toggleSort(.name) }) {
                    HStack(spacing: 2) {
                        Text("Name").font(.system(size: 11, weight: .semibold))
                        if sortColumn == .name {
                            Image(systemName: sortAsc ? "chevron.up" : "chevron.down").font(.system(size: 8))
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(tc)
                .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                
                // CPU Header
                let cpuPct = monitor.cpuUsage.total
                HeaderCell(title: "CPU", val: String(format: "%d%%", Int(cpuPct)), ratio: cpuPct / 100.0, tc: tc, accent: accent)
                    .frame(width: 75)
                    .onTapGesture { toggleSort(.cpu) }
                
                // Memory Header
                let memUsed = Double(monitor.memory.used)
                let memTotal = Double(max(monitor.memory.total, 1))
                HeaderCell(title: "Memory", val: String(format: "%d%%", Int(memUsed / memTotal * 100.0)), ratio: memUsed / memTotal, tc: tc, accent: accent)
                    .frame(width: 85)
                    .onTapGesture { toggleSort(.memory) }
                
                // Disk Header
                let totalDiskRate = monitor.disks.reduce(0.0) { $0 + $1.readRate + $1.writeRate }
                HeaderCell(title: "Disk", val: bytesPerSec(totalDiskRate), ratio: min(totalDiskRate / (20 * 1024 * 1024), 1.0), tc: tc, accent: accent)
                    .frame(width: 80)
                    .onTapGesture { toggleSort(.disk) }
                
                // Network Header
                let totalNetRate = monitor.networkTotalRxRate + monitor.networkTotalTxRate
                HeaderCell(title: "Network", val: bitsPerSec(totalNetRate), ratio: min(totalNetRate / (5 * 1024 * 1024), 1.0), tc: tc, accent: accent)
                    .frame(width: 80)
                    .onTapGesture { toggleSort(.network) }
            }
            .frame(height: 34)
            .background(Color.gray.opacity(0.06))

            Divider()

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(groupedNodes) { node in
                        // Render Top-Level Row
                        ProcessRowItem(
                            process: node.process,
                            hasChildren: !node.children.isEmpty,
                            isExpanded: expandedPIDs.contains(node.process.pid),
                            cpu: node.totalCPU,
                            memory: node.totalMemory,
                            disk: node.totalDisk,
                            network: node.totalNetwork,
                            isChild: false,
                            selected: selectedPID == node.process.pid,
                            onToggleExpand: {
                                if expandedPIDs.contains(node.process.pid) {
                                    expandedPIDs.remove(node.process.pid)
                                } else {
                                    expandedPIDs.insert(node.process.pid)
                                }
                            },
                            totalMemorySystem: monitor.memory.total,
                            accent: accent
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPID = node.process.pid
                        }
                        .contextMenu {
                            contextMenuContent(for: node.process)
                        }
                        
                        Divider().opacity(0.15)
                        
                        // Render Child Rows if expanded
                        if expandedPIDs.contains(node.process.pid) {
                            ForEach(node.children) { child in
                                ProcessRowItem(
                                    process: child,
                                    hasChildren: false,
                                    isExpanded: false,
                                    cpu: child.cpu,
                                    memory: child.memory,
                                    disk: child.diskReadRate + child.diskWriteRate,
                                    network: child.networkRxRate + child.networkTxRate,
                                    isChild: true,
                                    selected: selectedPID == child.pid,
                                    onToggleExpand: {},
                                    totalMemorySystem: monitor.memory.total,
                                    accent: accent
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPID = child.pid
                                }
                                .contextMenu {
                                    contextMenuContent(for: child)
                                }
                                
                                Divider().opacity(0.15)
                            }
                        }
                    }
                }
            }
        }
        .background(cs == .dark ? Color(hex: "2B2B2B") : Color.white)
        .alert("End Task", isPresented: Binding(get: { confirmKillPID != nil }, set: { if !$0 { confirmKillPID = nil } })) {
            Button("End task", role: .destructive) {
                if let p = confirmKillPID {
                    if confirmKillName.hasSuffix("(tree)") {
                        kill(-p, SIGKILL)
                    }
                    kill(p, SIGKILL)
                }
                confirmKillPID = nil
                if selectedPID == confirmKillPID { selectedPID = nil }
            }
            Button("Cancel", role: .cancel) { confirmKillPID = nil }
        } message: {
            Text("Do you want to end \"\(confirmKillName.replacingOccurrences(of: " (tree)", with: ""))\"? Ending this process will close all associated windows and force the application to quit.")
        }
    }

    private func toggleSort(_ col: SortColumn) {
        if sortColumn == col {
            sortAsc.toggle()
        } else {
            sortColumn = col; sortAsc = false
        }
    }

    @ViewBuilder
    private func contextMenuContent(for proc: MachProcess) -> some View {
        Button("End Task") { confirmKillPID = proc.pid; confirmKillName = proc.name }
        Button("End Process Tree") {
            confirmKillPID = proc.pid; confirmKillName = "\(proc.name) (tree)"
        }
        Divider()
        Button("Properties") {}
    }
}

// Custom Shaded Column Header Cell
struct HeaderCell: View {
    var title: String
    var val: String
    var ratio: Double
    var tc: Color
    var accent: Color
    
    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundColor(tc)
            Text(val).font(.system(size: 9)).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(accent.opacity(max(0, min(ratio * 0.3, 0.3))))
        .border(Color.gray.opacity(0.12))
    }
}

// Single Process Row Item supporting nesting, heatmap overlays, and carets
struct ProcessRowItem: View {
    var process: MachProcess
    var hasChildren: Bool
    var isExpanded: Bool
    var cpu: Double
    var memory: UInt64
    var disk: Double
    var network: Double
    var isChild: Bool
    var selected: Bool
    var onToggleExpand: () -> Void
    var totalMemorySystem: UInt64
    var accent: Color

    var body: some View {
        HStack(spacing: 0) {
            // Name Column
            HStack(spacing: 4) {
                if isChild {
                    Spacer().frame(width: 20)
                }
                
                if hasChildren {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 14)
                }
                
                AppIconView(processName: process.name)
                    .frame(width: 16, height: 16)
                
                Text(process.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)


            // CPU Cell
            Text(String(format: "%.1f%%", cpu))
                .font(.system(size: 11, weight: cpu > 10.0 ? .semibold : .regular))
                .foregroundColor(cpu > 50.0 ? .red : .primary)
                .frame(width: 75, alignment: .trailing)
                .padding(.trailing, 4)
                .frame(maxHeight: .infinity)
                .background(heatmapColor(val: cpu, maxVal: 100.0))

            // Memory Cell
            Text(formatWinMem(memory))
                .font(.system(size: 11))
                .frame(width: 85, alignment: .trailing)
                .padding(.trailing, 4)
                .frame(maxHeight: .infinity)
                .background(heatmapColor(val: Double(memory), maxVal: Double(totalMemorySystem) * 0.15))

            // Disk Cell
            Text(bytesPerSec(disk))
                .font(.system(size: 11))
                .frame(width: 80, alignment: .trailing)
                .padding(.trailing, 4)
                .frame(maxHeight: .infinity)
                .background(heatmapColor(val: disk, maxVal: 10.0 * 1024 * 1024))

            // Network Cell
            Text(bitsPerSec(network))
                .font(.system(size: 11))
                .frame(width: 80, alignment: .trailing)
                .padding(.trailing, 4)
                .frame(maxHeight: .infinity)
                .background(heatmapColor(val: network, maxVal: 2.0 * 1024 * 1024))
        }
        .padding(.vertical, 2)
        .frame(height: 28)
        .background(selected ? accent.opacity(0.15) : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(accent).frame(width: 3)
            }
        }
    }

    private func heatmapColor(val: Double, maxVal: Double) -> Color {
        guard val > 0 else { return Color.clear }
        let ratio = min(val / maxVal, 1.0)
        return accent.opacity(0.04 + ratio * 0.35)
    }

    private func iconFor(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("xcode") || n.contains("swift") || n.contains("compiler") { return "hammer" }
        if n.contains("safari") || n.contains("chrome") || n.contains("firefox") || n.contains("browser") || n.contains("edge") || n.contains("opera") { return "globe" }
        if n.contains("terminal") || n.contains("iterm") || n.contains("bash") || n.contains("zsh") || n.contains("sh") { return "terminal" }
        if n.contains("finder") { return "folder" }
        if n.contains("mail") || n.contains("outlook") { return "envelope" }
        if n.contains("music") || n.contains("spotify") { return "music.note" }
        if n.contains("photos") || n.contains("photo") || n.contains("image") { return "photo" }
        if n.contains("settings") || n.contains("system") || n.contains("prefer") || n.contains("control") { return "gearshape" }
        return "doc"
    }
}

import AppKit

// MARK: - Real app icon lookup using NSWorkspace
struct AppIconView: View {
    let processName: String
    @State private var icon: NSImage? = nil

    var body: some View {
        Group {
            if let img = icon {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            Task.detached(priority: .background) {
                let img = AppIconView.resolveIcon(for: processName)
                await MainActor.run { self.icon = img }
            }
        }
    }

    nonisolated static func resolveIcon(for name: String) -> NSImage? {
        let ws = NSWorkspace.shared
        // Try running apps first
        if let app = ws.runningApplications.first(where: {
            ($0.localizedName?.lowercased() ?? "") == name.lowercased() ||
            ($0.bundleIdentifier ?? "").lowercased().hasSuffix(name.lowercased())
        }), let icon = app.icon {
            return icon
        }
        // Try to find the app by name in /Applications
        let candidates = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Library/CoreServices/\(name).app",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return ws.icon(forFile: path)
            }
        }
        return nil
    }
}
