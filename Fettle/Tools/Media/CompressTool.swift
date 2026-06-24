import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CompressResult: Identifiable {
    let id = UUID()
    var name: String
    var before: Int64
    var after: Int64
    var failed: Bool
    var savedPercent: Int {
        guard before > 0, after > 0, after < before else { return 0 }
        return Int(((Double(before) - Double(after)) / Double(before) * 100).rounded())
    }
}

@MainActor
@Observable
final class CompressTool: FettleTool {
    let kind: ToolID = .compress
    let title = "Compress"
    let symbol = "arrow.down.right.and.arrow.up.left"
    let tint = Color(hex: 0x30D158)
    let section: ToolSection = .tools

    var quality: Double = Store.double("comp.quality", default: 0.7) {
        didSet { Store.set(quality, "comp.quality") }
    }
    var resizeEnabled = Store.bool("comp.resize", default: false) {
        didSet { Store.set(resizeEnabled, "comp.resize") }
    }
    var maxDimension: Double = Store.double("comp.maxDim", default: 2048) {
        didSet { Store.set(maxDimension, "comp.maxDim") }
    }
    var stripMetadata = Store.bool("comp.strip", default: true) {
        didSet { Store.set(stripMetadata, "comp.strip") }
    }
    var replaceOriginals = Store.bool("comp.replace", default: false) {
        didSet { Store.set(replaceOriginals, "comp.replace") }
    }
    var videoQuality = Store.rawValue("comp.vq", default: MediaConverter.VideoQuality.high) {
        didSet { Store.set(videoQuality, "comp.vq") }
    }

    private(set) var results: [CompressResult] = []
    private(set) var isWorking = false

    var isActive: Bool { false }
    var statusText: String { "Shrink images & videos on-device" }
    var statusTint: Color { Theme.textMuted }
    var control: ToolControl { .navigate }
    var hasDetail: Bool { true }

    var totalSaved: Int64 {
        results.filter { !$0.failed }.reduce(0) { $0 + max(0, $1.before - $1.after) }
    }
    var averageSaved: Int {
        let valid = results.filter { !$0.failed && $0.savedPercent > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0) { $0 + $1.savedPercent } / valid.count
    }

    func pickAndCompress() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .movie, .video, .audiovisualContent]
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        results.removeAll()
        isWorking = true
        Task {
            for url in urls { await compress(url) }
            isWorking = false
        }
    }

    private func compress(_ url: URL) async {
        let before = MediaConverter.fileSize(url)
        let type = UTType(filenameExtension: url.pathExtension)
        let isVideo = type?.conforms(to: .movie) == true || type?.conforms(to: .audiovisualContent) == true
        do {
            let out: URL
            if isVideo {
                out = try await MediaConverter.compressVideo(url, quality: videoQuality)
            } else {
                let imgType = type ?? .png
                let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
                out = try MediaConverter.convertImage(
                    url, to: imgType, ext: ext,
                    quality: quality,
                    maxDimension: resizeEnabled ? Int(maxDimension) : 0,
                    preserveMetadata: !stripMetadata)
            }
            var after = MediaConverter.fileSize(out)
            var finalName = out.lastPathComponent
            if replaceOriginals {
                // Atomic replace — a failure can't destroy the original.
                if (try? FileManager.default.replaceItemAt(url, withItemAt: out)) != nil {
                    finalName = url.lastPathComponent
                    after = MediaConverter.fileSize(url)
                }
            }
            results.append(CompressResult(name: finalName, before: before, after: after, failed: false))
        } catch {
            results.append(CompressResult(name: url.lastPathComponent, before: before, after: 0, failed: true))
        }
    }
}
