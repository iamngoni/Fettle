import Foundation
import Darwin
import IOKit
import IOKit.hid
import IOKit.ps
import SwiftUI
import CoreBluetooth

enum DeviceKind {
    case mac, keyboard, mouse, trackpad, headphones, phone, tablet, watch, generic

    var supportsStandardBLEBatteryProbe: Bool {
        switch self {
        case .keyboard, .mouse, .trackpad, .headphones, .phone, .tablet, .watch:
            return true
        case .mac, .generic:
            return false
        }
    }

    var symbol: String {
        switch self {
        case .mac: return "laptopcomputer"
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .headphones: return "headphones"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .watch: return "applewatch"
        case .generic: return "dot.radiowaves.right"
        }
    }
    var tint: Color {
        switch self {
        case .mac: return Color(hex: 0x0A84FF)
        case .keyboard, .mouse, .trackpad: return Color(hex: 0x8E8E96)
        case .headphones: return Color(hex: 0xBF5AF2)
        case .phone: return Color(hex: 0x0A84FF)
        case .tablet: return Color(hex: 0x64D2FF)
        case .watch: return Color(hex: 0xFF375F)
        case .generic: return Color(hex: 0x5E5CE6)
        }
    }
}

enum DevicePresence: Int {
    case connected = 0
    case continuity = 1
    case nearby = 2
    case paired = 3

    var label: String {
        switch self {
        case .connected: return "Connected"
        case .continuity: return "Continuity"
        case .nearby: return "Nearby"
        case .paired: return "Paired"
        }
    }
}

struct BatteryDevice: Identifiable {
    let id: String
    var name: String
    var percent: Int?
    var kind: DeviceKind
    var charging: Bool
    var presence: DevicePresence
    var detail: String?
    var address: String?
    var sourceRank: Int

    var levelColor: Color {
        guard let percent else { return Color(hex: 0x8E8E96) }
        if charging || percent > 50 { return Color(hex: 0x32D74B) }
        if percent >= 25 { return Color(hex: 0xFF9F0A) }
        return Color(hex: 0xFF453A)
    }
    var batterySymbol: String {
        guard let percent else { return "battery.0percent" }
        if charging { return "battery.100percent.bolt" }
        if percent >= 80 { return "battery.100percent" }
        if percent >= 50 { return "battery.75percent" }
        if percent >= 25 { return "battery.50percent" }
        if percent >= 10 { return "battery.25percent" }
        return "battery.0percent"
    }
    var percentText: String { percent.map { "\($0)%" } ?? "" }
    var statusText: String {
        guard let detail, !detail.isEmpty else { return presence.label }
        if percent != nil, detail.localizedCaseInsensitiveContains("waiting for level") || detail.localizedCaseInsensitiveContains("wake to update") {
            return presence.label
        }
        return detail
    }
}

/// Enumerates battery-reporting devices: the Mac (IOKit power sources) and any
/// accessory exposing a `BatteryPercent` property anywhere in the IORegistry.
/// It also folds in Bluetooth profiler records and paired iOS/iPadOS devices
/// reported by MobileDevice so the Devices panel does not hide Continuity
/// hardware just because it is not a HID accessory.
enum DeviceScanner {

