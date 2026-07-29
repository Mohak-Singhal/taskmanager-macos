import Foundation

struct CPUUsage {
    var system: Double = 0
    var user: Double = 0
    var idle: Double = 0
    var total: Double { user + system }
}

struct MemoryStatus {
    var total: UInt64 = 0
    var active: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var free: UInt64 = 0
    var cached: UInt64 = 0
    var used: UInt64 = 0
    var appMemory: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0
}

struct NetworkIface: Identifiable {
    var id: String { name }
    var name: String
    var displayName: String
    var ipAddress: String
    var ipv6Address: String = "N/A"
    var linkSpeed: String = "1.0 Gbps"
    var isWiFi: Bool
    var rxRate: Double = 0
    var txRate: Double = 0
    var signal: Int?
}

struct DiskInfo: Identifiable {
    var id: String { bsdName }
    var device: String
    var bsdName: String
    var name: String
    var isInternal: Bool
    var totalBytes: UInt64 = 0
    var usedBytes: UInt64 = 0
    var readRate: Double = 0
    var writeRate: Double = 0
    var fsType: String = "APFS"
    var mediaType: String = "SSD"
    
    var referenceIORate: Double {
        switch mediaType {
        case "SSD": return 1024.0 * 1024.0 * 1024.0
        case "HDD": return 200.0 * 1024.0 * 1024.0
        case "USB": return 50.0 * 1024.0 * 1024.0
        default: return 500.0 * 1024.0 * 1024.0
        }
    }

    var activeTimePercent: Int {
        let rate = readRate + writeRate
        guard rate > 0 else { return 0 }
        return Int(min((rate / referenceIORate) * 100.0, 100.0))
    }
}

struct MachProcess: Identifiable, Hashable {
    var id: pid_t { pid }
    var pid: pid_t
    var ppid: pid_t = 0
    var uid: uid_t = 0
    var username: String = ""
    var name: String
    var cpu: Double
    var memory: UInt64
    var threads: Int
    
    var diskReadBytes: UInt64 = 0
    var diskWriteBytes: UInt64 = 0
    var diskReadRate: Double = 0
    var diskWriteRate: Double = 0
    
    var networkRxBytes: UInt64 = 0
    var networkTxBytes: UInt64 = 0
    var networkRxRate: Double = 0
    var networkTxRate: Double = 0
    
    var interruptWakeups: UInt64 = 0
    var idleWakeups: UInt64 = 0
    var energyImpact: Double = 0
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
    static func == (lhs: MachProcess, rhs: MachProcess) -> Bool {
        lhs.pid == rhs.pid
    }
}

struct PowerSourceStatus {
    var onAC: Bool = true
    var batteryPercent: Int = 100
    var isCharging: Bool = false
    var timeRemaining: Int = -1
    var timeRemainingString: String = "N/A"
    var powerSourceName: String = "Power Adapter"
    var batteryHealth: String = "Normal"
    var batteryCapacity: Int = 0
    var batteryMaxCapacity: Int = 0
    var batteryWatts: Double = 0
    var batteryAmperage: Int = 0
    var batteryVoltage: Int = 0
    var hasBattery: Bool = false

    var powerDrawString: String {
        if !hasBattery { return "N/A" }
        if batteryWatts < 0.1 { return "0 W" }
        return String(format: "%.1f W", batteryWatts)
    }
}

struct StartupItem: Identifiable {
    var id: String { plistPath }
    var name: String
    var publisher: String
    var status: String // "Enabled" or "Disabled"
    var impact: String // "Low", "Medium", "High"
    var plistPath: String
}

struct LaunchdService: Identifiable {
    var id: String { label }
    var label: String
    var pid: pid_t?
    var status: Int32
    var state: String { pid != nil ? "Running" : "Stopped" }
}

struct AppHistoryItem: Identifiable {
    var id: String { name }
    var name: String
    var cpuTime: Double // in seconds
    var networkBytes: UInt64
}

// Windows-style consumer level memory formatter helper
func formatWinMem(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824.0
    if gb >= 1.0 {
        return String(format: "%.2f GB", gb)
    } else {
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }
}

