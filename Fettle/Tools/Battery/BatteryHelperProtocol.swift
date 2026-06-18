import Foundation

/// XPC contract shared between the app and the privileged `FettleBatteryHelper`
/// daemon. The daemon runs as root and is the only component allowed to write
/// the SMC charge-control keys.
@objc public protocol BatteryHelperProtocol {
    func setChargeLimit(_ percent: Int, withReply reply: @escaping (Bool) -> Void)
    func clearLimit(withReply reply: @escaping (Bool) -> Void)
    func currentLimit(withReply reply: @escaping (Int) -> Void)
    func helperVersion(withReply reply: @escaping (String) -> Void)
}

public enum BatteryHelperInfo {
    public static let machServiceName = "com.fettle.FettleBatteryHelper"
    public static let daemonPlistName = "com.fettle.FettleBatteryHelper.plist"
    public static let version = "1.0.0"
}
