import SwiftUI
import Observation

enum Route: Hashable {
    case dashboard
    case settings
    case tool(ToolID)
}

/// Owns every tool instance and the menu navigation state.
/// Registering a new tool = add a stored property + include it in `allTools`.
@MainActor
@Observable
final class AppState {
    let keepAwake = KeepAwakeTool()
    let cleanMode = CleanModeTool()
    let micMute = MicMuteTool()
    let audioMixer = AudioMixerTool()
    let hideDesktop = HideDesktopTool()
    let presentation = PresentationTool()
    let battery = BatteryTool()

    var route: Route = .dashboard
    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    init() {
        launchAtLogin = LaunchAtLogin.isEnabled
        presentation.configure(keepAwake: keepAwake, hideDesktop: hideDesktop, micMute: micMute)
        if keepAwake.activateOnLaunch { keepAwake.start() }
    }

    var allTools: [any FettleTool] {
        [keepAwake, presentation, cleanMode, micMute, audioMixer, hideDesktop, battery]
    }

    func tools(in section: ToolSection) -> [any FettleTool] {
        allTools.filter { $0.section == section }
    }

    var activeCount: Int {
        allTools.reduce(0) { $0 + ($1.isActive ? 1 : 0) }
    }

    func tool(for id: ToolID) -> any FettleTool {
        switch id {
        case .keepAwake: keepAwake
        case .cleanMode: cleanMode
        case .micMute: micMute
        case .audioMixer: audioMixer
        case .hideDesktop: hideDesktop
        case .presentation: presentation
        case .battery: battery
        }
    }
}
