import SwiftUI

/// Sections shown on the dashboard, in display order.
enum ToolSection: String, CaseIterable, Identifiable {
    case sessions = "SESSIONS"
    case tools = "CAPTURE & TOOLS"
    case inputAudio = "INPUT & AUDIO"
    case windows = "WINDOWS & MORE"
    case system = "SYSTEM"
    var id: String { rawValue }
}

/// Stable identity for every tool. Adding a tool starts here.
enum ToolID: String, CaseIterable, Identifiable, Hashable {
    case keepAwake, cleanMode, micMute, audioMixer, hideDesktop, presentation, battery
    case captureText, devices, meetings, smartNotes
    case calculator, convert, compress
    case windowSnap, shortcuts, measure, notch
    var id: String { rawValue }
}

/// The trailing control a tool exposes on the dashboard row.
enum ToolControl {
    case toggle          // on/off switch
    case navigate        // chevron only (opens detail)
    case toggleAndNavigate
    case value(String)   // a value label + chevron (e.g. "80%")
}

/// Every tool is a self-contained, observable module. The dashboard renders
/// it generically; its detail view is resolved by `kind`.
@MainActor
protocol FettleTool: AnyObject, Identifiable {
    var kind: ToolID { get }
    var title: String { get }
    var symbol: String { get }          // SF Symbol
    var tint: Color { get }
    var section: ToolSection { get }

    var isActive: Bool { get }
    var statusText: String { get }
    var statusTint: Color { get }       // color for the status sub-label
    var control: ToolControl { get }
    var hasDetail: Bool { get }

    /// Invoked when the dashboard toggle is flipped.
    func setActive(_ active: Bool)
}

extension FettleTool {
    var id: ToolID { kind }
    var statusTint: Color { isActive ? Theme.accentLight : Theme.textMuted }
    func setActive(_ active: Bool) {}
}
