import Foundation
import IOKit
import IOKit.hid

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
        let candidates = [
            // Intel
            "Tp09", "Tp0d", "Tp0T", "TC0D", "TC0E", "TC0F", "TC0P", "TC0H",
            // Apple Silicon (M1/M2/M3/M4/M5 series)
            "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
            "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
            "Te05", "Te09", "Te0H", "Te0L", "Te0P", "Te0S",
            "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
            "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0V", "Tp0Y",
            "Tp0a", "Tp0d", "Tp0g", "Tp0m", "Tp0p", "Tp0u", "Tp0y", "Tp0e",
        ]
        for key in candidates {
            if let temp = getTemperature(key), temp > 20, temp < 110 {
                return temp
            }
        }
        return appleSiliconCPUFromHID()
    }

    func getGPUTemperature() -> Double? {
        let candidates = ["TGDD", "TCGC", "Tg05", "Tg0D", "TG0D", "TG0P"]
        for key in candidates {
            if let temp = getTemperature(key), temp > 20, temp < 110 {
                return temp
            }
        }
        return appleSiliconGPUFromHID()
    }

    // On Apple Silicon the SMC does not expose temperature keys publicly; the
    // sensors are only readable through the HID temperature device (AppleVendor
    // page 0xff00, usage 0x0005). The same approach used by Stats / iStat.
    private func readHIDTemperatures() -> [String: Double] {
        var sensors: [String: Double] = [:]

        let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary
        matching[kIOHIDPrimaryUsagePageKey] = 0xff00
        matching[kIOHIDPrimaryUsageKey] = 0x0005

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) {
                if IOHIDDeviceOpen(device, 0) == kIOReturnSuccess {
                    defer { IOHIDDeviceClose(device, 0) }
                    let elementMatching: [String: Int] = [
                        kIOHIDElementUsagePageKey: 0xff00,
                        kIOHIDElementUsageKey: 0x0005,
                    ]
                    if let elements = IOHIDDeviceCopyMatchingElements(device, elementMatching as CFDictionary, 0) {
                        let array = elements as NSArray
                        for case let element as IOHIDElement in array {
                            guard let name = IOHIDElementGetName(element) as String?, !name.isEmpty else { continue }
                            var valueRef: Unmanaged<IOHIDValue> = unsafeBitCast(element, to: Unmanaged<IOHIDValue>.self)
                            guard IOHIDDeviceGetValue(device, element, &valueRef) == kIOReturnSuccess else { continue }
                            let value = valueRef.takeUnretainedValue()
                            let raw = IOHIDValueGetIntegerValue(value)
                            // HID temperature values are reported in 0.1 °C steps
                            let temp = raw > 200 ? Double(raw) / 10.0 : Double(raw)
                            if temp > 0, temp < 125 {
                                sensors[name] = temp
                            }
                        }
                    }
                }
            }
            service = IOIteratorNext(iterator)
        }

        return sensors
    }

    private func appleSiliconCPUFromHID() -> Double? {
        let temps = readHIDTemperatures().filter { key, _ in
            key.hasPrefix("pACC MTR Temp") || key.hasPrefix("eACC MTR Temp") || key.hasPrefix("CPU MTR Temp")
        }.map { $0.value }
        guard !temps.isEmpty else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
    }

    private func appleSiliconGPUFromHID() -> Double? {
        let temps = readHIDTemperatures().filter { key, _ in
            key.hasPrefix("GPU MTR Temp")
        }.map { $0.value }
        guard !temps.isEmpty else { return nil }
        return temps.reduce(0, +) / Double(temps.count)
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
