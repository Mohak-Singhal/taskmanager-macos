import Testing
import Foundation

@testable import TaskManagerNative

// Known-bug reproduction tests.
//
// These now PASS because the underlying defects were fixed (BUG-13 and BUG-17).
// Keep them enabled as regression guards; see AUDIT_REPORT.md for context.

@Suite("Bug reproduction & regression tests")
struct BugReproTests {

    // BUG-13 (fixed): SystemMonitor.convertToBytes() now handles tera ("t") units.
    // nettop reports cumulative byte counts and can print "T"/"TiB" for
    // long-lived, high-traffic processes.
    @Test func convertToBytesSupportsTera() {
        let expected = 3 * UInt64(1024) * UInt64(1024) * UInt64(1024) * UInt64(1024)
        #expect(SystemMonitor.convertToBytes(val: 3, unit: "TiB") == expected)
        #expect(SystemMonitor.convertToBytes(val: 3, unit: "T") == expected)
    }

    // BUG-17 (fixed): formatWinMem() now keeps precision below 1 MiB instead of
    // collapsing every small value to "0.x MB".
    @Test func formatWinMemShowsSmallUnits() {
        #expect(formatWinMem(1024) == "1 KB")
        #expect(formatWinMem(512 * 1024) == "512 KB")
    }
}
