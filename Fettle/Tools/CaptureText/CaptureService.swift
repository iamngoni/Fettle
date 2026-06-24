import Foundation
import AppKit
import Vision

/// Region screen capture + on-device OCR. Uses the system `screencapture`
/// interactive selector (native crosshair, no custom overlay) and Apple's Vision
/// framework for recognition — everything stays on the Mac.
enum CaptureService {

    struct Result {
        var text: String
        var isBarcode: Bool
    }

    /// Presents the interactive region selector, OCRs the result, and returns the
    /// recognized text. Returns nil if the user cancelled or nothing was found.
    static func captureAndRecognize(keepLineBreaks: Bool, detectBarcodes: Bool) async -> Result? {
        guard let image = await selectRegion() else { return nil }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        if let text = recognizeText(in: cg, keepLineBreaks: keepLineBreaks), !text.isEmpty {
            return Result(text: text, isBarcode: false)
        }
        if detectBarcodes, let payload = recognizeBarcode(in: cg) {
            return Result(text: payload, isBarcode: true)
        }
        return nil
    }

    /// Runs `/usr/sbin/screencapture -i -o -x` to a temp file and loads it.
    private static func selectRegion() async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("fettle-ocr-\(UUID().uuidString).png")
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-i", "-o", "-x", tmp.path]   // interactive, no shadow, no sound
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    continuation.resume(returning: nil); return
                }
                defer { try? FileManager.default.removeItem(at: tmp) }
                guard FileManager.default.fileExists(atPath: tmp.path),
                      let image = NSImage(contentsOf: tmp) else {
                    continuation.resume(returning: nil); return     // user pressed Esc
                }
                continuation.resume(returning: image)
            }
        }
    }

    private static func recognizeText(in image: CGImage, keepLineBreaks: Bool) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: keepLineBreaks ? "\n" : " ")
    }

    private static func recognizeBarcode(in image: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return request.results?.compactMap { $0.payloadStringValue }.first
    }
}