    static func scan() async -> (mac: BatteryDevice?, peripherals: [BatteryDevice]) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let bluetooth = bluetoothProfilerDevices()
                let addressNamePairs: [(String, String)] = bluetooth.compactMap { device in
                    guard let address = device.address else { return nil }
                    return (normalizedAddress(address), device.name)
                }
                let lookup = Dictionary(uniqueKeysWithValues: addressNamePairs)
                let powerSources = powerSourceAccessoryDevices(nameLookup: lookup)
                let registry = registryBatteries(nameLookup: lookup)
                let classic = privateIOBluetoothDevices()
                let logitech = LogitechHIDPPBatterySource.scan(nameLookup: lookup)
                let mobile = MobileDeviceBridge.scan(timeout: 7)
                var peripherals = mergedDevices(powerSources + registry + classic + bluetooth + logitech + mobile)
                let bleTargets = peripherals.filter { $0.percent == nil && $0.kind.supportsStandardBLEBatteryProbe }
                if !bleTargets.isEmpty {
                    let ble = StandardBLEBatteryProbe.scan(targets: bleTargets, timeout: 2.5)
                    peripherals = mergedDevices(peripherals + ble)
                }
                DeviceBatteryCache.recordLiveReadings(peripherals)
                peripherals = mergedDevices(peripherals + DeviceBatteryCache.cachedReadings(for: peripherals))
                cont.resume(returning: (macBattery(), peripherals))
            }
        }
    }

    // MARK: Mac

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
        let name = Host.current().localizedName ?? "This Mac"
        return BatteryDevice(id: "this-mac", name: name, percent: pct, kind: .mac, charging: charging, presence: .connected, detail: nil, address: nil, sourceRank: 0)
    }

    // MARK: Accessory power sources

    /// `pmset -g accps` is the same public surface macOS uses for accessory
    /// power sources that do not appear in IOPSCopyPowerSourcesList on newer
    /// systems. It catches devices such as AirPods and, when macOS has a live
    /// reading, Bluetooth keyboards/mice that do not expose `BatteryPercent` in
    /// IORegistry.
    private static func powerSourceAccessoryDevices(nameLookup: [String: String]) -> [BatteryDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "accps"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }

        return text
            .components(separatedBy: .newlines)
            .compactMap { accessoryPowerSource(from: $0, nameLookup: nameLookup) }
    }

    private static func accessoryPowerSource(from line: String, nameLookup: [String: String]) -> BatteryDevice? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("-"), trimmed.contains("%") else { return nil }
        guard let percentRange = trimmed.range(of: #"(\d{1,3})%;"#, options: .regularExpression),
              let percent = Int(trimmed[percentRange].filter(\.isNumber)),
              (0...100).contains(percent)
        else { return nil }

        let beforePercent = String(trimmed[..<percentRange.lowerBound])
        let rawName = beforePercent
            .replacingOccurrences(of: #"^\-"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(id=\d+\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty, !rawName.localizedCaseInsensitiveContains("InternalBattery") else { return nil }

        let normalizedRaw = normalizedName(rawName)
        let canonicalName = nameLookup.values.first { normalizedName($0) == normalizedRaw } ?? rawName
        let name = cleanDeviceName(canonicalName)
        let lower = trimmed.lowercased()
        let charging = lower.contains("charging") && !lower.contains("discharging")
        let detail = charging ? "Charging" : "Connected"

        return BatteryDevice(
            id: "powersource-\(normalizedName(name))",
            name: name,
            percent: percent,
            kind: kind(forName: name),
            charging: charging,
            presence: .connected,
            detail: detail,
            address: nil,
            sourceRank: 0
        )
    }

    // MARK: Accessories (recursive IORegistry walk for BatteryPercent)

    private static func registryBatteries(nameLookup: [String: String]) -> [BatteryDevice] {
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }

        var devices: [BatteryDevice] = []
        var seen = Set<String>()
        var entry = IOIteratorNext(iterator)
        var guardCount = 0
        while entry != 0, guardCount < 20_000 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator); guardCount += 1 }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }
            guard let percent = (dict["BatteryPercent"] as? NSNumber)?.intValue, percent >= 0 else { continue }

            let address = registryAddress(from: dict)
            let normalized = address.map(normalizedAddress)
            let rawName = nonEmptyString(dict["Product"])
                ?? nonEmptyString(dict["BD_NAME"])
                ?? nonEmptyString(dict["DeviceName"])
                ?? normalized.flatMap { nameLookup[$0] }
                ?? "Accessory"
            let name = cleanDeviceName(rawName)
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            devices.append(BatteryDevice(id: normalized ?? name, name: name, percent: percent, kind: kind(forName: name, minorType: nonEmptyString(dict["Accessory Category"])), charging: false, presence: .connected, detail: nil, address: normalized, sourceRank: 0))
        }
        return devices
    }

    // MARK: IOBluetooth private battery fields

    private static func privateIOBluetoothDevices() -> [BatteryDevice] {
        _ = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)
        guard let deviceClass = NSClassFromString("IOBluetoothDevice") as AnyObject?,
              deviceClass.responds(to: NSSelectorFromString("connectedDevices")),
              let raw = deviceClass.perform(NSSelectorFromString("connectedDevices"))?.takeUnretainedValue() as? NSSet
        else { return [] }

        return raw.compactMap { item -> BatteryDevice? in
            guard let device = item as? NSObject,
                  let name = stringValue(device, "name")
            else { return nil }
            let cleanName = cleanDeviceName(name)
            let address = stringValue(device, "addressString").map(normalizedAddress)
            let percent = [
                intValue(device, "batteryPercentSingle"),
                intValue(device, "batteryPercentCombined"),
                intValue(device, "batteryPercentCase")
            ].compactMap { $0 }.first { (1...100).contains($0) }
            guard percent != nil else { return nil }

            return BatteryDevice(
                id: address ?? "iobluetooth-\(normalizedName(cleanName))",
                name: cleanName,
                percent: percent,
                kind: kind(forName: cleanName),
                charging: false,
                presence: .connected,
                detail: nil,
                address: address,
                sourceRank: 1
            )
        }
    }

    // MARK: Bluetooth profiler

    private static func bluetoothProfilerDevices() -> [BatteryDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty,
              let report = try? JSONDecoder().decode(BluetoothSystemReport.self, from: data)
        else { return [] }

        var devices: [BatteryDevice] = []
        for section in report.SPBluetoothDataType {
            devices.append(contentsOf: bluetoothDevices(from: section.deviceConnected, presence: .connected))
            devices.append(contentsOf: bluetoothDevices(from: section.deviceNotConnected, presence: .nearby))
        }
        return devices
    }

    private static func bluetoothDevices(from records: [[String: BluetoothDeviceInfo]]?, presence: DevicePresence) -> [BatteryDevice] {
        guard let records else { return [] }
        return records.flatMap { record -> [BatteryDevice] in
            record.compactMap { rawName, info in
                let name = cleanDeviceName(rawName)
                let kind = kind(forName: name, minorType: info.deviceMinorType)
                let percent = info.primaryBatteryPercent
                let resolvedPresence: DevicePresence = presence == .connected ? .connected : (info.deviceRSSI == nil ? .paired : .nearby)
                guard shouldShowBluetoothDevice(name: name, kind: kind, info: info, presence: presence) else { return nil }
                let address = info.deviceAddress.map(normalizedAddress)
                let detail = info.detailText ?? availabilityDetail(presence: resolvedPresence, percent: percent)
                return BatteryDevice(
                    id: address ?? "bluetooth-\(normalizedName(name))",
                    name: name,
                    percent: percent,
                    kind: kind,
                    charging: false,
                    presence: resolvedPresence,
                    detail: detail,
                    address: address,
                    sourceRank: percent == nil ? 3 : 1
                )
            }
        }
    }

    private static func availabilityDetail(presence: DevicePresence, percent: Int?) -> String? {
        if percent != nil { return nil }
        switch presence {
        case .connected: return "Connected"
        case .continuity: return "Continuity"
        case .nearby: return "Nearby"
        case .paired: return "Paired"
        }
    }

    private static func shouldShowBluetoothDevice(name: String, kind: DeviceKind, info: BluetoothDeviceInfo, presence: DevicePresence) -> Bool {
        if presence == .connected { return true }
        if info.primaryBatteryPercent != nil { return true }
        switch kind {
        case .phone, .tablet, .watch:
            return info.deviceRSSI != nil
        case .keyboard, .mouse, .trackpad:
            return true
        case .headphones:
            return false
        case .mac, .generic:
            return false
        }
    }

    // MARK: Merging

    private static func mergedDevices(_ devices: [BatteryDevice]) -> [BatteryDevice] {
        var merged: [String: BatteryDevice] = [:]
        for device in devices {
            let key = mergeKey(for: device)
            let nameKey = "name-\(normalizedName(device.name))"
            let existingKey = merged[key] != nil ? key : merged.first { _, value in
                normalizedName(value.name) == normalizedName(device.name)
            }?.key

            guard let existingKey, var existing = merged[existingKey] else {
                merged[key] = device
                continue
            }
            if existing.percent == nil || (device.percent != nil && device.sourceRank < existing.sourceRank) {
                existing.percent = device.percent
                existing.charging = device.charging
                existing.sourceRank = min(existing.sourceRank, device.sourceRank)
            }
            if existing.kind == .generic { existing.kind = device.kind }
            if existing.name == "Accessory" || device.name.count > existing.name.count { existing.name = device.name }
            if device.presence.rawValue < existing.presence.rawValue { existing.presence = device.presence }
            if existing.detail == nil || (device.detail != nil && device.sourceRank <= existing.sourceRank) { existing.detail = device.detail }
            if existing.address == nil { existing.address = device.address }
            merged[existingKey] = existing
            if existingKey != key, existingKey != nameKey {
                merged.removeValue(forKey: nameKey)
            }
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.presence.rawValue != rhs.presence.rawValue { return lhs.presence.rawValue < rhs.presence.rawValue }
            if (lhs.percent == nil) != (rhs.percent == nil) { return lhs.percent != nil }
            if kindSort(lhs.kind) != kindSort(rhs.kind) { return kindSort(lhs.kind) < kindSort(rhs.kind) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func mergeKey(for device: BatteryDevice) -> String {
        if let address = device.address { return "addr-\(normalizedAddress(address))" }
        return "name-\(normalizedName(device.name))"
    }

    private static func kindSort(_ kind: DeviceKind) -> Int {
        switch kind {
        case .keyboard: return 0
        case .mouse: return 1
        case .trackpad: return 2
        case .headphones: return 3
        case .phone: return 4
        case .tablet: return 5
        case .watch: return 6
        case .mac: return 7
        case .generic: return 8
        }
    }

    // MARK: Helpers

    static func kind(forName product: String, minorType: String? = nil) -> DeviceKind {
        let p = "\(product) \(minorType ?? "")".lowercased()
        if p.contains("keyboard") || p.contains("keys") { return .keyboard }
        if p.contains("trackpad") { return .trackpad }
        if p.contains("mouse") { return .mouse }
        if p.contains("airpod") || p.contains("headphone") || p.contains("buds") || p.contains("beats") || p.contains("powerbeats") { return .headphones }
        if p.contains("watch") { return .watch }
        if p.contains("iphone") || p.contains("mobile phone") { return .phone }
        if p.contains("ipad") || p.contains("tablet") { return .tablet }
        return .generic
    }

    fileprivate static func cleanDeviceName(_ name: String) -> String {
        var cleaned = name.replacingOccurrences(of: "\u{00a0}", with: " ")
        cleaned = cleaned.replacingOccurrences(of: " ’", with: "’")
        cleaned = cleaned.replacingOccurrences(of: " '", with: "'")
        while cleaned.contains("  ") { cleaned = cleaned.replacingOccurrences(of: "  ", with: " ") }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func normalizedName(_ name: String) -> String {
        cleanDeviceName(name)
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    fileprivate static func stringValue(_ object: NSObject, _ key: String) -> String? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key) as? String
    }

    fileprivate static func intValue(_ object: NSObject, _ key: String) -> Int? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return (object.value(forKey: key) as? NSNumber)?.intValue
    }

    private static func normalizedAddress(_ address: String) -> String {
        address
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
            .map(String.init)
            .joined()
    }

    private static func registryAddress(from dict: [String: Any]) -> String? {
        if let value = nonEmptyString(dict["DeviceAddress"]) ?? nonEmptyString(dict["SerialNumber"]) {
            return value
        }
        if let data = dict["BD_ADDR"] as? Data {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum LogitechHIDPPBatterySource {
    static func scan(nameLookup: [String: String]) -> [BatteryDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x046d
        ] as CFDictionary)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>
        else { return [] }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        return devices.flatMap { device -> [BatteryDevice] in
            let product = stringProperty(device, kIOHIDProductKey) ?? ""
            let reader = HIDPPReader(device: device)

            if isReceiverDevice(device) {
                let readings = reader.readReceiverBatteryDevices(nameLookup: nameLookup, receiverName: DeviceScanner.cleanDeviceName(product))
                if !readings.isEmpty {
                    FettleLog.log("Devices: Logitech receiver \(product) returned \(readings.count) HID++ battery reading(s)")
                }
                return readings
            }

            guard isLikelyDirectHIDPPDevice(device),
                  let percent = reader.readBatteryPercent(deviceIndex: 0xff)
            else { return [] }

            let name = productName(device, nameLookup: nameLookup)
            let address = bluetoothAddress(device)
            return [BatteryDevice(
                id: address ?? "hidpp-\(DeviceScanner.normalizedName(name))",
                name: name,
                percent: percent.value,
                kind: DeviceScanner.kind(forName: name),
                charging: percent.charging,
                presence: .connected,
                detail: nil,
                address: address,
                sourceRank: 0
            )]
        }
    }

    private static func isLikelyDirectHIDPPDevice(_ device: IOHIDDevice) -> Bool {
        let vendor = intProperty(device, kIOHIDVendorIDKey)
        let product = stringProperty(device, kIOHIDProductKey)?.lowercased() ?? ""
        guard vendor == 0x046d else { return false }
        if product.contains("bolt") || product.contains("receiver") { return false }
        return true
    }

    private static func isReceiverDevice(_ device: IOHIDDevice) -> Bool {
        let vendor = intProperty(device, kIOHIDVendorIDKey)
        let product = stringProperty(device, kIOHIDProductKey)?.lowercased() ?? ""
        guard vendor == 0x046d else { return false }
        return product.contains("bolt") || product.contains("receiver")
    }

    private static func productName(_ device: IOHIDDevice, nameLookup: [String: String]) -> String {
        if let address = bluetoothAddress(device), let name = nameLookup[address] {
            return name
        }
        if let product = stringProperty(device, kIOHIDProductKey), !product.isEmpty {
            return DeviceScanner.cleanDeviceName(product)
        }
        return "Logitech Device"
    }

    private static func bluetoothAddress(_ device: IOHIDDevice) -> String? {
        let keys = [
            "DeviceAddress",
            "BluetoothDeviceAddress",
            "BD_ADDR",
            kIOHIDSerialNumberKey
        ]
        for key in keys {
            if let value = stringProperty(device, key) {
                let normalized = value
                    .lowercased()
                    .unicodeScalars
                    .filter { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
                    .map(String.init)
                    .joined()
                if normalized.count == 12 { return normalized }
            }
        }
        return nil
    }

    private static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }

    private struct BatteryResult {
        let value: Int
        let charging: Bool
    }

    private final class HIDPPReader {
        private static let reportLong: UInt8 = 0x11
        private static let softwareID: UInt8 = 0x01
        private static let errorFeature: UInt8 = 0xff

        private let device: IOHIDDevice
        private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        private let lock = NSLock()
        private var responses: [[UInt8]] = []

        init(device: IOHIDDevice) {
            self.device = device
        }

        deinit {
            inputBuffer.deallocate()
        }

        func readBatteryPercent(deviceIndex: UInt8) -> BatteryResult? {
            guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return nil }
            defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, Self.inputCallback, context)
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            defer { IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }

            return readBatteryPercentOpen(deviceIndex: deviceIndex)
        }

        func readReceiverBatteryDevices(nameLookup: [String: String], receiverName: String) -> [BatteryDevice] {
            guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return [] }
            defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, 64, Self.inputCallback, context)
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            defer { IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }

            let fallbackNames = nameLookup.values
                .filter { name in
                    let kind = DeviceScanner.kind(forName: name)
                    return kind == .keyboard || kind == .mouse || kind == .trackpad
                }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            return (1...6).compactMap { rawIndex -> BatteryDevice? in
                let index = UInt8(rawIndex)
                guard let percent = readBatteryPercentOpen(deviceIndex: index) else { return nil }
                let name = readDeviceName(deviceIndex: index)
                    ?? fallbackNames[safe: rawIndex - 1]
                    ?? "Logitech Device \(rawIndex)"
                let cleanName = DeviceScanner.cleanDeviceName(name)
                return BatteryDevice(
                    id: "hidpp-receiver-\(receiverID)-\(rawIndex)",
                    name: cleanName,
                    percent: percent.value,
                    kind: DeviceScanner.kind(forName: cleanName),
                    charging: percent.charging,
                    presence: .connected,
                    detail: receiverName.isEmpty ? "Logitech receiver" : receiverName,
                    address: nil,
                    sourceRank: 0
                )
            }
        }

        private var receiverID: String {
            let serial = LogitechHIDPPBatterySource.stringProperty(device, kIOHIDSerialNumberKey)
            let productID = LogitechHIDPPBatterySource.intProperty(device, kIOHIDProductIDKey).map { String(format: "%04x", $0) } ?? "unknown"
            return DeviceScanner.normalizedName(serial ?? productID)
        }

        private func readBatteryPercentOpen(deviceIndex: UInt8) -> BatteryResult? {
            if let unified = readUnifiedBattery(deviceIndex: deviceIndex) { return unified }
            if let status = readBatteryStatus(deviceIndex: deviceIndex) { return status }
            if let voltage = readBatteryVoltage(deviceIndex: deviceIndex) { return voltage }
            return nil
        }

        private func readUnifiedBattery(deviceIndex: UInt8) -> BatteryResult? {
            guard let feature = rootFeature(0x1004, deviceIndex: deviceIndex),
                  request(deviceIndex: deviceIndex, feature: feature, function: 0x00) != nil,
                  let response = request(deviceIndex: deviceIndex, feature: feature, function: 0x10)
            else { return nil }

            let stateOfCharge = intParam(response, 0)
            guard (1...100).contains(stateOfCharge) else { return nil }
            let chargingStatus = intParam(response, 2)
            let externalPower = intParam(response, 3)
            return BatteryResult(value: stateOfCharge, charging: chargingStatus == 1 || externalPower == 1)
        }

        private func readBatteryStatus(deviceIndex: UInt8) -> BatteryResult? {
            guard let feature = rootFeature(0x1000, deviceIndex: deviceIndex),
                  let response = request(deviceIndex: deviceIndex, feature: feature, function: 0x00)
            else { return nil }

            let capacity = intParam(response, 0)
            guard (1...100).contains(capacity) else { return nil }
            let status = intParam(response, 2)
            return BatteryResult(value: capacity, charging: status == 1)
        }

        private func readBatteryVoltage(deviceIndex: UInt8) -> BatteryResult? {
            guard let feature = rootFeature(0x1001, deviceIndex: deviceIndex),
                  let response = request(deviceIndex: deviceIndex, feature: feature, function: 0x00)
            else { return nil }

            let voltage = (intParam(response, 0) << 8) | intParam(response, 1)
            guard let percent = Self.estimatedPercent(forMillivolts: voltage) else { return nil }
            let flags = intParam(response, 2)
            return BatteryResult(value: percent, charging: (flags & 0x40) != 0 || (flags & 0x20) != 0)
        }

        private func rootFeature(_ feature: UInt16, deviceIndex: UInt8) -> UInt8? {
            let params = [UInt8(feature >> 8), UInt8(feature & 0x00ff)]
            guard let response = request(deviceIndex: deviceIndex, feature: 0x00, function: 0x00, params: params) else { return nil }
            let index = UInt8(intParam(response, 0))
            return index == 0 ? nil : index
        }

        private func readDeviceName(deviceIndex: UInt8) -> String? {
            guard let feature = rootFeature(0x0005, deviceIndex: deviceIndex),
                  let countResponse = request(deviceIndex: deviceIndex, feature: feature, function: 0x00)
            else { return nil }
            let count = intParam(countResponse, 0)
            guard count > 0, count < 80 else { return nil }

            var bytes: [UInt8] = []
            var offset = 0
            while bytes.count < count, offset < count {
                guard let response = request(deviceIndex: deviceIndex, feature: feature, function: 0x10, params: [UInt8(offset)]) else { break }
                let chunk = response.dropFirst(4).prefix(min(16, count - bytes.count)).filter { $0 != 0 }
                bytes.append(contentsOf: chunk)
                offset += chunk.count
                if chunk.isEmpty { break }
            }
            guard !bytes.isEmpty else { return nil }
            return String(bytes: bytes, encoding: .utf8)
        }

        private func request(deviceIndex: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = []) -> [UInt8]? {
            let command = function | Self.softwareID
            var report = Array(repeating: UInt8(0), count: 20)
            report[0] = Self.reportLong
            report[1] = deviceIndex
            report[2] = feature
            report[3] = command
            for (index, value) in params.prefix(16).enumerated() {
                report[4 + index] = value
            }

            lock.lock()
            responses.removeAll()
            lock.unlock()

            let reportWithID = report
            let reportWithoutID = Array(report.dropFirst())

            guard sendReport(reportWithID) else { return nil }
            var deadline = Date().addingTimeInterval(0.25)
            while Date() < deadline {
                if let response = takeResponse(deviceIndex: deviceIndex, feature: feature, command: command) {
                    return response
                }
                CFRunLoopRunInMode(.defaultMode, 0.025, true)
            }

            // Some macOS HID stacks expect the report ID only in the
            // IOHIDDeviceSetReport `reportID` parameter, not duplicated at byte 0.
            // Keep the older form first because several Logitech receivers accept it.
            guard sendReport(reportWithoutID) else { return nil }
            deadline = Date().addingTimeInterval(0.25)
            while Date() < deadline {
                if let response = takeResponse(deviceIndex: deviceIndex, feature: feature, command: command) {
                    return response
                }
                CFRunLoopRunInMode(.defaultMode, 0.025, true)
            }
            return nil
        }

        private func sendReport(_ report: [UInt8]) -> Bool {
            report.withUnsafeBufferPointer { buffer -> Bool in
                guard let base = buffer.baseAddress else { return false }
                let out = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(Self.reportLong), base, report.count)
                if out == kIOReturnSuccess { return true }
                let featureResult = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(Self.reportLong), base, report.count)
                return featureResult == kIOReturnSuccess
            }
        }

        private func takeResponse(deviceIndex: UInt8, feature: UInt8, command: UInt8) -> [UInt8]? {
            lock.lock()
            defer { lock.unlock() }
            guard let index = responses.firstIndex(where: { response in
                guard response.count >= 4 else { return false }
                if response[0] != Self.reportLong { return false }
                if response[1] != deviceIndex { return false }
                if response[2] == Self.errorFeature {
                    return response.count > 5 && response[3] == feature && response[4] == command
                }
                return response[2] == feature && response[3] == command
            }) else { return nil }

            let response = responses.remove(at: index)
            return response.count > 2 && response[2] == Self.errorFeature ? nil : response
        }

        private func appendResponse(_ response: [UInt8]) {
            lock.lock()
            responses.append(response)
            lock.unlock()
        }

        private func intParam(_ response: [UInt8], _ index: Int) -> Int {
            let paramIndex = 4 + index
            guard response.indices.contains(paramIndex) else { return 0 }
            return Int(response[paramIndex])
        }

        private static let inputCallback: IOHIDReportCallback = { context, result, _, reportType, reportID, report, reportLength in
            guard result == kIOReturnSuccess,
                  reportType == kIOHIDReportTypeInput,
                  let context
            else { return }

            let reader = Unmanaged<HIDPPReader>.fromOpaque(context).takeUnretainedValue()
            var bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
            let id = UInt8(truncatingIfNeeded: reportID)
            if id != 0, bytes.first != id {
                bytes.insert(id, at: 0)
            }
            reader.appendResponse(bytes)
        }

        private static func estimatedPercent(forMillivolts value: Int) -> Int? {
            let curve: [(Int, Int)] = [
                (4186, 100), (4067, 90), (3989, 80), (3922, 70), (3852, 60),
                (3794, 50), (3747, 40), (3711, 30), (3676, 20), (3637, 10),
                (3579, 2), (3500, 0)
            ]
            guard value > 0 else { return nil }
            if value >= curve[0].0 { return curve[0].1 }
            if value <= curve[curve.count - 1].0 { return curve[curve.count - 1].1 }
            for index in 0..<(curve.count - 1) {
                let high = curve[index]
                let low = curve[index + 1]
                if value <= high.0, value >= low.0 {
                    let fraction = Double(value - low.0) / Double(high.0 - low.0)
                    return Int((Double(low.1) + (Double(high.1 - low.1) * fraction)).rounded())
                }
            }
            return nil
        }
    }
}

