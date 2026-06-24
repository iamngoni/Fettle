import Foundation
import IOKit
import IOKit.ps
import SwiftUI

enum DeviceKind {
    case mac, keyboard, mouse, trackpad, headphones, generic

    var symbol: String {
        switch self {
        case .mac: return "laptopcomputer"
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "trackpad"
        case .headphones: return "headphones"
        case .generic: return "dot.radiowaves.right"
        }
    }
    var tint: Color {
        switch self {
        case .mac: return Color(hex: 0x0A84FF)
        case .keyboard, .mouse, .trackpad: return Color(hex: 0x8E8E96)
        case .headphones: return Color(hex: 0xBF5AF2)
        case .generic: return Color(hex: 0x5E5CE6)
        }
    }
}

struct BatteryDevice: Identifiable {
    let id: String
    var name: String
    var percent: Int
    var kind: DeviceKind
    var charging: Bool

    var levelColor: Color {
        if percent > 50 { return Color(hex: 0x32D74B) }
        if percent >= 25 { return Color(hex: 0xFF9F0A) }
        return Color(hex: 0xFF453A)
    }
    var batterySymbol: String {
        if charging { return "battery.100percent.bolt" }
        if percent >= 80 { return "battery.100percent" }
        if percent >= 50 { return "battery.75percent" }
        if percent >= 25 { return "battery.50percent" }
        if percent >= 10 { return "battery.25percent" }
        return "battery.0percent"
    }
}

/// Enumerates battery-reporting devices. The Mac itself comes from IOKit power
/// sources; Bluetooth peripherals (Magic Keyboard / Mouse / Trackpad and other
/// HID accessories) come from the IORegistry `BatteryPercent` property.
enum DeviceScanner {

    static func scan() -> (mac: BatteryDevice?, peripherals: [BatteryDevice]) {
        (macBattery(), hidBatteries())
    }

    private static func macBattery() -> BatteryDevice? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let source = list.first { src in
            guard let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any]
            else { return false }
            return (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        } ?? list.first
        guard let source,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
              let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
        else { return nil }
        let pct = Int((Double(capacity) / Double(max) * 100).rounded())
        let charging = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return BatteryDevice(id: "this-mac", name: "This Mac", percent: pct, kind: .mac, charging: charging)
    }

    private static func hidBatteries() -> [BatteryDevice] {
        var devices: [BatteryDevice] = []
        var iter = io_iterator_t()
        let match = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == kIOReturnSuccess else {
            return devices
        }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }
            guard let percent = (dict["BatteryPercent"] as? NSNumber)?.intValue, percent > 0 else { continue }

            let name = (dict["Product"] as? String) ?? "Accessory"
            devices.append(BatteryDevice(
                id: (dict["DeviceAddress"] as? String) ?? name,
                name: name,
                percent: percent,
                kind: kind(for: name),
                charging: false))
        }
        return devices
    }

    private static func kind(for product: String) -> DeviceKind {
        let p = product.lowercased()
        if p.contains("keyboard") { return .keyboard }
        if p.contains("trackpad") { return .trackpad }
        if p.contains("mouse") { return .mouse }
        if p.contains("airpod") || p.contains("headphone") || p.contains("beats") { return .headphones }
        return .generic
    }
}
