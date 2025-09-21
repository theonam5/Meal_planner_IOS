import Foundation
import Vision
import UIKit

enum OCRService {
    /// Reconnaît le texte d'une image et renvoie les lignes (ordre approximatif).
    static func recognizeLines(from image: UIImage,
                               languages: [String] = ["fr-FR", "en-US"],
                               level: VNRequestTextRecognitionLevel = .accurate) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err { return cont.resume(throwing: err) }
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines)
            }
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
