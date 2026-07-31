import Foundation
import Darwin
import IOKit
import IOKit.ps
import SystemConfiguration
import DiskArbitration
import AppKit
import CoreWLAN

// Not exported by the Darwin SDK (sys/sysctl.h KERN_PROC_CPUTYPE == 20).
let KERN_PROC_CPUTYPE: Int32 = 20

@MainActor
class SystemMonitor: ObservableObject {
    @Published var cpuUsage = CPUUsage()
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var systemCPUHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var userCPUHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var memory = MemoryStatus()
    @Published var memoryHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var disks: [DiskInfo] = []
    @Published var diskHistory: [String: [Double]] = [:]
    @Published var diskTotalHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var networkIfaces: [NetworkIface] = []
    @Published var networkTotalRxRate: Double = 0
    @Published var networkTotalTxRate: Double = 0
    @Published var networkRxHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var networkTxHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var processes: [MachProcess] = []
    @Published private(set) var appPIDs: Set<pid_t> = []
    @Published private(set) var systemPIDs: Set<pid_t> = []
    @Published var uptime: time_t = 0
    @Published var cpuBrand = ""
    @Published var cpuCores = 0
    @Published var cpuPhysicalCores = 0
    @Published var l1Cache = "N/A"
    @Published var l2Cache = "N/A"
    @Published var l3Cache = "N/A"
    @Published var baseSpeed = "N/A"
    @Published var cpuSockets = 1
    @Published var perfCoreCount = 0
    @Published var efficiencyCoreCount = 0
    @Published var totalHandles = 0
    @Published var gpuUsage: Double = 0.0
    @Published var gpuHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published var virtualizationEnabled = false
    
    @Published var perCoreCPUHistory: [[Double]] = []
    private var prevCoreTicks: [(usr: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)] = []

    @Published var powerSource = PowerSourceStatus()
    @Published var systemEnergyImpact: Double = 0
    @Published var energyImpactHistory: [Double] = Array(repeating: 0, count: 60)

    var cpuSpeedString: String {
        let speedStr = baseSpeed.replacingOccurrences(of: " GHz", with: "").replacingOccurrences(of: " MHz", with: "")
        guard let base = Double(speedStr) else { return baseSpeed.isEmpty ? "N/A" : baseSpeed }
        let active = base * (0.6 + 0.4 * (cpuUsage.total / 100.0))
        return String(format: "%.2f GHz", active)
    }
    
    
    @Published var startupItems: [StartupItem] = []
    @Published var services: [LaunchdService] = []
    @Published var appHistory: [AppHistoryItem] = []
    @Published var actionError: String?

    private var prevCPU = CPUAbsoluteTicks()
    private var prevDiskRead: [String: UInt64] = [:]
    private var prevDiskWrite: [String: UInt64] = [:]
    var diskReadHistory: [String: [Double]] = [:]
    var diskWriteHistory: [String: [Double]] = [:]
    private var prevNet: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var lastNetworkPollTime: Date = Date()
    private var lastDiskIOPollTime: Date = Date()
    private var lastProcessSampleDate = Date()

    nonisolated(unsafe) private var prevProcessCPU: [pid_t: (user: UInt64, system: UInt64)] = [:]
    nonisolated(unsafe) private var prevProcessDisk: [pid_t: (read: UInt64, write: UInt64)] = [:]
    nonisolated(unsafe) private var prevProcessWakeups: [pid_t: (interrupt: UInt64, idle: UInt64)] = [:]
    // Cumulative bytes from nettop (for App History totals)
    private var processNetBytes: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
    // Precomputed bytes/sec rates from nettop (avoid double-diff in sampleProcesses)
    nonisolated(unsafe) private var processNetRates: [pid_t: (rx: Double, tx: Double)] = [:]
    nonisolated(unsafe) private var prevNettopBytes: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
    nonisolated(unsafe) private var lastNettopTime: Date = Date()
    nonisolated(unsafe) private var usernameCache: [uid_t: String] = [:]
    private var historyMap: [String: (cpu: Double, net: UInt64)] = [:]
    nonisolated(unsafe) private var cachedCmdMap: [pid_t: String] = [:]
    nonisolated(unsafe) private var cachedBrowserTabs: [String: [String]] = [:]
    nonisolated(unsafe) private var cachedProcessPaths: [pid_t: (path: String, cwd: String, parentApp: String, architecture: String)] = [:]
    nonisolated(unsafe) private var cachedLinkSpeeds: [String: String] = [:]

    private let processSampleLock = NSLock()
    private var samplingInProgress = false

    private var tickCount = 0
    
    private var diskBSDMapping: [String: String] = [:]

    struct CPUAbsoluteTicks { var system: UInt64 = 0; var user: UInt64 = 0; var idle: UInt64 = 0; var nice: UInt64 = 0 }

    // pti_total_user + pti_total_system are in nanoseconds. A core fully busy
    // for 1s accumulates 1e9 ns, which must read as 100% of that core.
    nonisolated static func cpuPercent(deltaTicks: UInt64, elapsedSeconds: Double) -> Double {
        guard elapsedSeconds > 0 else { return 0 }
        return Double(deltaTicks) / 10_000_000.0 / elapsedSeconds
    }

    nonisolated static func ratePerSecond(delta: UInt64, elapsedSeconds: Double) -> Double {
        guard elapsedSeconds > 0 else { return 0 }
        return Double(delta) / elapsedSeconds
    }

    nonisolated static func architectureString(cpuType: Int32) -> String {
        switch cpuType {
        case CPU_TYPE_ARM64: return "Apple Silicon (arm64)"
        case CPU_TYPE_X86_64: return "Intel 64-bit"
        case CPU_TYPE_X86: return "Intel 32-bit"
        default: return "64-bit"
        }
    }

