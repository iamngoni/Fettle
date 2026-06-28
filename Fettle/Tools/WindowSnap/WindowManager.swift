import AppKit
import ApplicationServices

/// Moves and resizes the focused window of the frontmost app using the
/// Accessibility API. Coordinates are converted from AppKit (bottom-left origin)
/// to Accessibility (top-left of the primary display).
enum WindowManager {

    enum Zone: String, CaseIterable {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case maximize, center
        case leftThird, centerThird, rightThird
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns the snapped frame (AppKit coords) on success, for the snap-flash.
    @discardableResult
    static func apply(_ zone: Zone, gap: CGFloat = 0) -> NSRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let windowRef = focused,
              CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement

        let screen = screenForWindow(window) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return nil }
        let target = frame(for: zone, in: visible.insetBy(dx: gap, dy: gap))

        setFrame(window, target)
        return target
    }

    // MARK: Zone math (AppKit bottom-left coordinates)

    private static func frame(for zone: Zone, in v: NSRect) -> NSRect {
        let halfW = v.width / 2, halfH = v.height / 2
        let thirdW = v.width / 3
        switch zone {
        case .leftHalf:   return NSRect(x: v.minX, y: v.minY, width: halfW, height: v.height)
        case .rightHalf:  return NSRect(x: v.minX + halfW, y: v.minY, width: halfW, height: v.height)
        case .topHalf:    return NSRect(x: v.minX, y: v.minY + halfH, width: v.width, height: halfH)
        case .bottomHalf: return NSRect(x: v.minX, y: v.minY, width: v.width, height: halfH)
        case .topLeft:    return NSRect(x: v.minX, y: v.minY + halfH, width: halfW, height: halfH)
        case .topRight:   return NSRect(x: v.minX + halfW, y: v.minY + halfH, width: halfW, height: halfH)
        case .bottomLeft: return NSRect(x: v.minX, y: v.minY, width: halfW, height: halfH)
        case .bottomRight:return NSRect(x: v.minX + halfW, y: v.minY, width: halfW, height: halfH)
        case .maximize:   return v
        case .center:     return NSRect(x: v.minX + v.width * 0.15, y: v.minY + v.height * 0.12,
                                        width: v.width * 0.7, height: v.height * 0.76)
        case .leftThird:  return NSRect(x: v.minX, y: v.minY, width: thirdW, height: v.height)
        case .centerThird:return NSRect(x: v.minX + thirdW, y: v.minY, width: thirdW, height: v.height)
        case .rightThird: return NSRect(x: v.minX + 2 * thirdW, y: v.minY, width: thirdW, height: v.height)
        }
    }

    // MARK: AX plumbing

    private static func setFrame(_ window: AXUIElement, _ nsRect: NSRect) {
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
        var point = CGPoint(x: nsRect.minX, y: primaryHeight - nsRect.minY - nsRect.height)
        var size = CGSize(width: nsRect.width, height: nsRect.height)

        if let posValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        // Re-apply position (some apps clamp size first).
        if let posValue = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
    }

    private static func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              let posRef, CFGetTypeID(posRef) == AXValueGetTypeID() else { return NSScreen.main }
        var point = CGPoint.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
        let nsPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first { $0.frame.contains(nsPoint) } ?? NSScreen.main
    }
}
