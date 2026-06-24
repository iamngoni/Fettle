import SwiftUI
import AppKit
import UniformTypeIdentifiers
import IOKit.ps

/// A borderless window pinned under the notch on the main screen. It shows a
/// small bar that expands on hover into a drag-and-drop shelf plus clock/battery.
@MainActor
final class NotchController {
    private weak var tool: NotchTool?
    private var window: NSWindow?

    init(tool: NotchTool) { self.tool = tool }

    func show() {
        guard window == nil, let tool, let screen = NSScreen.main else { return }
        let width: CGFloat = 420, height: CGFloat = 220
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        let win = NSWindow(contentRect: NSRect(x: x, y: y, width: width, height: height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.contentView = NSHostingView(rootView: NotchPanelView(tool: tool))
        win.orderFrontRegardless()
        window = win
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

struct NotchPanelView: View {
    @Bindable var tool: NotchTool
    @State private var expanded = false
    @State private var shelf: [URL] = []
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            panel
                .onHover { hovering in
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { expanded = hovering }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var panel: some View {
        VStack(spacing: expanded ? 10 : 0) {
            if expanded { infoRow }
            if expanded && tool.showShelf { shelfRow }
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
