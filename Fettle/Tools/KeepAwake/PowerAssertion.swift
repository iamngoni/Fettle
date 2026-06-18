import IOKit.pwr_mgt
import IOKit.ps
import Foundation

/// Holds an IOKit power-management assertion that keeps the Mac (and optionally
/// the display) awake. This is the same mechanism `caffeinate` uses, called
/// directly rather than shelling out.
final class PowerAssertion {
    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private(set) var isHeld = false
    private var heldPreventsDisplay = false

    /// Begin (or re-target) the assertion. Safe to call repeatedly.
    func begin(preventDisplaySleep: Bool, reason: String) {
        if isHeld && heldPreventsDisplay == preventDisplaySleep { return }
        end()
        let type = preventDisplaySleep
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id)
        if result == kIOReturnSuccess {
            assertionID = id
            isHeld = true
            heldPreventsDisplay = preventDisplaySleep
        }
    }

    func end() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        isHeld = false
    }

    deinit { if isHeld { IOPMAssertionRelease(assertionID) } }
}

/// Reads whether the Mac is currently running on AC power.
enum PowerSource {
    static func isOnACPower() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return true } // desktops report no battery; treat as plugged in
        if list.isEmpty { return true }
        for source in list {
            if let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
               let state = desc[kIOPSPowerSourceStateKey] as? String {
                if state == kIOPSACPowerValue { return true }
            }
        }
        return false
    }
}
