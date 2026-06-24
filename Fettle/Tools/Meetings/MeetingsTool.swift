import SwiftUI
import EventKit
import AppKit
import OSLog

private let meetLog = Logger(subsystem: "com.fettle.app", category: "Meetings")

struct MeetingEvent: Identifiable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var url: URL?
    var attendees: Int
    var calendarColor: Color

    var startsInText: String {
        let mins = Int(start.timeIntervalSinceNow / 60)
        if mins <= 0 { return "now" }
        if mins < 60 { return "in \(mins) min" }
        return "in \(mins / 60)h \(mins % 60)m"
    }
    var timeRange: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        let f2 = DateFormatter(); f2.dateFormat = "h:mm a"
        return "\(f.string(from: start)) – \(f2.string(from: end))"
    }
    var sourceName: String {
        guard let host = url?.host else { return "Calendar" }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("teams") { return "Teams" }
        if host.contains("webex") { return "Webex" }
        return "Video call"
    }
}

@MainActor
@Observable
final class MeetingsTool: FettleTool {
    let kind: ToolID = .meetings
    let title = "Meetings"
    let symbol = "video.fill"
    let tint = Color(hex: 0x0A84FF)
    let section: ToolSection = .sessions

    var alertEnabled = Store.bool("meet.alert", default: true) {
        didSet { Store.set(alertEnabled, "meet.alert"); alertEnabled ? startMonitor() : stopMonitor() }
    }
    var leadMinutes = Store.double("meet.lead", default: 2) {
        didSet { Store.set(leadMinutes, "meet.lead") }
    }
    var autoOpenLink = Store.bool("meet.autoOpen", default: true) {
        didSet { Store.set(autoOpenLink, "meet.autoOpen") }
    }
    var playSound = Store.bool("meet.sound", default: true) {
        didSet { Store.set(playSound, "meet.sound") }
    }

    private(set) var authorized = false
    private(set) var upcoming: [MeetingEvent] = []
    private(set) var nextMeeting: MeetingEvent?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var monitor: Timer?
    @ObservationIgnored private var alertedIDs: Set<String> = []
    @ObservationIgnored private var snoozedUntil: [String: Date] = [:]
    @ObservationIgnored private lazy var alertController = MeetingAlertController(tool: self)

    var isActive: Bool { alertEnabled && authorized }
    var statusText: String {
        guard authorized else { return "Grant calendar access" }
        if let next = nextMeeting { return "Next · \(next.title) \(next.startsInText)" }
        return "No meetings today"
    }
    var statusTint: Color { isActive ? Theme.greenLight : Theme.textMuted }
    var control: ToolControl { .toggleAndNavigate }
    func setActive(_ active: Bool) {
        if active && !authorized { requestAccess() }
        alertEnabled = active
    }
    var hasDetail: Bool { true }

    var accessDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted
    }

    init() {
        syncAuth()
        meetLog.log("init — authStatus rawValue=\(EKEventStore.authorizationStatus(for: .event).rawValue) authorized=\(self.authorized)")
        if authorized {
            refresh()
            if alertEnabled { startMonitor() }
        }
    }

    private func syncAuth() {
        let s = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            authorized = (s == .fullAccess)
        } else {
            authorized = (s == .authorized)
        }
    }

    /// Prompts when undecided; deep-links to System Settings when already denied
    /// (EventKit will not re-prompt after a denial).
    func requestAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        meetLog.log("requestAccess tapped — status rawValue=\(status.rawValue)")
        switch status {
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            meetLog.log("status notDetermined → calling requestFullAccessToEvents")
            let handler: (Bool, Error?) -> Void = { granted, error in
                meetLog.log("request callback granted=\(granted) error=\(error?.localizedDescription ?? "nil")")
                Task { @MainActor in
                    self.syncAuth()
                    self.refresh()
                    if self.alertEnabled { self.startMonitor() }
                }
            }
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents(completion: handler)
            } else {
                store.requestAccess(to: .event, completion: handler)
            }
        case .denied, .restricted:
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
            let ok = NSWorkspace.shared.open(url)
            meetLog.log("status denied/restricted → opened Settings url result=\(ok)")
        default:
            meetLog.log("status already authorized → refreshing")
            syncAuth()
            refresh()
        }
    }

    func refresh() {
        syncAuth()
        guard authorized else { return }
        let cal = Calendar.current
        let now = Date()
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        upcoming = events.map { ev in
            MeetingEvent(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "Untitled",
                start: ev.startDate,
                end: ev.endDate,
                url: Self.meetingURL(from: ev),
                attendees: ev.attendees?.count ?? 0,
                calendarColor: ev.calendar.map { Color(nsColor: NSColor(cgColor: $0.cgColor) ?? .systemBlue) } ?? Color(hex: 0x0A84FF))
        }
        nextMeeting = upcoming.first
    }

    /// Finds a video-meeting URL in the event's URL, location, or notes.
    private static func meetingURL(from ev: EKEvent) -> URL? {
        if let u = ev.url, isMeetingHost(u.host) { return u }
        let blob = [ev.location, ev.notes].compactMap { $0 }.joined(separator: "\n")
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(blob.startIndex..., in: blob)
        let matches = detector?.matches(in: blob, range: range) ?? []
        for m in matches {
            if let u = m.url, isMeetingHost(u.host) { return u }
        }
        return ev.url
    }

    private static func isMeetingHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return ["zoom", "meet.google", "teams", "webex", "meet."].contains { host.contains($0) }
    }

    // MARK: Alert monitor

    func startMonitor() {
        guard monitor == nil, authorized else { return }
        monitor = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func stopMonitor() {
        monitor?.invalidate()
        monitor = nil
    }

    private func tick() {
        refresh()
        guard alertEnabled, let next = nextMeeting else { return }
        if let snooze = snoozedUntil[next.id], Date() < snooze { return }
        let lead = leadMinutes * 60
        let secondsToStart = next.start.timeIntervalSinceNow
        if secondsToStart <= lead, secondsToStart > -300, !alertedIDs.contains(next.id) {
            alertedIDs.insert(next.id)
            presentAlert(for: next)
        }
    }

    private func presentAlert(for meeting: MeetingEvent) {
        if playSound { NSSound(named: "Ping")?.play() }
        if autoOpenLink, let url = meeting.url { NSWorkspace.shared.open(url) }
        alertController.present(meeting: meeting)
    }

    // MARK: Alert actions

    func join(_ meeting: MeetingEvent) {
        if let url = meeting.url { NSWorkspace.shared.open(url) }
        alertController.dismiss()
    }

    func snooze(_ meeting: MeetingEvent, minutes: Int = 1) {
        snoozedUntil[meeting.id] = Date().addingTimeInterval(Double(minutes) * 60)
        alertedIDs.remove(meeting.id)
        alertController.dismiss()
    }

    func dismissAlert() {
        alertController.dismiss()
    }

    /// For previewing the overlay from the detail screen.
    func testAlert() {
        let demo = nextMeeting ?? MeetingEvent(
            id: "demo", title: "Design Review",
            start: Date().addingTimeInterval(120), end: Date().addingTimeInterval(1920),
            url: URL(string: "https://meet.google.com/abc-defg-hij"), attendees: 5,
            calendarColor: Color(hex: 0x0A84FF))
        presentAlert(for: demo)
    }
}
