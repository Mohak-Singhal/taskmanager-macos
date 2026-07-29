import Testing
import Foundation

@testable import TaskManagerNative

@Test func testFormatWinMemBytes() {
    #expect(formatWinMem(0) == "0.0 MB")
    #expect(formatWinMem(1_048_576) == "1.0 MB")
    #expect(formatWinMem(1_073_741_824) == "1.00 GB")
    #expect(formatWinMem(5_368_709_120) == "5.00 GB")
}

@Test func testFormatWinMemSmall() {
    #expect(formatWinMem(512_000) == "0.5 MB")
    #expect(formatWinMem(1_024) == "0.0 MB")
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
