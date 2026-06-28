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
    static let shared = AppState()

    let keepAwake = KeepAwakeTool()
    let cleanMode = CleanModeTool()
    let micMute = MicMuteTool()
    let audioMixer = AudioMixerTool()
    let hideDesktop = HideDesktopTool()
    let presentation = PresentationTool()
    let battery = BatteryTool()
    let captureText = CaptureTextTool()
    let devices = DevicesTool()
    let meetings = MeetingsTool()
    let smartNotes = SmartNotesTool()
    let calculator = CalculatorTool()
    let convert = ConvertTool()
    let compress = CompressTool()
    let windowSnap = WindowSnapTool()
    let shortcuts = ShortcutsTool()
    let measure = MeasureTool()
    let notch = NotchTool()
    let license = LicenseManager()

    var route: Route = .dashboard
    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    init() {
        FettleLog.setup()
        launchAtLogin = LaunchAtLogin.isEnabled
        presentation.configure(keepAwake: keepAwake, hideDesktop: hideDesktop, micMute: micMute)
        keepAwake.restoreOnLaunch()
        shortcuts.configure(handlers: [
            "mute":         { [micMute] in micMute.setActive(!micMute.isActive) },
            "capture":      { [captureText] in captureText.triggerCapture() },
            "notes":        { [smartNotes] in smartNotes.toggle() },
            "keepAwake":    { [keepAwake] in keepAwake.setActive(!keepAwake.isActive) },
            "presentation": { [presentation] in presentation.setActive(!presentation.isActive) },
            "hideDesktop":  { [hideDesktop] in hideDesktop.setActive(!hideDesktop.isActive) },
        ])
    }

    var allTools: [any FettleTool] {
        [keepAwake, presentation, meetings, smartNotes, captureText, calculator, convert, compress, cleanMode, micMute, audioMixer, windowSnap, shortcuts, measure, notch, hideDesktop, battery, devices]
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
        case .captureText: captureText
        case .devices: devices
        case .meetings: meetings
        case .smartNotes: smartNotes
        case .calculator: calculator
        case .convert: convert
        case .compress: compress
        case .windowSnap: windowSnap
        case .shortcuts: shortcuts
        case .measure: measure
        case .notch: notch
        }
    }
}