private struct BluetoothSystemReport: Decodable {
    let SPBluetoothDataType: [BluetoothSection]
}

private enum DeviceBatteryCache {
    private static let key = "devices.batteryCache.v1"
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    private struct Entry: Codable {
        var name: String
        var percent: Int
        var charging: Bool
        var kind: String
        var address: String?
        var updatedAt: TimeInterval
    }

    static func recordLiveReadings(_ devices: [BatteryDevice]) {
        var cache = readCache()
        var changed = false
        let now = Date().timeIntervalSince1970

        for device in devices {
            guard let percent = device.percent, (0...100).contains(percent) else { continue }
            let entry = Entry(
                name: device.name,
                percent: percent,
                charging: device.charging,
                kind: kindString(device.kind),
                address: device.address,
                updatedAt: now
            )
            for key in cacheKeys(for: device) {
                cache[key] = entry
                changed = true
            }
        }

        if changed { writeCache(cache) }
    }

    static func cachedReadings(for devices: [BatteryDevice]) -> [BatteryDevice] {
        let cache = readCache()
        let now = Date().timeIntervalSince1970

        return devices.compactMap { device -> BatteryDevice? in
            guard device.percent == nil,
                  let entry = cacheKeys(for: device).compactMap({ cache[$0] }).first,
                  now - entry.updatedAt <= maxAge
            else { return nil }

            var cached = device
            cached.percent = entry.percent
            cached.charging = entry.charging
            cached.detail = "Last seen \(relativeAge(since: entry.updatedAt, now: now))"
            cached.sourceRank = max(cached.sourceRank, 4)
            return cached
        }
    }

