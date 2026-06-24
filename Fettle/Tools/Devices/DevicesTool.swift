import SwiftUI

@MainActor
@Observable
final class DevicesTool: FettleTool {
    let kind: ToolID = .devices
    let title = "Devices"
    let symbol = "laptopcomputer.and.iphone"
    let tint = Color(hex: 0x0A84FF)
    let section: ToolSection = .system

    private(set) var mac: BatteryDevice?
    private(set) var peripherals: [BatteryDevice] = []

    private var timer: Timer?

    var isActive: Bool { false }
    var statusText: String {
        let count = peripherals.count
        return count == 0 ? "No accessories found" : "\(count) connected"
    }
    var statusTint: Color { Theme.textMuted }
    var control: ToolControl {
        if let mac { return .value("\(mac.percent)%") }
        return .navigate
    }
    var hasDetail: Bool { true }

    init() { refresh() }

    func refresh() {
        let result = DeviceScanner.scan()
        mac = result.mac
        peripherals = result.peripherals
    }

    func startAutoRefresh() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
}
