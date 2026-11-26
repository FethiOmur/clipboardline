import AppKit
import ImageIO
import Vision

/// Reads the text in an image. Pure and synchronous, so it can run on any queue and be tested directly.
enum RegionTextRecognizer {
    static func text(in image: CGImage, languages: [String] = ["tr-TR", "en-US"]) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        try VNImageRequestHandler(cgImage: image).perform([request])
        return readingOrder(request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Top to bottom, then left to right inside one visual row. Vision's boxes are normalized with the origin at the bottom left.
    private static func readingOrder(_ observations: [VNRecognizedTextObservation]) -> [VNRecognizedTextObservation] {
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in sorted {
            if let first = rows.last?.first,
               abs(first.boundingBox.midY - observation.boundingBox.midY) < min(first.boundingBox.height, observation.boundingBox.height) / 2 {
                rows[rows.count - 1].append(observation)
            } else {
                rows.append([observation])
            }
        }
        return rows.flatMap { $0.sorted { $0.boundingBox.minX < $1.boundingBox.minX } }
    }
}

/// Global "copy text from a screen area": the system's interactive area capture writes a temporary PNG,
/// the text in it is recognized, and the image is deleted again. No image is kept anywhere.
@MainActor
final class RegionTextCapture {
    var onText: (String) -> Void = { _ in }
    var onNoText: () -> Void = {}
    var onNeedsPermission: () -> Void = {}
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // A fresh subfolder of the temporary directory, never inside a folder the app watches.
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("copyline-region-\(UUID().uuidString)", isDirectory: true)
        let file = folder.appendingPathComponent("capture.png")
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { finish(folder: folder); return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", file.path]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.captureEnded(file: file, folder: folder) }
        }
        do { try process.run() } catch { finish(folder: folder) }
    }

    private func captureEnded(file: URL, folder: URL) {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0 else {
            // Escape, or screen recording is not allowed. Only the second case needs a message.
            if !CGPreflightScreenCaptureAccess() { onNeedsPermission() }
            finish(folder: folder); return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var text = ""
            if let source = CGImageSourceCreateWithURL(file as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                text = (try? RegionTextRecognizer.text(in: image)) ?? ""
            }
            Task { @MainActor in
                guard let self else { try? FileManager.default.removeItem(at: folder); return }
                self.finish(folder: folder)
                if text.isEmpty { self.onNoText() } else { self.onText(text) }
            }
        }
    }

    /// Every path ends here: the image and its folder are removed and the next capture may start.
    private func finish(folder: URL) {
        try? FileManager.default.removeItem(at: folder)
        isRunning = false
    }
}
