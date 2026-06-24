import Foundation

/// XPC contract shared between the app and the privileged `FettleBatteryHelper`
/// daemon. The daemon runs as root and is the only component allowed to write
/// the SMC charge-control keys.
///
/// `apply` carries the full charge policy in one call:
///  • `limit`       – charge ceiling 50…100 (100 = no ceiling)
///  • `dischargeTo` – if > 0, run on battery while plugged until level ≤ this
///  • `heatLimitC`  – if > 0, pause charging when battery temp ≥ this (°C)
///  • `sailingBand` – hysteresis %, charging resumes at `limit − sailingBand`
@objc public protocol BatteryHelperProtocol {
    func apply(limit: Int, dischargeTo: Int, heatLimitC: Int, sailingBand: Int,
               withReply reply: @escaping (Bool) -> Void)
    func clearAll(withReply reply: @escaping (Bool) -> Void)
    func batteryTempCelsius(withReply reply: @escaping (Int) -> Void)
    /// Toggles system-wide sleep disable (`pmset disablesleep`) — powers
    /// closed-lid / clamshell Keep Awake. Needs root, hence the helper.
    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (Bool) -> Void)
    func helperVersion(withReply reply: @escaping (String) -> Void)
}

public enum BatteryHelperInfo {
    public static let machServiceName = "com.fettle.FettleBatteryHelper"
    public static let daemonPlistName = "com.fettle.FettleBatteryHelper.plist"
    public static let version = "1.2.0"
}
