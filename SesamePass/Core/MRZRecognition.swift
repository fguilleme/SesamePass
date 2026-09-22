import Foundation
import Vision

actor MRZRecognition {
    func recognize(_ image: Data, kind: DocumentKind = .passport) throws -> MRZAccess {
        // The accurate model can collapse repeated MRZ fillers or split a number.
        // The fast model uses a different recognition path and can recover these rows.
        // Both paths must pass exactly the same checks; neither authenticates a document.
        for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
            try Task.checkCancellation()
            let lines = try recognizeLines(image, level: level)
            let access = kind == .passport ? try? MRZAccess.parseOCRLines(lines) : try? MRZAccess.parseTD1OCR(lines)
            if let access { return access }
        }
        throw MRZError.unreadable
    }

    private func recognizeLines(_ image: Data, level: VNRequestTextRecognitionLevel) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(data: image, options: [:])
        try handler.perform([request])
        // Vision can return separate blocks for one printed line. Group by vertical
        // overlap, then join left-to-right instead of sorting fragments by midY alone.
        let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in observations {
            if let index = rows.firstIndex(where: { row in
                guard let anchor = row.first else { return false }
                let a = anchor.boundingBox, b = observation.boundingBox
                let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
                return overlap > min(a.height, b.height) * 0.5
            }) {
                rows[index].append(observation)
            } else { rows.append([observation]) }
        }
        var lines: [String] = []
        for row in rows {
            var combinations = [""]
            for block in row.sorted(by: { $0.boundingBox.minX < $1.boundingBox.minX }) {
                let candidates = block.topCandidates(3).map(\.string)
                lines.append(contentsOf: candidates)
                combinations = Array(combinations.flatMap { prefix in
                    candidates.map { prefix + $0 }
                }.prefix(81))
            }
            lines.append(contentsOf: combinations)
        }
        return lines
    }
}
