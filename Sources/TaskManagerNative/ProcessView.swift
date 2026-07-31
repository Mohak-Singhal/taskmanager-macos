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
    
    var category: ProcessCategory
}

struct ProcessView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @Binding var searchText: String
    
    @State private var sortColumn = SortColumn.cpu
    @State private var sortAsc = false
    @Binding var selectedPID: pid_t?
    @State private var expandedPIDs: Set<pid_t> = []
    @State private var expandApps = true
    @State private var expandBackground = true
    @State private var expandWindows = false
    @State private var confirmKillPID: pid_t?
    @State private var confirmKillName: String = ""
    @State private var selectedPropertiesProcess: MachProcess? = nil

    enum SortColumn { case name, cpu, memory, disk, network, pid }

    private var tc: Color { cs == .dark ? .white : .black }
    private var bg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F4F4F4") }
    private var accent: Color { Color(hex: "0078D7") }

    private var totalDiskRate: Double {
        let hardware = monitor.disks.reduce(0.0) { $0 + $1.readRate + $1.writeRate }
        let processes = monitor.processes.reduce(0.0) { $0 + $1.diskReadRate + $1.diskWriteRate }
        return max(hardware, processes)
    }

    private var totalNetRate: Double {
        let hardware = monitor.networkTotalRxRate + monitor.networkTotalTxRate
        let processes = monitor.processes.reduce(0.0) { $0 + $1.networkRxRate + $1.networkTxRate }
        return max(hardware, processes)
    }

    private var groupedNodes: [ProcessNode] {
        let list = monitor.processes
        let filtered = searchText.isEmpty ? list : list.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.tabName.localizedCaseInsensitiveContains(searchText) ||
            $0.workingDirectory.localizedCaseInsensitiveContains(searchText)
        }
        
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
                
                let category: ProcessCategory
                if monitor.systemPIDs.contains(proc.pid) {
                    category = .system
                } else if monitor.appPIDs.contains(proc.pid) {
                    category = .app
                } else {
                    category = .background
                }
                
                topLevelNodes.append(ProcessNode(
                    process: proc,
                    children: children.sorted { $0.cpu > $1.cpu },
                    totalCPU: totalCPU,
                    totalMemory: totalMemory,
                    totalDisk: totalDisk,
                    totalNetwork: totalNetwork,
                    category: category
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

    private var appNodes: [ProcessNode] { groupedNodes.filter { $0.category == .app } }
    private var bgNodes: [ProcessNode] { groupedNodes.filter { $0.category == .background } }
    private var sysNodes: [ProcessNode] { groupedNodes.filter { $0.category == .system } }

    var body: some View {
        VStack(spacing: 0) {
            
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
                
                
                let cpuPct = monitor.cpuUsage.total
                HeaderCell(title: "CPU", val: String(format: "%d%%", Int(cpuPct)), ratio: cpuPct / 100.0, tc: tc, accent: accent, cs: cs)
                    .frame(width: 80)
                    .onTapGesture { toggleSort(.cpu) }
                
                
                let memUsed = Double(monitor.memory.used)
                let memTotal = Double(max(monitor.memory.total, 1))
                HeaderCell(title: "Memory", val: String(format: "%d%%", Int(memUsed / memTotal * 100.0)), ratio: memUsed / memTotal, tc: tc, accent: accent, cs: cs)
                    .frame(width: 85)
                    .onTapGesture { toggleSort(.memory) }
                
                
                HeaderCell(title: "Disk", val: bytesPerSec(totalDiskRate), ratio: min(totalDiskRate / (20 * 1024 * 1024), 1.0), tc: tc, accent: accent, cs: cs)
                    .frame(width: 80)
                    .onTapGesture { toggleSort(.disk) }
                
                
                HeaderCell(title: "Network", val: bitsPerSec(totalNetRate), ratio: min(totalNetRate / (5 * 1024 * 1024), 1.0), tc: tc, accent: accent, cs: cs)
                    .frame(width: 80)
                    .onTapGesture { toggleSort(.network) }
            }
            .frame(height: 36)
            .background(cs == .dark ? Color(hex: "232323") : Color(hex: "EDEDED"))

            Divider()

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    if monitor.processes.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("Collecting process data...")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        
                        SectionHeaderView(title: "Apps (\(appNodes.count))", icon: "window", isExpanded: $expandApps, cs: cs)
                        
                        if expandApps {
                            ForEach(appNodes) { node in
                                renderNodeRow(node)
                            }
                        }

                        
                        SectionHeaderView(title: "Background processes (\(bgNodes.count))", icon: "gearshape.2", isExpanded: $expandBackground, cs: cs)
                        
                        if expandBackground {
                            ForEach(bgNodes) { node in
                                renderNodeRow(node)
                            }
                        }

                        
                        SectionHeaderView(title: "Windows processes (\(sysNodes.count))", icon: "shield", isExpanded: $expandWindows, cs: cs)
                        
                        if expandWindows {
                            ForEach(sysNodes) { node in
                                renderNodeRow(node)
                            }
                        }
                    }
                }
            }
        }
        .background(cs == .dark ? Color(hex: "2B2B2B") : Color.white)
        .onChange(of: monitor.processes) { _, newList in
            let names = newList.prefix(100).map { $0.name }
            Task.detached(priority: .background) {
                AppIconStore.shared.prefetch(names: names)
            }
        }
        .alert("End Task", isPresented: Binding(get: { confirmKillPID != nil }, set: { if !$0 { confirmKillPID = nil } })) {
            Button("End task", role: .destructive) {
                if let p = confirmKillPID {
                    let isTree = confirmKillName.hasSuffix("(tree)")
                    let cleanName = confirmKillName.replacingOccurrences(of: " (tree)", with: "")
                    if let err = isTree ? monitor.endProcessTree(pid: p, name: cleanName) : monitor.endProcess(pid: p, name: cleanName) {
                        monitor.actionError = err
                    }
                    if selectedPID == p { selectedPID = nil }
                }
                confirmKillPID = nil
                confirmKillName = ""
            }
            Button("Cancel", role: .cancel) { confirmKillPID = nil }
        } message: {
            Text("Do you want to end \"\(confirmKillName.replacingOccurrences(of: " (tree)", with: ""))\"? Ending this process will close all associated windows and force the application to quit.")
        }
        .sheet(item: $selectedPropertiesProcess) { proc in
            ProcessPropertiesView(process: proc)
        }
        .sheet(item: $selectedCodeSigningProcess) { proc in
            CodeSigningSheet(process: proc, isPresented: Binding(get: { selectedCodeSigningProcess != nil }, set: { if !$0 { selectedCodeSigningProcess = nil } }))
        }
        .sheet(item: $diagnosticProcess) { proc in
            ProcessDiagnosticsSheet(
                process: proc,
                isPresented: Binding(
                    get: { diagnosticProcess != nil },
                    set: { if !$0 { diagnosticProcess = nil } }
                ),
                selectedTab: activeDiagnosticTab
            )
        }
        .onDeleteCommand {
            if let pid = selectedPID, let proc = monitor.processes.first(where: { $0.pid == pid }) {
                confirmKillPID = pid
                confirmKillName = proc.name
            }
        }
    }

    @ViewBuilder
    private func renderNodeRow(_ node: ProcessNode) -> some View {
        
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
            accent: accent,
            cs: cs
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPID = node.process.pid
            if !node.children.isEmpty {
                if expandedPIDs.contains(node.process.pid) {
                    expandedPIDs.remove(node.process.pid)
                } else {
                    expandedPIDs.insert(node.process.pid)
                }
            }
        }
        .contextMenu {
            contextMenuContent(for: node.process)
        }
        
        Divider().opacity(0.15)
        
        
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
                    accent: accent,
                    cs: cs
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

    private func toggleSort(_ col: SortColumn) {
        if sortColumn == col {
            sortAsc.toggle()
        } else {
            sortColumn = col; sortAsc = false
        }
    }

    @State private var selectedCodeSigningProcess: MachProcess? = nil
    @State private var scopeFilter = 0
    @State private var diagnosticProcess: MachProcess? = nil
    @State private var activeDiagnosticTab = 0

    @ViewBuilder
    private func contextMenuContent(for proc: MachProcess) -> some View {
        Button("End Task (SIGKILL)") { confirmKillPID = proc.pid; confirmKillName = proc.name }
        Button("End Process Tree") {
            confirmKillPID = proc.pid; confirmKillName = "\(proc.name) (tree)"
        }
        
        Menu("Set Process Priority") {
            Button("High Priority (-10)") {
                if let err = monitor.setProcessPriority(pid: proc.pid, priority: -10) { monitor.actionError = err }
            }
            Button("Normal Priority (0)") {
                if let err = monitor.setProcessPriority(pid: proc.pid, priority: 0) { monitor.actionError = err }
            }
            Button("Low Priority (10)") {
                if let err = monitor.setProcessPriority(pid: proc.pid, priority: 10) { monitor.actionError = err }
            }
        }

        Menu("Control Signals") {
            Button("Pause Process (SIGSTOP)") { if let e = monitor.signalProcess(pid: proc.pid, name: proc.name, signal: SIGSTOP) { monitor.actionError = e } }
            Button("Resume Process (SIGCONT)") { if let e = monitor.signalProcess(pid: proc.pid, name: proc.name, signal: SIGCONT) { monitor.actionError = e } }
            Button("Graceful Terminate (SIGTERM)") { if let e = monitor.signalProcess(pid: proc.pid, name: proc.name, signal: SIGTERM) { monitor.actionError = e } }
            Button("Force Kill (SIGKILL)") { if let e = monitor.signalProcess(pid: proc.pid, name: proc.name, signal: SIGKILL) { monitor.actionError = e } }
        }

        Divider()

        Menu("Diagnostics & Profiling") {
            Button("Inspect Open Files & Ports") {
                activeDiagnosticTab = 0
                diagnosticProcess = proc
            }
            Button("Sample Process (Stack Trace)") {
                activeDiagnosticTab = 1
                diagnosticProcess = proc
            }
            Button("Run Spindump (Elevated)") {
                activeDiagnosticTab = 2
                diagnosticProcess = proc
            }
            Button("Run System Diagnostics (Elevated)") {
                activeDiagnosticTab = 3
                diagnosticProcess = proc
            }
        }

        Button("Inspect Security & Code Signing") {
            selectedCodeSigningProcess = proc
        }

        Button("Create memory dump file (.core)") {
            createMemoryDump(for: proc)
        }

        Button("Copy process details") {
            let details = "PID: \(proc.pid)\nName: \(proc.name)\nCPU: \(String(format: "%.1f%%", proc.cpu))\nMemory: \(formatWinMem(proc.memory))\nPath: \(proc.executablePath.isEmpty ? "N/A" : proc.executablePath)\nArchitecture: \(proc.architecture)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(details, forType: .string)
        }
        Button("Export process list to CSV") {
            exportToCSV()
        }
        Divider()
        Button("Open file location") {
            monitor.openFileLocation(for: proc)
        }
        Button("Search online") {
            monitor.searchOnline(for: proc)
        }
        Divider()
        Button("Properties") {
            selectedPropertiesProcess = proc
        }
    }

    private func createMemoryDump(for proc: MachProcess) {
        let dest = "\(NSHomeDirectory())/Desktop/\(proc.name)_\(proc.pid).core"
        Task.detached(priority: .userInitiated) {
            let p = Process()
            p.launchPath = "/usr/bin/gcore"
            p.arguments = ["-o", dest, "\(proc.pid)"]
            try? p.run()
            p.waitUntilExit()
        }
    }



    private func exportToCSV() {
        var csvText = "PID,Name,CPU %,Memory (Bytes),Architecture,Path\n"
        for p in monitor.processes {
            let path = p.executablePath.replacingOccurrences(of: "\"", with: "\"\"")
            csvText += "\(p.pid),\"\(p.name)\",\(String(format: "%.2f", p.cpu)),\(p.memory),\(p.architecture),\"\(path)\"\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csvText, forType: .string)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ProcessList.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? csvText.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}


struct SectionHeaderView: View {
    var title: String
    var icon: String
    @Binding var isExpanded: Bool
    var cs: ColorScheme

    var body: some View {
        Button(action: { isExpanded.toggle() }) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 12)
                
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(cs == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(cs == .dark ? Color(hex: "222222") : Color(hex: "F2F2F2"))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}


struct HeaderCell: View {
    var title: String
    var val: String
    var ratio: Double
    var tc: Color
    var accent: Color
    var cs: ColorScheme
    
    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundColor(tc)
            Text(val).font(.system(size: 9)).foregroundColor(.gray).monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(headerHeatmapBg(ratio: ratio, cs: cs))
        .border(Color.gray.opacity(0.12))
    }
    
    private func headerHeatmapBg(ratio: Double, cs: ColorScheme) -> Color {
        guard ratio > 0.01 else { return Color.clear }
        let clamped = min(ratio, 1.0)
        return cs == .dark 
            ? Color(hex: "E88300").opacity(0.12 + clamped * 0.35) 
            : Color(hex: "FFF4CE").opacity(0.4 + clamped * 0.6)
    }
}


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
    var cs: ColorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            
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
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(process.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(cs == .dark ? .white : .black)
                            .lineLimit(1)
                        
                        if !process.tabName.contains("📂 Workspace") && !process.workingDirectory.isEmpty && process.workingDirectory != "/" {
                            let folder = (process.workingDirectory as NSString).lastPathComponent
                            if !folder.isEmpty && folder != "/" {
                                Text(folder)
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(3)
                            }
                        }
                    }
                    
                    let details: String = {
                        var sub = process.tabName
                        if !process.parentAppName.isEmpty {
                            let prefix = sub.isEmpty ? "" : "  |  "
                            sub += "\(prefix)via \(process.parentAppName)"
                        }
                        return sub
                    }()
                    
                    if !details.isEmpty {
                        Text(details)
                            .font(.system(size: 9.5))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .frame(minWidth: 240, maxWidth: .infinity, alignment: .leading)

            
            Text(String(format: "%.1f%%", cpu))
                .font(.system(size: 11, weight: cpu > 10.0 ? .semibold : .regular))
                .monospacedDigit()
                .foregroundColor(cpuText(cpu))
                .frame(width: 80, alignment: .trailing)
                .padding(.trailing, 6)
                .frame(maxHeight: .infinity)
                .background(heatmapBg(val: cpu, maxVal: 100.0))

            
            Text(formatWinMem(memory))
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 85, alignment: .trailing)
                .padding(.trailing, 6)
                .frame(maxHeight: .infinity)
                .background(heatmapBg(val: Double(memory), maxVal: Double(totalMemorySystem) * 0.15))

            
            Text(bytesPerSec(disk))
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
                .padding(.trailing, 6)
                .frame(maxHeight: .infinity)
                .background(heatmapBg(val: disk, maxVal: 10.0 * 1024 * 1024))

            
            Text(bitsPerSec(network))
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
                .padding(.trailing, 6)
                .frame(maxHeight: .infinity)
                .background(heatmapBg(val: network, maxVal: 2.0 * 1024 * 1024))
        }
        .padding(.vertical, 2)
        .frame(height: 28)
        .contentShape(Rectangle())
        .background(
            selected
                ? accent.opacity(0.22)
                : isHovered
                    ? (cs == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
                    : Color.clear
        )
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(accent).frame(width: 3.5)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(process.name), CPU \(String(format: "%.1f", cpu)) percent, Memory \(formatWinMem(memory))")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func cpuText(_ val: Double) -> Color {
        if val > 60.0 { return .red }
        if val > 20.0 { return cs == .dark ? Color(hex: "FFCC00") : Color(hex: "D46B08") }
        return cs == .dark ? .white : .black
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

import AppKit

final class AppIconStore: @unchecked Sendable {
    static let shared = AppIconStore()
    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]

    func cachedIcon(for name: String) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        return cache[name]
    }

    func resolve(name: String) -> NSImage? {
        if let img = cachedIcon(for: name) { return img }
        let img = AppIconView.resolveIcon(for: name)
        if let img = img {
            lock.lock(); cache[name] = img; lock.unlock()
        }
        return img
    }

    func prefetch(names: [String]) {
        for name in names { _ = resolve(name: name) }
    }
}

