import Foundation
import Darwin
import IOKit
import IOKit.ps
import DiskArbitration
import AppKit

let PROC_INFO: Int32 = 17

@MainActor
class SystemMonitor: ObservableObject {
    @Published var cpuUsage = CPUUsage()
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var memory = MemoryStatus()
    @Published var memoryHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var disks: [DiskInfo] = []
    @Published var diskHistory: [String: [Double]] = [:]
    @Published var networkIfaces: [NetworkIface] = []
    @Published var networkTotalRxRate: Double = 0
    @Published var networkTotalTxRate: Double = 0
    @Published var networkRxHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var networkTxHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var processes: [MachProcess] = []
    @Published var uptime: time_t = 0
    @Published var cpuBrand = ""
    @Published var cpuCores = 0
    @Published var cpuPhysicalCores = 0
    @Published var l1Cache = "N/A"
    @Published var l2Cache = "N/A"
    @Published var l3Cache = "N/A"
    @Published var baseSpeed = "N/A"
    @Published var cpuSockets = 1
    @Published var totalHandles = 0
    @Published var gpuUsage: Double = 0.0
    @Published var gpuHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published var virtualizationEnabled = false
    
    @Published var powerSource = PowerSourceStatus()
    @Published var systemEnergyImpact: Double = 0
    @Published var energyImpactHistory: [Double] = Array(repeating: 0, count: 60)
    
    var cpuSpeedString: String {
        let speedStr = baseSpeed.replacingOccurrences(of: " GHz", with: "").replacingOccurrences(of: " MHz", with: "")
        guard let base = Double(speedStr) else { return baseSpeed.isEmpty ? "2.40 GHz" : baseSpeed }
        let active = base * (0.6 + 0.4 * (cpuUsage.total / 100.0))
        return String(format: "%.2f GHz", active)
    }
    
    // Additional tabs data
    @Published var startupItems: [StartupItem] = []
    @Published var services: [LaunchdService] = []
    @Published var appHistory: [AppHistoryItem] = []

    private var prevCPU = CPUAbsoluteTicks()
    private var prevDiskRead: [String: UInt64] = [:]
    private var prevDiskWrite: [String: UInt64] = [:]
    var diskReadHistory: [String: [Double]] = [:]
    var diskWriteHistory: [String: [Double]] = [:]
    private var prevNet: [String: (rx: UInt64, tx: UInt64)] = [:]
    
    private var prevProcessCPU: [pid_t: UInt64] = [:]
    private var prevProcessDisk: [pid_t: (read: UInt64, write: UInt64)] = [:]
    private var prevProcessWakeups: [pid_t: (interrupt: UInt64, idle: UInt64)] = [:]
    private var processNetBytes: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
    private var prevProcessNet: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
    private var usernameCache: [uid_t: String] = [:]
    private var historyMap: [String: (cpu: Double, net: UInt64)] = [:]
    
    private var tickCount = 0
    /// Maps logical APFS disk numbers (e.g. "disk3") to their physical NVMe drive (e.g. "disk0")
    private var diskBSDMapping: [String: String] = [:]

    struct CPUAbsoluteTicks { var system: UInt64 = 0; var user: UInt64 = 0; var idle: UInt64 = 0; var nice: UInt64 = 0 }

    private var timer: Timer?
    private var cachedWiFiRSSI: Int? = -50
    @Published var updateInterval: Double = 1.0

    // Window behaviour toggles (bound from native menu bar)
    @Published var alwaysOnTop: Bool = false
    @Published var minimizeOnUse: Bool = false
    @Published var hideWhenMinimized: Bool = false