    nonisolated func processArchitecture(pid: pid_t) -> String {
        var mib = [Int32](repeating: 0, count: Int(CTL_MAXNAME))
        var mibLen: size_t = size_t(CTL_MAXNAME)
        let name = "sysctl.proc_cputype"
        guard sysctlnametomib(name, &mib, &mibLen) == 0 else {
            return "64-bit"
        }
        var finalMib = Array(mib.prefix(mibLen))
        finalMib.append(pid)
        
        var cpuType: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&finalMib, u_int(finalMib.count), &cpuType, &size, nil, 0) == 0 else {
            return "64-bit"
        }
        return Self.architectureString(cpuType: cpuType)
    }

    // kern.memorystatus_level: 100 is healthy (no pressure), 0 is critical (jetsam active).
    nonisolated static func memoryPressure(fromSystemLevel level: Int32) -> (percent: Double, level: String) {
        let percent = max(0.0, min(100.0, 100.0 - Double(level)))
        return (percent, pressureLabel(percent))
    }

    nonisolated static func memoryPressure(fromUsedPct usedPct: Double) -> (percent: Double, level: String) {
        let percent = max(0.0, min(100.0, usedPct))
        return (percent, pressureLabel(percent))
    }

    nonisolated static func pressureLabel(_ percent: Double) -> String {
        if percent < 50.0 { return "Normal" }
        if percent < 80.0 { return "Warning" }
        return "Critical"
    }

    nonisolated static func parseLaunchctlLine(_ line: String) -> (pid: pid_t?, status: Int32, label: String)? {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 3 else { return nil }
        return (pid_t(parts[0]), Int32(parts[1]) ?? 0, parts[2])
    }

    private var timer: Timer?
    private var cachedWiFiRSSI: Int? = -50
    @Published var updateInterval: Double = 1.0
    @Published var cpuTemperature: Double = 0.0
    @Published var gpuTemperature: Double = 0.0
    @Published var fanSpeed: Double = 0.0

    
    @Published var alwaysOnTop: Bool = false {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop") }
    }

    static private(set) var shared: SystemMonitor? = nil

    init() {
        Self.shared = self
        let defaults = UserDefaults.standard
        self.alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        self.updateInterval = defaults.object(forKey: "updateInterval") as? Double ?? 1.0
        loadCPUInfo()
        tick()
        pollStartupItems()
        pollServices()
        startBackgroundNetworkMonitor()
        startWiFiMonitor()
        setupTimer()
        // Resolve physical-disk mappings off the main thread; each volume spawns
        // a /usr/sbin/diskutil subprocess which can stall first launch.
        Task { @MainActor [weak self] in
            let mapping = await Task.detached(priority: .utility) {
                Self.buildDiskBSDMapping()
            }.value
            self?.diskBSDMapping = mapping
        }
    }

    private func setupTimer() {
        timer?.invalidate()
        guard updateInterval > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    func setUpdateInterval(_ interval: Double) {
        self.updateInterval = interval
        UserDefaults.standard.set(interval, forKey: "updateInterval")
        setupTimer()
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        self.alwaysOnTop = enabled
        
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: {
                $0.isVisible && $0.styleMask.contains(.titled)
            }) else { return }
            window.level = enabled ? .floating : .normal
        }
    }


    private func startWiFiMonitor() {
        Task.detached(priority: .background) { [weak self] in
            while true {
                let rssi = self?.queryWiFiSignalDirect()
                await MainActor.run { [weak self] in
                    self?.cachedWiFiRSSI = rssi
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000) 
            }
        }
    }

    nonisolated private func queryWiFiSignalDirect() -> Int? {
        if let rssi = queryWiFiSignalCoreWLAN() {
            return rssi
        }
        // Fallback for macOS versions without CoreWLAN access to the current
        // interface (/usr/sbin/airport was removed in macOS 14+).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/airport")
        p.arguments = ["-I"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let d = out.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: d, encoding: .utf8) else { return nil }
        for line in s.components(separatedBy: "\n") where line.contains("agrCtlRSSI:") {
            return Int(line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        return nil
    }

    nonisolated private func queryWiFiSignalCoreWLAN() -> Int? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        return iface.rssiValue()
    }


    private func loadCPUInfo() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buf = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
            cpuBrand = String(decoding: Data(bytes: buf, count: strnlen(buf, size)), as: UTF8.self)
        }
        cpuPhysicalCores = Foundation.ProcessInfo.processInfo.processorCount
        cpuCores = Foundation.ProcessInfo.processInfo.activeProcessorCount
        
        
        var val64: Int64 = 0
        var valSize = MemoryLayout<Int64>.size
        
        if sysctlbyname("hw.l1dcachesize", &val64, &valSize, nil, 0) == 0 {
            let l1d = val64
            var l1i: Int64 = 0
            sysctlbyname("hw.l1icachesize", &l1i, &valSize, nil, 0)
            l1Cache = "\(ByteCountFormatter.string(fromByteCount: l1d + l1i, countStyle: .binary))"
        } else {
            l1Cache = "N/A"
        }
        
        if sysctlbyname("hw.l2cachesize", &val64, &valSize, nil, 0) == 0 && val64 > 0 {
            l2Cache = "\(ByteCountFormatter.string(fromByteCount: val64, countStyle: .binary))"
        } else {
            l2Cache = "N/A"
        }
        
        if sysctlbyname("hw.l3cachesize", &val64, &valSize, nil, 0) == 0 && val64 > 0 {
            l3Cache = "\(ByteCountFormatter.string(fromByteCount: val64, countStyle: .binary))"
        } else {
            l3Cache = "N/A"
        }

        var pkgs: Int32 = 1
        var pkgSize = MemoryLayout<Int32>.size
        if sysctlbyname("hw.packages", &pkgs, &pkgSize, nil, 0) == 0 {
            cpuSockets = Int(pkgs)
        }
        
        
        var hz: UInt64 = 0
        var hzSize = MemoryLayout<UInt64>.size
        var measured = false
        if sysctlbyname("hw.cpufrequency_max", &hz, &hzSize, nil, 0) == 0, hz > 0 {
            measured = true
        } else if sysctlbyname("hw.cpufrequency", &hz, &hzSize, nil, 0) == 0, hz > 0 {
            measured = true
        }
        if measured {
            baseSpeed = String(format: "%.2f GHz", Double(hz) / 1_000_000_000.0)
        } else {
            // Intel machines expose the speed in the brand string ("@ 3.20 GHz");
            // Apple Silicon exposes no frequency sysctl, so report N/A instead of
            // fabricating a speed.
            let pattern = "@\\s*([0-9.]+)\\s*(GHz|MHz)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: cpuBrand, options: [], range: NSRange(location: 0, length: cpuBrand.utf16.count)),
               let speedRange = Range(match.range(at: 1), in: cpuBrand),
               let unitRange = Range(match.range(at: 2), in: cpuBrand) {
                baseSpeed = "\(cpuBrand[speedRange]) \(cpuBrand[unitRange])"
            } else {
                baseSpeed = "N/A"
            }
        }
        
        var hvSupport: Int32 = 0
        var hvSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.hv_support", &hvSupport, &hvSize, nil, 0) == 0 {
            virtualizationEnabled = (hvSupport == 1)
        } else {
            virtualizationEnabled = false
        }

        var perf: Int32 = 0
        var eff: Int32 = 0
        var plSize = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &perf, &plSize, nil, 0) == 0,
           sysctlbyname("hw.perflevel1.physicalcpu", &eff, &plSize, nil, 0) == 0,
           perf > 0, eff > 0 {
            perfCoreCount = Int(perf)
            efficiencyCoreCount = Int(eff)
        } else {
            perfCoreCount = max(4, cpuPhysicalCores - cpuPhysicalCores / 3)
            efficiencyCoreCount = max(2, cpuPhysicalCores / 3)
        }
    }

    func tick() {
        pollCPU()
        pollMemory()
        pollDisks()
        pollDiskIO()
        pollNetwork()
        pollProcesses()          // updateProcessCategories() is called inside the async callback
        pollUptime()
        pollGPU()
        pollPowerSource()
        pollSMC()

        var handles: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.num_files", &handles, &size, nil, 0) == 0 {
            totalHandles = Int(handles)
        }

        tickCount += 1
        if tickCount % 5 == 0 {
            pollStartupItems()
            pollServices()
        }
    }

    private func pollSMC() {
        if let temp = SMC.shared.getCPUTemperature() {
            self.cpuTemperature = temp
        }
        if let gTemp = SMC.shared.getGPUTemperature() {
            self.gpuTemperature = gTemp
        }
        if let rpm = SMC.shared.getFanRPM() {
            self.fanSpeed = rpm
        }
    }

    

    private func pollCPU() {
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        var n: natural_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count)
        guard kr == KERN_SUCCESS, let ptr = info else { return }

        let load = UnsafeBufferPointer(start: ptr, count: Int(count))
        var sys: UInt64 = 0; var usr: UInt64 = 0; var idle: UInt64 = 0; var nice: UInt64 = 0
        
        let numCores = Int(n)
        if perCoreCPUHistory.count != numCores {
            perCoreCPUHistory = Array(repeating: Array(repeating: 0.0, count: 60), count: numCores)
            prevCoreTicks = Array(repeating: (usr: 0, sys: 0, idle: 0, nice: 0), count: numCores)
        }

        for i in 0..<numCores {
            let offset = i * 4
            if offset + 3 < Int(count) {
                let u = UInt64(load[offset + 0])
                let s = UInt64(load[offset + 1])
                let id = UInt64(load[offset + 2])
                let ni = UInt64(load[offset + 3])
                
                usr += u; sys += s; idle += id; nice += ni
                
                let prev = prevCoreTicks[i]
                let hasPrev = prev.usr > 0 || prev.sys > 0 || prev.idle > 0 || prev.nice > 0
                let dU = hasPrev && u >= prev.usr ? u - prev.usr : 0
                let dS = hasPrev && s >= prev.sys ? s - prev.sys : 0
                let dId = hasPrev && id >= prev.idle ? id - prev.idle : 0
                let dNi = hasPrev && ni >= prev.nice ? ni - prev.nice : 0
                let totalCore = dU + dS + dId + dNi
                let corePct = totalCore > 0 ? Double(dU + dS + dNi) / Double(totalCore) * 100.0 : 0.0
                
                perCoreCPUHistory[i] = Array(perCoreCPUHistory[i].dropFirst()) + [corePct]
                prevCoreTicks[i] = (usr: u, sys: s, idle: id, nice: ni)
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: ptr), vm_size_t(count * UInt32(MemoryLayout<integer_t>.size)))

        let cur = CPUAbsoluteTicks(system: sys, user: usr, idle: idle, nice: nice)
        // First sample has no baseline; deltas would reflect lifetime totals.
        if prevCPU.system == 0 && prevCPU.user == 0 && prevCPU.idle == 0 && prevCPU.nice == 0 {
            prevCPU = cur
            return
        }
        let dSys = cur.system - prevCPU.system
        let dUsr = cur.user - prevCPU.user
        let dIdle = cur.idle - prevCPU.idle
        let dNice = cur.nice - prevCPU.nice
        let total = dSys + dUsr + dIdle + dNice
        if total > 0 {
            cpuUsage = CPUUsage(system: Double(dSys)/Double(total)*100, user: Double(dUsr+dNice)/Double(total)*100, idle: Double(dIdle)/Double(total)*100)
        }
        prevCPU = cur
        cpuHistory = Array(cpuHistory.dropFirst()) + [cpuUsage.total]
        systemCPUHistory = Array(systemCPUHistory.dropFirst()) + [cpuUsage.system]
        userCPUHistory = Array(userCPUHistory.dropFirst()) + [cpuUsage.user]
    }

    

    private func pollMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let ret = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard ret == KERN_SUCCESS else { return }

        var pageSize: vm_size_t = 0
        let _ = withUnsafeMutablePointer(to: &pageSize) { ptr in
            ptr.withMemoryRebound(to: UInt.self, capacity: 1) { rebound in
                host_page_size(mach_host_self(), rebound)
            }
        }
        let ps = UInt64(pageSize)
        let total = Foundation.ProcessInfo.processInfo.physicalMemory
        
        let free = UInt64(stats.free_count) * ps
        let wired = UInt64(stats.wire_count) * ps
        let compressed = UInt64(stats.compressor_page_count) * ps
        
        let purgeable = UInt64(stats.purgeable_count) * ps
        let active = UInt64(stats.active_count) * ps
        let inactive = UInt64(stats.inactive_count) * ps
        let speculative = UInt64(stats.speculative_count) * ps
        let external = UInt64(stats.external_page_count) * ps
        
        
        let totalResident = active + inactive + speculative
        let appMemory = (totalResident >= (external + purgeable)) ? (totalResident - external - purgeable) : active
        
        
        let cached = external + purgeable
        
        
        let used = total >= (free + cached) ? (total - free - cached) : (appMemory + wired + compressed)

        // Read memory pressure level from kernel (XNU Jetsam status)
        var pressureVal: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        var pressurePercent = 0.0
        var pressureLevelString = "Normal"

        if sysctlbyname("kern.memorystatus_level", &pressureVal, &pressureSize, nil, 0) == 0 {
            let pressure = Self.memoryPressure(fromSystemLevel: pressureVal)
            pressurePercent = pressure.percent
            pressureLevelString = pressure.level
        } else {
            let usedPct = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0
            let pressure = Self.memoryPressure(fromUsedPct: usedPct)
            pressurePercent = pressure.percent
            pressureLevelString = pressure.level
        }

        memory = MemoryStatus(
            total: total,
            active: appMemory,
            wired: wired,
            compressed: compressed,
            free: free,
            cached: cached,
            used: used,
            appMemory: appMemory,
            pressurePercentage: pressurePercent,
            pressureLevel: pressureLevelString
        )

        var usage = xsw_usage()
        var s = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &s, nil, 0) == 0 {
            memory.swapTotal = usage.xsu_total
            memory.swapUsed = usage.xsu_used
        }
        memoryHistory = Array(memoryHistory.dropFirst()) + [(total > 0 ? Double(used)/Double(total)*100 : 0)]
    }

    

    
    
    nonisolated private static func buildDiskBSDMapping() -> [String: String] {
        var mapping: [String: String] = [:]
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return mapping }
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsInternalKey],
            options: [.skipHiddenVolumes]
        ) else { return mapping }

        for url in volumes {
            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else { continue }
            
            guard let descRaw = DADiskCopyDescription(disk) as? [CFString: Any],
                  let volBSD = descRaw[kDADiskDescriptionMediaBSDNameKey] as? String else { continue }
            let volDisk = stripToDiskNumber(volBSD) 

            if mapping[volDisk] == nil {
                if let parent = diskutilPhysicalParent(of: volDisk) {
                    mapping[volDisk] = parent
                } else {
                    mapping[volDisk] = volDisk
                }
            }
        }
        return mapping
    }

    nonisolated private static func stripToDiskNumber(_ bsd: String) -> String {
        guard bsd.hasPrefix("disk") else { return bsd }
        let digits = bsd.dropFirst(4).prefix(while: { $0.isNumber })
        return "disk" + digits
    }

    
    nonisolated private static func diskutilPhysicalParent(of disk: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["info", "-plist", disk]
        task.qualityOfService = .utility
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        
        
        if let stores = plist["APFSPhysicalStores"] as? [[String: Any]],
           let firstStore = stores.first?["APFSPhysicalStore"] as? String {
            return stripToDiskNumber(firstStore)
        }
        
        
        if let parent = plist["ParentWholeDisk"] as? String, parent != disk {
            return stripToDiskNumber(parent)
        }
        
        return nil
    }

    private func diskBSDName(for mountPath: String) -> String {
        var fs = statfs()
        guard statfs(mountPath, &fs) == 0 else { return mountPath }
        let from = withUnsafePointer(to: fs.f_mntfromname) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }
        let components = from.components(separatedBy: "/dev/")
        guard components.count > 1 else { return mountPath }
        let dev = components[1]
        guard dev.hasPrefix("disk") else { return dev }
        let digits = dev.dropFirst(4).prefix(while: { $0.isNumber })
        let logicalDisk = "disk" + digits
        
        return diskBSDMapping[logicalDisk] ?? logicalDisk
    }

    private func pollDisks() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedFormatDescriptionKey]
        guard let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return }
        var result: [DiskInfo] = []
        for url in volumes {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity.map(UInt64.init),
                  let available = values.volumeAvailableCapacity.map(UInt64.init),
                  total > 0 else { continue }
            let isInternal = values.volumeIsInternal ?? true
            let isRemovable = values.volumeIsRemovable ?? false
            let fsType = values.volumeLocalizedFormatDescription ?? "APFS"
            
            
            let mediaType: String
            if isRemovable {
                mediaType = "USB"
            } else {
                mediaType = isInternal ? "SSD" : "External"
            }

            
            let rawVolumeName = values.volumeName ?? ""
            let displayName: String
            if isInternal {
                displayName = rawVolumeName.isEmpty ? "Internal SSD" : rawVolumeName
            } else {
                
                if !rawVolumeName.isEmpty && rawVolumeName != "No name" {
                    displayName = rawVolumeName
                } else if isRemovable {
                    displayName = "USB Drive (\(fsType))"
                } else {
                    displayName = "External Drive (\(fsType))"
                }
            }
            
            let bsd = diskBSDName(for: url.path)
            
            
            
            if let idx = result.firstIndex(where: { $0.bsdName == bsd }) {
                
                if url.path == "/" {
                    result[idx] = DiskInfo(device: url.path, bsdName: bsd, name: displayName, isInternal: isInternal, totalBytes: total, usedBytes: total - available, readRate: diskReadHistory[bsd]?.last ?? 0, writeRate: diskWriteHistory[bsd]?.last ?? 0, fsType: fsType, mediaType: mediaType)
                }
            } else {
                result.append(DiskInfo(device: url.path, bsdName: bsd, name: displayName, isInternal: isInternal, totalBytes: total, usedBytes: total - available, readRate: diskReadHistory[bsd]?.last ?? 0, writeRate: diskWriteHistory[bsd]?.last ?? 0, fsType: fsType, mediaType: mediaType))
            }
        }
        disks = result
    }

    

    private func pollDiskIO() {
        var matching: io_iterator_t = 0
        let matchDict = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &matching) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(matching) }

        var service = IOIteratorNext(matching)
        var current: [String: (read: UInt64, write: UInt64)] = [:]
        while service != 0 {
            guard let props = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else {
                IOObjectRelease(service); service = IOIteratorNext(matching); continue
            }
            let readBytes = (props["Bytes (Read)"] as? NSNumber)?.uint64Value ?? (props["Bytes (Read)"] as? UInt64) ?? 0
            let writeBytes = (props["Bytes (Write)"] as? NSNumber)?.uint64Value ?? (props["Bytes (Write)"] as? UInt64) ?? 0

            var childIterator: io_iterator_t = 0
            var targetName: String? = nil
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == KERN_SUCCESS {
                var child = IOIteratorNext(childIterator)
                while child != 0 {
                    if let childName = IORegistryEntryCreateCFProperty(child, "BSD Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                        targetName = childName
                        IOObjectRelease(child)
                        break
                    }
                    IOObjectRelease(child)
                    child = IOIteratorNext(childIterator)
                }
                IOObjectRelease(childIterator)
            }

            if let bsdName = targetName {
                var cleanName = bsdName
                if bsdName.hasPrefix("disk") {
                    let digits = bsdName.dropFirst(4).prefix(while: { $0.isNumber })
                    cleanName = "disk" + digits
                }
                let existing = current[cleanName] ?? (read: 0, write: 0)
                current[cleanName] = (read: existing.read + readBytes, write: existing.write + writeBytes)
            }
            IOObjectRelease(service); service = IOIteratorNext(matching)
        }
        
        let diskNow = Date()
        let diskElapsed = max(diskNow.timeIntervalSince(lastDiskIOPollTime), 0.1)
        lastDiskIOPollTime = diskNow

        for (name, bytes) in current {
            let prevRead = prevDiskRead[name] ?? 0
            let prevWrite = prevDiskWrite[name] ?? 0

            let hasSeenBefore = prevDiskRead[name] != nil
            let readRate = hasSeenBefore && bytes.read >= prevRead ? Double(bytes.read - prevRead) / diskElapsed : 0
            let writeRate = hasSeenBefore && bytes.write >= prevWrite ? Double(bytes.write - prevWrite) / diskElapsed : 0
            
            if diskReadHistory[name] == nil { diskReadHistory[name] = Array(repeating: 0.0, count: 60) }
            if diskWriteHistory[name] == nil { diskWriteHistory[name] = Array(repeating: 0.0, count: 60) }
            
            diskReadHistory[name] = Array(diskReadHistory[name]!.dropFirst()) + [readRate]
            diskWriteHistory[name] = Array(diskWriteHistory[name]!.dropFirst()) + [writeRate]
            
            prevDiskRead[name] = bytes.read
            prevDiskWrite[name] = bytes.write
        }
        
        for key in prevDiskRead.keys where current[key] == nil {
            prevDiskRead.removeValue(forKey: key)
            prevDiskWrite.removeValue(forKey: key)
            diskReadHistory.removeValue(forKey: key)
            diskWriteHistory.removeValue(forKey: key)
        }
        
        for i in 0..<disks.count {
            let bsd = disks[i].bsdName
            disks[i].readRate = diskReadHistory[bsd]?.last ?? 0
            disks[i].writeRate = diskWriteHistory[bsd]?.last ?? 0
        }
        
        let total = disks.reduce(0.0) { $0 + $1.readRate + $1.writeRate }
        diskTotalHistory = Array(diskTotalHistory.dropFirst()) + [total]
    }

    

    
    
    
    private func interfaceInfo() -> (wifiNames: Set<String>, hwNames: [String: String]) {
        var wifiNames = Set<String>()
        var hwNames: [String: String] = [:]
        guard let ifaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return (wifiNames, hwNames)
        }
        for iface in ifaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) as? String else { continue }
            if SCNetworkInterfaceGetInterfaceType(iface) == kSCNetworkInterfaceTypeIEEE80211 {
                wifiNames.insert(bsd)
            }
            
            
            if let hw = SCNetworkInterfaceGetLocalizedDisplayName(iface) as? String, !hw.isEmpty {
                hwNames[bsd] = hw
            }
        }
        return (wifiNames, hwNames)
    }

    
    
    
    private func linkSpeedString(for ifName: String) -> String? {
        if let cached = cachedLinkSpeeds[ifName] {
            return cached
        }
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return nil }
        defer { close(sock) }

        var ifmr = ifmediareq()
        let nameSize = MemoryLayout.size(ofValue: ifmr.ifm_name)
        withUnsafeMutableBytes(of: &ifmr.ifm_name) { ptr in
            ifName.withCString { src in
                _ = Darwin.strlcpy(ptr.baseAddress!.assumingMemoryBound(to: CChar.self), src, nameSize)
            }
        }
        
        guard ioctl(sock, 0xC0286F63, &ifmr) == 0 else { return nil }

        let active = ifmr.ifm_active
        
        // SIOCGIFMEDIA media subtype selector (IFM_GMASK).
        let subtype = Int32(active) & 0x0ff0
        let result: String?
        switch subtype {
        case 0x0030: result = "10 Mbps"      
        case 0x0060: result = "100 Mbps"     
        case 0x00a0, 0x00b0, 0x00c0, 0x00d0: result = "1.0 Gbps"     
        case 0x0100: result = "2.5 Gbps"     
        case 0x0110: result = "5.0 Gbps"     
        case 0x0120, 0x0130, 0x0140, 0x0150: result = "10 Gbps"      
        case 0x0160: result = "25 Gbps"      
        case 0x0170: result = "40 Gbps"      
        case 0x0180: result = "100 Gbps"     
        default: result = nil
        }
        if let result {
            cachedLinkSpeeds[ifName] = result
        }
        return result
    }

    private func pollNetwork() {
        let (wifiNames, hwNames) = interfaceInfo()

        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let head = ptr else { return }
        defer { freeifaddrs(head) }

        var byName: [String: (ip4: String, ip6: String, isWiFi: Bool)] = [:]
        var curData: [String: (rx: UInt64, tx: UInt64)] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let p = cursor {
            let name = String(cString: p.pointee.ifa_name)
            let flags = Int32(p.pointee.ifa_flags)

            
            
            
            let accepted: Bool = {
                if name.hasPrefix("en"), name.count >= 3, name.dropFirst(2).allSatisfy({ $0.isNumber }) { return true }
                if name.hasPrefix("bridge"), name.dropFirst(6).allSatisfy({ $0.isNumber }) { return true }
                if name.hasPrefix("anpi"), name.dropFirst(4).allSatisfy({ $0.isNumber }) { return true }
                if name.hasPrefix("ipheth"), name.dropFirst(6).allSatisfy({ $0.isNumber }) { return true }
                return false
            }()
            guard accepted else { cursor = p.pointee.ifa_next; continue }
            if (flags & IFF_UP) == 0 || (flags & IFF_RUNNING) == 0 {
                cursor = p.pointee.ifa_next; continue
            }

            let isWiFi = wifiNames.contains(name)
            let addr = p.pointee.ifa_addr.pointee
            if addr.sa_family == AF_INET || addr.sa_family == AF_INET6 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(p.pointee.ifa_addr, socklen_t(addr.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = String(decoding: Data(bytes: host, count: strnlen(host, host.count)), as: UTF8.self)
                    let currentInfo = byName[name] ?? ("", "", isWiFi)
                    if addr.sa_family == AF_INET {
                        byName[name] = (ipStr, currentInfo.ip6, isWiFi)
                    } else if addr.sa_family == AF_INET6 {
                        let strippedIp = ipStr.components(separatedBy: "%").first ?? ipStr
                        byName[name] = (currentInfo.ip4, strippedIp, isWiFi)
                    }
                }
            }
            if addr.sa_family == AF_LINK, let data = p.pointee.ifa_data {
                let ld = data.assumingMemoryBound(to: if_data.self).pointee
                curData[name] = (UInt64(ld.ifi_ibytes), UInt64(ld.ifi_obytes))
            }
            cursor = p.pointee.ifa_next
        }

        // Use real elapsed time so speeds are correct regardless of timer interval
        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastNetworkPollTime), 0.1)
        lastNetworkPollTime = now

        var ifaces: [NetworkIface] = []
        var totalRx: Double = 0; var totalTx: Double = 0
        for (name, info) in byName {
            guard let c = curData[name] else { continue }
            let p = prevNet[name] ?? c
            let rxRate = c.rx >= p.rx ? Double(c.rx - p.rx) / elapsed : 0
            let txRate = c.tx >= p.tx ? Double(c.tx - p.tx) / elapsed : 0
            totalRx += rxRate; totalTx += txRate
            var sig: Int?
            if info.isWiFi { sig = cachedWiFiRSSI }

            let ip4 = info.ip4.isEmpty ? "N/A" : info.ip4
            let ip6 = info.ip6.isEmpty ? "N/A" : info.ip6

            
            let linkSpeed: String
            if info.isWiFi {
                linkSpeed = "Wi-Fi"   
            } else {
                linkSpeed = linkSpeedString(for: name) ?? "Unknown"
            }

            let displayName: String
            if info.isWiFi {
                displayName = hwNames[name] ?? "Wi-Fi"
            } else if let hw = hwNames[name] {
                
                
                displayName = hw
            } else if name.hasPrefix("ipheth") {
                displayName = "iPhone"
            } else if name.hasPrefix("bridge") {
                displayName = "Network Bridge"
            } else if name.hasPrefix("anpi") {
                displayName = "Apple Network Interface"
            } else {
                displayName = "Ethernet"
            }

            ifaces.append(NetworkIface(name: name, displayName: displayName, ipAddress: ip4, ipv6Address: ip6, linkSpeed: linkSpeed, isWiFi: info.isWiFi, rxRate: rxRate, txRate: txRate, signal: sig))
            prevNet[name] = c
        }
        
        networkIfaces = ifaces.sorted { a, b in
            if a.isWiFi != b.isWiFi { return a.isWiFi }
            return a.name < b.name
        }
        networkTotalRxRate = totalRx
        networkTotalTxRate = totalTx
        networkRxHistory = Array(networkRxHistory.dropFirst()) + [totalRx]
        networkTxHistory = Array(networkTxHistory.dropFirst()) + [totalTx]
    }


    

    nonisolated private func getCachedUsername(uid: uid_t) -> String {
        if let name = usernameCache[uid] {
            return name
        }
        if let pw = getpwuid(uid) {
            let name = String(cString: pw.pointee.pw_name)
            usernameCache[uid] = name
            return name
        }
        let fallback = "\(uid)"
        usernameCache[uid] = fallback
        return fallback
    }

    private func pollProcesses() {
        guard !samplingInProgress else { return }
        samplingInProgress = true
        let netBytesSnapshot = processNetBytes
        let netRatesSnapshot = processNetRates
        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastProcessSampleDate), 0.05)
        lastProcessSampleDate = now
        let tickNumber = tickCount
        // CRITICAL: Pre-fetch running app names on MainActor NOW.
        // fetchAllBrowserTabs previously called DispatchQueue.main.sync from a
        // background thread, which deadlocked when the main thread was busy,
        // causing sampleProcesses to never return and the process list to stay empty.
        let runningApps = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName?.lowercased() })
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let result = self.sampleProcesses(
                netBytesSnapshot: netBytesSnapshot,
                netRatesSnapshot: netRatesSnapshot,
                runningApps: runningApps,
                elapsedSeconds: elapsed,
                tickNumber: tickNumber
            )
            Task { @MainActor in
                self.samplingInProgress = false
                self.processes = result

                let totalEnergy = result.reduce(0.0) { $0 + $1.energyImpact }
                self.systemEnergyImpact = totalEnergy
                self.energyImpactHistory = Array(self.energyImpactHistory.dropFirst()) + [totalEnergy]

                self.updateAppHistory(processes: result)
                self.updateProcessCategories()
            }
        }
    }

    nonisolated private func fetchAllProcessCommands() -> [pid_t: String] {
        let p = Process()
        p.launchPath = "/bin/ps"
        p.arguments = ["-ax", "-o", "pid=,command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        let start = Date()
        while p.isRunning {
            if Date().timeIntervalSince(start) > 2.0 {
                p.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        
        var map: [pid_t: String] = [:]
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2, let pid = pid_t(parts[0]) {
                map[pid] = String(parts[1])
            }
        }
        return map
    }

    nonisolated private func sampleProcesses(
        netBytesSnapshot: [pid_t: (rx: UInt64, tx: UInt64)],
        netRatesSnapshot: [pid_t: (rx: Double, tx: Double)],
        runningApps: Set<String>,
        elapsedSeconds: Double,
        tickNumber: Int
    ) -> [MachProcess] {
        processSampleLock.lock()
        defer { processSampleLock.unlock() }

        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count))
        proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))

        // /bin/ps is expensive; refresh the command map every 5 samples.
        if tickNumber % 5 == 0 {
            cachedCmdMap = fetchAllProcessCommands()
            cachedProcessPaths.removeAll(keepingCapacity: true)
        }
        let cmdMap = cachedCmdMap

        var newPrev: [pid_t: (user: UInt64, system: UInt64)] = [:]
        var nextProcessDisk: [pid_t: (read: UInt64, write: UInt64)] = [:]
        var result: [MachProcess] = []

        // NSAppleScript tab queries are expensive; refresh every 10 samples.
        if tickNumber % 10 == 0 {
            var newTabs: [String: [String]] = [:]
            for app in ["Brave Browser", "Google Chrome", "Safari", "Microsoft Edge"] {
                // Pass pre-fetched running apps — avoids DispatchQueue.main.sync deadlock
                let tabs = fetchAllBrowserTabs(appName: app, runningApps: runningApps)
                if !tabs.isEmpty {
                    newTabs[app] = tabs
                }
            }
            cachedBrowserTabs = newTabs
        }
        let browserTabsCache = cachedBrowserTabs
        var rendererIndexMap: [String: Int] = [:]

        for pid in pids where pid >= 0 {
            var ti = proc_taskinfo()
            let sz = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.size))
            guard sz > 0 else { continue }

            var bsdInfo = proc_bsdinfo()
            let bsdSz = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
            let ppid = bsdSz > 0 ? pid_t(bsdInfo.pbi_ppid) : 0
            let uid = bsdSz > 0 ? bsdInfo.pbi_uid : 0
            let username = getCachedUsername(uid: uid)

            var nb = [CChar](repeating: 0, count: 1024)
            proc_name(pid, &nb, UInt32(nb.count))
            let name = String(decoding: Data(bytes: nb, count: strnlen(nb, nb.count)), as: UTF8.self).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let userTicks = ti.pti_total_user
            let systemTicks = ti.pti_total_system
            newPrev[pid] = (user: userTicks, system: systemTicks)

            let pct: Double
            let userPct: Double
            let systemPct: Double
            if let prev = prevProcessCPU[pid] {
                let dUser = userTicks >= prev.user ? userTicks - prev.user : 0
                let dSys = systemTicks >= prev.system ? systemTicks - prev.system : 0
                let delta = dUser + dSys
                if delta > 0 {
                    pct = Self.cpuPercent(deltaTicks: delta, elapsedSeconds: elapsedSeconds)
                    userPct = Self.cpuPercent(deltaTicks: dUser, elapsedSeconds: elapsedSeconds)
                    systemPct = Self.cpuPercent(deltaTicks: dSys, elapsedSeconds: elapsedSeconds)
                } else {
                    pct = 0; userPct = 0; systemPct = 0
                }
            } else {
                pct = 0; userPct = 0; systemPct = 0
            }

            
            var diskReadRate: Double = 0
            var diskWriteRate: Double = 0
            var diskReadBytes: UInt64 = 0
            var diskWriteBytes: UInt64 = 0
            
            var rusage = rusage_info_v4()
            let RUSAGE_INFO_V4 = 4
            let rusageRet = withUnsafeMutablePointer(to: &rusage) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, Int32(RUSAGE_INFO_V4), rebound)
                }
            }
            var interruptWakeups: UInt64 = 0
            var idleWakeups: UInt64 = 0
            var energyImpact: Double = 0

            if rusageRet == 0 {
                diskReadBytes = rusage.ri_diskio_bytesread
                diskWriteBytes = rusage.ri_diskio_byteswritten
                
                if let prevDisk = prevProcessDisk[pid] {
                    diskReadRate = diskReadBytes >= prevDisk.read ? Self.ratePerSecond(delta: diskReadBytes - prevDisk.read, elapsedSeconds: elapsedSeconds) : 0
                    diskWriteRate = diskWriteBytes >= prevDisk.write ? Self.ratePerSecond(delta: diskWriteBytes - prevDisk.write, elapsedSeconds: elapsedSeconds) : 0
                }
                nextProcessDisk[pid] = (read: diskReadBytes, write: diskWriteBytes)

                interruptWakeups = rusage.ri_interrupt_wkups
                idleWakeups = rusage.ri_pkg_idle_wkups

                if let prevWake = prevProcessWakeups[pid] {
                    let dInt = interruptWakeups >= prevWake.interrupt ? Double(interruptWakeups - prevWake.interrupt) : 0
                    let dIdle = idleWakeups >= prevWake.idle ? Double(idleWakeups - prevWake.idle) : 0
                    energyImpact = (dInt * 0.01 + dIdle * 0.005) / elapsedSeconds + pct * 0.1
                    energyImpact = max(0, energyImpact)
                }
                prevProcessWakeups[pid] = (interrupt: interruptWakeups, idle: idleWakeups)
            }


            var netRxRate: Double = 0
            var netTxRate: Double = 0
            var netRxBytes: UInt64 = 0
            var netTxBytes: UInt64 = 0

            // Use precomputed rates from nettop (already time-normalised, no double-diff)
            if let netBytes = netBytesSnapshot[pid] {
                netRxBytes = netBytes.rx
                netTxBytes = netBytes.tx
            }
            if let rate = netRatesSnapshot[pid] {
                netRxRate = rate.rx
                netTxRate = rate.tx
            }

            // proc_pidpath / proc_vnodepathinfo are per-process syscalls; reuse
            // cached values between refreshes to cut sample cost by ~5x.
            let execPath: String
            let cwd: String
            let parentApp: String
            let architecture: String
            if let cached = cachedProcessPaths[pid] {
                execPath = cached.path
                cwd = cached.cwd
                parentApp = cached.parentApp
                architecture = cached.architecture
            } else {
                var pathBuf = [CChar](repeating: 0, count: 1024)
                let pathLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
                execPath = pathLen > 0 ? String(decoding: Data(bytes: pathBuf, count: strnlen(pathBuf, pathBuf.count)), as: UTF8.self) : ""

                cwd = resolveWorkingDirectory(pid: pid)
                parentApp = resolveParentAppName(ppid: ppid)
                architecture = processArchitecture(pid: pid)
                cachedProcessPaths[pid] = (path: execPath, cwd: cwd, parentApp: parentApp, architecture: architecture)
            }
            let resolvedName = resolveAppBundleName(execPath: execPath, defaultName: name)

            let processMemory: UInt64
            let realMem: UInt64
            let compressedMem: UInt64
            if rusageRet == 0 {
                processMemory = rusage.ri_phys_footprint
                realMem = rusage.ri_resident_size
                compressedMem = rusage.ri_phys_footprint > rusage.ri_resident_size ? (rusage.ri_phys_footprint - rusage.ri_resident_size) : 0
            } else {
                processMemory = ti.pti_resident_size
                realMem = ti.pti_resident_size
                compressedMem = 0
            }

            result.append(MachProcess(
                pid: pid,
                ppid: ppid,
                uid: uid,
                username: username,
                name: resolvedName,
                cpu: pct,
                userCPU: userPct,
                systemCPU: systemPct,
                memory: processMemory,
                realMemory: realMem,
                vmCompressed: compressedMem,
                threads: Int(ti.pti_threadnum),
                diskReadBytes: diskReadBytes,
                diskWriteBytes: diskWriteBytes,
                diskReadRate: diskReadRate,
                diskWriteRate: diskWriteRate,
                networkRxBytes: netRxBytes,
                networkTxBytes: netTxBytes,
                networkRxRate: netRxRate,
                networkTxRate: netTxRate,
                interruptWakeups: interruptWakeups,
                idleWakeups: idleWakeups,
                energyImpact: energyImpact,
                executablePath: execPath,
                architecture: architecture,
                tabName: resolveChromiumTabName(pid: pid, name: resolvedName, tabsCache: browserTabsCache, rendererIndexMap: &rendererIndexMap, cwd: cwd, cmdMap: cmdMap),
                parentAppName: parentApp,
                workingDirectory: cwd
            ))
        }
        prevProcessCPU = newPrev
        prevProcessDisk = nextProcessDisk
        // Prune wakeup baselines for dead processes so the map cannot grow unbounded.
        let liveSet = Set(newPrev.keys)
        for pid in prevProcessWakeups.keys where !liveSet.contains(pid) {
            prevProcessWakeups.removeValue(forKey: pid)
        }
        return result
    }

    nonisolated private func resolveAppBundleName(execPath: String, defaultName: String) -> String {
        guard !execPath.isEmpty else { return defaultName }
        let components = execPath.components(separatedBy: "/")
        if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
            let appName = components[appIndex].replacingOccurrences(of: ".app", with: "")
            if !appName.isEmpty {
                return appName
            }
        }
        return defaultName
    }

    nonisolated private func resolveWorkingDirectory(pid: pid_t) -> String {
        var vpi = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, Int32(size))
        guard ret > 0 else { return "" }
        let cPath = withUnsafeBytes(of: &vpi.pvi_cdir.vip_path) { ptr in
            return String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return cPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func resolveParentAppName(ppid: pid_t) -> String {
        guard ppid > 1 else { return "" }
        var currentPPID = ppid
        var visited = Set<pid_t>()
        while currentPPID > 1 && !visited.contains(currentPPID) {
            visited.insert(currentPPID)
            var nb = [CChar](repeating: 0, count: 1024)
            proc_name(currentPPID, &nb, UInt32(nb.count))
            let pName = String(decoding: Data(bytes: nb, count: strnlen(nb, nb.count)), as: UTF8.self).trimmingCharacters(in: .whitespaces)
            guard !pName.isEmpty else { break }

            let lower = pName.lowercased()
            if lower.contains("antigravity") || lower.contains("opencode") || lower.contains("code") || lower.contains("terminal") || lower.contains("iterm") || lower.contains("cursor") || lower.contains("xcode") || lower.contains("idea") {
                return pName
            }

            var bsdInfo = proc_bsdinfo()
            let bsdSz = proc_pidinfo(currentPPID, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard bsdSz > 0 else { break }
            currentPPID = pid_t(bsdInfo.pbi_ppid)
        }
        return ""
    }

    nonisolated private func fetchAllBrowserTabs(appName: String, runningApps: Set<String>) -> [String] {
        // runningApps is pre-fetched on MainActor — no sync dispatch needed here
        let searchKey = appName.lowercased().replacingOccurrences(of: " browser", with: "")
        let isRunning = runningApps.contains { $0.contains(searchKey) }
        guard isRunning else { return [] }

        // NSAppleScript is only safe on the main thread, so shell out to
        // /usr/bin/osascript instead (this runs on a background queue).
        let scriptSource = """
        set AppleScript's text item delimiters to "|||"
        tell application "\(appName)"
            if running then
                try
                    set titleList to {}
                    repeat with w in windows
                        repeat with t in tabs of w
                            set end of titleList to (title of t)
                        end repeat
                    end repeat
                    return titleList as string
                end try
            end if
        end tell
        """
        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = ["-e", scriptSource]
        p.qualityOfService = .utility
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let start = Date()
        while p.isRunning {
            if Date().timeIntervalSince(start) > 1.0 {
                p.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return trimmed.components(separatedBy: "|||").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    nonisolated private func resolveChromiumTabName(pid: pid_t, name: String, tabsCache: [String: [String]], rendererIndexMap: inout [String: Int], cwd: String, cmdMap: [pid_t: String]) -> String {
        let lowerName = name.lowercased()
        if lowerName.contains("opencode") || lowerName.contains("node") || lowerName.contains("python") || lowerName.contains("bun") || lowerName.contains("deno") || lowerName.contains("antigravity") {
            if !cwd.isEmpty && cwd != "/" {
                let folderName = (cwd as NSString).lastPathComponent
                if !folderName.isEmpty && folderName != "/" {
                    return "📂 Workspace: \(folderName)"
                }
            }
        }

        guard let cmd = cmdMap[pid], !cmd.isEmpty else { return "" }
        
        let appToQuery: String? = {
            if lowerName.contains("brave") { return "Brave Browser" }
            if lowerName.contains("chrome") { return "Google Chrome" }
            if lowerName.contains("safari") { return "Safari" }
            if lowerName.contains("edge") { return "Microsoft Edge" }
            return nil
        }()

        if cmd.contains("--type=renderer") {
            if let app = appToQuery, let tabs = tabsCache[app], !tabs.isEmpty {
                let idx = rendererIndexMap[app, default: 0]
                rendererIndexMap[app] = idx + 1
                if idx < tabs.count {
                    return "🌐 \(tabs[idx])"
                }
            }
            return "🌐 Web Renderer"
        } else if cmd.contains("--type=extension") || cmd.contains("extension-process") {
            return "🧩 Extension Host"
        } else if cmd.contains("--type=gpu-process") {
            return "⚡ Hardware GPU Accelerator"
        } else if cmd.contains("--type=utility") {
            if cmd.contains("network.mojom.NetworkService") || cmd.contains("network") {
                return "🌐 Network Engine"
            } else if cmd.contains("audio") {
                return "🔊 Audio Controller"
            } else if cmd.contains("storage") {
                return "💾 Storage Manager"
            } else if cmd.contains("data_decoder") {
                return "⚙️ Data Decoder"
            }
            return "⚙️ Subsystem Worker"
        } else if cmd.contains("--type=zygote") {
            return "🌱 App Process Manager"
        } else if !cmd.contains("--type=") {
            if let app = appToQuery, let tabs = tabsCache[app], let first = tabs.first {
                return "🌐 Active: \(first)"
            }
        }
        return ""
    }

    func openFileLocation(for process: MachProcess) {
        let path = process.executablePath
        if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            return
        }
        let candidates = [
            "/Applications/\(process.name).app",
            "/System/Applications/\(process.name).app",
            "/System/Library/CoreServices/\(process.name).app"
        ]
        for p in candidates {
            if FileManager.default.fileExists(atPath: p) {
                NSWorkspace.shared.selectFile(p, inFileViewerRootedAtPath: "")
                return
            }
        }
    }

    func searchOnline(for process: MachProcess) {
        let query = process.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? process.name
        if let url = URL(string: "https://www.bing.com/search?q=\(query)+process") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateProcessCategories() {
        var owners = Set<pid_t>()
        if let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] {
            for w in list {
                guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                if let pidNum = w[kCGWindowOwnerPID as String] as? Int, pidNum > 0 {
                    owners.insert(pid_t(pidNum))
                }
            }
        }
        appPIDs = owners

        var sys = Set<pid_t>()
        for proc in processes where isSystemProcess(proc) {
            sys.insert(proc.pid)
        }
        systemPIDs = sys
    }

    private func isSystemProcess(_ proc: MachProcess) -> Bool {
        if proc.pid == 1 { return true }
        switch proc.name {
        case "kernel_task", "WindowServer", "loginwindow", "Finder", "Dock",
             "SystemUIServer", "ControlCenter", "launchd":
            return true
        default:
            break
        }
        if proc.uid == 0 && proc.ppid == 1 { return true }
        return false
    }

    private func pollUptime() {
        var tv = timeval(); var sz = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &sz, nil, 0) == 0 {
            uptime = time(nil) - tv.tv_sec
        }
    }
    
    private func pollGPU() {
        var matching: io_iterator_t = 0
        let matchDict = IOServiceMatching("IOAccelerator")
        var kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &matching)
        if kr != KERN_SUCCESS || matching == 0 {
            let matchDict2 = IOServiceMatching("AGXAccelerator")
            kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict2, &matching)
        }
        
        guard kr == KERN_SUCCESS, matching != 0 else {
            gpuUsage = 0
            gpuHistory = Array(gpuHistory.dropFirst()) + [0]
            return
        }
        defer { IOObjectRelease(matching) }
        
        var service = IOIteratorNext(matching)
        var maxUtil: Double = 0.0
        while service != 0 {
            if let props = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                if let util = props["Device Utilization %"] as? NSNumber {
                    let val = util.doubleValue
                    if val > maxUtil { maxUtil = val }
                } else if let util = props["Device Utilization"] as? NSNumber {
                    let val = util.doubleValue
                    if val > maxUtil { maxUtil = val }
                } else if let util = props["utilization"] as? NSNumber {
                    let val = util.doubleValue
                    if val > maxUtil { maxUtil = val }
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(matching)
        }
        
        let usage = max(0.0, min(100.0, maxUtil))
        gpuUsage = usage
        gpuHistory = Array(gpuHistory.dropFirst()) + [usage]
    }

    

    private func pollPowerSource() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [[String: Any]],
              let first = sources.first else {
            powerSource = PowerSourceStatus(onAC: true, batteryPercent: 100, isCharging: false, timeRemaining: -1, timeRemainingString: "N/A", powerSourceName: "Power Adapter")
            return
        }

        let powerState = first["Power Source State"] as? String ?? "AC Power"
        let onAC = powerState == "AC Power"
        let isCharging = (first["Is Charging"] as? Bool) ?? false
        let currentCapacity = first["Current Capacity"] as? Int ?? 0
        let maxCapacity = first["Max Capacity"] as? Int ?? 100
        let name = first["Name"] as? String ?? (onAC ? "Power Adapter" : "Battery")
        let timeRemaining = first["Time Remaining"] as? Int ?? -1
        let health = first["BatteryHealthCondition"] as? String ?? "Normal"

        let percent = maxCapacity > 0 ? Int(Double(currentCapacity) / Double(maxCapacity) * 100) : 100

        var timeStr = ""
        if onAC {
            // On AC power: time remaining is meaningless, always show N/A
            timeStr = "N/A"
        } else if timeRemaining == -1 {
            // On battery but macOS is still estimating
            timeStr = "Calculating..."
        } else if timeRemaining == -2 {
            timeStr = "N/A"
        } else if timeRemaining > 0 {
            let h = timeRemaining / 3600
            let m = (timeRemaining % 3600) / 60
            timeStr = h > 0 ? "\(h)h \(m)m remaining" : "\(m) min remaining"
        } else {
            timeStr = "N/A"
        }

        let hasBattery = maxCapacity > 0
        var batteryAmperage = 0
        var batteryVoltage = 0
        var batteryWatts = 0.0

        if hasBattery {
            let bs = readBatteryStats()
            batteryAmperage = bs.amperage
            batteryVoltage = bs.voltage
            batteryWatts = bs.watts
        }

        powerSource = PowerSourceStatus(
            onAC: onAC,
            batteryPercent: percent,
            isCharging: isCharging,
            timeRemaining: timeRemaining,
            timeRemainingString: timeStr,
            powerSourceName: name,
            batteryHealth: health,
            batteryCapacity: currentCapacity,
            batteryMaxCapacity: maxCapacity,
            batteryWatts: batteryWatts,
            batteryAmperage: batteryAmperage,
            batteryVoltage: batteryVoltage,
            hasBattery: hasBattery
        )
    }

    nonisolated private func readBatteryStats() -> (amperage: Int, voltage: Int, watts: Double) {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSmartBattery")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (0, 0, 0)
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return (0, 0, 0) }
        defer { IOObjectRelease(service) }

        let amperage = (IORegistryEntryCreateCFProperty(service, "Amperage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
        let voltage = (IORegistryEntryCreateCFProperty(service, "Voltage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int) ?? 0
        // Amperage is in mA, Voltage in mV: mA * mV = µW, so divide by 1e6 to get watts.
        let watts = abs(Double(amperage)) * Double(voltage) / 1_000_000.0

        return (amperage, voltage, watts)
    }

    
 
    nonisolated private static func extractFriendlyName(label: String, dict: [String: Any]) -> String {
        var programPath = dict["Program"] as? String
        if programPath == nil, let args = dict["ProgramArguments"] as? [String], !args.isEmpty {
            programPath = args[0]
        }
        
        if let path = programPath, !path.isEmpty {
            if let range = path.range(of: ".app") {
                let appPath = String(path[..<range.upperBound])
                let appName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                if !appName.isEmpty {
                    return appName
                }
            }
        }
        
        let parts = label.components(separatedBy: ".")
        if parts.count >= 2 {
            let last = parts.last!
            let genericSuffixes = ["agent", "daemon", "helper", "service", "privhelper", "wake", "wake.system", "socket", "vmnetd", "vmnets"]
            if genericSuffixes.contains(last.lowercased()) && parts.count >= 3 {
                let prev = parts[parts.count - 2]
                return "\(prev.replacingOccurrences(of: "-", with: " ").capitalized) \(last.replacingOccurrences(of: "-", with: " ").capitalized)"
            }
            return last.replacingOccurrences(of: "-", with: " ").capitalized
        }
        
        return label
    }

    func pollStartupItems() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            var items: [StartupItem] = []
            let paths = [
                NSHomeDirectory() + "/Library/LaunchAgents",
                "/Library/LaunchAgents",
                "/Library/LaunchDaemons"
            ]
            let fm = FileManager.default
            for path in paths {
                guard let files = try? fm.contentsOfDirectory(atPath: path) else { continue }
                for file in files where file.hasSuffix(".plist") {
                    let fullPath = (path as NSString).appendingPathComponent(file)
                    guard let dict = NSDictionary(contentsOfFile: fullPath) as? [String: Any] else { continue }
                    
                    let label = dict["Label"] as? String ?? file.replacingOccurrences(of: ".plist", with: "")
                    
                    var publisher = "Unknown"
                    if label.contains("com.google") { publisher = "Google LLC" }
                    else if label.contains("com.apple") { publisher = "Apple Inc." }
                    else if label.contains("com.microsoft") { publisher = "Microsoft Corp." }
                    else if label.contains("homebrew") { publisher = "Homebrew" }
                    else if label.contains("com.lwouis") { publisher = "Lukas Wouters" }
                    else {
                        let parts = label.components(separatedBy: ".")
                        if parts.count >= 2 {
                            publisher = parts[1].capitalized
                        }
                    }
                    
                    let disabled = dict["Disabled"] as? Bool ?? false
                    let status = disabled ? "Disabled" : "Enabled"
                    
                    let impact: String
                    if label.contains("google") || label.contains("keystone") { impact = "Medium" }
                    else if label.contains("postgresql") || label.contains("mysql") { impact = "High" }
                    else { impact = "Low" }
                    
                    let friendlyName = Self.extractFriendlyName(label: label, dict: dict)
                    items.append(StartupItem(name: friendlyName, bundleID: label, publisher: publisher, status: status, impact: impact, plistPath: fullPath))
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.startupItems = items
            }
        }
    }
 
    func toggleStartupItem(_ item: StartupItem) {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: item.plistPath) else {
            actionError = "Cannot modify \"\(item.plistPath)\". It is owned by the system or another user."
            return
        }
        
        guard var dict = NSMutableDictionary(contentsOfFile: item.plistPath) as? [String: Any] else {
            actionError = "Unable to read \"\(item.plistPath)\"."
            return
        }
        let currentDisabled = dict["Disabled"] as? Bool ?? false
        dict["Disabled"] = !currentDisabled
        
        let nsDict = dict as NSDictionary
        guard nsDict.write(toFile: item.plistPath, atomically: true) else {
            actionError = "Unable to write \"\(item.plistPath)\"."
            return
        }
        
        pollStartupItems()
    }
 
    
 
    func pollServices() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let process = Process()
            process.launchPath = "/bin/launchctl"
            process.arguments = ["list"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else { return }

                      
                var list: [LaunchdService] = []
                let lines = output.components(separatedBy: "\n")
                for line in lines.dropFirst() {
                    guard let parsed = Self.parseLaunchctlLine(line) else { continue }
                    list.append(LaunchdService(label: parsed.label, pid: parsed.pid, status: parsed.status))
                }
                let sortedList = list.sorted { $0.label < $1.label }
                DispatchQueue.main.async { [weak self] in
                    self?.services = sortedList
                }
            } catch {
                print("Failed to run launchctl list: \(error)")
            }
        }
    }

    func startService(_ service: LaunchdService) {
        if let err = runLaunchctl(arguments: ["start", service.label]) {
            actionError = "Failed to start \"\(service.label)\": \(err)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.pollServices()
        }
    }

    func stopService(_ service: LaunchdService) {
        if let err = runLaunchctl(arguments: ["stop", service.label]) {
            actionError = "Failed to stop \"\(service.label)\": \(err)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.pollServices()
        }
    }

    private func runLaunchctl(arguments: [String]) -> String? {
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return error.localizedDescription
        }
        if p.terminationStatus == 0 { return nil }
        let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return errStr.isEmpty ? "exit code \(p.terminationStatus)" : errStr
    }

    

    func resetAppHistory() {
        historyMap = [:]
        appHistory = []
    }

    private func updateAppHistory(processes: [MachProcess]) {
        for p in processes {
            let name = p.name
            let deltaCPU = (p.cpu / 100.0)
            let deltaNet = UInt64(p.networkRxRate + p.networkTxRate)
            
            let prev = historyMap[name] ?? (cpu: 0, net: 0)
            historyMap[name] = (cpu: prev.cpu + deltaCPU, net: prev.net + deltaNet)
        }
        
        // Cap the map so it cannot grow without bound.
        if historyMap.count > 2000 {
            let sorted = historyMap.sorted { $0.value.cpu > $1.value.cpu }
            for entry in sorted.dropFirst(2000) {
                historyMap.removeValue(forKey: entry.key)
            }
        }
        
        appHistory = historyMap.map { (key, value) in
            AppHistoryItem(name: key, cpuTime: value.cpu, networkBytes: value.net)
        }.sorted { $0.cpuTime > $1.cpuTime }
    }

    

    nonisolated private func startBackgroundNetworkMonitor() {
        Task.detached(priority: .background) {
            while true {
                self.runNettop()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    nonisolated private func runNettop() {
        let process = Process()
        process.launchPath = "/usr/bin/nettop"
        // -l 1 = one snapshot; output is cumulative bytes since process start
        process.arguments = ["-J", "bytes_in,bytes_out", "-l", "1"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return }

            let now = Date()
            let elapsed = max(now.timeIntervalSince(lastNettopTime), 0.5)
            lastNettopTime = now

            var newNetBytes: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
            for line in output.components(separatedBy: "\n") {
                if let parsed = Self.parseNettopLine(line) {
                    newNetBytes[parsed.pid] = (rx: parsed.rx, tx: parsed.tx)
                }
            }

            // Compute per-process rates: delta cumulative bytes / elapsed seconds
            var newRates: [pid_t: (rx: Double, tx: Double)] = [:]
            for (pid, bytes) in newNetBytes {
                if let prev = prevNettopBytes[pid] {
                    let rxDelta = bytes.rx >= prev.rx ? Double(bytes.rx - prev.rx) : 0
                    let txDelta = bytes.tx >= prev.tx ? Double(bytes.tx - prev.tx) : 0
                    newRates[pid] = (rx: rxDelta / elapsed, tx: txDelta / elapsed)
                } else {
                    // First time seen — no previous baseline, rate = 0
                    newRates[pid] = (rx: 0, tx: 0)
                }
                prevNettopBytes[pid] = bytes
            }
            // Remove stale entries for dead processes
            for key in prevNettopBytes.keys where newNetBytes[key] == nil {
                prevNettopBytes.removeValue(forKey: key)
            }

            let selfRef = self
            Task { @MainActor in
                selfRef.processNetBytes = newNetBytes
                selfRef.processNetRates = newRates
            }
        } catch {
            print("Failed to run nettop: \(error)")
        }
    }

    nonisolated static func parseNettopLine(_ line: String) -> (pid: pid_t, rx: UInt64, tx: UInt64)? {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 6 else { return nil }
        
        let txUnit = parts[parts.count - 1]
        let txValStr = parts[parts.count - 2]
        let rxUnit = parts[parts.count - 3]
        let rxValStr = parts[parts.count - 4]
        
        guard let rxVal = Double(rxValStr), let txVal = Double(txValStr) else { return nil }
        
        let rxBytes = convertToBytes(val: rxVal, unit: rxUnit)
        let txBytes = convertToBytes(val: txVal, unit: txUnit)
        
        for i in 1..<(parts.count - 4) {
            let comp = parts[i]
            if let dotIdx = comp.lastIndex(of: ".") {
                let pidStr = comp[comp.index(after: dotIdx)...]
                if let pid = pid_t(pidStr) {
                    return (pid, rxBytes, txBytes)
                }
            }
        }
        return nil
    }

    nonisolated static func convertToBytes(val: Double, unit: String) -> UInt64 {
        let u = unit.lowercased()
        if u.hasPrefix("k") { return UInt64(val * 1024) }
        if u.hasPrefix("m") { return UInt64(val * 1024 * 1024) }
        if u.hasPrefix("g") { return UInt64(val * 1024 * 1024 * 1024) }
        if u.hasPrefix("t") { return UInt64(val * 1024 * 1024 * 1024 * 1024) }
        return UInt64(val)
    }

    // MARK: - Process control (guarded, with user-visible feedback)

    private static let criticalProcessNames: Set<String> = [
        "kernel_task", "WindowServer", "loginwindow", "launchd",
        "runningboardd", "kernelmanagerd"
    ]

    @MainActor
    func endProcess(pid: pid_t, name: String) -> String? {
        if let err = guardTermination(pid: pid, name: name) { return err }
        return checkedSignal(pid: pid, signal: SIGKILL)
    }

    @MainActor
    func endProcessTree(pid: pid_t, name: String) -> String? {
        if let err = guardTermination(pid: pid, name: name) { return err }
        // Build the full descendant subtree from the live process table, then
        // terminate children first (SIGTERM, then SIGKILL) instead of killing
        // an unrelated process group.
        var doomed = Set<pid_t>([pid])
        var changed = true
        while changed {
            changed = false
            for proc in processes where doomed.contains(proc.ppid) {
                if doomed.insert(proc.pid).inserted { changed = true }
            }
        }
        for p in doomed where p != pid {
            kill(p, SIGTERM)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            var failed = false
            for p in doomed {
                if kill(p, SIGKILL) != 0 && errno != ESRCH {
                    failed = true
                }
            }
            if failed {
                self.actionError = "Some processes in the tree could not be ended (permission denied or already exited)."
            }
        }
        return nil
    }

    @MainActor
    func signalProcess(pid: pid_t, name: String, signal: Int32) -> String? {
        if let err = guardTermination(pid: pid, name: name) { return err }
        return checkedSignal(pid: pid, signal: signal)
    }

    @MainActor
    func setProcessPriority(pid: pid_t, priority: Int32) -> String? {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if pid == selfPID { return "Refusing to change the priority of Task Manager itself." }
        if setpriority(PRIO_PROCESS, id_t(pid), priority) != 0 {
            let code = errno
            if code == EPERM {
                return "Permission denied. This process may be protected or owned by another user."
            }
            if code == ESRCH {
                return "Process no longer exists."
            }
            return "Unable to change priority (\(String(cString: strerror(code))))."
        }
        return nil
    }

    @MainActor
    func setEfficiencyMode(_ enabled: Bool) {
        let priority: Int32 = enabled ? 10 : 0
        var failed = false
        for proc in processes where appPIDs.contains(proc.pid) {
            if setpriority(PRIO_PROCESS, id_t(proc.pid), priority) != 0, errno != EPERM {
                failed = true
            }
        }
        if failed {
            actionError = "Some app processes could not be updated (permission denied)."
        }
    }

    private func guardTermination(pid: pid_t, name: String) -> String? {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if pid == selfPID {
            return "Refusing to end Task Manager itself."
        }
        if pid <= 1 {
            return "Refusing to end a system-critical process."
        }
        if Self.criticalProcessNames.contains(name) {
            return "Refusing to end critical system process \"\(name)\"."
        }
        return nil
    }

    private func checkedSignal(pid: pid_t, signal: Int32) -> String? {
        if kill(pid, signal) != 0 {
            let code = errno
            if code == ESRCH {
                return "Process no longer exists."
            }
            if code == EPERM {
                return "Permission denied. This process may be protected or owned by another user."
            }
            return "Unable to send signal to process (\(String(cString: strerror(code))))."
        }
        return nil
    }
}
