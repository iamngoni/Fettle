import Foundation
import IOKit.ps

// Shared XPC contract — must match the app's BatteryHelperProtocol exactly.
@objc protocol BatteryHelperProtocol {
    func setChargeLimit(_ percent: Int, withReply reply: @escaping (Bool) -> Void)
    func clearLimit(withReply reply: @escaping (Bool) -> Void)
    func currentLimit(withReply reply: @escaping (Int) -> Void)
    func helperVersion(withReply reply: @escaping (String) -> Void)
}

private let machServiceName = "com.fettle.FettleBatteryHelper"
private let helperVersionString = "1.0.0"

/// Root daemon: receives a target percentage and enforces it. On Intel it sets
/// `BCLM`; on Apple Silicon it polls battery level and toggles charge-inhibit
/// around the threshold.
final class BatteryHelperService: NSObject, BatteryHelperProtocol, NSXPCListenerDelegate {
    private var targetLimit: Int = 0
    private var enforcing = false
    private var monitor: Timer?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: BatteryHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func setChargeLimit(_ percent: Int, withReply reply: @escaping (Bool) -> Void) {
        targetLimit = max(20, min(100, percent))
        enforcing = percent < 100
        if SMC.isAppleSilicon {
            startMonitor()
            enforce()
            reply(true)
        } else {
            reply(SMC.setIntelLimit(targetLimit))
        }
    }

    func clearLimit(withReply reply: @escaping (Bool) -> Void) {
        enforcing = false
        stopMonitor()
        if SMC.isAppleSilicon {
            reply(SMC.setCharging(true))
        } else {
            reply(SMC.clearIntelLimit())
        }
    }

    func currentLimit(withReply reply: @escaping (Int) -> Void) {
        reply(enforcing ? targetLimit : 100)
    }

    func helperVersion(withReply reply: @escaping (String) -> Void) {
        reply(helperVersionString)
    }

    // MARK: Apple Silicon enforcement loop

    private func startMonitor() {
        guard monitor == nil else { return }
        monitor = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.enforce() }
    }

    private func stopMonitor() {
        monitor?.invalidate()
        monitor = nil
    }

    private func enforce() {
        guard enforcing else { return }
        let level = batteryPercentage()
        // Small hysteresis band so we don't thrash the charger.
        if level >= targetLimit {
            SMC.setCharging(false)
        } else if level <= targetLimit - 3 {
            SMC.setCharging(true)
        }
    }

    private func batteryPercentage() -> Int {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              let capacity = desc[kIOPSCurrentCapacityKey] as? Int,
              let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
        else { return 100 }
        return Int((Double(capacity) / Double(max) * 100).rounded())
    }
}

let delegate = BatteryHelperService()
let listener = NSXPCListener(machServiceName: machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
