import Foundation
import WhisperKit

/// Local Whisper transcription via WhisperKit (CoreML, on-device). The model
/// downloads on first use; everything after is offline.
actor WhisperTranscriber {
    static let shared = WhisperTranscriber()

    /// The model the user chose — distil large-v3, 626 MB.
    static let modelName = "large-v3-v20240930_626MB"

    enum Status: Equatable {
        case notLoaded
        case downloading(Double)   // 0...1
        case loading
        case ready
        case failed(String)
    }

    private(set) var status: Status = .notLoaded
    private var pipe: WhisperKit?

    /// True once a usable model is loaded.
    var isReady: Bool { if case .ready = status { return true }; return false }

    /// Loads (and downloads on first use) the Whisper model. `onProgress` reports
    /// download progress 0...1. Returns true if a model is ready.
    @discardableResult
    func load(onProgress: (@Sendable (Double) -> Void)? = nil) async -> Bool {
        if pipe != nil { return true }
        status = .downloading(0)
        do {
            let folder = try await WhisperKit.download(
                variant: Self.modelName,
                downloadBase: nil,
                useBackgroundSession: false,
                from: "argmaxinc/whisperkit-coreml"
            ) { progress in
                onProgress?(progress.fractionCompleted)
                Task { await WhisperTranscriber.shared.setDownloading(progress.fractionCompleted) }
            }

            await setLoading()
            let config = WhisperKitConfig(model: Self.modelName, modelFolder: folder.path, load: true)
            pipe = try await WhisperKit(config)
            status = .ready
            FettleLog.log("WhisperKit ready (\(Self.modelName))")
            return true
        } catch {
            status = .failed(error.localizedDescription)
            FettleLog.error("WhisperKit load failed: \(error.localizedDescription)")
            return false
        }
    }

    private func setDownloading(_ p: Double) { if pipe == nil { status = .downloading(p) } }
    private func setLoading() { status = .loading }

    /// Transcribes an audio file to plain text, or nil on failure.
    func transcribe(_ url: URL) async -> String? {
        guard let pipe else { return nil }
        do {
            let results = try await pipe.transcribe(audioPath: url.path)
            let text = results.map(\.text).joined(separator: " ")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            FettleLog.error("WhisperKit transcribe failed: \(error.localizedDescription)")
            return nil
        }
    }
}
