import AppKit
import Vision

struct OCRResult {
    var text: String = ""
    var barcodes: [String] = []
    var isEmpty: Bool {
        text.isEmpty && barcodes.isEmpty
    }
    var displayText: String {
        var parts: [String] = []
        if !barcodes.isEmpty {
            parts.append("二维码/条形码：")
            parts.append(barcodes.joined(separator: "\n"))
        }
        if !text.isEmpty {
            if !parts.isEmpty { parts.append("") }
            parts.append("文字：")
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }
    var clipboardText: String {
        var parts: [String] = []
        if !barcodes.isEmpty {
            parts.append(barcodes.joined(separator: "\n"))
        }
        if !text.isEmpty {
            parts.append(text)
        }
        return parts.joined(separator: "\n")
    }
}

final class OCRManager {
    static let shared = OCRManager()

    func recognize(image: NSImage, completion: @escaping (OCRResult) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(OCRResult())
            return
        }

        let textRequest = VNRecognizeTextRequest { request, _ in
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")

            let barcodeRequest = VNDetectBarcodesRequest { req, _ in
                let observations = req.results as? [VNBarcodeObservation] ?? []
                let payloads = observations.compactMap { $0.payloadStringValue }

                DispatchQueue.main.async {
                    var result = OCRResult()
                    result.text = text
                    result.barcodes = payloads
                    completion(result)
                }
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try? handler.perform([barcodeRequest])
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        textRequest.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([textRequest])
        }
    }
}
