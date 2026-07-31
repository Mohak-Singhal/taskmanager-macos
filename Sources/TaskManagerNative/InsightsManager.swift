import Foundation
import Combine
import AppKit

struct StorageSnapshot: Codable {
    var date: Date
    var sizes: [String: UInt64] // Path -> Bytes
}

struct DailyNetworkLog: Codable {
    var dateString: String // YYYY-MM-DD
    var uploads: [String: UInt64] // ProcessName -> Bytes
    var downloads: [String: UInt64] // ProcessName -> Bytes
}

struct InsightsData: Codable {
    var storageSnapshots: [StorageSnapshot] = []
    var networkLogs: [DailyNetworkLog] = []
}

@MainActor
class InsightsManager: ObservableObject {
    static let shared = InsightsManager()
    
    @Published var bottleneckExplanation: String = "Analyzing system health..."
    @Published var bottlenecks: [Bottleneck] = []
    
    @Published var storageInsights: [StorageInsight] = []
    @Published var sleepAssertions: [SleepAssertion] = []
    @Published var browserTabEnergy: [BrowserTabEnergy] = []
    
    @Published var networkPrivacyLogs: [NetworkPrivacyLog] = []
    @Published var dailyUploads: [String: UInt64] = [:] // Process -> Bytes
    @Published var telemetryAlerts: [TelemetryAlert] = []
    
    @Published var isScanningStorage = false
    
    private var data = InsightsData()
    private let dataURL: URL
    private var timer: Timer?
    
    // Tracking network traffic deltas
    private var lastProcessTx: [pid_t: UInt64] = [:]
    private var lastProcessRx: [pid_t: UInt64] = [:]
    
    // Tracking telemetry connection hits
    private var telemetryConnectionHits: [String: [String: Date]] = [:] // AppName -> [RemoteIP: LastSeen]
    private var telemetryCounts: [String: [String: Int]] = [:] // AppName -> [RemoteIP: Count]
    
    struct Bottleneck: Identifiable {
        let id = UUID()
        let severity: Severity
        let title: String
        let description: String
        
        enum Severity {
            case info, warning, critical
        }
    }
    
    struct StorageInsight: Identifiable {
        let id = UUID()
        let path: String
        let displayName: String
        let currentSize: UInt64
        let growthToday: Int64
        let growthThisWeek: Int64
    }
    
    struct SleepAssertion: Identifiable {
        let id = UUID()
        let pid: pid_t
        let name: String
        let assertionType: String
        let detail: String
    }
    
    struct BrowserTabEnergy: Identifiable {
        let id = UUID()
        let tabName: String
        let processName: String
        let cpu: Double
        let memory: UInt64
        let pid: pid_t
    }
    
    struct NetworkPrivacyLog: Identifiable {
        let id = UUID()
        let appName: String
        let server: String
        let protocolType: String
    }
    
    struct TelemetryAlert: Identifiable {
        let id = UUID()
        let appName: String
        let destination: String
        let count: Int
        let frequencyDescription: String
    }
    
    init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("TaskManagerNative")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.dataURL = appSupport.appendingPathComponent("insights_data.json")
        loadData()
        
