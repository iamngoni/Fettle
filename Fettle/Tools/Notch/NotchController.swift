import SwiftUI
import AppKit
import UniformTypeIdentifiers
import IOKit.ps

/// A borderless window pinned to the notch on the main screen. It stays visually
/// blank and notch-sized while collapsed, then expands on hover into utilities.
/// Drives the notch panel's collapsed/expanded state. Driven by cursor polling
/// in the controller (not SwiftUI hover) so resizing the window can't create a
/// hover feedback loop.
@MainActor
@Observable
final class NotchState {
    var expanded = false
    var metrics = NotchDisplayMetrics()
}

struct NotchDisplayMetrics: Equatable {
    var notchGapWidth: CGFloat = 0
    var menuBarHeight: CGFloat = 32

    var hasCameraHousing: Bool { notchGapWidth > 24 }
    var collapsedHeight: CGFloat { max(26, min(34, menuBarHeight)) }
    var collapsedWidth: CGFloat { hasCameraHousing ? notchGapWidth : 210 }
    var triggerHeight: CGFloat { collapsedHeight + 28 }
    var triggerWidth: CGFloat { hasCameraHousing ? max(collapsedWidth, min(collapsedWidth + 90, 280)) : collapsedWidth }
}

@MainActor
final class NotchController {
    private weak var tool: NotchTool?
    private var window: NSWindow?
    private let state = NotchState()
    private var pollTask: Task<Void, Never>?

    init(tool: NotchTool) { self.tool = tool }

    // Collapsed window is a tiny trigger strip at the notch; expanded shows the
    // panel. While collapsed the window is click-through so it never blocks the
    // desktop.
    private static let expandedSize = CGSize(width: 1150, height: 180)

