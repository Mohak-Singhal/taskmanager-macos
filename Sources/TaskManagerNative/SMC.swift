import Foundation
import IOKit

final class SMC: Sendable {
    static let shared = SMC()
    
    private let connection: io_connect_t

    struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                   (0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)
    }

    init() {
        let service = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var conn: io_connect_t = 0
            let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
            if result == kIOReturnSuccess {
                self.connection = conn
                return
            }
        }
        self.connection = 0
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    private func callDriver(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        guard connection != 0 else { return nil }
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size
        let result = IOConnectCallStructMethod(
            connection,
            5, // Selector: kSMCHandleYPCEvent
            &input,
            MemoryLayout<SMCParamStruct>.size,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess && output.result == 0 else { return nil }
        return output
    }

    func readKeyInfo(_ key: String) -> SMCKeyInfoData? {
        guard key.count == 4 else { return nil }
        var input = SMCParamStruct()
        input.key = fourCharCode(key)
        input.data8 = 9 // Selector: kSMCGetKeyInfo
        guard let output = callDriver(&input) else { return nil }
        return output.keyInfo
    }

    func readKey(_ key: String) -> [UInt8]? {
        guard key.count == 4 else { return nil }
        guard let info = readKeyInfo(key) else { return nil }
        var input = SMCParamStruct()
        input.key = fourCharCode(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5 // Selector: kSMCReadKey
        guard let output = callDriver(&input) else { return nil }
        
        let tuple = output.bytes
        let mirror = Mirror(reflecting: tuple)
        var array = [UInt8]()
        var count = 0
        for child in mirror.children {
            if count >= Int(info.dataSize) { break }
            if let val = child.value as? UInt8 {
                array.append(val)
            }
            count += 1
        }
        return array
    }

    func getTemperature(_ key: String) -> Double? {
        guard let bytes = readKey(key), let info = readKeyInfo(key) else { return nil }
        let typeStr = fourCharCodeToString(info.dataType)
        
        switch typeStr {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.load(as: Float.self) })
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
            return Double(raw) / 256.0
        case "sp87":
            guard bytes.count >= 2 else { return nil }
            let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
            return Double(raw) / 128.0
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
            return Double(raw)
        default:
            if bytes.count == 2 {
                let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
                let val = Double(raw) / 256.0
                return val > 0 ? val : nil
            } else if bytes.count == 4 {
                return Double(bytes.withUnsafeBytes { $0.load(as: Float.self) })
            }
            return nil
        }
    }

    func getFanSpeed(_ key: String) -> Double? {
        guard let bytes = readKey(key), let info = readKeyInfo(key) else { return nil }
        let typeStr = fourCharCodeToString(info.dataType)
        
        switch typeStr {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.load(as: Float.self) })
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
            return Double(raw) / 4.0
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double((Int(bytes[0]) << 8) | Int(bytes[1]))
        default:
            if bytes.count == 2 {
                let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
                return Double(raw) / 4.0
            }
            return nil
        }
    }

    func getCPUTemperature() -> Double? {
        let candidates = ["Tp09", "Tp0d", "Tp0T", "TC0D", "TC0P", "TC0H"]
        for key in candidates {
            if let temp = getTemperature(key), temp > 20, temp < 125 {
                return temp
            }
        }
        return nil
    }

    func getGPUTemperature() -> Double? {
        let candidates = ["Tg05", "Tg0D", "TG0D", "TG0P"]
        for key in candidates {
            if let temp = getTemperature(key), temp > 20, temp < 125 {
                return temp
            }
        }
        return nil
    }

    func getFanRPM() -> Double? {
        if let speed = getFanSpeed("F0Ac"), speed >= 0 {
            return speed
        }
        return nil
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        var code: UInt32 = 0
        for char in string.utf8 {
            code = (code << 8) + UInt32(char)
        }
        return code
    }

    private func fourCharCodeToString(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}
