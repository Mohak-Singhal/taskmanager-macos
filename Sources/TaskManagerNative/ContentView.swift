import SwiftUI
import Charts
import AppKit


// Window delegate: make the close button terminate the app (not just close the window)
@MainActor
final class AppWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = AppWindowDelegate()
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApplication.shared.terminate(nil)
        return false
    }
}

struct ContentView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var selectedTab = 1 // Default to Performance
    @State private var selectedPerf = "cpu"
    @State private var showBits = true
    @State private var searchText = ""
    @State private var selectedPID: pid_t? = nil
    
    @State private var showRunDialog = false
    @State private var runCommand = ""

    private var bg: Color { cs == .dark ? Color(hex: "202020") : Color(hex: "F3F3F3") }
    private var accent: Color { Color(hex: "0078D7") }
    private var tc: Color { cs == .dark ? .white : .black }
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color(hex: "FFFFFF") }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {

                // Tab Bar Navigation
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        TabButton(index: 0, label: "Processes", selectedTab: $selectedTab, tc: tc, accent: accent, cs: cs)
                        TabButton(index: 1, label: "Performance", selectedTab: $selectedTab, tc: tc, accent: accent, cs: cs)
                        TabButton(index: 2, label: "App history", selectedTab: $selectedTab, tc: tc, accent: accent, cs: cs)
                        TabButton(index: 3, label: "Startup apps", selectedTab: $selectedTab, tc: tc, accent: accent, cs: cs)
                        TabButton(index: 4, label: "Users", selectedTab: $selectedTab, tc: tc, accent: accent, cs: cs)
                        TabButton(index: 5, label: "Details", selectedTab: $selectedTab, tc: tc, accent: accent, cs: cs)
                        TabButton(index: 6, label: "Services", selectedTab: $selectedTab, tc: tc, accent: accent, cs: cs)
                        TabButton(index: 7, label: "Settings", selectedTab: $selectedTab, tc: tc, accent: accent, cs: cs)
                    }
                }
                .padding(.horizontal, 4)
                .background(bg)
                
                Divider()
                
                // 4. Main Content Area (Full window size!)
                VStack(spacing: 0) {
                    activeView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(cardBg)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(bg)
        .frame(minWidth: 480, minHeight: 450)
        .onReceive(NotificationCenter.default.publisher(for: .showRunDialog)) { _ in
            showRunDialog = true
        }
        .onAppear {
            setupNativeWindow()
        }
        .sheet(isPresented: $showRunDialog) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create New Task")
                    .font(.system(size: 13, weight: .bold))
                Text("Type the name of a program, folder, document, or Internet resource, and Windows will open it for you.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                
                HStack {
                    Text("Open:").font(.system(size: 11))
                    TextField("", text: $runCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
                
                HStack {
                    Spacer()
                    Button("OK") {
                        if !runCommand.isEmpty {
                            let p = Process()
                            p.launchPath = "/bin/zsh"
                            p.arguments = ["-c", runCommand]
                            try? p.run()
                        }
                        showRunDialog = false
                        runCommand = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    
                    Button("Cancel") {
                        showRunDialog = false
                        runCommand = ""
                    }
                }
            }
            .padding()
            .frame(width: 360)
        }
    }

    private var currentTabTitle: String {
        switch selectedTab {
        case 0: return "Processes"
        case 1: return "Performance"
        case 2: return "App history"
        case 3: return "Startup apps"
        case 4: return "Users"
        case 5: return "Details"
        case 6: return "Services"
        case 7: return "Settings"
        default: return "Performance"
        }
    }

    @ViewBuilder
    private var activeView: some View {
        switch selectedTab {
        case 0: ProcessView(searchText: $searchText, selectedPID: $selectedPID)
        case 1: performanceContent
        case 2: AppHistoryView()
        case 3: StartupView()
        case 4: UsersView()
        case 5: DetailsView(searchText: $searchText, selectedPID: $selectedPID, accent: accent, cs: cs)
        case 6: ServicesView()
        case 7: SettingsView()
        default: EmptyView()
        }
    }

struct TabButton: View {
    var index: Int
    var label: String
    @Binding var selectedTab: Int
    var tc: Color
    var accent: Color
    var cs: ColorScheme
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { selectedTab = index }) {
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(selectedTab == index ? tc : .gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                
                // Active indicator line
                Rectangle()
                    .fill(selectedTab == index ? accent : Color.clear)
                    .frame(height: 2)
            }
            .background(
                selectedTab == index 
                    ? (cs == .dark ? Color(hex: "2B2B2B") : Color.white) 
                    : (isHovered ? (cs == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

    // Performance detail panels
    @ViewBuilder
    private var performanceContent: some View {
        ViewThatFits(in: .horizontal) {
            // Desktop Side-by-Side layout (requires at least 700 width)
            HStack(spacing: 12) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        perfCard("cpu", title: "CPU", val: "\(Int(monitor.cpuUsage.total))% \(monitor.cpuSpeedString)")
                        perfCard("memory", title: "Memory", val: formatWinMem(monitor.memory.used) + "/" + formatWinMem(monitor.memory.total) + " (" + String(Int(Double(monitor.memory.used)/Double(max(monitor.memory.total, 1))*100)) + "%)")
                        ForEach(monitor.disks) { d in
                            perfCard("disk-\(d.bsdName)", title: d.name, description: d.mediaType, val: "R: \(bytesPerSec(d.readRate))\nW: \(bytesPerSec(d.writeRate))")
                        }
                        ForEach(monitor.networkIfaces) { iface in
                            perfCard("net-\(iface.name)", title: iface.displayName, description: iface.isWiFi ? "Wi-Fi" : "Ethernet", val: "S: \(bitsPerSec(iface.txRate))\nR: \(bitsPerSec(iface.rxRate))")
                        }
                        perfCard("gpu", title: "GPU 0", description: MTLCreateSystemDefaultDevice()?.name ?? "Apple GPU", val: "\(Int(monitor.gpuUsage))%")
                        perfCard("energy", title: "Power", description: batteryDescription(monitor.powerSource), val: powerCardValue(monitor.powerSource, impact: monitor.systemEnergyImpact))
                    }
                    .padding(.vertical, 4)
                }
                .frame(width: 210)
                .clipped()
                
                perfDetail
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 700)

            // Mobile/Narrow stacked layout
            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        perfCard("cpu", title: "CPU", val: "\(Int(monitor.cpuUsage.total))% \(monitor.cpuSpeedString)")
                        perfCard("memory", title: "Memory", val: formatWinMem(monitor.memory.used) + "/" + formatWinMem(monitor.memory.total) + " (" + String(Int(Double(monitor.memory.used)/Double(max(monitor.memory.total, 1))*100)) + "%)")
                        ForEach(monitor.disks) { d in
                            perfCard("disk-\(d.bsdName)", title: d.name, description: d.mediaType, val: "R: \(bytesPerSec(d.readRate))\nW: \(bytesPerSec(d.writeRate))")
                        }
                        ForEach(monitor.networkIfaces) { iface in
                            perfCard("net-\(iface.name)", title: iface.displayName, description: iface.isWiFi ? "Wi-Fi" : "Ethernet", val: "S: \(bitsPerSec(iface.txRate))\nR: \(bitsPerSec(iface.rxRate))")
                        }
                        perfCard("gpu", title: "GPU 0", description: MTLCreateSystemDefaultDevice()?.name ?? "Apple GPU", val: "\(Int(monitor.gpuUsage))%")
                        perfCard("energy", title: "Power", description: batteryDescription(monitor.powerSource), val: powerCardValue(monitor.powerSource, impact: monitor.systemEnergyImpact))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .frame(height: 64)
                
                perfDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }

    private func perfCard(_ key: String, title: String, description: String? = nil, val: String) -> some View {
        let isSelected = selectedPerf == key
        let sparkColor = sparklineColor(for: key)
        let data = sparklineData(for: key)
        let isPercentage = (key == "cpu" || key == "memory" || key == "gpu")
        
        return HStack(spacing: 6) {
            // Miniature sparkline inside a small bordered container on the left
            SparklineView(data: data, color: sparkColor, isPercentage: isPercentage)
                .frame(width: 52, height: 34)
                .background(cs == .dark ? Color(hex: "1A1A1A") : Color.white)
                .border(Color.gray.opacity(0.3), width: 0.8)
            
            // Text labels on the right
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(tc)
                    .lineLimit(1)
                
                if let desc = description {
                    Text(desc)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                Text(val)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? tc : .gray)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(minWidth: 198, maxWidth: 198, minHeight: 54)
        .background(isSelected ? (cs == .dark ? Color(hex: "3A3A3A") : Color(hex: "E5E5E5")) : Color.clear)
        .cornerRadius(3)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isSelected ? (cs == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8)) : Color.clear, lineWidth: 1.0)
        )
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPerf = key
        }
    }

    @ViewBuilder
    private var perfDetail: some View {
        if selectedPerf == "cpu" { CPUDetailView() }
        else if selectedPerf == "memory" { MemoryDetailView() }
        else if selectedPerf.hasPrefix("disk-") { DiskDetailView(bsdName: selectedPerf.replacingOccurrences(of: "disk-", with: "")) }
        else if selectedPerf.hasPrefix("net-") { NetworkDetailView(ifaceName: selectedPerf.replacingOccurrences(of: "net-", with: ""), showBits: $showBits) }
        else if selectedPerf == "gpu" { GPUDetailView() }
        else if selectedPerf == "energy" { PowerDetailView() }
        else { CPUDetailView() }
    }


    private func setupNativeWindow() {
        // Apply with small retries to ensure the window is ready
        for delay in [0.0, 0.1, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = NSApplication.shared.windows.first(where: {
                    $0.isVisible && $0.styleMask.contains(.titled)
                }) else { return }

                // Make title bar transparent and integrate content seamlessly
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden          // hide the text title; we draw our own
                window.styleMask.insert(.fullSizeContentView)  // content extends under title bar

                // ✅ SHOW the real macOS traffic light buttons (close/minimize/zoom)
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false

                // Ensure the close button terminates the app (matches our previous behaviour)
                // (default macOS close just closes the window; we want terminate for this utility)
                window.delegate = AppWindowDelegate.shared
            }
        }
    }

    private func sparklineColor(for key: String) -> Color {
        if key == "cpu" { return Color(hex: "0078D7") }
        if key == "memory" { return Color(hex: "A154D4") }
        if key.hasPrefix("disk-") { return Color(hex: "D47C20") }
        if key.hasPrefix("net-") { return Color(hex: "FF5722") }
        if key == "gpu" { return Color(hex: "00A2E8") }
        if key == "energy" { return Color(hex: "E88D2A") }
        return Color(hex: "00A2E8")
    }

    private func sparklineData(for key: String) -> [Double] {
        if key == "cpu" {
            return monitor.cpuHistory
        } else if key == "memory" {
            return monitor.memoryHistory
        } else if key.hasPrefix("disk-") {
            let bsd = key.replacingOccurrences(of: "disk-", with: "")
            let reads = monitor.diskReadHistory[bsd] ?? Array(repeating: 0.0, count: 60)
            let writes = monitor.diskWriteHistory[bsd] ?? Array(repeating: 0.0, count: 60)
            return zip(reads, writes).map { r, w in r + w }
        } else if key.hasPrefix("net-") {
            return zip(monitor.networkRxHistory, monitor.networkTxHistory).map { rx, tx in Double(rx + tx) }
        } else if key == "gpu" {
            return monitor.gpuHistory
        } else if key == "energy" {
            return monitor.energyImpactHistory
        }
        return Array(repeating: 0.0, count: 60)
    }
}