    func show() {
        guard window == nil, let tool, let screen = NSScreen.main else { return }
        let metrics = Self.displayMetrics(for: screen)
        state.metrics = metrics
        // Fixed window at the expanded size; the panel animates *within* it (so the
        // popout stays smooth). Click-through while collapsed; interactive while open.
        let win = NSWindow(contentRect: Self.frameRect(for: Self.expandedSize, on: screen),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.hasShadow = false
        win.ignoresMouseEvents = true        // collapsed: clicks pass through entirely
        win.contentView = NSHostingView(rootView: NotchPanelView(tool: tool, state: state))
        win.orderFrontRegardless()
        window = win
        startPolling()
    }

    func hide() {
        pollTask?.cancel(); pollTask = nil
        window?.orderOut(nil)
        window = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    /// Expand when the cursor is in the trigger strip; collapse when it leaves the
    /// expanded frame. Uses fixed screen rects + absolute cursor position, so the
    /// window resizing can't feed back into the hit-testing.
    private func poll() {
        guard let window, let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let metrics = Self.displayMetrics(for: screen)
        if state.metrics != metrics {
            state.metrics = metrics
        }
        reposition(window, on: screen)
        if state.expanded {
            if !window.frame.insetBy(dx: -6, dy: -6).contains(mouse) { setExpanded(false) }
        } else {
            if Self.triggerRect(for: metrics, on: screen).contains(mouse) { setExpanded(true) }
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard let window, state.expanded != expanded else { return }
        state.expanded = expanded
        // Only toggle interactivity — the window frame stays fixed so the panel
        // can spring open/closed smoothly inside it.
        window.ignoresMouseEvents = !expanded
    }

    private func reposition(_ window: NSWindow, on screen: NSScreen) {
        let target = Self.frameRect(for: Self.expandedSize, on: screen)
        guard abs(window.frame.minX - target.minX) > 0.5 ||
              abs(window.frame.minY - target.minY) > 0.5 ||
              abs(window.frame.width - target.width) > 0.5 ||
              abs(window.frame.height - target.height) > 0.5
        else { return }
        window.setFrame(target, display: true)
    }

    private static func frameRect(for size: CGSize, on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2,
                      y: screen.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private static func triggerRect(for metrics: NotchDisplayMetrics, on screen: NSScreen) -> NSRect {
        frameRect(for: CGSize(width: metrics.triggerWidth, height: metrics.triggerHeight), on: screen)
    }

    private static func displayMetrics(for screen: NSScreen) -> NotchDisplayMetrics {
        var menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        var notchGapWidth: CGFloat = 0
        if #available(macOS 12.0, *) {
            menuBarHeight = max(menuBarHeight, screen.safeAreaInsets.top)
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                notchGapWidth = max(0, right.minX - left.maxX)
            }
        }
        return NotchDisplayMetrics(notchGapWidth: notchGapWidth, menuBarHeight: menuBarHeight)
    }
}

struct NotchPanelView: View {
    private enum Module: Hashable {
        case nowPlaying, devices, meetings, quickActions, shelf, status

        var width: CGFloat {
            switch self {
            case .nowPlaying: return 380
            case .devices: return 300
            case .meetings: return 260
            case .quickActions: return 190
            case .shelf: return 170
            case .status: return 84
            }
        }
    }

    @Bindable var tool: NotchTool
    @Bindable var state: NotchState
    @State private var shelf: [URL] = []
    @State private var dropTargeted = false
    @State private var lastExpandedRefresh = Date.distantPast

    private var expanded: Bool { state.expanded }
    private var app: AppState { AppState.shared }
    private var metrics: NotchDisplayMetrics { state.metrics }

    var body: some View {
        panel
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.expanded)
            .onChange(of: state.expanded) { _, expanded in
                if expanded { refreshExpandedDataIfNeeded() }
            }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedRow
            } else {
                collapsedRow
            }
        }
        .padding(.horizontal, expanded ? 14 : 0)
        .padding(.top, expanded ? 14 : 0)
        .padding(.bottom, expanded ? 14 : 0)
        .frame(width: expanded ? expandedPanelWidth : metrics.collapsedWidth,
               height: expanded ? 144 : metrics.collapsedHeight)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: expanded ? 22 : 12,
                                   bottomTrailingRadius: expanded ? 22 : 12, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(.black)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: expanded ? 22 : 12,
                                   bottomTrailingRadius: expanded ? 22 : 12, topTrailingRadius: 0,
                                   style: .continuous)
                .stroke(Color.white.opacity(dropTargeted ? 0.5 : 0.08), lineWidth: 1)
        )
    }

    private var expandedRow: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(visibleModules, id: \.self) { module in
                moduleView(module)
                    .frame(width: module.width)
            }
        }
    }

    private var visibleModules: [Module] {
        let enabled: [Module] = [
            tool.showNowPlaying ? .nowPlaying : nil,
            tool.showDevices ? .devices : nil,
            tool.showMeetings ? .meetings : nil,
            tool.showQuickActions ? .quickActions : nil,
            tool.showShelf ? .shelf : nil,
            tool.showClock ? .status : nil
        ].compactMap { $0 }
        return Array((enabled.isEmpty ? [.status] : enabled).prefix(tool.maxItems))
    }

    private var expandedPanelWidth: CGFloat {
        let modules = visibleModules
        let contentWidth = modules.reduce(CGFloat(0)) { $0 + $1.width }
        let spacing = CGFloat(max(0, modules.count - 1)) * 8
        return contentWidth + spacing + 28
    }

    @ViewBuilder
    private func moduleView(_ module: Module) -> some View {
        switch module {
        case .nowPlaying: nowPlayingRow
        case .devices: devicesRow
        case .meetings: meetingsRow
        case .quickActions: quickActionsRow
        case .shelf: shelfRow
        case .status: statusChip
        }
    }

    @ViewBuilder
    private var collapsedRow: some View {
        Color.clear
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var nowPlayingRow: some View {
        if let track = tool.nowPlaying.track {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(track.artist).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    progressBar(track)
                }
                transportControls(track)
            }
            .padding(11)
            .frame(height: 116)
            .background(moduleBackground)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("No media playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("Start audio or video")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
            }
            .padding(11)
            .frame(height: 116)
            .background(moduleBackground)
        }
    }

    private var artwork: some View {
        Group {
            if let image = tool.nowPlaying.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(hex: 0xFF6B8A), Color(hex: 0x5E5CE6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8)))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func progressBar(_ track: NowPlayingModel.Track) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let frac = track.duration > 0 ? track.liveElapsed(at: ctx.date) / track.duration : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 3)
                    Capsule().fill(.white).frame(width: max(0, geo.size.width * frac), height: 3)
                }
            }
            .frame(height: 3)
        }
        .frame(height: 3)
    }

    private func transportControls(_ track: NowPlayingModel.Track) -> some View {
        HStack(spacing: 14) {
            Button { tool.nowPlaying.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 13)).foregroundStyle(.white)
            }.buttonStyle(.plain)
            Button { tool.nowPlaying.togglePlayPause() } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16)).foregroundStyle(.white)
            }.buttonStyle(.plain)
            Button { tool.nowPlaying.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 13)).foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
    }

    private var devicesRow: some View {
        let devices = notchDevices
        return HStack(spacing: 10) {
            moduleIcon("laptopcomputer.and.iphone", tint: Color(hex: 0x0A84FF))
            VStack(alignment: .leading, spacing: 5) {
                Text("Devices")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                if devices.isEmpty {
                    Text("Scanning nearby batteries")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                } else {
                    HStack(spacing: 6) {
                        ForEach(devices.prefix(3)) { device in deviceChip(device) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(height: 116)
        .background(moduleBackground)
    }

    private var meetingsRow: some View {
        HStack(spacing: 10) {
            moduleIcon("calendar", tint: Color(hex: 0x64D2FF))
            VStack(alignment: .leading, spacing: 2) {
                if app.meetings.authorized, let meeting = app.meetings.nextMeeting {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                    Text("\(meeting.startsInText) · \(meeting.timeRange)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                } else if app.meetings.authorized {
                    Text("No more meetings today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                } else {
                    Text("Calendar access needed")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            Spacer(minLength: 0)
            if app.meetings.authorized, let meeting = app.meetings.nextMeeting, meeting.url != nil {
                Button { app.meetings.join(meeting) } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(hex: 0x0A84FF).opacity(0.85)))
                }
                .buttonStyle(.plain)
                .help("Join meeting")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(height: 116)
        .background(moduleBackground)
    }

    private var quickActionsRow: some View {
        HStack(spacing: 8) {
            quickActionButton(symbol: app.micMute.isMuted ? "mic.slash.fill" : "mic.fill",
                              tint: Theme.red,
                              active: app.micMute.isMuted,
                              help: app.micMute.isMuted ? "Unmute mic" : "Mute mic") {
                app.micMute.toggle()
            }
            quickActionButton(symbol: app.keepAwake.isActive ? "sun.max.fill" : "moon.zzz.fill",
                              tint: Theme.accent,
                              active: app.keepAwake.isActive,
                              help: app.keepAwake.isActive ? "Stop Keep Awake" : "Start Keep Awake") {
                app.keepAwake.toggle()
            }
            quickActionButton(symbol: app.smartNotes.isActive ? "stop.circle.fill" : "waveform.badge.mic",
                              tint: Color(hex: 0x5E5CE6),
                              active: app.smartNotes.isActive,
                              help: app.smartNotes.isActive ? "Stop Smart Notes" : "Start Smart Notes") {
                app.smartNotes.toggle()
            }
            quickActionButton(symbol: "text.viewfinder",
                              tint: Color(hex: 0x32D74B),
                              active: false,
                              help: "Capture text") {
                app.captureText.triggerCapture()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(height: 116)
        .background(moduleBackground)
    }

    private var notchDevices: [BatteryDevice] {
        let withLevels = app.devices.peripherals.filter { $0.percent != nil }
        if !withLevels.isEmpty { return Array(withLevels.prefix(4)) }
        return Array(app.devices.peripherals.prefix(3))
    }

    private func deviceChip(_ device: BatteryDevice) -> some View {
        HStack(spacing: 4) {
            Image(systemName: device.kind.symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(device.percentText.isEmpty ? "No level" : device.percentText)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(device.percent == nil ? .white.opacity(0.48) : device.levelColor)
        .padding(.horizontal, 6)
        .frame(height: 21)
        .background(Capsule().fill(.white.opacity(0.07)))
        .fixedSize(horizontal: true, vertical: false)
        .help(device.name)
    }

    private func quickActionButton(symbol: String, tint: Color, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? .black : tint)
                .frame(width: 34, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.16)))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func moduleIcon(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.18))
            .frame(width: 54, height: 54)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            )
    }

    private var moduleBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.06))
    }

    private var statusChip: some View {
        let batt = NotchBattery.read()
        return VStack(spacing: 3) {
            if tool.showClock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(compactTimeString(context.date))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            HStack(spacing: 3) {
                Image(systemName: batt.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(batt.color)
                Text("\(batt.percent)%")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .background(moduleBackground)
    }

    private var shelfRow: some View {
        HStack(spacing: 8) {
            if shelf.isEmpty {
                VStack(spacing: 3) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Drop")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, minHeight: 116)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf, id: \.self) { url in
                            shelfItem(url)
                        }
                    }
                }
                .frame(height: 116)
            }
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.white.opacity(dropTargeted ? 0.5 : 0.12)))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { if !shelf.contains(url) { shelf.append(url) } } }
                }
            }
            return true
        }
    }

    private func shelfItem(_ url: URL) -> some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 30, height: 30)
            Text(url.lastPathComponent).font(.system(size: 8)).foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).frame(width: 46)
        }
        .padding(4)
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Remove") { shelf.removeAll { $0 == url } }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE  h:mm"; return f.string(from: date)
    }

    private func compactTimeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f.string(from: date)
    }

    private func refreshExpandedDataIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastExpandedRefresh) > 15 else { return }
        lastExpandedRefresh = now
        if tool.showDevices { app.devices.refresh() }
        if tool.showMeetings { app.meetings.refresh() }
    }
}

enum NotchBattery {
    struct Snapshot {
        let percent: Int
        let charging: Bool
        var symbol: String {
            if charging { return "battery.100percent.bolt" }
            if percent >= 80 { return "battery.100percent" }
            if percent >= 50 { return "battery.75percent" }
            if percent >= 25 { return "battery.50percent" }
            if percent >= 10 { return "battery.25percent" }
            return "battery.0percent"
        }
        var color: Color {
            if charging || percent > 50 { return Color(hex: 0x32D74B) }
            if percent >= 25 { return Color(hex: 0xFF9F0A) }
            return Color(hex: 0xFF453A)
        }
    }

    /// One lightweight power-source read (no Bluetooth HID enumeration).
    static func read() -> Snapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let src = list.first,
              let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any],
              let cap = d[kIOPSCurrentCapacityKey] as? Int,
              let mx = d[kIOPSMaxCapacityKey] as? Int, mx > 0
        else { return Snapshot(percent: 100, charging: false) }
        let pct = Int((Double(cap) / Double(mx) * 100).rounded())
        let charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return Snapshot(percent: pct, charging: charging)
    }
}