    private static func readCache() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return cache
    }

    private static func writeCache(_ cache: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func cacheKeys(for device: BatteryDevice) -> [String] {
        var keys: [String] = []
        if let address = device.address {
            let normalized = normalizedAddress(address)
            if normalized.count == 12 { keys.append("addr-\(normalized)") }
        }
        let normalizedName = DeviceScanner.normalizedName(device.name)
        if !normalizedName.isEmpty { keys.append("name-\(normalizedName)") }
        return keys
    }

    private static func normalizedAddress(_ address: String) -> String {
        address
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
            .map(String.init)
            .joined()
    }

    private static func kindString(_ kind: DeviceKind) -> String {
        switch kind {
        case .mac: return "mac"
        case .keyboard: return "keyboard"
        case .mouse: return "mouse"
        case .trackpad: return "trackpad"
        case .headphones: return "headphones"
        case .phone: return "phone"
        case .tablet: return "tablet"
        case .watch: return "watch"
        case .generic: return "generic"
        }
    }

    private static func relativeAge(since timestamp: TimeInterval, now: TimeInterval) -> String {
        let seconds = max(0, Int(now - timestamp))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        return "recently"
    }
}

private struct BluetoothSection: Decodable {
    let deviceConnected: [[String: BluetoothDeviceInfo]]?
    let deviceNotConnected: [[String: BluetoothDeviceInfo]]?

