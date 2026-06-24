import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum JobStatus: Equatable { case running, done, failed }

struct ConvertJob: Identifiable {
    let id = UUID()
    var name: String
    var status: JobStatus
    var detail: String
}

@MainActor
@Observable
final class ConvertTool: FettleTool {
    enum Category: String, CaseIterable { case video = "Video", audio = "Audio", image = "Image" }

    let kind: ToolID = .convert
    let title = "Convert"
    let symbol = "arrow.triangle.2.circlepath"
    let tint = Color(hex: 0x0A84FF)
    let section: ToolSection = .tools

    var category: Category = .video
    var videoFormat = "mp4"
    var audioFormat = "m4a"
    var imageFormat = "png"
    private(set) var jobs: [ConvertJob] = []

    var isActive: Bool { false }
    var statusText: String { "Audio · video · image" }
    var statusTint: Color { Theme.textMuted }
    var control: ToolControl { .navigate }
    var hasDetail: Bool { true }

    var formatOptions: [String] {
        switch category {
        case .video: return ["mp4", "mov", "m4v"]
        case .audio: return ["m4a", "wav", "aiff", "caf"]
        case .image: return ["png", "jpeg", "heic", "tiff"]
        }
    }
    var selectedFormat: String {
        switch category {
        case .video: return videoFormat
        case .audio: return audioFormat
        case .image: return imageFormat
        }
    }
    func selectFormat(_ f: String) {
        switch category {
        case .video: videoFormat = f
        case .audio: audioFormat = f
        case .image: imageFormat = f
        }
    }

    func pickAndConvert() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = allowedTypes
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { for url in urls { await run(url) } }
    }

    private var allowedTypes: [UTType] {
        switch category {
        case .video: return [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        case .audio: return [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        case .image: return [.image]
        }
    }

    private func run(_ url: URL) async {
        let inputSize = MediaConverter.fileSize(url)
        let job = ConvertJob(name: url.lastPathComponent, status: .running, detail: "Converting…")
        jobs.insert(job, at: 0)
        let id = job.id
        do {
            let out = try await convert(url)
            let outSize = MediaConverter.fileSize(out)
            update(id, .done, "→ \(out.lastPathComponent) · \(MediaConverter.humanSize(outSize)) (was \(MediaConverter.humanSize(inputSize)))")
        } catch {
            update(id, .failed, "Couldn’t convert")
        }
    }

    private func convert(_ url: URL) async throws -> URL {
        switch category {
        case .video:
            let map: [String: (AVFileType, String)] = [
                "mp4": (.mp4, "mp4"), "mov": (.mov, "mov"), "m4v": (.m4v, "m4v")]
            let (type, ext) = map[videoFormat] ?? (.mp4, "mp4")
            return try await MediaConverter.convertVideo(url, to: type, ext: ext)
        case .audio:
            return try await MediaConverter.convertAudio(url, format: audioFormat)
        case .image:
            let map: [String: (UTType, String)] = [
                "png": (.png, "png"), "jpeg": (.jpeg, "jpg"), "heic": (.heic, "heic"), "tiff": (.tiff, "tiff")]
            let (type, ext) = map[imageFormat] ?? (.png, "png")
            return try MediaConverter.convertImage(url, to: type, ext: ext, quality: 0.9)
        }
    }

    private func update(_ id: UUID, _ status: JobStatus, _ detail: String) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].status = status
        jobs[i].detail = detail
    }
}
