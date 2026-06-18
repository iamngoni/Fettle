import SwiftUI
import AppKit

@MainActor
@Observable
final class KeepAwakeTool: FettleTool {
    let kind: ToolID = .keepAwake
    let title = "Keep Awake"
    let symbol = "cup.and.saucer.fill"
    let tint = Theme.accent
    let section: ToolSection = .sessions

    enum Duration: String, CaseIterable, Identifiable {
        case m15, m30, h1, h2, h5, indefinite
        var id: String { rawValue }
        var label: String {
            switch self {
            case .m15: "15 min"; case .m30: "30 min"; case .h1: "1 hour"
            case .h2: "2 hours"; case .h5: "5 hours"; case .indefinite: "∞"
            }
        }
        var seconds: TimeInterval? {
            switch self {
            case .m15: 900; case .m30: 1800; case .h1: 3600
            case .h2: 7200; case .h5: 18000; case .indefinite: nil
            }
        }
    }

    // Persisted preferences
    var keepDisplayAwake = Store.bool("ka.keepDisplay", default: true) {
        didSet { Store.set(keepDisplayAwake, "ka.keepDisplay"); reassert() }
    }
    var activateOnLaunch = Store.bool("ka.activateOnLaunch", default: false) {
        didSet { Store.set(activateOnLaunch, "ka.activateOnLaunch") }
    }
    var selectedDuration = Store.rawValue("ka.duration", default: Duration.indefinite) {
        didSet { Store.set(selectedDuration, "ka.duration") }
    }

    // Triggers
    var triggerWhileOnPower = Store.bool("ka.trigPower", default: false) {
        didSet { Store.set(triggerWhileOnPower, "ka.trigPower"); evaluate() }
    }
    var triggerWhileAppRunning = Store.bool("ka.trigApp", default: false) {
        didSet { Store.set(triggerWhileAppRunning, "ka.trigApp"); evaluate() }
    }
    var triggerAppName = Store.string("ka.appName", default: "Final Cut Pro") {
        didSet { Store.set(triggerAppName, "ka.appName") }
    }
    var triggerAppBundleID = Store.string("ka.appBundle", default: "com.apple.FinalCut") {
        didSet { Store.set(triggerAppBundleID, "ka.appBundle") }
    }

    // Runtime state
    private(set) var isActive = false
    private(set) var endDate: Date?
    private var manualOn = false
    private var tick = 0   // drives countdown re-render

    private let assertion = PowerAssertion()
    private var ticker: Timer?
    private var poller: Timer?

    var statusText: String {
        _ = tick
        guard isActive else { return "Off" }
        if let endDate {
            let remaining = max(0, endDate.timeIntervalSinceNow)
            return "On · \(Self.format(remaining)) left"
        }
        if manualOn { return "On · indefinite" }
        return "On · trigger active"
    }

    var control: ToolControl { .toggleAndNavigate }
    var hasDetail: Bool { true }

    func setActive(_ active: Bool) { active ? start() : stop() }
    func toggle() { manualOn ? stop() : start() }

    func start() {
        manualOn = true
        if let secs = selectedDuration.seconds {
            endDate = Date().addingTimeInterval(secs)
        } else {
            endDate = nil
        }
        startTickerIfNeeded()
        evaluate()
    }

    func stop() {
        manualOn = false
        endDate = nil
        evaluate()
    }

    /// Decide whether the assertion should be held right now.
    private func evaluate() {
        var shouldHold = manualOn
        if let endDate, Date() >= endDate { shouldHold = false; manualOn = false; self.endDate = nil }
        if triggerWhileOnPower && PowerSource.isOnACPower() { shouldHold = true }
        if triggerWhileAppRunning && isTriggerAppRunning() { shouldHold = true }

        if shouldHold {
            assertion.begin(preventDisplaySleep: keepDisplayAwake, reason: "Fettle — Keep Awake")
            startPollerIfNeeded()
        } else {
            assertion.end()
        }
        isActive = assertion.isHeld
        if !isActive { stopTimersIfIdle() }
    }

    private func reassert() { if isActive { evaluate() } }

    private func isTriggerAppRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == triggerAppBundleID
        }
    }

    // MARK: Timers

    private func startTickerIfNeeded() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick &+= 1
                if let end = self.endDate, Date() >= end { self.stop() }
            }
        }
    }

    private func startPollerIfNeeded() {
        guard poller == nil, triggerWhileOnPower || triggerWhileAppRunning else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
    }

    private func stopTimersIfIdle() {
        if endDate == nil { ticker?.invalidate(); ticker = nil }
        if !triggerWhileOnPower && !triggerWhileAppRunning {
            poller?.invalidate(); poller = nil
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