    enum CodingKeys: String, CodingKey {
        case deviceConnected = "device_connected"
        case deviceNotConnected = "device_not_connected"
    }
}

private struct BluetoothDeviceInfo: Decodable {
    let deviceAddress: String?
    let deviceMinorType: String?
    let deviceRSSI: String?
    let deviceBatteryLevelCase: String?
    let deviceBatteryLevelLeft: String?
    let deviceBatteryLevelRight: String?

    enum CodingKeys: String, CodingKey {
        case deviceAddress = "device_address"
        case deviceMinorType = "device_minorType"
        case deviceRSSI = "device_rssi"
        case deviceBatteryLevelCase = "device_batteryLevelCase"
        case deviceBatteryLevelLeft = "device_batteryLevelLeft"
        case deviceBatteryLevelRight = "device_batteryLevelRight"
    }

    var primaryBatteryPercent: Int? {
        batteryPercent(deviceBatteryLevelCase)
            ?? batteryPercent(deviceBatteryLevelLeft)
            ?? batteryPercent(deviceBatteryLevelRight)
    }

    var detailText: String? {
        let casePercent = batteryPercent(deviceBatteryLevelCase)
        let leftPercent = batteryPercent(deviceBatteryLevelLeft)
        let rightPercent = batteryPercent(deviceBatteryLevelRight)

        var parts: [String] = []
        if let casePercent { parts.append("Case \(casePercent)%") }
        if let leftPercent, let rightPercent, leftPercent == rightPercent {
            parts.append("Buds \(leftPercent)%")
        } else {
            if let leftPercent { parts.append("L \(leftPercent)%") }
            if let rightPercent { parts.append("R \(rightPercent)%") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func batteryPercent(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        return Int(digits)
    }
}

private struct BLEBatteryTarget {
    let name: String
    let normalizedName: String
    let kind: DeviceKind
    let presence: DevicePresence
}

private final class StandardBLEBatteryProbe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let queueKey = DispatchSpecificKey<Void>()
    private let queue = DispatchQueue(label: "fettle.devices.ble-battery")
    private let semaphore = DispatchSemaphore(value: 0)
    private let batteryService = CBUUID(string: "180F")
    private let batteryCharacteristic = CBUUID(string: "2A19")
    private let targets: [BLEBatteryTarget]

    private var manager: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheralTargets: [UUID: BLEBatteryTarget] = [:]
    private var foundNames = Set<String>()
    private var results: [BatteryDevice] = []
    private var finished = false

    private init(devices: [BatteryDevice]) {
        targets = devices.map {
            BLEBatteryTarget(
                name: $0.name,
                normalizedName: DeviceScanner.normalizedName($0.name),
                kind: $0.kind,
                presence: $0.presence
            )
        }
        super.init()
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    static func scan(targets devices: [BatteryDevice], timeout: TimeInterval) -> [BatteryDevice] {
        guard !devices.isEmpty else { return [] }
        let probe = StandardBLEBatteryProbe(devices: devices)
        probe.queue.async {
            probe.manager = CBCentralManager(delegate: probe, queue: probe.queue)
        }
        _ = probe.semaphore.wait(timeout: .now() + timeout)
        return probe.finish()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            _ = finish()
            return
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name = advertisedName ?? peripheral.name,
              let target = target(forPeripheralName: name),
              !foundNames.contains(target.normalizedName)
        else { return }

        foundNames.insert(target.normalizedName)
        peripherals[peripheral.identifier] = peripheral
        peripheralTargets[peripheral.identifier] = target
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        cleanup(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == batteryService })
        else {
            manager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([batteryCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { $0.uuid == batteryCharacteristic })
        else {
            manager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { manager?.cancelPeripheralConnection(peripheral) }
        guard error == nil,
              let data = characteristic.value,
              let first = data.first,
              let target = peripheralTargets[peripheral.identifier]
        else { return }

        results.append(BatteryDevice(
            id: "ble-\(target.normalizedName)",
            name: target.name,
            percent: Int(first),
            kind: target.kind,
            charging: false,
            presence: target.presence,
            detail: nil,
            address: nil,
            sourceRank: 1
        ))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cleanup(peripheral)
    }

    private func target(forPeripheralName name: String) -> BLEBatteryTarget? {
        let normalized = DeviceScanner.normalizedName(name)
        guard normalized.count > 2 else { return nil }
        return targets.first {
            $0.normalizedName == normalized
                || $0.normalizedName.contains(normalized)
                || normalized.contains($0.normalizedName)
        }
    }

    private func cleanup(_ peripheral: CBPeripheral) {
        peripherals.removeValue(forKey: peripheral.identifier)
        peripheralTargets.removeValue(forKey: peripheral.identifier)
    }

    private func finish() -> [BatteryDevice] {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            finishOnQueue()
            return results
        }

        var snapshot: [BatteryDevice] = []
        queue.sync {
            finishOnQueue()
            snapshot = results
        }
        return snapshot
    }

    private func finishOnQueue() {
        guard !finished else { return }
        finished = true
        manager?.stopScan()
        peripherals.values.forEach { manager?.cancelPeripheralConnection($0) }
        semaphore.signal()
    }
}

private enum MobileDeviceBridge {
    private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private typealias SubscribeFn = @convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    private typealias SubscribeWithOptionsFn = @convention(c) (Callback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?, CFDictionary) -> Int32
    private typealias UnsubscribeFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias DeviceFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias CopyValueFn = @convention(c) (UnsafeMutableRawPointer?, CFString?, CFString) -> Unmanaged<CFTypeRef>?

    private static var subscribe: SubscribeFn?
    private static var subscribeWithOptions: SubscribeWithOptionsFn?
    private static var unsubscribe: UnsubscribeFn?
    private static var connect: DeviceFn?
    private static var disconnect: DeviceFn?
    private static var validatePairing: DeviceFn?
    private static var startSession: DeviceFn?
    private static var stopSession: DeviceFn?
    private static var copyValue: CopyValueFn?
    private static var didLoad = false

    static func scan(timeout: TimeInterval) -> [BatteryDevice] {
        guard load() else { return [] }

        let collector = MobileDeviceCollector()
        let context = Unmanaged.passRetained(collector)
        defer { context.release() }

        var notification: UnsafeMutableRawPointer?
        let didSubscribe: Bool
        if let subscribeWithOptions {
            let options: CFDictionary = [
                "NotificationOptionSearchForPairedDevices": true,
                "NotificationOptionSearchForWiFiPairableDevices": true,
                "NotificationOptionEnableRemoteXPC": true,
                "NotificationOptionEnableUSBMux": true
            ] as CFDictionary
            didSubscribe = subscribeWithOptions(callback, 0, 0, context.toOpaque(), &notification, options) == 0
        } else {
            didSubscribe = subscribe?(callback, 0, 0, context.toOpaque(), &notification) == 0
        }
        guard didSubscribe else { return [] }
        defer { _ = unsubscribe?(notification) }
        CFRunLoopRunInMode(.defaultMode, timeout, false)
        return collector.snapshot()
    }

    private static let callback: Callback = { rawInfo, rawContext in
        guard let rawInfo,
              let rawContext,
              let device = rawInfo.load(as: UnsafeMutableRawPointer?.self)
        else { return }
        let collector = Unmanaged<MobileDeviceCollector>.fromOpaque(rawContext).takeUnretainedValue()
        if let device = readDevice(device) {
            collector.add(device)
        }
    }

    private static func load() -> Bool {
        if didLoad { return subscribe != nil }
        didLoad = true

        guard let handle = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_NOW) else {
            return false
        }
        subscribe = symbol("AMDeviceNotificationSubscribe", handle: handle, as: SubscribeFn.self)
        subscribeWithOptions = symbol("AMDeviceNotificationSubscribeWithOptions", handle: handle, as: SubscribeWithOptionsFn.self)
        unsubscribe = symbol("AMDeviceNotificationUnsubscribe", handle: handle, as: UnsubscribeFn.self)
        connect = symbol("AMDeviceConnect", handle: handle, as: DeviceFn.self)
        disconnect = symbol("AMDeviceDisconnect", handle: handle, as: DeviceFn.self)
        validatePairing = symbol("AMDeviceValidatePairing", handle: handle, as: DeviceFn.self)
        startSession = symbol("AMDeviceStartSession", handle: handle, as: DeviceFn.self)
        stopSession = symbol("AMDeviceStopSession", handle: handle, as: DeviceFn.self)
        copyValue = symbol("AMDeviceCopyValue", handle: handle, as: CopyValueFn.self)

        return (subscribe != nil || subscribeWithOptions != nil)
            && unsubscribe != nil
            && connect != nil
            && disconnect != nil
            && validatePairing != nil
            && startSession != nil
            && stopSession != nil
            && copyValue != nil
    }

    private static func readDevice(_ device: UnsafeMutableRawPointer?) -> BatteryDevice? {
        guard connect?(device) == 0 else { return nil }
        defer { _ = disconnect?(device) }

        _ = validatePairing?(device)
        let sessionStarted = startSession?(device) == 0
        defer {
            if sessionStarted { _ = stopSession?(device) }
        }

        guard let rawName = stringValue(copy(domain: nil, key: "DeviceName", from: device)) else { return nil }
        let name = DeviceScanner.cleanDeviceName(rawName)
        let productType = stringValue(copy(domain: nil, key: "ProductType", from: device)) ?? ""
        let deviceClass = stringValue(copy(domain: nil, key: "DeviceClass", from: device)) ?? ""
        let percent = intValue(copy(domain: "com.apple.mobile.battery", key: "BatteryCurrentCapacity", from: device))
        let charging = boolValue(copy(domain: "com.apple.mobile.battery", key: "BatteryIsCharging", from: device)) ?? false
        let kind = DeviceScanner.kind(forName: "\(name) \(productType) \(deviceClass)")
        guard percent != nil || kind == .phone || kind == .tablet || kind == .watch else { return nil }

        return BatteryDevice(
            id: "mobile-\(normalizedName(name))",
            name: name,
            percent: percent,
            kind: kind,
            charging: charging,
            presence: .continuity,
            detail: nil,
            address: nil,
            sourceRank: 0
        )
    }

    private static func copy(domain: String?, key: String, from device: UnsafeMutableRawPointer?) -> CFTypeRef? {
        copyValue?(device, domain.map { $0 as CFString }, key as CFString)?.takeRetainedValue()
    }

    private static func stringValue(_ value: CFTypeRef?) -> String? {
        value as? String
    }

    private static func intValue(_ value: CFTypeRef?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func boolValue(_ value: CFTypeRef?) -> Bool? {
        (value as? NSNumber)?.boolValue
    }

    private static func symbol<T>(_ name: String, handle: UnsafeMutableRawPointer, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}

private final class MobileDeviceCollector {
    private var devices: [BatteryDevice] = []
    private let lock = NSLock()

    func add(_ device: BatteryDevice) {
        lock.lock()
        defer { lock.unlock() }
        guard !devices.contains(where: { DeviceScanner.normalizedName($0.name) == DeviceScanner.normalizedName(device.name) }) else { return }
        devices.append(device)
    }

    func snapshot() -> [BatteryDevice] {
        lock.lock()
        defer { lock.unlock() }
        return devices
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
