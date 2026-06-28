import Foundation
import MLXLLM
import MLXVLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Runs Gemma 4 in-process via MLX (no Ollama, no external install). The model
/// downloads from Hugging Face on first use, then runs fully offline.
actor MLXSummarizer {
    static let shared = MLXSummarizer()

    enum Variant: String {
        case e2b, e4b
        var modelID: String {
            switch self {
            case .e2b: return "mlx-community/gemma-4-e2b-it-4bit"
            case .e4b: return "mlx-community/gemma-4-e4b-it-4bit"
            }
        }
    }

    enum Status: Equatable {
        case notLoaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    private(set) var status: Status = .notLoaded
    private var container: ModelContainer?
    private var loadedVariant: Variant?

    var isReady: Bool { if case .ready = status { return true }; return false }

    /// Loads (downloading on first use) the given Gemma variant.
    @discardableResult
    func load(_ variant: Variant, onProgress: (@Sendable (Double) -> Void)? = nil) async -> Bool {
        if container != nil, loadedVariant == variant { return true }
        container = nil
        loadedVariant = nil
        status = .downloading(0)
        do {
            let config = ModelConfiguration(id: variant.modelID)
            let loaded = try await #huggingFaceLoadModelContainer(configuration: config) { progress in
                onProgress?(progress.fractionCompleted)
                Task { await MLXSummarizer.shared.setDownloading(progress.fractionCompleted) }
            }
            container = loaded
            loadedVariant = variant
            status = .ready
            FettleLog.log("MLX ready (\(variant.modelID))")
            return true
        } catch {
            status = .failed(error.localizedDescription)
            FettleLog.error("MLX load failed: \(error.localizedDescription)")
            return false
        }
    }

    private func setDownloading(_ p: Double) { if container == nil { status = .downloading(p) } }
    func markLoading() { if container == nil { status = .loading } }

    /// Generates a completion. Returns nil on failure.
    func generate(prompt: String, instructions: String) async -> String? {
        guard let container else { return nil }
        do {
            let session = ChatSession(
                container,
                instructions: instructions,
                generateParameters: GenerateParameters(temperature: 0.3))
            return try await session.respond(to: prompt)
        } catch {
            FettleLog.error("MLX generate failed: \(error.localizedDescription)")
            return nil
        }
    }
}
