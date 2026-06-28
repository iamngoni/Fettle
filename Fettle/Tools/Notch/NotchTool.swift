import SwiftUI

@MainActor
@Observable
final class NotchTool: FettleTool {
    let kind: ToolID = .notch
    let title = "Notch"
    let symbol = "macbook"
    let tint = Color(hex: 0xBF5AF2)
    let section: ToolSection = .windows

    var enabled = Store.bool("notch.enabled", default: false) {
        didSet {
            Store.set(enabled, "notch.enabled")
            if enabled { controller.show(); nowPlaying.start() }
            else { controller.hide(); nowPlaying.stop() }
        }
    }
    var showShelf = Store.bool("notch.shelf", default: true) {
        didSet { Store.set(showShelf, "notch.shelf") }
    }
    var showClock = Store.bool("notch.clock", default: true) {
        didSet { Store.set(showClock, "notch.clock") }
    }
    var showNowPlaying = Store.bool("notch.nowplaying", default: true) {
        didSet { Store.set(showNowPlaying, "notch.nowplaying") }
    }
    var showDevices = Store.bool("notch.devices", default: true) {
        didSet { Store.set(showDevices, "notch.devices") }
    }
    var showMeetings = Store.bool("notch.meetings", default: true) {
        didSet { Store.set(showMeetings, "notch.meetings") }
    }
    var showQuickActions = Store.bool("notch.quickActions", default: true) {
        didSet { Store.set(showQuickActions, "notch.quickActions") }
    }
    var maxItems = min(3, max(1, Store.int("notch.maxItems", default: 3))) {
        didSet {
            maxItems = min(3, max(1, maxItems))
            Store.set(maxItems, "notch.maxItems")
        }
    }

    let nowPlaying = NowPlayingModel()
    @ObservationIgnored private lazy var controller = NotchController(tool: self)

    var isActive: Bool { enabled }
    var statusText: String { enabled ? "Active under the notch" : "Hover widgets & file shelf" }
    var statusTint: Color { enabled ? Theme.greenLight : Theme.textMuted }
    var control: ToolControl { .toggleAndNavigate }
    func setActive(_ active: Bool) { enabled = active }
    var hasDetail: Bool { true }

    init() {
        if enabled { controller.show(); nowPlaying.start() }
    }
}
