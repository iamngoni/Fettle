import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class KeepAwakeTool: FettleTool {
    let kind: ToolID = .keepAwake
    let title = "Keep Awake"
    let symbol = "sun.max.fill"
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
    var triggerAppName = Store.string("ka.appName", default: "") {
        didSet { Store.set(triggerAppName, "ka.appName") }
    }
    var triggerAppBundleID = Store.string("ka.appBundle", default: "") {
        didSet { Store.set(triggerAppBundleID, "ka.appBundle") }
    }
    var hasTriggerApp: Bool { !triggerAppBundleID.isEmpty }

    /// Closed-lid (clamshell) mode — keeps the Mac awake with the lid shut, even
    /// with no external display. Backed by `pmset disablesleep` via the helper.
    var clamshellMode = Store.bool("ka.clamshell", default: false) {
        didSet { Store.set(clamshellMode, "ka.clamshell"); applyClamshell() }
    }
    var helperInstalled: Bool { BatteryHelper.shared.isRegistered }

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
        persistSession()
    }

    func stop() {
        manualOn = false
        endDate = nil
        evaluate()
        persistSession()
    }

    /// Persists the live on/off session so it survives relaunch.
    private func persistSession() {
        Store.set(manualOn, "ka.manualOn")
        Store.set(endDate?.timeIntervalSinceReferenceDate ?? 0, "ka.endDate")
    }

    /// Restores the session on launch: resumes an indefinite session, resumes a
    /// timed session with its remaining time, or honors "Activate on launch".
    func restoreOnLaunch() {
        if Store.bool("ka.manualOn", default: false) {
            let savedEnd = Store.double("ka.endDate", default: 0)
            if savedEnd == 0 {                       // was indefinite
                manualOn = true
                endDate = nil
                startTickerIfNeeded()
                evaluate()
                return
            }
            let end = Date(timeIntervalSinceReferenceDate: savedEnd)
            if end > Date() {                        // timed session still has time left
                manualOn = true
                endDate = end
                startTickerIfNeeded()
                evaluate()
                return
            }
            persistSession()                         // expired while quit → leave off
        }
        if activateOnLaunch { start() }
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
        guard !triggerAppBundleID.isEmpty else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == triggerAppBundleID
        }
    }

    /// Lets the user pick which app should hold the Mac awake.
    func chooseTriggerApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        triggerAppBundleID = Bundle(url: url)?.bundleIdentifier ?? ""
        triggerAppName = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        evaluate()
    }

    func installHelper() { BatteryHelper.shared.register() }

    // MARK: Clamshell (closed-lid) mode

    private func applyClamshell() {
        if clamshellMode {
            if !helperInstalled { BatteryHelper.shared.register() }
            startPollerIfNeeded()
            pushClamshellState()
        } else {
            BatteryHelper.shared.setDisableSleep(false)
            stopTimersIfIdle()
        }
    }

    /// Only disables sleep while on AC power — running closed-lid on battery is
    /// unsafe, so we revert automatically when unplugged (and re-apply on plug-in).
    private func pushClamshellState() {
        BatteryHelper.shared.setDisableSleep(clamshellMode && PowerSource.isOnACPower())
    }

    // MARK: Timers

    private func startTickerIfNeeded() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick &+= 1
                if let end = self.endDate, Date() >= end { self.stop() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func startPollerIfNeeded() {
        guard poller == nil, triggerWhileOnPower || triggerWhileAppRunning || clamshellMode else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.evaluate()
                if self.clamshellMode { self.pushClamshellState() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    private func stopTimersIfIdle() {
        if endDate == nil { ticker?.invalidate(); ticker = nil }
        if !triggerWhileOnPower && !triggerWhileAppRunning && !clamshellMode {
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
