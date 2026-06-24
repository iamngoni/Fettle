import SwiftUI
import AppKit
import UniformTypeIdentifiers
import IOKit.ps

/// A borderless window pinned under the notch on the main screen. It shows a
/// small bar that expands on hover into a drag-and-drop shelf plus clock/battery.
/// Drives the notch panel's collapsed/expanded state. Driven by cursor polling
/// in the controller (not SwiftUI hover) so resizing the window can't create a
/// hover feedback loop.
@MainActor
@Observable
final class NotchState {
    var expanded = false
}

@MainActor
final class NotchController {
    private weak var tool: NotchTool?
    private var window: NSWindow?
    private let state = NotchState()
    private var pollTimer: Timer?

    init(tool: NotchTool) { self.tool = tool }

    // Collapsed window is a tiny trigger strip at the notch; expanded shows the
    // panel. While collapsed the window is click-through so it never blocks the
    // desktop.
    private static let collapsedSize = CGSize(width: 220, height: 30)
    private static let expandedSize = CGSize(width: 390, height: 212)

    func show() {
        guard window == nil, let tool, let screen = NSScreen.main else { return }
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
        pollTimer?.invalidate(); pollTimer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Expand when the cursor is in the trigger strip; collapse when it leaves the
    /// expanded frame. Uses fixed screen rects + absolute cursor position, so the
    /// window resizing can't feed back into the hit-testing.
    private func poll() {
        guard let window, let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        if state.expanded {
            if !window.frame.insetBy(dx: -6, dy: -6).contains(mouse) { setExpanded(false) }
        } else {
            if Self.frameRect(for: Self.collapsedSize, on: screen).contains(mouse) { setExpanded(true) }
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard let window, state.expanded != expanded else { return }
        state.expanded = expanded
        // Only toggle interactivity — the window frame stays fixed so the panel
        // can spring open/closed smoothly inside it.
        window.ignoresMouseEvents = !expanded
    }

    private static func frameRect(for size: CGSize, on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2,
               y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }
}

struct NotchPanelView: View {
    @Bindable var tool: NotchTool
    @Bindable var state: NotchState
    @State private var shelf: [URL] = []
    @State private var dropTargeted = false

    private var expanded: Bool { state.expanded }

    var body: some View {
        panel
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.expanded)
    }

    private var panel: some View {
        VStack(spacing: expanded ? 10 : 0) {
            if expanded {
                infoRow
                if tool.showNowPlaying, tool.nowPlaying.track != nil { nowPlayingRow }
                if tool.showShelf { shelfRow }
            }
        }
        .padding(.horizontal, expanded ? 14 : 0)
        .padding(.top, expanded ? 12 : 0)
        .padding(.bottom, expanded ? 14 : 0)
        .frame(width: expanded ? 360 : 190, height: expanded ? nil : 26)
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

    @ViewBuilder
    private var nowPlayingRow: some View {
        if let track = tool.nowPlaying.track {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(track.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    progressBar(track)
                }
                transportControls(track)
            }
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
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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

    private var infoRow: some View {
        let batt = NotchBattery.read()
        return HStack {
            if tool.showClock {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timeString(context.date))
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: batt.symbol).font(.system(size: 13)).foregroundStyle(batt.color)
                Text("\(batt.percent)%").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var shelfRow: some View {
        HStack(spacing: 8) {
            if shelf.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 15)).foregroundStyle(.white.opacity(0.5))
                    Text("Drop files here").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf, id: \.self) { url in
                            shelfItem(url)
                        }
                    }
                }
                .frame(height: 56)
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
