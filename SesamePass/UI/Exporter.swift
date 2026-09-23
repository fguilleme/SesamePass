import SwiftUI
import UIKit

@MainActor
enum Exporter {
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("SesameExports", isDirectory: true) }
    static func cleanExpiredFiles() { try? FileManager.default.removeItem(at: directory) }
    static func write(_ data: Data, extension ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let url = directory.appendingPathComponent("Document-\(UUID().uuidString.prefix(8)).\(ext)")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
    static func pdf(_ record: PassportRecord) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            var y: CGFloat = 0
            func text(_ value: String, size: CGFloat = 12, color: UIColor = .darkGray, bold: Bool = false, width: CGFloat = 491) {
                let attributes: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size), .foregroundColor: color]
                let rect = (value as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
                (value as NSString).draw(in: CGRect(x: 52, y: y, width: width, height: ceil(rect.height) + 3), withAttributes: attributes)
                y += ceil(rect.height) + 12
            }
            func newPage() {
                context.beginPage()
                UIColor(red: 0.04, green: 0.11, blue: 0.18, alpha: 1).setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 595, height: 106))
                y = 36
                text(L10n.string("SESAMEPASS  /  COPIE PERSONNELLE"), size: 20, color: .white, bold: true)
                y = 121
                text(L10n.string("Copie numérique — ne remplace pas un document de voyage."), size: 10, bold: true)
                y = 163
            }
            func field(_ label: String, _ value: String) {
                if y > 670 { newPage() }
                text(label.uppercased(), size: 9, color: .gray, bold: true)
                text(value.isEmpty ? L10n.string("Non disponible") : value, size: 15, color: .black)
                y += 7
            }
            newPage()
            if let bytes = record.photograph, let photo = UIImage(data: bytes) {
                let frame = CGRect(x: 425, y: 169, width: 118, height: 148)
                let ratio = min(frame.width / photo.size.width, frame.height / photo.size.height)
                photo.draw(in: CGRect(x: frame.midX - photo.size.width * ratio / 2, y: frame.minY, width: photo.size.width * ratio, height: photo.size.height * ratio))
            }
            text(record.givenNames, size: 21, color: .black, width: 350)
            text(record.surname, size: 27, color: .black, bold: true, width: 350)
            y = max(y + 20, 335)
            field(L10n.string("Type"), record.kind.title)
            field(L10n.string("Document"), record.documentNumber)
            field(L10n.string("Nationalité"), record.nationality)
            field(L10n.string("Date de naissance"), record.birthDate)
            field(L10n.string("Date d’expiration"), record.expiryDate)
            field(L10n.string("Lecture NFC"), record.readAt.formatted(date: .long, time: .shortened))
            newPage()
            text(L10n.string("Vérifications cryptographiques"), size: 23, color: .black, bold: true)
            if record.checks.isEmpty { text(L10n.string("Aucune vérification enregistrée.")) }
            for check in record.checks {
                if y > 620 { newPage() }
                let resultKey = switch check.result { case .passed: "Réussie"; case .failed: "Échec"; case .notPerformed: "Non effectuée" }
                let result = L10n.string(resultKey)
                text("\(L10n.string(check.name)) · \(result)", size: 14, color: .black, bold: true)
                text(L10n.string(check.detail))
            }
            text(L10n.string("Ces résultats décrivent les contrôles effectués lors de la lecture ; ils ne constituent pas une certification administrative."), size: 10)
        }
        return try write(data, extension: "pdf")
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var completion: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
            Task { @MainActor in completion() }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
