import Foundation
import IOKit
import IOKit.ps

// Shared XPC contract — must match the app's BatteryHelperProtocol exactly.
@objc protocol BatteryHelperProtocol {
    func apply(limit: Int, dischargeTo: Int, heatLimitC: Int, sailingBand: Int,
               withReply reply: @escaping (Bool) -> Void)
    func clearAll(withReply reply: @escaping (Bool) -> Void)
    func batteryTempCelsius(withReply reply: @escaping (Int) -> Void)
    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (Bool) -> Void)
    func helperVersion(withReply reply: @escaping (String) -> Void)
}

private let machServiceName = "com.fettle.FettleBatteryHelper"
private let helperVersionString = "1.2.0"

/// Reads live battery facts straight from the IORegistry (no root needed for the
/// reads, but the daemon already runs as root and needs them in its loop).
enum BatteryReg {
    static func properties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    /// Battery temperature in whole degrees Celsius (AppleSmartBattery reports 1/100 °C).
    static func tempCelsius() -> Int {
        guard let raw = properties()?["Temperature"] as? Int else { return 0 }
        return Int((Double(raw) / 100.0).rounded())
    }

    static func percentage() -> Int {
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

/// Root daemon: receives the full charge policy and enforces it from a monitor
/// loop. On Intel it sets `BCLM`; on Apple Silicon it polls level + temperature
/// and drives charge-inhibit / force-discharge accordingly.
final class BatteryHelperService: NSObject, BatteryHelperProtocol, NSXPCListenerDelegate {
    private var limit = 100
    private var dischargeTo = 0
    private var heatLimitC = 0
    private var sailingBand = 5
    private var enforcing = false
    private var monitor: Timer?

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: BatteryHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func apply(limit: Int, dischargeTo: Int, heatLimitC: Int, sailingBand: Int,
               withReply reply: @escaping (Bool) -> Void) {
        // XPC delivers on a connection queue; the monitor Timer must live on the
        // main runloop (the only one being run), so marshal all of it to main.
        DispatchQueue.main.async {
            self.limit = max(20, min(100, limit))
            self.dischargeTo = max(0, min(100, dischargeTo))
            self.heatLimitC = max(0, heatLimitC)
            self.sailingBand = max(1, min(20, sailingBand))
            self.enforcing = self.limit < 100 || self.dischargeTo > 0 || self.heatLimitC > 0

            if SMC.isAppleSilicon {
                if self.enforcing { self.startMonitor() } else { self.stopMonitor() }
                self.enforce()
                reply(true)
            } else {
                // Intel only supports a fixed charge ceiling.
                reply(SMC.setIntelLimit(self.limit))
            }
        }
    }

    func clearAll(withReply reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            self.enforcing = false
            self.stopMonitor()
            if SMC.isAppleSilicon {
                SMC.setDischarge(false)
                reply(SMC.setCharging(true))
            } else {
                reply(SMC.clearIntelLimit())
            }
        }
    }

    func batteryTempCelsius(withReply reply: @escaping (Int) -> Void) {
        reply(BatteryReg.tempCelsius())
    }

    func setDisableSleep(_ disabled: Bool, withReply reply: @escaping (Bool) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        do {
            try task.run()
            task.waitUntilExit()
            reply(task.terminationStatus == 0)
        } catch {
            reply(false)
        }
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
        guard enforcing, SMC.isAppleSilicon else { return }
        let level = BatteryReg.percentage()
        let temp = BatteryReg.tempCelsius()

        // 1. Heat protection wins: too hot → stop charging, never discharge.
        if heatLimitC > 0, temp >= heatLimitC {
            SMC.setDischarge(false)
            SMC.setCharging(false)
            return
        }
        // 2. Discharge: run the battery down to the target while plugged in.
        if dischargeTo > 0, level > dischargeTo {
            SMC.setDischarge(true)
            return
        }
        SMC.setDischarge(false)
        // 3. Charge ceiling with a sailing (hysteresis) band.
        if limit < 100 {
            if level >= limit {
                SMC.setCharging(false)
            } else if level <= limit - sailingBand {
                SMC.setCharging(true)
            }
        } else {
            SMC.setCharging(true)
        }
    }
}

let delegate = BatteryHelperService()
let listener = NSXPCListener(machServiceName: machServiceName)
listener.delegate = delegate
listener.resume()

// Safety net: if the daemon is stopped/killed while charging is inhibited or the
// battery is being force-discharged, revert the SMC so the Mac isn't left stuck
// not charging or draining. DispatchSource handlers run on the main queue (not in
// signal context), so calling into IOKit here is safe.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        if SMC.isAppleSilicon { SMC.setDischarge(false); SMC.setCharging(true) }
        else { SMC.clearIntelLimit() }
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

RunLoop.main.run()
