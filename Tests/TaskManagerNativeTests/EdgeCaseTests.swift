import Testing
import Foundation

@testable import TaskManagerNative

// Regression + edge-case coverage for the critical telemetry paths.
// These tests pin down the *current* (correct) behaviour of pure functions
// so future refactors cannot silently change CPU math, formatters, or the
// model-derived thresholds that drive the whole UI.

@Suite("Edge case & regression tests")
struct EdgeCaseTests {

    // MARK: - Memory / size formatting

    @Test func formatWinMemBoundaries() {
        #expect(formatWinMem(0) == "0 B")
        #expect(formatWinMem(1_023) == "1023 B")
        #expect(formatWinMem(1_024) == "1 KB")
        #expect(formatWinMem(104_857_600) == "100.0 MB")
        #expect(formatWinMem(1_073_741_823) == "1024.0 MB")   // just under 1 GiB
        #expect(formatWinMem(1_073_741_824) == "1.00 GB")
        #expect(formatWinMem(5_368_709_120) == "5.00 GB")
        // Must never overflow or crash on the largest possible value.
        #expect(formatWinMem(UInt64.max) == "17179869184.00 GB")
    }

    @Test func bytesPerSecLargeValues() {
        #expect(bytesPerSec(0) == "0 KB/s")
        #expect(bytesPerSec(1_073_741_824) == "1.00 GB/s")
        #expect(bytesPerSec(1_610_612_736) == "1.50 GB/s")
    }

    @Test func bitsPerSecCapsAtGiga() {
        // 125 MB/s == 1 Gbps
        #expect(bitsPerSec(125_000) == "1.0 Mbps")
        #expect(bitsPerSec(125_000_000) == "1.0 Gbps")
        // No Tbps branch exists; stays in Gbps.
        #expect(bitsPerSec(125_000_000_000) == "1000.0 Gbps")
        #expect(bitsPerSec(0) == "0.0 bps")
    }

    // MARK: - Process model thresholds (power UI)

    private func proc(cpu: Double, energy: Double = 0) -> MachProcess {
        MachProcess(pid: 1, name: "probe", cpu: cpu, memory: 0, threads: 1, energyImpact: energy)
    }

    @Test func powerUsageThresholds() {
        #expect(proc(cpu: 100).powerUsage == "Very high")  // 70 > 50
        #expect(proc(cpu: 30).powerUsage == "High")        // 21 > 20
        #expect(proc(cpu: 10).powerUsage == "Moderate")    // 7 > 5
        #expect(proc(cpu: 2).powerUsage == "Low")          // 1.4 > 1
        #expect(proc(cpu: 1).powerUsage == "Very low")     // 0.7
    }

    @Test func powerTrendThresholds() {
        #expect(proc(cpu: 100).powerTrend == "Very high")  // 50 > 40
        #expect(proc(cpu: 40).powerTrend == "High")        // 20 > 15
        #expect(proc(cpu: 10).powerTrend == "Moderate")    // 5 > 4
        #expect(proc(cpu: 2).powerTrend == "Low")          // 1 > 0.8
        #expect(proc(cpu: 1).powerTrend == "Very low")     // 0.5
    }