        // Start periodic telemetry update loop (every 5 seconds)
        self.timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTelemetry()
            }
        }
        
        // Run initial scans
        Task { @MainActor in
            self.updateTelemetry()
            self.scanStorage()
        }
    }
    
    // MARK: - Persistence
    
    private func loadData() {
        guard let rawData = try? Data(contentsOf: dataURL) else { return }
        if let decoded = try? JSONDecoder().decode(InsightsData.self, from: rawData) {
            self.data = decoded
            updateDailyNetworkStats()
        }
    }
    
    private var lastSaveDate: Date = .distantPast

    private func saveData() {
        // Throttle disk writes: telemetry mutates every 5 s but only needs
        // persisting periodically.
        let now = Date()
        guard now.timeIntervalSince(lastSaveDate) > 30 else { return }
        lastSaveDate = now
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: dataURL)
        }
    }
    
    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func updateDailyNetworkStats() {
        let today = currentDateString()
        if let log = data.networkLogs.first(where: { $0.dateString == today }) {
            self.dailyUploads = log.uploads
        } else {
            self.dailyUploads = [:]
        }
    }
    
    // MARK: - Telemetry & Analysis
    
    func updateTelemetry() {
        guard let monitor = SystemMonitor.shared else { return }
        
        updateBottlenecks(monitor: monitor)
        updateBrowserTabEnergy(monitor: monitor)
        updateSleepAssertions()
        updateNetworkLogsAndTelemetry(monitor: monitor)
    }
    
    private func updateBottlenecks(monitor: SystemMonitor) {
        var list: [Bottleneck] = []
        
        // 1. CPU Throttling and Heat
        let cpuTemp = monitor.cpuTemperature
        if cpuTemp > 85.0 {
            list.append(Bottleneck(
                severity: .critical,
                title: "Thermal Throttling Active",
                description: "Your CPU is running extremely hot (\(String(format: "%.1f", cpuTemp))°C). macOS is throttling processor speeds to prevent damage, which makes the Mac feel slow."
            ))
        } else if cpuTemp > 70.0 {
            list.append(Bottleneck(
                severity: .warning,
                title: "CPU Temperature is High",
                description: "Processor temperature is \(String(format: "%.1f", cpuTemp))°C. Fans are working hard to cool it down."
            ))
        }
        
        // 2. CPU Usage & Heavy processes
        let totalCPU = monitor.cpuUsage.system + monitor.cpuUsage.user
        if totalCPU > 80.0 {
            let heavyProcess = monitor.processes.max(by: { $0.cpu < $1.cpu })
            let nameStr = heavyProcess != nil ? "'\(heavyProcess!.name)' (PID \(heavyProcess!.pid)) is using \(String(format: "%.1f", heavyProcess!.cpu))% CPU." : ""
            list.append(Bottleneck(
                severity: .critical,
                title: "CPU Capacity Saturated",
                description: "System CPU utilization is \(String(format: "%.1f", totalCPU))%. \(nameStr) Close heavy tasks to restore responsiveness."
            ))
        }
        
        // 3. RAM Pressure & Compression
        let pressure = monitor.memory.pressurePercentage
        if pressure > 80.0 {
            list.append(Bottleneck(
                severity: .critical,
                title: "Critical Memory Pressure",
                description: "Your Mac is running out of physical RAM (Memory Pressure is \(String(format: "%.1f", pressure))%). The kernel is compressing memory and paging to swap space."
            ))
        } else if pressure > 60.0 {
            list.append(Bottleneck(
                severity: .warning,
                title: "Elevated Memory Pressure",
                description: "Memory Pressure is \(String(format: "%.1f", pressure))%. Close inactive applications or browser tabs to free up RAM."
            ))
        }
        
        // 4. SSD Swapping
        let swapUsed = monitor.memory.swapUsed
        if swapUsed > 2 * 1024 * 1024 * 1024 { // > 2 GB swap
            let gbStr = String(format: "%.1f", Double(swapUsed) / (1024 * 1024 * 1024))
            list.append(Bottleneck(
                severity: .critical,
                title: "Excessive SSD Swapping",
                description: "Your system has allocated \(gbStr) GB of virtual swap space on your SSD. SSD swapping is significantly slower than RAM and can cause system freezes."
            ))
        }
        
        // 5. Disk Read/Write bottleneck (placeholder for future implementation if IO rates are exposed)
        
        self.bottlenecks = list
        
        if list.isEmpty {
            self.bottleneckExplanation = "Your Mac is operating optimally. CPU usage, temperature, and memory pressure are all within normal parameters."
        } else {
            let criticalCount = list.filter { $0.severity == .critical }.count
            let warningCount = list.filter { $0.severity == .warning }.count
            self.bottleneckExplanation = "We detected \(criticalCount) critical and \(warningCount) warning bottlenecks affecting your Mac's performance."
        }
    }
    
    private func updateBrowserTabEnergy(monitor: SystemMonitor) {
        var tabEnergyMap: [String: BrowserTabEnergy] = [:]
        
        for proc in monitor.processes {
            guard !proc.tabName.isEmpty else { continue }
            
            let key = proc.tabName
            if let existing = tabEnergyMap[key] {
                tabEnergyMap[key] = BrowserTabEnergy(
                    tabName: key,
                    processName: proc.name,
                    cpu: existing.cpu + proc.cpu,
                    memory: existing.memory + proc.memory,
                    pid: proc.pid
                )
            } else {
                tabEnergyMap[key] = BrowserTabEnergy(
                    tabName: key,
                    processName: proc.name,
                    cpu: proc.cpu,
                    memory: proc.memory,
                    pid: proc.pid
                )
            }
        }
        
        self.browserTabEnergy = tabEnergyMap.values.sorted(by: { ($0.cpu * 0.7 + Double($0.memory) * 0.3) > ($1.cpu * 0.7 + Double($1.memory) * 0.3) })
    }
    
    private func updateSleepAssertions() {
        Task { @MainActor [weak self] in
            let parsed = await Task.detached(priority: .utility) {
                Self.parseAssertions(Self.captureOutput(launchPath: "/usr/bin/pmset", arguments: ["-g", "assertions"], timeout: 3.0))
            }.value
            self?.sleepAssertions = parsed
        }
    }
    
    nonisolated static func parseAssertions(_ output: String) -> [SleepAssertion] {
        var parsed: [SleepAssertion] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("pid ") && line.contains("Assertion") {
                let parts = line.components(separatedBy: "pid ")
                if parts.count > 1 {
                    let mainPart = parts[1].trimmingCharacters(in: .whitespaces)
                    if let parenStart = mainPart.firstIndex(of: "("),
                       let parenEnd = mainPart.firstIndex(of: ")") {
                        let pidStr = String(mainPart[..<parenStart]).trimmingCharacters(in: .whitespaces)
                        let processName = String(mainPart[mainPart.index(after: parenStart)..<parenEnd])
                        
                        if let namedIndex = mainPart.range(of: " named: ") {
                            let preNamed = String(mainPart[parenEnd..<namedIndex.lowerBound])
                            let preNamedParts = preNamed.components(separatedBy: .whitespaces)
                            let assertionType = preNamedParts.last?.trimmingCharacters(in: .punctuationCharacters) ?? "Sleep Prevention"
                            
                            let detail = mainPart[namedIndex.upperBound...].replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
                            
                            if let pid = pid_t(pidStr) {
                                parsed.append(SleepAssertion(pid: pid, name: processName, assertionType: assertionType, detail: detail))
                            }
                        }
                    }
                }
            }
        }
        return parsed
    }
    
    private func updateNetworkLogsAndTelemetry(monitor: SystemMonitor) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let logs = await Task.detached(priority: .utility) {
                Self.parseLsof(Self.captureOutput(launchPath: "/usr/sbin/lsof", arguments: ["-i", "-n", "-P"], timeout: 3.0))
            }.value
            self.networkPrivacyLogs = Array(logs.prefix(40)) // limit UI list size
            for log in logs {
                self.recordConnectionHit(appName: log.appName, destination: log.server)
            }
            self.accumulateDailyUploads(monitor: monitor)
            self.buildTelemetryAlerts()
        }
    }
    
    nonisolated static func parseLsof(_ output: String) -> [NetworkPrivacyLog] {
        var logs: [NetworkPrivacyLog] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("->") {
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 9 {
                    let appName = parts[0]
                    let proto = parts[7]
                    let connection = parts[8]
                    
                    let connParts = connection.components(separatedBy: "->")
                    if connParts.count == 2 {
                        let remoteServer = connParts[1].components(separatedBy: " (")[0]
                        logs.append(NetworkPrivacyLog(appName: appName, server: remoteServer, protocolType: proto))
                    }
                }
            }
        }
        return logs
    }
    
    private func accumulateDailyUploads(monitor: SystemMonitor) {
        // 2. Accumulate network rx/tx upload deltas
        let today = currentDateString()
        var updatedDailyUploads = self.dailyUploads
        
        // Prune pids that no longer exist so the maps cannot grow without bound.
        let livePids = Set(monitor.processes.map { $0.pid })
        for pid in lastProcessTx.keys where !livePids.contains(pid) {
            lastProcessTx.removeValue(forKey: pid)
        }
        for pid in lastProcessRx.keys where !livePids.contains(pid) {
            lastProcessRx.removeValue(forKey: pid)
        }
        
        for proc in monitor.processes {
            let pid = proc.pid
            let name = proc.name
            
            let currentTx = proc.networkTxBytes
            if let lastTx = lastProcessTx[pid] {
                if currentTx >= lastTx {
                    let deltaTx = currentTx - lastTx
                    if deltaTx > 0 {
                        updatedDailyUploads[name, default: 0] += deltaTx
                    }
                }
            }
            lastProcessTx[pid] = currentTx
        }
        
        self.dailyUploads = updatedDailyUploads
        
        // Save to database
        if let index = data.networkLogs.firstIndex(where: { $0.dateString == today }) {
            data.networkLogs[index].uploads = updatedDailyUploads
        } else {
            data.networkLogs.append(DailyNetworkLog(dateString: today, uploads: updatedDailyUploads, downloads: [:]))
        }
        
        // Clean old logs (keep last 7 days)
        if data.networkLogs.count > 7 {
            data.networkLogs.removeFirst()
        }
        saveData()
    }
    
    private func buildTelemetryAlerts() {
        // 3. Build Telemetry Alert list
        var alerts: [TelemetryAlert] = []
        for (app, dests) in telemetryCounts {
            for (dest, count) in dests {
                // If contacted more than 15 times within the last minutes, flag it!
                if count > 10 {
                    let ipOnly = dest.components(separatedBy: ":")[0]
                    alerts.append(TelemetryAlert(
                        appName: app,
                        destination: ipOnly,
                        count: count,
                        frequencyDescription: "Sends traffic continuously (\(count) checks in last 5 mins)"
                    ))
                }
            }
        }
        self.telemetryAlerts = alerts.sorted(by: { $0.count > $1.count })
    }
    
    nonisolated private static func captureOutput(launchPath: String, arguments: [String], timeout: TimeInterval) -> String {
        let p = Process()
        p.launchPath = launchPath
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return ""
        }
        let start = Date()
        while p.isRunning {
            if Date().timeIntervalSince(start) > timeout {
                p.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func recordConnectionHit(appName: String, destination: String) {
        let now = Date()
        let ipOnly = destination.components(separatedBy: ":")[0]
        
        // We track hits within a moving 5-minute window
        var appHits = telemetryConnectionHits[appName, default: [:]]
        var appCounts = telemetryCounts[appName, default: [:]]
        
        let lastSeen = appHits[ipOnly]
        if let prev = lastSeen, now.timeIntervalSince(prev) < 30.0 {
            // If we've seen it very recently, increment frequency count
            appCounts[ipOnly, default: 0] += 1
        } else {
            // Reset count if it's been quiet
            if lastSeen == nil || now.timeIntervalSince(lastSeen!) > 300.0 {
                appCounts[ipOnly] = 1
            }
        }
        
        appHits[ipOnly] = now
        telemetryConnectionHits[appName] = appHits
        telemetryCounts[appName] = appCounts
    }
    
    // MARK: - Storage Scanning
    
    func scanStorage() {
        guard !isScanningStorage else { return }
        isScanningStorage = true
        
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        
        // Directories to scan
        let targetDirs = [
            (home.appendingPathComponent("Library/Caches"), "System & App Cache"),
            (home.appendingPathComponent("Library/Application Support"), "Application Data"),
            (home.appendingPathComponent("Downloads"), "Downloads Folder"),
            (home.appendingPathComponent("Documents"), "Documents Folder"),
            (URL(fileURLWithPath: "/tmp"), "Temporary Items")
        ]
        
        DispatchQueue.global(qos: .background).async {
            var sizesMap: [String: UInt64] = [:]
            
            for (url, _) in targetDirs {
                let size = Self.calculateDirectorySize(at: url)
                sizesMap[url.path] = size
            }
            
            Task { @MainActor in
                self.processStorageSizes(sizesMap: sizesMap, targetDirs: targetDirs)
                self.isScanningStorage = false
            }
        }
    }
    
    nonisolated static private func calculateDirectorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        var totalSize: UInt64 = 0
        
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: nil) else {
            return 0
        }
        
        var fileCount = 0
        for case let fileURL as URL in enumerator {
            // Throttle slightly to keep background CPU impact low
            fileCount += 1
            if fileCount % 1000 == 0 {
                Thread.sleep(forTimeInterval: 0.005)
            }
            
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if resourceValues.isDirectory == true { continue }
            if let size = resourceValues.fileSize {
                totalSize += UInt64(size)
            }
        }
        
        return totalSize
    }
    
    private func processStorageSizes(sizesMap: [String: UInt64], targetDirs: [(URL, String)]) {
        let now = Date()
        let newSnapshot = StorageSnapshot(date: now, sizes: sizesMap)
        
        data.storageSnapshots.append(newSnapshot)
        
        // Limit storage snapshots to last 30 items
        if data.storageSnapshots.count > 30 {
            data.storageSnapshots.removeFirst()
        }
        saveData()
        
        // Find past snapshots for comparison
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        
        // Growth today (diff with start of today)
        let todayStartSnapshot = data.storageSnapshots.first {
            calendar.isDate($0.date, inSameDayAs: todayStart)
        } ?? data.storageSnapshots.first
        
        // Growth this week (diff with 7 days ago)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let weekAgoSnapshot = data.storageSnapshots.first {
            $0.date <= weekAgo
        } ?? data.storageSnapshots.first
        
        var insights: [StorageInsight] = []
        for (url, displayName) in targetDirs {
            let path = url.path
            let current = sizesMap[path] ?? 0
            
            let todaySize = todayStartSnapshot?.sizes[path] ?? current
            let weekSize = weekAgoSnapshot?.sizes[path] ?? current
            
            let growthToday = Int64(current) - Int64(todaySize)
            let growthWeek = Int64(current) - Int64(weekSize)
            
            insights.append(StorageInsight(
                path: path,
                displayName: displayName,
                currentSize: current,
                growthToday: growthToday,
                growthThisWeek: growthWeek
            ))
        }
        
        self.storageInsights = insights
    }
}
