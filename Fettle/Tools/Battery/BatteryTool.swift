import SwiftUI
import IOKit.ps

@MainActor
@Observable
final class BatteryTool: FettleTool {
    let kind: ToolID = .battery
    let title = "Battery Limit"
    let symbol = "battery.100percent.bolt"
    let tint = Color(hex: 0x32D74B)
    let section: ToolSection = .system

    var limitEnabled = Store.bool("bat.limitEnabled", default: false) {
        didSet { Store.set(limitEnabled, "bat.limitEnabled"); applyLimit() }
    }
    var chargeLimit = Store.double("bat.chargeLimit", default: 80) {   // 50…100
        didSet { Store.set(chargeLimit, "bat.chargeLimit"); applyLimit() }
    }
    var topUpBeforeUnplug = Store.bool("bat.topUp", default: false) {
        didSet { Store.set(topUpBeforeUnplug, "bat.topUp") }
    }

    private(set) var currentLevel: Int = 0
    private(set) var isCharging = false
    private(set) var hasBattery = true

    var helperInstalled: Bool { BatteryHelper.shared.isRegistered }
    var helperNeedsApproval: Bool { BatteryHelper.shared.needsApproval }

    /// Pushes the current limit state to the privileged helper.
    private func applyLimit() {
        guard hasBattery else { return }
        if limitEnabled {
            BatteryHelper.shared.setChargeLimit(Int(chargeLimit))
        } else {
            BatteryHelper.shared.clearLimit()
        }
    }

    func installHelper() { BatteryHelper.shared.register() }
    func openHelperApproval() { BatteryHelper.shared.openSystemSettingsForApproval() }

    var isActive: Bool { limitEnabled }
    var statusText: String {
        guard hasBattery else { return "No battery" }
        return limitEnabled ? "Charging to \(Int(chargeLimit))%" : "No limit · \(currentLevel)%"
    }
    var statusTint: Color { limitEnabled ? Theme.greenLight : Theme.textMuted }
    var control: ToolControl { .value("\(Int(chargeLimit))%") }
    var hasDetail: Bool { true }

    init() { refresh() }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { hasBattery = false; return }
        guard let source = list.first,
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
    }
}