// MARK: - Mini Sparkline Component

struct SparklineView: View {
    var data: [Double]
    var color: Color
    var isPercentage: Bool = true
    
    var body: some View {
        let maxVal = max(data.max() ?? 1.0, 1.0)
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("Time", i), y: .value("Value", v))
                    .foregroundStyle(color.opacity(0.18))
            }
            ForEach(Array(data.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("Time", i), y: .value("Value", v))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.0))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(isPercentage ? 100.0 : maxVal))
    }
}



struct DetailsRow: View {
    var proc: MachProcess
    var accent: Color
    var selected: Bool
    var setPrio: (pid_t, Int32) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(proc.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            Text(String(proc.pid))
                .font(.system(size: 12))
                .frame(width: 60, alignment: .trailing)
            Text(proc.threads > 0 ? "Running" : "Suspended")
                .font(.system(size: 12))
                .frame(width: 70, alignment: .leading)
                .padding(.leading, 8)
                .foregroundColor(proc.threads > 0 ? Color(hex: "0078D7") : .gray)
            Text(proc.username)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .frame(width: 100, alignment: .leading)
                .padding(.leading, 8)
            Text(String(format: "%.1f", proc.cpu))
                .font(.system(size: 12, weight: proc.cpu > 50 ? .bold : .regular))
                .foregroundColor(proc.cpu > 50 ? Color(hex: "CC0000") : .primary)
                .frame(width: 70, alignment: .trailing)
            Text(formatWinMem(proc.memory))
                .font(.system(size: 12))
                .frame(width: 80, alignment: .trailing)
            Text("\(proc.threads)")
                .font(.system(size: 12))
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 4)
        .background(selected ? accent.opacity(0.15) : Color.clear)
        .overlay(
            alignment: .leading
        ) {
            if selected {
                Rectangle().fill(accent).frame(width: 3)
            }
        }
    }
}

