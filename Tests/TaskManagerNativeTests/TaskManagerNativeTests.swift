import Testing
import Foundation

@testable import TaskManagerNative

@Test func testFormatWinMemBytes() {
    #expect(formatWinMem(0) == "0 B")
    #expect(formatWinMem(1_048_576) == "1.0 MB")
    #expect(formatWinMem(1_073_741_824) == "1.00 GB")
    #expect(formatWinMem(5_368_709_120) == "5.00 GB")
}

@Test func testFormatWinMemSmall() {
    #expect(formatWinMem(512_000) == "500 KB")
    #expect(formatWinMem(1_024) == "1 KB")
}

@Test func testBytesPerSec() {
    #expect(bytesPerSec(0) == "0 KB/s")
    #expect(bytesPerSec(500) == "500 B/s")
    #expect(bytesPerSec(1024) == "1.0 KB/s")
    #expect(bytesPerSec(1_048_576) == "1.0 MB/s")
}

@Test func testBitsPerSec() {
    #expect(bitsPerSec(0) == "0.0 bps")
    #expect(bitsPerSec(125_000) == "1.0 Mbps")
    #expect(bitsPerSec(125_000_000) == "1.0 Gbps")
}

@Test func testBatteryDescriptionOnAC() {
    let ps = PowerSourceStatus(onAC: true, batteryPercent: 100, hasBattery: true)
    #expect(batteryDescription(ps) == "AC Power")
}

@Test func testBatteryDescriptionCharging() {
    let ps = PowerSourceStatus(onAC: true, batteryPercent: 85, isCharging: true, hasBattery: true)
    #expect(batteryDescription(ps) == "85% (Charging)")
}

@Test func testBatteryDescriptionDischarging() {
    let ps = PowerSourceStatus(onAC: false, batteryPercent: 72, hasBattery: true)
    #expect(batteryDescription(ps) == "Battery 72%")
}

@Test func testBatteryDescriptionNoBattery() {
    let ps = PowerSourceStatus(onAC: true, hasBattery: false)
    #expect(batteryDescription(ps) == "AC Power")
}

@Test func testPowerDrawStringHasValue() {
    let ps = PowerSourceStatus(batteryWatts: 18.5, hasBattery: true)
    #expect(ps.powerDrawString == "18.5 W")
}

@Test func testPowerDrawStringZero() {
    let ps = PowerSourceStatus(batteryWatts: 0, hasBattery: true)
    #expect(ps.powerDrawString == "0 W")
}

@Test func testPowerDrawStringNoBattery() {
    let ps = PowerSourceStatus(hasBattery: false)
    #expect(ps.powerDrawString == "N/A")
}

@Test func testDiskActiveTimePercent() {
    let ssd = DiskInfo(device: "/", bsdName: "disk0", name: "Test SSD", isInternal: true, readRate: 1_073_741_824, writeRate: 0, mediaType: "SSD")
    #expect(ssd.activeTimePercent <= 100)
    #expect(ssd.activeTimePercent > 0)

    let idle = DiskInfo(device: "/", bsdName: "disk1", name: "Idle", isInternal: true, readRate: 0, writeRate: 0, mediaType: "SSD")
    #expect(idle.activeTimePercent == 0)
}

@Test func testAppHistoryItemSorting() {
    let items = [
        AppHistoryItem(name: "A", cpuTime: 100, networkBytes: 1000),
        AppHistoryItem(name: "B", cpuTime: 200, networkBytes: 500)
    ]
    let sorted = items.sorted { $0.cpuTime > $1.cpuTime }
    #expect(sorted[0].name == "B")
}

@Test func testCpuPercentAtOneSecondInterval() {
    // A full core for 1s accumulates 1e9 ns of CPU time == 100%.
    #expect(SystemMonitor.cpuPercent(deltaTicks: 1_000_000_000, elapsedSeconds: 1.0) == 100.0)
    #expect(SystemMonitor.cpuPercent(deltaTicks: 500_000_000, elapsedSeconds: 1.0) == 50.0)
}