    init() {
        self.diskBSDMapping = buildDiskBSDMapping()
        loadCPUInfo()
        tick()
        pollStartupItems()
        pollServices()
        startBackgroundNetworkMonitor()
        startWiFiMonitor()
        setupTimer()
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
        setupTimer()
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        self.alwaysOnTop = enabled
        // Apply the window level immediately
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
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            }
        }
    }

    nonisolated private func queryWiFiSignalDirect() -> Int? {
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
        
        // Read Cache Sizes
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
        
        // Determine base speed
        let brand = cpuBrand.lowercased()
        if brand.contains("m1") {
            baseSpeed = "3.20 GHz"
        } else if brand.contains("m2") {
            baseSpeed = "3.49 GHz"
        } else if brand.contains("m3") {
            baseSpeed = "4.05 GHz"
        } else if brand.contains("m4") {
            baseSpeed = "4.40 GHz"
        } else {
            // Try to parse speed from brand string like "Intel(R) Core(TM) i7-10700K CPU @ 3.80GHz"
            let pattern = "@\\s*([0-9.]+)\\s*(GHz|MHz)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: cpuBrand, options: [], range: NSRange(location: 0, length: cpuBrand.utf16.count)),
               let speedRange = Range(match.range(at: 1), in: cpuBrand),
               let unitRange = Range(match.range(at: 2), in: cpuBrand) {
                baseSpeed = "\(cpuBrand[speedRange]) \(cpuBrand[unitRange])"
            } else {
                baseSpeed = "2.40 GHz"
            }
        }
        
        var hvSupport: Int32 = 0
        var hvSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.hv_support", &hvSupport, &hvSize, nil, 0) == 0 {
            virtualizationEnabled = (hvSupport == 1)
        } else {
            virtualizationEnabled = false
        }
    }

    func tick() {
        pollCPU()
        pollMemory()
        pollDisks()
        pollDiskIO()
        pollNetwork()
        pollProcesses()
        pollUptime()
        pollGPU()
        pollPowerSource()
        
        // Poll open handles
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

    // MARK: - CPU

    private func pollCPU() {
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        var n: natural_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count)
        guard kr == KERN_SUCCESS, let ptr = info else { return }

        let load = UnsafeBufferPointer(start: ptr, count: Int(count))
        var sys: UInt64 = 0; var usr: UInt64 = 0; var idle: UInt64 = 0; var nice: UInt64 = 0
        for i in 0..<Int(n) {
            let offset = i * 4
            if offset + 3 < Int(count) {
                usr += UInt64(load[offset + 0])
                sys += UInt64(load[offset + 1])
                idle += UInt64(load[offset + 2])
                nice += UInt64(load[offset + 3])
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: ptr), vm_size_t(count * UInt32(MemoryLayout<integer_t>.size)))

        let cur = CPUAbsoluteTicks(system: sys, user: usr, idle: idle, nice: nice)
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
    }

    // MARK: - Memory

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
        
        // App Memory = active + inactive + speculative - external - purgeable (matches Activity Monitor)
        let totalResident = active + inactive + speculative
        let appMemory = (totalResident >= (external + purgeable)) ? (totalResident - external - purgeable) : active
        
        // Cached Files = external + purgeable (matches Activity Monitor)
        let cached = external + purgeable
        
        // Memory Used = Total Physical Memory - Free Memory - Cached Files (matches Activity Monitor)
        let used = total >= (free + cached) ? (total - free - cached) : (appMemory + wired + compressed)

        memory = MemoryStatus(
            total: total,
            active: appMemory,
            wired: wired,
            compressed: compressed,
            free: free,
            cached: cached,
            used: used,
            appMemory: appMemory
        )

        var usage = xsw_usage()
        var s = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &s, nil, 0) == 0 {
            memory.swapTotal = usage.xsu_total
            memory.swapUsed = usage.xsu_used
        }
        memoryHistory = Array(memoryHistory.dropFirst()) + [(total > 0 ? Double(used)/Double(total)*100 : 0)]
    }

    // MARK: - Disk capacity

    /// Runs once at startup. Resolves APFS logical volumes (e.g. disk3) to their
    /// underlying physical disk (e.g. disk0) by querying `diskutil info`.
    nonisolated private func buildDiskBSDMapping() -> [String: String] {
        var mapping: [String: String] = [:]
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return mapping }
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsInternalKey],
            options: [.skipHiddenVolumes]
        ) else { return mapping }

        for url in volumes {
            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL) else { continue }
            // Get the BSD name of this volume (e.g. disk3s1s1)
            guard let descRaw = DADiskCopyDescription(disk) as? [CFString: Any],
                  let volBSD = descRaw[kDADiskDescriptionMediaBSDNameKey] as? String else { continue }
            let volDisk = stripToDiskNumber(volBSD) // e.g. "disk3"

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

    nonisolated private func stripToDiskNumber(_ bsd: String) -> String {
        guard bsd.hasPrefix("disk") else { return bsd }
        let digits = bsd.dropFirst(4).prefix(while: { $0.isNumber })
        return "disk" + digits
    }

    /// Runs `diskutil info -plist <disk>` and returns ParentWholeDisk or APFS Physical Store.
    nonisolated private func diskutilPhysicalParent(of disk: String) -> String? {
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
        
        // 1. Check for APFS container physical store
        if let stores = plist["APFSPhysicalStores"] as? [[String: Any]],
           let firstStore = stores.first?["APFSPhysicalStore"] as? String {
            return stripToDiskNumber(firstStore)
        }
        
        // 2. Check for standard parent disk
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
        // Resolve APFS container to physical disk (e.g. disk3 → disk0 on Apple Silicon)
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
            
            // Determine media type label
            let mediaType: String
            if isRemovable {
                mediaType = "USB"
            } else {
                mediaType = isInternal ? "SSD" : "External"
            }

            // Use real volume name when available; fall back to a clean generated label
            let rawVolumeName = values.volumeName ?? ""
            let displayName: String
            if isInternal {
                displayName = rawVolumeName.isEmpty ? "Internal SSD" : rawVolumeName
            } else {
                // External: prefer real volume name, otherwise build a clean label
                if !rawVolumeName.isEmpty && rawVolumeName != "No name" {
                    displayName = rawVolumeName
                } else if isRemovable {
                    displayName = "USB Drive (\(fsType))"
                } else {
                    displayName = "External Drive (\(fsType))"
                }
            }
            
            let bsd = diskBSDName(for: url.path)
            
            // To prevent duplicates if multiple volumes mount on the same physical disk,
            // we update/aggregate capacity or keep the primary volume.
            if let idx = result.firstIndex(where: { $0.bsdName == bsd }) {
                // If it is the system disk (mounted on /), prioritize its details, otherwise keep existing
                if url.path == "/" {
                    result[idx] = DiskInfo(device: url.path, bsdName: bsd, name: displayName, isInternal: isInternal, totalBytes: total, usedBytes: total - available, readRate: diskReadHistory[bsd]?.last ?? 0, writeRate: diskWriteHistory[bsd]?.last ?? 0, fsType: fsType, mediaType: mediaType)
                }
            } else {
                result.append(DiskInfo(device: url.path, bsdName: bsd, name: displayName, isInternal: isInternal, totalBytes: total, usedBytes: total - available, readRate: diskReadHistory[bsd]?.last ?? 0, writeRate: diskWriteHistory[bsd]?.last ?? 0, fsType: fsType, mediaType: mediaType))
            }
        }
        disks = result
    }

    // MARK: - Disk I/O (via IOKit)

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
        
        for (name, bytes) in current {
            let prevRead = prevDiskRead[name] ?? 0
            let prevWrite = prevDiskWrite[name] ?? 0
            
            // Only compute delta if we've seen this disk before (prevDiskRead has entry)
            let hasSeenBefore = prevDiskRead[name] != nil
            let readRate = hasSeenBefore && bytes.read >= prevRead ? Double(bytes.read - prevRead) : 0
            let writeRate = hasSeenBefore && bytes.write >= prevWrite ? Double(bytes.write - prevWrite) : 0
            
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
    }

    // MARK: - Network

    private func pollNetwork() {
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let head = ptr else { return }
        defer { freeifaddrs(head) }

        var byName: [String: (ip4: String, ip6: String, isWiFi: Bool)] = [:]
        var curData: [String: (rx: UInt64, tx: UInt64)] = [:]

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let p = cursor {
            let name = String(cString: p.pointee.ifa_name)
            let flags = Int32(p.pointee.ifa_flags)
            if name != "en0" && name != "en1" {
                cursor = p.pointee.ifa_next; continue
            }
            if (flags & IFF_UP) == 0 || (flags & IFF_RUNNING) == 0 {
                cursor = p.pointee.ifa_next; continue
            }

            let addr = p.pointee.ifa_addr.pointee
            if addr.sa_family == AF_INET || addr.sa_family == AF_INET6 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(p.pointee.ifa_addr, socklen_t(addr.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ipStr = String(decoding: Data(bytes: host, count: strnlen(host, host.count)), as: UTF8.self)
                    let currentInfo = byName[name] ?? ("", "", name == "en0")
                    if addr.sa_family == AF_INET {
                        byName[name] = (ipStr, currentInfo.ip6, currentInfo.isWiFi)
                    } else if addr.sa_family == AF_INET6 {
                        let strippedIp = ipStr.components(separatedBy: "%").first ?? ipStr
                        byName[name] = (currentInfo.ip4, strippedIp, currentInfo.isWiFi)
                    }
                }
            }
            if addr.sa_family == AF_LINK, let data = p.pointee.ifa_data {
                let ld = data.assumingMemoryBound(to: if_data.self).pointee
                curData[name] = (UInt64(ld.ifi_ibytes), UInt64(ld.ifi_obytes))
            }
            cursor = p.pointee.ifa_next
        }

        var ifaces: [NetworkIface] = []
        var totalRx: Double = 0; var totalTx: Double = 0
        for (name, info) in byName {
            guard let c = curData[name] else { continue }
            let p = prevNet[name] ?? c
            let rxRate = c.rx >= p.rx ? Double(c.rx - p.rx) : 0
            let txRate = c.tx >= p.tx ? Double(c.tx - p.tx) : 0
            totalRx += rxRate; totalTx += txRate
            var sig: Int?
            if info.isWiFi { sig = cachedWiFiRSSI }
            
            let ip4 = info.ip4.isEmpty ? "N/A" : info.ip4
            let ip6 = info.ip6.isEmpty ? "N/A" : info.ip6
            let linkSpeed = info.isWiFi ? "866 Mbps" : "1.0 Gbps"
            
            ifaces.append(NetworkIface(name: name, displayName: info.isWiFi ? "Wi-Fi" : "Ethernet", ipAddress: ip4, ipv6Address: ip6, linkSpeed: linkSpeed, isWiFi: info.isWiFi, rxRate: rxRate, txRate: txRate, signal: sig))
            prevNet[name] = c
        }
        networkIfaces = ifaces
        networkTotalRxRate = totalRx
        networkTotalTxRate = totalTx
        networkRxHistory = Array(networkRxHistory.dropFirst()) + [totalRx]
        networkTxHistory = Array(networkTxHistory.dropFirst()) + [totalTx]
    }


    // MARK: - Processes

    private func getCachedUsername(uid: uid_t) -> String {
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
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(count))
        proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))

        var newPrev: [pid_t: UInt64] = [:]
        var nextProcessDisk: [pid_t: (read: UInt64, write: UInt64)] = [:]
        var result: [MachProcess] = []
        
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

            let totalTicks = ti.pti_total_user + ti.pti_total_system
            newPrev[pid] = totalTicks

            let pct: Double
            if let prev = prevProcessCPU[pid], totalTicks > prev {
                pct = Double(totalTicks - prev) / 10_000_000.0
            } else {
                pct = 0
            }

            // Disk I/O
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
                    diskReadRate = diskReadBytes >= prevDisk.read ? Double(diskReadBytes - prevDisk.read) : 0
                    diskWriteRate = diskWriteBytes >= prevDisk.write ? Double(diskWriteBytes - prevDisk.write) : 0
                }
                nextProcessDisk[pid] = (read: diskReadBytes, write: diskWriteBytes)

                interruptWakeups = rusage.ri_interrupt_wkups
                idleWakeups = rusage.ri_pkg_idle_wkups

                if let prevWake = prevProcessWakeups[pid] {
                    let dInt = interruptWakeups >= prevWake.interrupt ? Double(interruptWakeups - prevWake.interrupt) : 0
                    let dIdle = idleWakeups >= prevWake.idle ? Double(idleWakeups - prevWake.idle) : 0
                    energyImpact = dInt * 0.01 + dIdle * 0.005 + pct * 0.1
                    energyImpact = max(0, energyImpact)
                }
                prevProcessWakeups[pid] = (interrupt: interruptWakeups, idle: idleWakeups)
            }

            // Network I/O
            var netRxRate: Double = 0
            var netTxRate: Double = 0
            var netRxBytes: UInt64 = 0
            var netTxBytes: UInt64 = 0
            
            if let netBytes = processNetBytes[pid] {
                netRxBytes = netBytes.rx
                netTxBytes = netBytes.tx
                
                if let prevNet = prevProcessNet[pid] {
                    netRxRate = netRxBytes >= prevNet.rx ? Double(netRxBytes - prevNet.rx) : 0
                    netTxRate = netTxBytes >= prevNet.tx ? Double(netTxBytes - prevNet.tx) : 0
                }
                prevProcessNet[pid] = netBytes
            }

            result.append(MachProcess(
                pid: pid,
                ppid: ppid,
                uid: uid,
                username: username,
                name: name,
                cpu: pct,
                memory: ti.pti_resident_size,
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
                energyImpact: energyImpact
            ))
        }
        prevProcessCPU = newPrev
        prevProcessDisk = nextProcessDisk
        processes = result
        
        let totalEnergy = result.reduce(0.0) { $0 + $1.energyImpact }
        systemEnergyImpact = totalEnergy
        energyImpactHistory = Array(energyImpactHistory.dropFirst()) + [totalEnergy]
        
        updateAppHistory(processes: result)
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

    // MARK: - Power Source

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
        if timeRemaining == -1 {
            timeStr = "Calculating..."
        } else if timeRemaining == -2 || onAC {
            timeStr = "N/A"
        } else if timeRemaining > 0 {
            let h = timeRemaining / 3600
            let m = (timeRemaining % 3600) / 60
            timeStr = h > 0 ? "\(h):\(String(format: "%02d", m)) remaining" : "\(m) min remaining"
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
        let watts = abs(Double(amperage)) * Double(voltage) / 1_000_000_000.0

        return (amperage, voltage, watts)
    }

    // MARK: - Startup Items (LaunchAgents & LaunchDaemons)
 
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
                    
                    items.append(StartupItem(name: label, publisher: publisher, status: status, impact: impact, plistPath: fullPath))
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
            print("Plist not writable: \(item.plistPath)")
            return
        }
        
        guard var dict = NSMutableDictionary(contentsOfFile: item.plistPath) as? [String: Any] else { return }
        let currentDisabled = dict["Disabled"] as? Bool ?? false
        dict["Disabled"] = !currentDisabled
        
        let nsDict = dict as NSDictionary
        nsDict.write(toFile: item.plistPath, atomically: true)
        
        pollStartupItems()
    }
 
    // MARK: - Services (launchd services)
 
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
                    let parts = line.components(separatedBy: "\t")
                    guard parts.count >= 3 else { continue }
                    
                    let pidStr = parts[0]
                    let statusStr = parts[1]
                    let label = parts[2]
                    
                    let pid = pid_t(pidStr)
                    let status = Int32(statusStr) ?? 0
                    
                    list.append(LaunchdService(label: label, pid: pid, status: status))
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
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["start", service.label]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.pollServices()
        }
    }

    func stopService(_ service: LaunchdService) {
        let p = Process()
        p.launchPath = "/bin/launchctl"
        p.arguments = ["stop", service.label]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.pollServices()
        }
    }

    // MARK: - App History tracking

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
        
        appHistory = historyMap.map { (key, value) in
            AppHistoryItem(name: key, cpuTime: value.cpu, networkBytes: value.net)
        }.sorted { $0.cpuTime > $1.cpuTime }
    }

    // MARK: - Background Network Monitor

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
        process.arguments = ["-J", "bytes_in,bytes_out", "-l", "1"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return }
                  
            var newNetBytes: [pid_t: (rx: UInt64, tx: UInt64)] = [:]
            for line in output.components(separatedBy: "\n") {
                if let parsed = parseNettopLine(line) {
                    newNetBytes[parsed.pid] = (rx: parsed.rx, tx: parsed.tx)
                }
            }
            
            let selfRef = self
            Task { @MainActor in
                for (pid, bytes) in newNetBytes {
                    selfRef.processNetBytes[pid] = bytes
                }
            }
        } catch {
            print("Failed to run nettop: \(error)")
        }
    }

    nonisolated private func parseNettopLine(_ line: String) -> (pid: pid_t, rx: UInt64, tx: UInt64)? {
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

    nonisolated private func convertToBytes(val: Double, unit: String) -> UInt64 {
        let u = unit.lowercased()
        if u.hasPrefix("k") { return UInt64(val * 1024) }
        if u.hasPrefix("m") { return UInt64(val * 1024 * 1024) }
        if u.hasPrefix("g") { return UInt64(val * 1024 * 1024 * 1024) }
        return UInt64(val)
    }
}

extension UInt64 {
    func clampedSub(_ other: UInt32) -> UInt64 {
        let other64 = UInt64(other)
        return self > other64 ? self - other64 : 0
    }
    func clampedSub(_ other: UInt64) -> UInt64 {
        return self > other ? self - other : 0
    }
}
