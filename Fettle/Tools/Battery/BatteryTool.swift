import SwiftUI
import IOKit
import IOKit.ps

struct BatteryHealth {
    var cycleCount: Int
    var maxCapacityPercent: Int
    var tempC: Double
}

@MainActor
@Observable
final class BatteryTool: FettleTool {
    let kind: ToolID = .battery
    let title = "Battery"
    let symbol = "battery.100percent.bolt"
    let tint = Color(hex: 0x32D74B)
    let section: ToolSection = .system

    var limitEnabled = Store.bool("bat.limitEnabled", default: false) {
        didSet { Store.set(limitEnabled, "bat.limitEnabled"); applyPolicy() }
    }
    var chargeLimit = Store.double("bat.chargeLimit", default: 80) {   // 50…100
        didSet { Store.set(chargeLimit, "bat.chargeLimit"); applyPolicy() }
    }
    var dischargeEnabled = Store.bool("bat.discharge", default: false) {
        didSet { Store.set(dischargeEnabled, "bat.discharge"); applyPolicy() }
    }
    var dischargeTarget = Store.double("bat.dischargeTarget", default: 50) {
        didSet { Store.set(dischargeTarget, "bat.dischargeTarget"); applyPolicy() }
    }
    var heatProtect = Store.bool("bat.heat", default: false) {
        didSet { Store.set(heatProtect, "bat.heat"); applyPolicy() }
    }
    var heatLimit = Store.double("bat.heatLimit", default: 35) {
        didSet { Store.set(heatLimit, "bat.heatLimit"); applyPolicy() }
    }
    var sailingBand = Store.double("bat.sailing", default: 5) {
        didSet { Store.set(sailingBand, "bat.sailing"); applyPolicy() }
    }

    private(set) var currentLevel: Int = 0
    private(set) var isCharging = false
    private(set) var hasBattery = true
    private(set) var health: BatteryHealth?

    var helperInstalled: Bool { BatteryHelper.shared.isRegistered }
    var helperNeedsApproval: Bool { BatteryHelper.shared.needsApproval }

    /// Pushes the current charge policy to the privileged helper.
    func applyPolicy() {
        guard hasBattery else { return }
        let anyActive = limitEnabled || dischargeEnabled || heatProtect
        if anyActive {
            BatteryHelper.shared.apply(
                limit: limitEnabled ? Int(chargeLimit) : 100,
                dischargeTo: dischargeEnabled ? Int(dischargeTarget) : 0,
                heatLimitC: heatProtect ? Int(heatLimit) : 0,
                sailingBand: Int(sailingBand))
        } else {
            BatteryHelper.shared.clearAll()
        }
    }

    func installHelper() { BatteryHelper.shared.register() }
    func openHelperApproval() { BatteryHelper.shared.openSystemSettingsForApproval() }

    var isActive: Bool { limitEnabled || dischargeEnabled || heatProtect }
    var statusText: String {
        guard hasBattery else { return "No battery" }
        if dischargeEnabled { return "Discharging to \(Int(dischargeTarget))%" }
        if limitEnabled { return "Charging to \(Int(chargeLimit))%" }
        if heatProtect { return "Heat protection on · \(currentLevel)%" }
        return "No limit · \(currentLevel)%"
    }
    var statusTint: Color { isActive ? Theme.greenLight : Theme.textMuted }
    var control: ToolControl { .value("\(currentLevel)%") }
    var hasDetail: Bool { true }

    init() { refresh() }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { hasBattery = false; return }
        let source = list.first { src in
            guard let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any]
            else { return false }
            return (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        } ?? list.first
        guard let source,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else { hasBattery = false; return }

        hasBattery = true
        if let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
           let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
            currentLevel = Int((Double(capacity) / Double(max) * 100).rounded())
        }
        if let state = desc[kIOPSPowerSourceStateKey] as? String {
            isCharging = (state == kIOPSACPowerValue)
        }
        readHealth()
    }

    /// Reads cycle count, capacity health, and temperature from AppleSmartBattery.
    private func readHealth() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }

        let cycles = dict["CycleCount"] as? Int ?? 0
        let design = dict["DesignCapacity"] as? Int ?? 0
        // AppleRawMaxCapacity is in mAh (divide by design); MaxCapacity on Apple
        // Silicon is already a health percentage.
        var pct = 0
        if let rawMax = dict["AppleRawMaxCapacity"] as? Int, design > 0 {
            pct = Int((Double(rawMax) / Double(design) * 100).rounded())
        } else if let maxCapPct = dict["MaxCapacity"] as? Int {
            pct = maxCapPct
        }
        let temp = (dict["Temperature"] as? Int).map { Double($0) / 100.0 } ?? 0
        health = BatteryHealth(cycleCount: cycles,
                               maxCapacityPercent: min(100, max(0, pct)),
                               tempC: temp)
    }
}
