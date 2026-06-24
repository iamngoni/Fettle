import SwiftUI
import AppKit

struct MeasureRecord: Identifiable {
    let id = UUID()
    var symbol: String
    var value: String
    var kind: String
    var color: Color?
}

@MainActor
@Observable
final class MeasureTool: FettleTool {
    let kind: ToolID = .measure
    let title = "Measure"
    let symbol = "ruler"
    let tint = Color(hex: 0xFF375F)
    let section: ToolSection = .tools

    var colorAsHex = Store.bool("measure.hex", default: true) {
        didSet { Store.set(colorAsHex, "measure.hex") }
    }
    private(set) var recents: [MeasureRecord] = []

    @ObservationIgnored private lazy var overlay = MeasureOverlayController(tool: self)

    var isActive: Bool { false }
    var statusText: String { "Pixel ruler & color picker" }
    var statusTint: Color { Theme.textMuted }
    var control: ToolControl { .navigate }
    var hasDetail: Bool { true }

    func pickColor() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] picked in
            guard let self, let picked else { return }
            let srgb = picked.usingColorSpace(.sRGB) ?? picked
            let r = Int((srgb.redComponent * 255).rounded())
            let g = Int((srgb.greenComponent * 255).rounded())
            let b = Int((srgb.blueComponent * 255).rounded())
            let value = self.colorAsHex
                ? String(format: "#%02X%02X%02X", r, g, b)
                : "rgb(\(r), \(g), \(b))"
            self.copy(value)
            self.add(MeasureRecord(symbol: "eyedropper", value: value, kind: "Color",
                                   color: Color(srgb)))
        }
    }

    func measureSize() {
        overlay.present { [weak self] width, height in
            guard let self else { return }
            let value = "\(Int(width)) × \(Int(height)) px"
            self.copy(value)
            self.add(MeasureRecord(symbol: "ruler", value: value, kind: "Selection", color: nil))
        }
    }

    func copyRecent(_ record: MeasureRecord) { copy(record.value) }

    func clear() { recents.removeAll() }

    private func add(_ record: MeasureRecord) {
        recents.insert(record, at: 0)
        if recents.count > 8 { recents = Array(recents.prefix(8)) }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