struct AppIconView: View {
    let processName: String
    @State private var icon: NSImage? = nil

    var body: some View {
        Group {
            if let img = icon ?? AppIconStore.shared.cachedIcon(for: processName) {
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
            guard icon == nil else { return }
            let name = processName
            Task.detached(priority: .background) {
                let img = AppIconStore.shared.resolve(name: name)
                if let img = img {
                    await MainActor.run { self.icon = img }
                }
            }
        }
    }

    nonisolated static func resolveIcon(for name: String) -> NSImage? {
        let ws = NSWorkspace.shared
        if let app = ws.runningApplications.first(where: {
            ($0.localizedName?.lowercased() ?? "") == name.lowercased() ||
            ($0.bundleIdentifier ?? "").lowercased().hasSuffix(name.lowercased())
        }), let icon = app.icon {
            return icon
        }
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

struct ProcessPropertiesView: View {
    var process: MachProcess
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var cs

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppIconView(processName: process.name)
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.name)
                        .font(.system(size: 14, weight: .bold))
                    Text(process.executablePath.isEmpty ? "System Executable" : process.executablePath)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Divider()

            VStack(spacing: 8) {
                propertyRow("Process Name:", process.name)
                propertyRow("Process ID (PID):", "\(process.pid)")
                propertyRow("Parent PID:", "\(process.ppid)")
                propertyRow("User / Owner:", process.username)
                propertyRow("Architecture:", process.architecture)
                propertyRow("CPU Utilization:", String(format: "%.1f%%", process.cpu))
                propertyRow("Memory Footprint:", formatWinMem(process.memory))
                propertyRow("Thread Count:", "\(process.threads)")
                propertyRow("Power Usage:", process.powerUsage)
                propertyRow("Power Usage Trend:", process.powerTrend)
                propertyRow("Location:", process.executablePath.isEmpty ? "/usr/libexec" : process.executablePath)
            }

            Spacer()

            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 390, height: 420)
        .background(cs == .dark ? Color(hex: "252525") : Color.white)
    }

    private func propertyRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray)
                .frame(width: 125, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(cs == .dark ? .white : .black)
                .lineLimit(2)
            Spacer()
        }
    }
}