@Test func testCpuPercentScalesWithInterval() {
    // Same work over a shorter window must report a higher % per core.
    #expect(SystemMonitor.cpuPercent(deltaTicks: 1_000_000_000, elapsedSeconds: 0.5) == 200.0)
    // ...and over a longer window, a lower % per core.
    #expect(SystemMonitor.cpuPercent(deltaTicks: 1_000_000_000, elapsedSeconds: 4.0) == 25.0)
}

@Test func testCpuPercentZeroElapsed() {
    #expect(SystemMonitor.cpuPercent(deltaTicks: 1000, elapsedSeconds: 0) == 0)
}

@Test func testRatePerSecondScalesWithInterval() {
    #expect(SystemMonitor.ratePerSecond(delta: 1024, elapsedSeconds: 1.0) == 1024)
    #expect(SystemMonitor.ratePerSecond(delta: 1024, elapsedSeconds: 0.5) == 2048)
    #expect(SystemMonitor.ratePerSecond(delta: 1024, elapsedSeconds: 4.0) == 256)
}

@Test func testRatePerSecondZeroElapsed() {
    #expect(SystemMonitor.ratePerSecond(delta: 100, elapsedSeconds: 0) == 0)
}

@Test func testParseNettopLine() {
    // Real nettop -J bytes_in,bytes_out format: name.pid rxVal rxUnit txVal txUnit
    let parsed = SystemMonitor.parseNettopLine("16:54:34.904824 apsd.377 4408 B 64 KiB")
    #expect(parsed?.pid == 377)
    #expect(parsed?.rx == 4408)
    #expect(parsed?.tx == 64 * 1024)
}

@Test func testParseNettopLineDecimalUnits() {
    let parsed = SystemMonitor.parseNettopLine("16:54:34.904824 Safari.1234 1.5 K 2.0 M")
    #expect(parsed?.pid == 1234)
    #expect(parsed?.rx == 1536)
    #expect(parsed?.tx == 2 * 1024 * 1024)
}

@Test func testParseNettopLineTooShort() {
    #expect(SystemMonitor.parseNettopLine("too few") == nil)
    #expect(SystemMonitor.parseNettopLine("") == nil)
}

@Test func testConvertToBytes() {
    #expect(SystemMonitor.convertToBytes(val: 100, unit: "B") == 100)
    #expect(SystemMonitor.convertToBytes(val: 2, unit: "KB") == 2048)
    #expect(SystemMonitor.convertToBytes(val: 1.5, unit: "K") == 1536)
    #expect(SystemMonitor.convertToBytes(val: 2, unit: "MiB") == 2 * 1024 * 1024)
    #expect(SystemMonitor.convertToBytes(val: 1, unit: "G") == 1024 * 1024 * 1024)
}

@Test func testMemoryPressureMapping() {
    let healthy = SystemMonitor.memoryPressure(fromSystemLevel: 100)
    #expect(healthy.percent == 0)
    #expect(healthy.level == "Normal")

    let warning = SystemMonitor.memoryPressure(fromSystemLevel: 32)
    #expect(warning.percent == 68)
    #expect(warning.level == "Warning")

    let critical = SystemMonitor.memoryPressure(fromSystemLevel: 5)
    #expect(critical.percent == 95)
    #expect(critical.level == "Critical")

    let extreme = SystemMonitor.memoryPressure(fromSystemLevel: 0)
    #expect(extreme.percent == 100)
    #expect(extreme.level == "Critical")
}

@Test func testMemoryPressureFallback() {
    #expect(SystemMonitor.memoryPressure(fromUsedPct: 90).level == "Critical")
    #expect(SystemMonitor.memoryPressure(fromUsedPct: 60).level == "Warning")
    #expect(SystemMonitor.memoryPressure(fromUsedPct: 10).level == "Normal")
}

@Test func testParseLaunchctlLine() {
    let running = SystemMonitor.parseLaunchctlLine("123\t0\tcom.apple.Finder")
    #expect(running?.pid == 123)
    #expect(running?.status == 0)
    #expect(running?.label == "com.apple.Finder")

    let stopped = SystemMonitor.parseLaunchctlLine("-\t78\tcom.apple.unknown")
    #expect(stopped?.pid == nil)
    #expect(stopped?.status == 78)
    #expect(stopped?.label == "com.apple.unknown")

    #expect(SystemMonitor.parseLaunchctlLine("not enough fields") == nil)
}