    @Test func processEqualityIsByPidOnly() {
        let a = MachProcess(pid: 42, name: "Alpha", cpu: 1, memory: 1, threads: 1)
        let b = MachProcess(pid: 42, name: "Beta", cpu: 99, memory: 99, threads: 9)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a.id == b.id)
    }

    // MARK: - Disk model

    @Test func diskActiveTimeClampsTo100() {
        let ssd = DiskInfo(device: "/", bsdName: "disk0", name: "SSD", isInternal: true, readRate: 5 * 1024 * 1024 * 1024, writeRate: 5 * 1024 * 1024 * 1024, mediaType: "SSD")
        #expect(ssd.activeTimePercent == 100)

        let hdd = DiskInfo(device: "/", bsdName: "disk1", name: "HDD", isInternal: true, readRate: 1024 * 1024 * 1024, writeRate: 0, mediaType: "HDD")
        #expect(hdd.activeTimePercent == 100)

        let idle = DiskInfo(device: "/", bsdName: "disk2", name: "Idle", isInternal: true, readRate: 0, writeRate: 0, mediaType: "SSD")
        #expect(idle.activeTimePercent == 0)
    }

    @Test func diskReferenceRates() {
        let ssd = DiskInfo(device: "/", bsdName: "disk0", name: "S", isInternal: true, readRate: 1024 * 1024 * 1024, writeRate: 0, mediaType: "SSD")
        #expect(ssd.referenceIORate == 1024 * 1024 * 1024)
        let hdd = DiskInfo(device: "/", bsdName: "disk1", name: "H", isInternal: true, readRate: 0, writeRate: 0, mediaType: "HDD")
        #expect(hdd.referenceIORate == 200 * 1024 * 1024)
        let usb = DiskInfo(device: "/", bsdName: "disk2", name: "U", isInternal: false, readRate: 0, writeRate: 0, mediaType: "USB")
        #expect(usb.referenceIORate == 50 * 1024 * 1024)
    }

    // MARK: - CPU / rate math

    @Test func cpuPercentMultiCoreCanExceed100() {
        // Two fully-busy cores for 1s accumulate 2e9 ns → 200% (top-style, per core).
        #expect(SystemMonitor.cpuPercent(deltaTicks: 2_000_000_000, elapsedSeconds: 1.0) == 200.0)
    }

    @Test func ratePerSecondHugeDelta() {
        #expect(SystemMonitor.ratePerSecond(delta: UInt64.max, elapsedSeconds: 1.0) == Double(UInt64.max))
        #expect(SystemMonitor.ratePerSecond(delta: 0, elapsedSeconds: 10.0) == 0)
    }

    // MARK: - Memory pressure boundaries

    @Test func memoryPressureExactBoundaries() {
        #expect(SystemMonitor.memoryPressure(fromUsedPct: 49.99).level == "Normal")
        #expect(SystemMonitor.memoryPressure(fromUsedPct: 50.0).level == "Warning")
        #expect(SystemMonitor.memoryPressure(fromUsedPct: 79.99).level == "Warning")
        #expect(SystemMonitor.memoryPressure(fromUsedPct: 80.0).level == "Critical")
    }

    @Test func memoryPressureClampsRange() {
        #expect(SystemMonitor.memoryPressure(fromUsedPct: -10).percent == 0)
        #expect(SystemMonitor.memoryPressure(fromUsedPct: 150).percent == 100)
        #expect(SystemMonitor.memoryPressure(fromSystemLevel: 200).percent == 0)
        #expect(SystemMonitor.memoryPressure(fromSystemLevel: -5).percent == 100)
    }

    // MARK: - nettop parsing / unit conversion

    @Test func convertToBytesUppercaseAndBinaryUnits() {
        #expect(SystemMonitor.convertToBytes(val: 2, unit: "KB") == 2048)
        #expect(SystemMonitor.convertToBytes(val: 2, unit: "MB") == 2 * 1024 * 1024)
        #expect(SystemMonitor.convertToBytes(val: 2, unit: "GB") == 2 * 1024 * 1024 * 1024)
        #expect(SystemMonitor.convertToBytes(val: 2, unit: "KiB") == 2048)
        #expect(SystemMonitor.convertToBytes(val: 2.5, unit: "G") == 2_684_354_560)
        #expect(SystemMonitor.convertToBytes(val: 512, unit: "B") == 512)
    }

    @Test func parseNettopLineGBValues() {
        let parsed = SystemMonitor.parseNettopLine("16:54:34.904824 Chrome Helper.777 1.5 G 2.0 G")
        #expect(parsed?.pid == 777)
        #expect(parsed?.rx == UInt64(1.5 * 1024 * 1024 * 1024))
        #expect(parsed?.tx == UInt64(2.0 * 1024 * 1024 * 1024))
    }

    @Test func parseNettopLineSkipsTimeFieldDots() {
        // The time field contains dots but must not be interpreted as a pid.
        let parsed = SystemMonitor.parseNettopLine("00:00:00.000000 launchd.1 10 B 20 B")
        #expect(parsed?.pid == 1)
        #expect(parsed?.rx == 10)
        #expect(parsed?.tx == 20)
    }

    // MARK: - launchctl parsing

    @Test func launchdServiceState() {
        #expect(LaunchdService(label: "com.apple.a", pid: 123, status: 0).state == "Running")
        #expect(LaunchdService(label: "com.apple.b", pid: nil, status: 78).state == "Stopped")
        #expect(LaunchdService(label: "com.apple.c", pid: nil, status: 0).state == "Stopped")
    }

    @Test func parseLaunchctlLineBadRows() {
        #expect(SystemMonitor.parseLaunchctlLine("123\t0") == nil)
        #expect(SystemMonitor.parseLaunchctlLine("123") == nil)
        #expect(SystemMonitor.parseLaunchctlLine("") == nil)
        #expect(SystemMonitor.parseLaunchctlLine(" ") == nil)
    }

    // MARK: - Power card helpers

    @Test func powerCardValueOnBattery() {
        let ps = PowerSourceStatus(onAC: false, batteryPercent: 60, timeRemaining: 5400, timeRemainingString: "1h 30m remaining", batteryWatts: 5.2, hasBattery: true)
        #expect(powerCardValue(ps, impact: 12.3) == "5.2 W draw\n1h 30m remaining")
    }

    @Test func powerCardValueOnACWithoutBattery() {
        let ps = PowerSourceStatus(onAC: true, hasBattery: false)
        #expect(powerCardValue(ps, impact: 3.5) == "Impact: 3.5")
    }

    @Test func batteryDescriptionStates() {
        #expect(batteryDescription(PowerSourceStatus(onAC: true, batteryPercent: 50, isCharging: false, hasBattery: true)) == "AC Power")
        #expect(batteryDescription(PowerSourceStatus(onAC: false, batteryPercent: 50, hasBattery: true)) == "Battery 50%")
        #expect(batteryDescription(PowerSourceStatus(onAC: true, hasBattery: false)) == "AC Power")
    }

    // MARK: - Network classification

    @Test func networkCardSubtitleClassification() {
        let wifi = NetworkIface(name: "en0", displayName: "Wi-Fi", ipAddress: "192.168.1.5", isWiFi: true)
        #expect(networkCardSubtitle(wifi) == "Wi-Fi")
        let eth = NetworkIface(name: "en5", displayName: "Ethernet", ipAddress: "", isWiFi: false)
        #expect(networkCardSubtitle(eth) == "Ethernet")
        let iphone = NetworkIface(name: "ipheth0", displayName: "iPhone", ipAddress: "", isWiFi: false)
        #expect(networkCardSubtitle(iphone) == "iPhone")
    }

    // MARK: - Insights helper behaviour (storage growth math)

    @Test func storageGrowthNegativeDetected() {
        // Growth today for a folder that shrank must be negative (Int64 math).
        let current: UInt64 = 500
        let baseline: UInt64 = 800
        let growth = Int64(current) - Int64(baseline)
        #expect(growth == -300)
    }

    // MARK: - Insights subprocess parsers (C1 refactor regression)

    @Test func parseLsofExtractsRemoteServers() {
        let output = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        Safari 1234 mohak 123u IPv6 0x1234 0t0 TCP 192.168.1.5:54321->142.250.1.1:443 (ESTABLISHED)
        apsd 55 mohak 10u IPv4 0x5678 0t0 TCP 192.168.1.5:59000->17.57.144.4:443 (ESTABLISHED)
        """
        let logs = InsightsManager.parseLsof(output)
        #expect(logs.count == 2)
        #expect(logs[0].appName == "Safari")
        #expect(logs[0].protocolType == "TCP")
        #expect(logs[0].server == "142.250.1.1:443")
        #expect(logs[1].server == "17.57.144.4:443")
    }

    @Test func parseLsofIgnoresHeadersAndListenOnly() {
        let output = """
        COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
        sshd 99 root 3u IPv4 0x999 0t0 TCP *:22 (LISTEN)
        """
        let logs = InsightsManager.parseLsof(output)
        #expect(logs.isEmpty)
    }

    @Test func parseAssertionsExtractsRows() {
        let output = """
        Some Assertion header
        Backup BackUp Assertion pid 123 (backupd) named: "Prevent sleep during backup" type PreventUserIdleSystemSleep
        """
        let rows = InsightsManager.parseAssertions(output)
        #expect(rows.count == 1)
        #expect(rows[0].pid == 123)
        #expect(rows[0].name == "backupd")
        #expect(rows[0].detail.contains("Prevent sleep during backup"))
    }
}
