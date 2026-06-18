import Foundation
import IOKit

/// Minimal AppleSMC client for the battery charge-control keys.
///
/// Charge limiting is hardware-specific:
///  • Intel Macs use the `BCLM` key (battery charge level max, a percentage).
///  • Apple Silicon has no single "limit" key; charging is gated by `CH0B`/`CH0C`
///    (charge inhibit). We toggle inhibit around the target percentage from a
///    monitor loop in `main.swift`.
///
/// NOTE: These keys and behaviors need on-device verification per Mac model.
enum SMC {
    private static var connection: io_connect_t = 0

    // SMC selectors / struct mirror Apple's private AppleSMC interface.
    private static let kSMCHandleYPCEvent: UInt32 = 2
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCWriteKey: UInt8 = 6
    private static let kSMCGetKeyInfo: UInt8 = 9

    struct SMCKeyData {
        var key: UInt32 = 0
        var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
        var pLimitData: (UInt16, UInt16, UInt32) = (0, 0, 0)
        var keyInfo: (dataSize: UInt32, dataType: UInt32, dataAttributes: UInt8) = (0, 0, 0)
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    @discardableResult
    static func open() -> Bool {
        guard connection == 0 else { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
    }

    static func close() {
        if connection != 0 { IOServiceClose(connection); connection = 0 }
    }

    private static func fourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        for ch in str.utf8.prefix(4) { result = (result << 8) | UInt32(ch) }
        return result
    }

    private static func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        guard open() else { return nil }
        var output = SMCKeyData()
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(connection, kSMCHandleYPCEvent,
                                               &input, inputSize, &output, &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    /// Writes a single-byte SMC key.
    @discardableResult
    static func writeByte(_ key: String, value: UInt8) -> Bool {
        var info = SMCKeyData()
        info.key = fourCharCode(key)
        info.data8 = kSMCGetKeyInfo
        guard let infoOut = call(&info) else { return false }

        var write = SMCKeyData()
        write.key = fourCharCode(key)
        write.keyInfo.dataSize = infoOut.keyInfo.dataSize
        write.data8 = kSMCWriteKey
        write.bytes.0 = value
        return call(&write) != nil
    }

    static func readByte(_ key: String) -> UInt8? {
        var info = SMCKeyData()
        info.key = fourCharCode(key)
        info.data8 = kSMCGetKeyInfo
        guard let infoOut = call(&info) else { return nil }

        var read = SMCKeyData()
        read.key = fourCharCode(key)
        read.keyInfo.dataSize = infoOut.keyInfo.dataSize
        read.data8 = kSMCReadKey
        guard let out = call(&read) else { return nil }
        return out.bytes.0
    }

    // MARK: Charge control

    static let isAppleSilicon: Bool = {
        var size = 0
        sysctlbyname("hw.optional.arm64", nil, &size, nil, 0)
        var value: Int32 = 0
        var valueSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &value, &valueSize, nil, 0)
        return value == 1
    }()

    /// Enables/disables charging (Apple Silicon inhibit keys).
    @discardableResult
    static func setCharging(_ enabled: Bool) -> Bool {
        let value: UInt8 = enabled ? 0x00 : 0x02   // 0x02 = inhibit charging
        let a = writeByte("CH0B", value: value)
        let b = writeByte("CH0C", value: value)
        return a || b
    }

    /// Intel: set BCLM directly. Returns true if applied.
    @discardableResult
    static func setIntelLimit(_ percent: Int) -> Bool {
        writeByte("BCLM", value: UInt8(max(20, min(100, percent))))
    }

    @discardableResult
    static func clearIntelLimit() -> Bool {
        writeByte("BCLM", value: 100)
    }
}
