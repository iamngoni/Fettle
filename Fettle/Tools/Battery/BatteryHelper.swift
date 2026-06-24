import Foundation
import ServiceManagement
import OSLog

/// App-side client for the privileged battery helper. Registers the daemon via
/// `SMAppService` (prompts the user to approve it once) and talks to it over XPC.
@MainActor
final class BatteryHelper {
    static let shared = BatteryHelper()
    private let log = Logger(subsystem: "com.fettle.app", category: "BatteryHelper")

    private var connection: NSXPCConnection?

    private var service: SMAppService {
        SMAppService.daemon(plistName: BatteryHelperInfo.daemonPlistName)
    }

    var isRegistered: Bool { service.status == .enabled }
    var needsApproval: Bool { service.status == .requiresApproval }

    @discardableResult
    func register() -> Bool {
        guard service.status != .enabled else { return true }
        do {
            try service.register()
            return true
        } catch {
            log.error("Helper registration failed: \(error.localizedDescription)")
            return false
        }
    }

    func unregister() {
        try? service.unregister()
        connection?.invalidate()
        connection = nil
    }

    func openSystemSettingsForApproval() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func proxy(_ onError: @escaping () -> Void) -> BatteryHelperProtocol? {
        if connection == nil {
            let new = NSXPCConnection(machServiceName: BatteryHelperInfo.machServiceName, options: .privileged)
            new.remoteObjectInterface = NSXPCInterface(with: BatteryHelperProtocol.self)
            new.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
            new.interruptionHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
            new.resume()
            connection = new
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.log.error("XPC error: \(error.localizedDescription)")
            onError()
        } as? BatteryHelperProtocol
    }

    /// Pushes the full charge policy to the daemon.
    func apply(limit: Int, dischargeTo: Int, heatLimitC: Int, sailingBand: Int) {
        if !isRegistered { register() }
        proxy({})?.apply(limit: limit, dischargeTo: dischargeTo, heatLimitC: heatLimitC, sailingBand: sailingBand) { [weak self] ok in
            self?.log.log("apply(limit:\(limit) dischargeTo:\(dischargeTo) heat:\(heatLimitC) band:\(sailingBand)) -> \(ok)")
        }
    }

    func clearAll() {
        guard isRegistered else { return }
        proxy({})?.clearAll { [weak self] ok in
            self?.log.log("clearAll -> \(ok)")
        }
    }

    /// Closed-lid / clamshell Keep Awake via `pmset disablesleep`.
    func setDisableSleep(_ disabled: Bool) {
        if !isRegistered { register() }
        proxy({})?.setDisableSleep(disabled) { [weak self] ok in
            self?.log.log("setDisableSleep(\(disabled)) -> \(ok)")
        }
    }
}
