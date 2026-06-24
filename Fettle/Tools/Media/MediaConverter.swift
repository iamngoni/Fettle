import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Native media conversion — AVFoundation for audio/video, ImageIO for images.
/// No external binaries, fully offline.
enum MediaConverter {

    enum ConvertError: Error { case unreadable, exportFailed, writeFailed }

    /// Video compression quality. `lossless` is a passthrough re-wrap (no quality
    /// loss, ~no size change); the others re-encode to HEVC.
    enum VideoQuality: String, CaseIterable {
        case lossless = "Lossless", maximum = "Maximum", high = "High", medium = "Medium", small = "Small"
        var subtitle: String {
            switch self {
            case .lossless: return "No re-encode · size ~unchanged"
            case .maximum: return "HEVC · visually lossless"
            case .high: return "HEVC · up to 1080p"
            case .medium: return "HEVC · up to 720p"
            case .small: return "Smallest · up to 540p"
            }
        }
    }

    static func compressVideo(_ url: URL, quality: VideoQuality) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let candidates: [String]
        let fileType: AVFileType
        let ext: String
        // HEVC presets only exist down to 1080p; 720p/540p/480p are H.264.
        switch quality {
        case .lossless:
            candidates = [AVAssetExportPresetPassthrough]; fileType = .mov; ext = "mov"
        case .maximum:
            candidates = [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]; fileType = .mp4; ext = "mp4"
        case .high:
            candidates = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1920x1080, AVAssetExportPresetHEVCHighestQuality]; fileType = .mp4; ext = "mp4"
        case .medium:
            candidates = [AVAssetExportPreset1280x720, AVAssetExportPreset960x540]; fileType = .mp4; ext = "mp4"
        case .small:
            candidates = [AVAssetExportPreset960x540, AVAssetExportPreset640x480, AVAssetExportPreset1280x720]; fileType = .mp4; ext = "mp4"
        }

        var export: AVAssetExportSession?
        for preset in candidates {
            if let session = AVAssetExportSession(asset: asset, presetName: preset) { export = session; break }
        }
        guard let export else { throw ConvertError.exportFailed }
        let out = uniqueOutput(for: url, ext: ext)
        try await export.export(to: out, as: fileType)
        return out
    }

    // MARK: Video

    static func convertVideo(_ url: URL, to fileType: AVFileType, ext: String) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConvertError.exportFailed
        }
        let out = uniqueOutput(for: url, ext: ext)
        try await export.export(to: out, as: fileType)
        return out
    }

    // MARK: Audio

    static func convertAudio(_ url: URL, format: String) async throws -> URL {
        switch format {
        case "m4a":
            let asset = AVURLAsset(url: url)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw ConvertError.exportFailed
            }
            let out = uniqueOutput(for: url, ext: "m4a")
            try await export.export(to: out, as: .m4a)
            return out
        case "wav", "aiff", "caf":
            return try convertAudioPCM(url, ext: format)
        default:
            throw ConvertError.exportFailed
        }
    }

    /// Decodes any readable audio file and re-writes it as linear PCM.
    private static func convertAudioPCM(_ url: URL, ext: String) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let out = uniqueOutput(for: url, ext: ext)
        let output = try AVAudioFile(forWriting: out, settings: format.settings)
        let frames: AVAudioFrameCount = 8192
        while input.framePosition < input.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
            try input.read(into: buffer)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
        return out
    }

    // MARK: Image

    /// Converts/re-encodes an image. `maxDimension` (if > 0) downscales so the
    /// longest side fits; `quality` (0–1) applies to lossy formats.
    @discardableResult
    static func convertImage(_ url: URL, to type: UTType, ext: String,
                             quality: Double = 0.9, maxDimension: Int = 0,
                             preserveMetadata: Bool = false) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ConvertError.unreadable }

        let out = uniqueOutput(for: url, ext: ext)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError.writeFailed
        }

        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if preserveMetadata,
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            options.merge(props) { current, _ in current }
        }

        if maxDimension > 0 {
            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            ]
            guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                throw ConvertError.unreadable
            }
            CGImageDestinationAddImage(dest, scaled, options as CFDictionary)
        } else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ConvertError.unreadable }
            CGImageDestinationAddImage(dest, image, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.writeFailed }
        return out
    }

    // MARK: Helpers

    static func uniqueOutput(for url: URL, ext: String) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    static func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