// MARK: - Details Tab View

struct DetailsView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Binding var searchText: String
    @Binding var selectedPID: pid_t?
    var accent: Color
    var cs: ColorScheme
    @State private var sortCol = 0
    @State private var sortAsc = false
    @State private var confirmKillPID: pid_t?
    @State private var confirmKillName: String = ""

    enum Priority: String, CaseIterable { case realtime = "Realtime", high = "High", aboveNormal = "Above Normal", normal = "Normal", belowNormal = "Below Normal", low = "Low" }

    private var sorted: [MachProcess] {
        let l = monitor.processes
        let filtered = searchText.isEmpty ? l : l.filter { $0.name.localizedCaseInsensitiveContains(searchText) || "\($0.pid)".contains(searchText) }
        switch sortCol {
        case 0: return filtered.sorted { sortAsc ? $0.name < $1.name : $0.name > $1.name }
        case 1: return filtered.sorted { sortAsc ? $0.pid < $1.pid : $0.pid > $1.pid }
        case 3: return filtered.sorted { sortAsc ? $0.cpu < $1.cpu : $0.cpu > $1.cpu }
        case 4: return filtered.sorted { sortAsc ? $0.memory < $1.memory : $0.memory > $1.memory }
        default: return filtered.sorted { sortAsc ? $0.threads < $1.threads : $0.threads > $1.threads }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action & Search bar at the top of Details tab
            HStack(spacing: 12) {
                // Search box
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    TextField("Filter by name or PID", text: $searchText)
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
                    if let pid = selectedPID, let proc = monitor.processes.first(where: { $0.pid == pid }) {
                        confirmKillPID = pid
                        confirmKillName = proc.name
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
            
            headerContent
            Divider()
            
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(sorted) { proc in
                        DetailsRow(proc: proc, accent: accent, selected: selectedPID == proc.pid, setPrio: { p, v in setpriority(PRIO_PROCESS, id_t(p), v) })
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPID = proc.pid
                            }
                            .contextMenu { contextMenu(for: proc) }
                        
                        Divider().opacity(0.15)
                    }
                }
            }
        }
        .background(cs == .dark ? Color(hex: "2B2B2B") : Color.white)
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

    private var headerContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sortBtn("Name", 0).frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                sortBtn("PID", 1).frame(width: 60, alignment: .trailing)
                sortBtn("Status", 2).frame(width: 70, alignment: .leading).padding(.leading, 8)
                sortBtn("User name", 3).frame(width: 100, alignment: .leading).padding(.leading, 8)
                sortBtn("CPU", 4).frame(width: 70, alignment: .trailing)
                sortBtn("Memory", 5).frame(width: 80, alignment: .trailing)
                sortBtn("Threads", 6).frame(width: 60, alignment: .trailing).padding(.trailing, 8)
            }
            .font(.system(size: 11, weight: .medium)).foregroundColor(.gray)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.gray.opacity(0.06))
        }
    }

    private var footerContent: some View {
        HStack {
            Spacer()
            Button("End Task") { if let p = selectedPID { kill(p, SIGKILL); selectedPID = nil } }
                .font(.system(size: 12)).buttonStyle(.borderedProminent).tint(accent).controlSize(.small).disabled(selectedPID == nil)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func sortBtn(_ label: String, _ col: Int) -> some View {
        Button(action: { if sortCol == col { sortAsc.toggle() } else { sortCol = col; sortAsc = false } }) {
            HStack(spacing: 2) { Text(label); if sortCol == col { Image(systemName: sortAsc ? "chevron.up" : "chevron.down").font(.system(size: 8)) } }
        }.buttonStyle(.plain).foregroundColor(sortCol == col ? accent : .gray)
    }

    @ViewBuilder
    private func contextMenu(for proc: MachProcess) -> some View {
        Button("End Task") { confirmKillPID = proc.pid; confirmKillName = proc.name }
        Divider()
        Menu("Set Priority") {
            ForEach(Priority.allCases, id: \.self) { p in
                Button(p.rawValue) {
                    let v: Int32 = switch p {
                    case .realtime: -20; case .high: -15; case .aboveNormal: -5
                    case .normal: 0; case .belowNormal: 5; case .low: 19
                    }
                    setpriority(PRIO_PROCESS, id_t(proc.pid), v)
                }
            }
        }
        Divider()
        Button("Properties") {}
    }
}

// MARK: - Helpers

func bytesPerSec(_ bps: Double) -> String {
    if bps <= 0 { return "0 KB/s" }
    if bps < 1024 { return String(format: "%.0f B/s", bps) }
    let kb = bps / 1024
    if kb < 1024 { return String(format: "%.1f KB/s", kb) }
    let mb = kb / 1024
    if mb < 1024 { return String(format: "%.1f MB/s", mb) }
    return String(format: "%.2f GB/s", mb / 1024)
}

func bitsPerSec(_ bps: Double) -> String {
    let bits = bps * 8; let units = ["bps", "Kbps", "Mbps", "Gbps"]; var v = bits; var u = 0
    while v >= 1000 && u < units.count - 1 { v /= 1000; u += 1 }
    return "\(String(format: "%.1f", v)) \(units[u])"
}

func batteryDescription(_ ps: PowerSourceStatus) -> String {
    if !ps.hasBattery { return "AC Power" }
    if ps.onAC {
        return ps.isCharging ? "\(ps.batteryPercent)% (Charging)" : "AC Power"
    }
    return "Battery \(ps.batteryPercent)%"
}

func powerCardValue(_ ps: PowerSourceStatus, impact: Double) -> String {
    if !ps.hasBattery {
        return "Impact: \(String(format: "%.1f", impact))"
    }
    if ps.onAC {
        return "Impact: \(String(format: "%.1f", impact))\n\(ps.powerDrawString) draw"
    }
    return "\(ps.powerDrawString) draw\n\(ps.timeRemainingString)"
}

extension Color { init(hex: String) { let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted); var i: UInt64 = 0; Scanner(string: h).scanHexInt64(&i); self.init(.sRGB, red: Double((i>>16)&0xFF)/255, green: Double((i>>8)&0xFF)/255, blue: Double(i&0xFF)/255, opacity: 1) } }
