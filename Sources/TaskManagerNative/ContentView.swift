import SwiftUI
import Charts
import AppKit
import Metal



@MainActor
final class AppWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = AppWindowDelegate()
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApplication.shared.terminate(nil)
        return false
    }
}

enum AppTab: Int {
    case processes = 0
    case performance = 1
    case appHistory = 2
    case startup = 3
    case users = 4
    case details = 5
    case services = 6
    case settings = 7
    case overview = 8
    case insights = 9
}

struct ContentView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var selectedTab: AppTab = .processes
    @State private var selectedPerf = "cpu"
    @State private var showBits = true
    @State private var searchText = ""
    @State private var selectedPID: pid_t? = nil
    
    @State private var showRunDialog = false
    @State private var showCommandPalette = false
    @State private var runCommand = ""
    @State private var isSidebarExpanded = false
    @State private var efficiencyModeEnabled = false
    @State private var confirmKillPID: pid_t? = nil
    @State private var confirmKillName: String = ""

    private var bg: Color { cs == .dark ? Color(hex: "202020") : Color(hex: "F3F3F3") }
    private var accent: Color { Color(hex: "0078D7") }
    private var tc: Color { cs == .dark ? .white : .black }
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color(hex: "FFFFFF") }
    private static let cachedGPUName = MTLCreateSystemDefaultDevice()?.name ?? "Apple GPU"

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                
                topCommandBar
                
                Divider()

                
                HStack(spacing: 0) {
                    
                    VStack(spacing: 2) {
                        SidebarNavItem(tab: .processes, icon: "square.grid.2x2", label: "Processes", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                        SidebarNavItem(tab: .overview, icon: "house.fill", label: "Overview", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                        SidebarNavItem(tab: .insights, icon: "sparkles", label: "Insights & Diagnostics", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                        SidebarNavItem(tab: .performance, icon: "chart.line.uptrend.xyaxis", label: "Performance", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                        SidebarNavItem(tab: .appHistory, icon: "clock.arrow.circlepath", label: "App history", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                        SidebarNavItem(tab: .startup, icon: "gauge.with.dots.needle.bottom.50percent", label: "Startup apps", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                        SidebarNavItem(tab: .users, icon: "person.2", label: "Users", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                        SidebarNavItem(tab: .details, icon: "list.bullet.rectangle", label: "Details", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                        SidebarNavItem(tab: .services, icon: "gearshape.2", label: "Services", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)

                        Spacer()

                        Divider().opacity(0.15)

                        SidebarNavItem(tab: .settings, icon: "gearshape", label: "Settings", selectedTab: $selectedTab, isExpanded: isSidebarExpanded, tc: tc, accent: accent, cs: cs)
                            .padding(.bottom, 6)
                    }
                    .padding(.top, 4)
                    .frame(width: isSidebarExpanded ? 180 : 48)
                    .background(bg)

                    Divider()

                    
                    activeView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(cardBg)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(bg)
        .frame(minWidth: 620, minHeight: 460)
        .onReceive(NotificationCenter.default.publisher(for: .showRunDialog)) { _ in
            showRunDialog = true
        }
        .onAppear {
            setupNativeWindow()
        }
        .overlay {
            if showCommandPalette {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { showCommandPalette = false }
                CommandPaletteView(isPresented: $showCommandPalette, selectedTab: $selectedTab, selectedPID: $selectedPID)
                    .environmentObject(monitor)
            }
        }
        .sheet(isPresented: $showRunDialog) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create New Task")
                    .font(.system(size: 13, weight: .bold))
                Text("Type the name of a program, folder, document, or Internet resource, and macOS will open it for you.")
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
                        let cmd = runCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cmd.isEmpty {
                            launchRunTask(cmd)
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
        .alert("Action Failed", isPresented: Binding(get: { monitor.actionError != nil }, set: { if !$0 { monitor.actionError = nil } })) {
            Button("OK", role: .cancel) { monitor.actionError = nil }
        } message: {
            Text(monitor.actionError ?? "")
        }
    }

    private func toggleEfficiencyMode(_ enabled: Bool) {
        efficiencyModeEnabled = enabled
        monitor.setEfficiencyMode(enabled)
    }

    private func launchRunTask(_ cmd: String) {
        // Prefer LaunchServices so plain command names (e.g. "Terminal"),
        // paths, and URLs open naturally. Never execute arbitrary shell input.
        if let url = URL(string: cmd), NSWorkspace.shared.open(url) {
            return
        }
        if FileManager.default.fileExists(atPath: cmd) {
            NSWorkspace.shared.open(URL(fileURLWithPath: cmd))
            return
        }
        let p = Process()
        p.launchPath = "/usr/bin/open"
        p.arguments = ["-a", cmd]
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                monitor.actionError = "Unable to launch \"\(cmd)\"."
            }
        } catch {
            monitor.actionError = "Unable to launch \"\(cmd)\"."
        }
    }

    private var topCommandBar: some View {
        HStack(spacing: 12) {
            
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarExpanded.toggle()
                    }
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(tc)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Text(currentTabTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(tc)
                    .lineLimit(1)
            }
            .padding(.leading, 78)

            Spacer()

            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                TextField("Type to search...", text: $searchText)
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
            .frame(width: 180, height: 26)
            .background(cs == .dark ? Color(hex: "333333") : Color.white)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
            )

            
            Button(action: { showCommandPalette.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "command")
                    Text("Cmd+K")
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.18))
                .cornerRadius(4)
                .foregroundColor(tc)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)

            Button(action: { NotificationCenter.default.post(name: .showRunDialog, object: nil) }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("Run new task")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(cs == .dark ? Color(hex: "333333") : Color.white)
                .border(Color.gray.opacity(0.3), width: 0.5)
                .cornerRadius(3)
            }
            .buttonStyle(.plain)

            Button(action: {
                if let pid = selectedPID, let proc = monitor.processes.first(where: { $0.pid == pid }) {
                    confirmKillPID = pid
                    confirmKillName = proc.name
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.square")
                        .font(.system(size: 10, weight: .bold))
                    Text("End task")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selectedPID != nil ? (cs == .dark ? Color(hex: "C42B1C") : Color(hex: "FDF3F2")) : (cs == .dark ? Color(hex: "3A3A3A") : Color(hex: "FFFFFF")))
                .foregroundColor(selectedPID != nil ? (cs == .dark ? .white : Color(hex: "C42B1C")) : .gray)
                .border(selectedPID != nil ? (cs == .dark ? Color.clear : Color(hex: "F8C0BC")) : Color.gray.opacity(0.3), width: 0.5)
                .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .disabled(selectedPID == nil)

            Button(action: { toggleEfficiencyMode(!efficiencyModeEnabled) }) {
                HStack(spacing: 4) {
                    Image(systemName: "leaf")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(efficiencyModeEnabled ? .green : .gray)
                    Text("Efficiency mode")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(efficiencyModeEnabled ? (cs == .dark ? Color.green.opacity(0.2) : Color.green.opacity(0.1)) : (cs == .dark ? Color(hex: "333333") : Color.white))
                .border(Color.gray.opacity(0.3), width: 0.5)
                .cornerRadius(3)
            }
            .buttonStyle(.plain)

            
            Button(action: {
                monitor.setAlwaysOnTop(!monitor.alwaysOnTop)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: monitor.alwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(monitor.alwaysOnTop ? accent : .gray)
                    Text("Always on top")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(monitor.alwaysOnTop ? (cs == .dark ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1)) : (cs == .dark ? Color(hex: "333333") : Color.white))
                .border(Color.gray.opacity(0.3), width: 0.5)
                .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .help("Toggle compact always-on-top window mode")
        }
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow, state: .active))
    }

    private var currentTabTitle: String {
        switch selectedTab {
        case .processes: return "Processes"
        case .performance: return "Performance"
        case .appHistory: return "App history"
        case .startup: return "Startup apps"
        case .users: return "Users"
        case .details: return "Details"
        case .services: return "Services"
        case .settings: return "Settings"
        case .overview: return "Overview"
        case .insights: return "Insights & Diagnostics"
        }
    }

    @ViewBuilder
    private var activeView: some View {
        switch selectedTab {
        case .processes: ProcessView(searchText: $searchText, selectedPID: $selectedPID)
        case .performance: performanceContent
        case .appHistory: AppHistoryView()
        case .startup: StartupView()
        case .users: UsersView()
        case .details: DetailsView(searchText: $searchText, selectedPID: $selectedPID, accent: accent, cs: cs)
        case .services: ServicesView()
        case .settings: SettingsView()
        case .overview: OverviewView()
        case .insights: InsightsView()
        }
    }

struct SidebarNavItem: View {
    var tab: AppTab
    var icon: String
    var label: String
    @Binding var selectedTab: AppTab
    var isExpanded: Bool
    var tc: Color
    var accent: Color
    var cs: ColorScheme
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(selectedTab == tab ? accent : Color.clear)
                    .frame(width: 3, height: 16)
                    .cornerRadius(1.5)

                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(selectedTab == tab ? accent : .gray)
                    .frame(width: 20)

                if isExpanded {
                    Text(label)
                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? tc : .gray)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .background(
                selectedTab == tab
                    ? (cs == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    : (isHovered ? (cs == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)) : Color.clear)
            )
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
    }
}

    
    @ViewBuilder
    private var perfCards: some View {
        perfCard("cpu", title: "CPU", val: "\(Int(monitor.cpuUsage.total))% \(monitor.cpuSpeedString)")
        perfCard("memory", title: "Memory", val: formatWinMem(monitor.memory.used) + "/" + formatWinMem(monitor.memory.total) + " (" + String(Int(Double(monitor.memory.used)/Double(max(monitor.memory.total, 1))*100)) + "%)")
        ForEach(monitor.disks) { d in
            perfCard("disk-\(d.bsdName)", title: d.name, description: d.mediaType, val: "R: \(bytesPerSec(d.readRate))\nW: \(bytesPerSec(d.writeRate))")
        }
        ForEach(monitor.networkIfaces) { iface in
            perfCard("net-\(iface.name)", title: iface.displayName, description: networkCardSubtitle(iface), val: "S: \(bitsPerSec(iface.txRate))\nR: \(bitsPerSec(iface.rxRate))")
        }
        perfCard("gpu", title: "GPU 0", description: Self.cachedGPUName, val: "\(Int(monitor.gpuUsage))%")
        perfCard("energy", title: "Power", description: batteryDescription(monitor.powerSource), val: powerCardValue(monitor.powerSource, impact: monitor.systemEnergyImpact))
    }

    @ViewBuilder
    private var performanceContent: some View {
        ViewThatFits(in: .horizontal) {
            
            HStack(spacing: 12) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        perfCards
                    }
                    .padding(.vertical, 4)
                }
                .frame(width: 210)
                .clipped()
                
                perfDetail
                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 700)

            
            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        perfCards
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
            
            SparklineView(data: data, color: sparkColor, isPercentage: isPercentage)
                .frame(width: 60, height: 40)
                .background(cs == .dark ? Color(hex: "1A1A1A") : Color.white)
                .border(Color.gray.opacity(0.3), width: 0.8)
            
            
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
        .frame(minWidth: 198, maxWidth: 198, minHeight: 62)
        .background(isSelected ? (cs == .dark ? Color(hex: "3A3A3A") : Color(hex: "E5E5E5")) : Color.clear)
        .cornerRadius(3)
        .overlay(
            alignment: .leading
        ) {
            if isSelected {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3.5)
            }
        }
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
        
        for delay in [0.0, 0.1, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = NSApplication.shared.windows.first(where: {
                    $0.isVisible && $0.styleMask.contains(.titled)
                }) else { return }

                
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden          
                window.styleMask.insert(.fullSizeContentView)  

                
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false

                
                
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
    var cs: ColorScheme
    var selected: Bool
    var setPrio: (pid_t, Int32) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                AppIconView(processName: proc.name)
                    .frame(width: 14, height: 14)
                Text(proc.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            
            Text(String(proc.pid))
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
            
            HStack {
                Text(proc.threads > 0 ? "Running" : "Suspended")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(proc.threads > 0 ? Color(hex: "107C41") : .gray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(proc.threads > 0 ? Color(hex: "DFF6DD") : Color.gray.opacity(0.15))
                    .cornerRadius(8)
            }
            .frame(width: 80, alignment: .leading)
            .padding(.leading, 8)
            
            Text(proc.username)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
                .padding(.leading, 8)
            
            Text(String(format: "%.1f%%", proc.cpu))
                .font(.system(size: 11, weight: proc.cpu > 50 ? .bold : .regular))
                .monospacedDigit()
                .foregroundColor(proc.cpu > 50 ? Color(hex: "CC0000") : .primary)
                .frame(width: 70, alignment: .trailing)
            
            Text(formatWinMem(proc.memory))
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            
            Text("\(proc.threads)")
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(
            selected
                ? accent.opacity(0.22)
                : isHovered
                    ? (cs == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
                    : Color.clear
        )
        .overlay(
            alignment: .leading
        ) {
            if selected {
                Rectangle().fill(accent).frame(width: 3.5)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}



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
        case 2: return filtered.sorted { sortAsc ? $0.threads < $1.threads : $0.threads > $1.threads }
        case 3: return filtered.sorted { sortAsc ? $0.username < $1.username : $0.username > $1.username }
        case 4: return filtered.sorted { sortAsc ? $0.cpu < $1.cpu : $0.cpu > $1.cpu }
        case 5: return filtered.sorted { sortAsc ? $0.memory < $1.memory : $0.memory > $1.memory }
        default: return filtered.sorted { sortAsc ? $0.threads < $1.threads : $0.threads > $1.threads }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            
            HStack(spacing: 12) {
                
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
                .frame(width: 220, height: 24)
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
            
            headerContent
            Divider()
            
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(sorted) { proc in
                        DetailsRow(proc: proc, accent: accent, cs: cs, selected: selectedPID == proc.pid, setPrio: { p, v in
                            if let err = monitor.setProcessPriority(pid: p, priority: v) {
                                monitor.actionError = err
                            }
                        })
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

    private var headerContent: some View {
        HStack(spacing: 0) {
            sortBtn("Name", 0).frame(minWidth: 180, maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
            sortBtn("PID", 1).frame(width: 60, alignment: .trailing)
            sortBtn("Status", 2).frame(width: 80, alignment: .leading).padding(.leading, 8)
            sortBtn("User name", 3).frame(width: 100, alignment: .leading).padding(.leading, 8)
            sortBtn("CPU", 4).frame(width: 70, alignment: .trailing)
            sortBtn("Memory", 5).frame(width: 80, alignment: .trailing)
            sortBtn("Threads", 6).frame(width: 60, alignment: .trailing).padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(cs == .dark ? Color(hex: "232323") : Color(hex: "EDEDED"))
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
                    if let err = monitor.setProcessPriority(pid: proc.pid, priority: v) {
                        monitor.actionError = err
                    }
                }
            }
        }
        Divider()
        Button("Properties") {}
    }
}



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

func networkCardSubtitle(_ iface: NetworkIface) -> String {
    if iface.isWiFi { return "Wi-Fi" }
    let n = iface.name
    if n.hasPrefix("ipheth") { return "iPhone" }
    if n.hasPrefix("bridge") { return "Network Bridge" }
    if n.hasPrefix("anpi") { return "Apple Network Interface" }
    return "Ethernet"
}

extension Color { init(hex: String) { let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted); var i: UInt64 = 0; Scanner(string: h).scanHexInt64(&i); self.init(.sRGB, red: Double((i>>16)&0xFF)/255, green: Double((i>>8)&0xFF)/255, blue: Double(i&0xFF)/255, opacity: 1) } }
