import Foundation
import CoreNFC
@preconcurrency import NFCPassportReader

/// Each read owns its reader locally. Only the Sendable snapshot crosses back to the UI.
enum NFCReadingService {
    static var available: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        NFCTagReaderSession.readingAvailable
        #endif
    }

    static func read(_ access: MRZAccess, kind: DocumentKind = .passport) async throws -> PassportRecord {
        guard available else { throw NFCReadError.unavailable }
        let reader = PassportReader()
        let detection = NFCDetection()
        reader.trackingDelegate = detection
        // Read supported public groups, never fingerprints/iris requiring terminal authorization.
        let model: NFCPassportModel
        do {
            model = try await reader.readPassport(mrzKey: access.key, skipSecureElements: true, usePACEDiscovery: kind == .identityCard, customDisplayMessage: displayMessage)
        } catch let error as NFCPassportReaderError {
            if case .TimeOutError = error, !detection.detected { throw NFCReadError.noChipDetected }
            throw error
        }
        try Task.checkCancellation()
        guard model.dataGroupsRead[.DG1] != nil, model.dataGroupsRead[.DG2] != nil,
              model.dataGroupsRead[.SOD] != nil else { throw NFCReadError.incomplete }
        // Reject a mismatch with the document requested; do not save manual/OCR identity as NFC data.
        let chipAccess = try kind == .passport ? MRZAccess.parseTD3(model.passportMRZ) : MRZAccess.parseTD1(model.passportMRZ)
        guard chipAccess == access else { throw NFCReadError.documentMismatch }
        let rawGroups = Dictionary(uniqueKeysWithValues: model.dataGroupsRead.filter { $0.key != .SOD }.map { ($0.key.getName(), Data($0.value.data)) })
        let hashes = Dictionary(uniqueKeysWithValues: model.dataGroupHashes.map { id, value in
            (id.getName(), NFCEvidence.HashResult(expected: value.sodHash, computed: value.computedHash, matches: value.match))
        })
        let readGroups = Set(rawGroups.keys.filter { $0.hasPrefix("DG") })
        let verification = NFCVerification(
            pace: model.isPACESupported ? result(model.PACEStatus) : .notPerformed, bac: result(model.BACStatus), chip: result(model.chipAuthenticationStatus),
            active: model.activeAuthenticationSupported ? (model.activeAuthenticationPassed ? .passed : .failed) : .notPerformed,
            signatureValid: model.documentSigningCertificateVerified,
            hashesValid: model.passportDataNotTampered,
            hashedGroups: Set(hashes.keys), readGroups: readGroups)
        var record = PassportRecord(
            givenNames: model.firstName.trimmingCharacters(in: .whitespaces),
            surname: model.lastName.trimmingCharacters(in: .whitespaces),
            documentNumber: model.documentNumber, nationality: model.nationality,
            birthDate: MRZAccess.displayedDate(model.dateOfBirth, birth: true),
            expiryDate: MRZAccess.displayedDate(model.documentExpiryDate, birth: false),
            mrz: model.passportMRZ,
            photograph: (model.dataGroupsRead[.DG2] as? DataGroup2).map { Data($0.imageData) },
            readAt: Date(), dataGroups: rawGroups, sod: model.dataGroupsRead[.SOD].map { Data($0.data) },
            checks: verification.checks)
        record.documentKind = kind
        record.nfcEvidence = NFCEvidence(
            cardAccess: model.cardAccess.map { Data($0.rawData) },
            activeAuthenticationChallenge: Data(model.activeAuthenticationChallenge),
            activeAuthenticationSignature: Data(model.activeAuthenticationSignature), hashes: hashes,
            unreadGroups: model.dataGroupsPresent.filter { !readGroups.contains($0) }.sorted())
        return record
    }

    private static func result(_ status: PassportAuthenticationStatus) -> PassportRecord.Verification.Result {
        switch status { case .notDone: .notPerformed; case .success: .passed; case .failed: .failed }
    }
    static func displayMessage(_ message: NFCViewDisplayMessage) -> String? {
        switch message {
        case .requestPresentPassport: "Posez le haut de l’iPhone contre le document et maintenez-le immobile."
        case .authenticatingWithPassport: "Connexion sécurisée au document…\nGardez l’iPhone immobile."
        case .readingDataGroupProgress(let group, let progress):
            group == .DG2 ? "Lecture de la photographie · \(min(100, max(0, progress))) %\nGardez l’iPhone immobile." : "Lecture du document · \(min(100, max(0, progress))) %\nGardez l’iPhone immobile."
        case .activeAuthentication: "Vérification de la puce…\nNe déplacez pas l’iPhone."
        case .successfulRead: "Lecture terminée."
        case .error(let error): userMessage(error)
        }
    }
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let nfc = error as? NFCPassportReaderError, case .UserCanceled = nfc { return true }
        return false
    }
    static func userMessage(_ error: Error) -> String {
        if let known = error as? NFCReadError { return known.localizedDescription }
        if let nfc = error as? NFCPassportReaderError {
            switch nfc {
            case .PACEError:
                return "La puce a été détectée, mais la connexion sécurisée PACE a échoué. Le code CAN et certaines variantes de PACE ne sont pas encore pris en charge. Les données n’ont pas été enregistrées."
            case .NotYetSupported:
                return "La puce utilise une fonction non prise en charge par cette version du lecteur. Aucun document n’a été enregistré."
            case .ResponseError(_, let sw1, let sw2):
                return String(format: "La puce a répondu, mais a refusé une commande NFC (code %02X%02X). Aucun document n’a été enregistré.", Int(sw1), Int(sw2))
            case .UserCanceled: return "Lecture annulée. Vous pouvez réessayer."
            case .InvalidMRZKey: return "Vérifiez le numéro du document et les deux dates, puis réessayez."
            case .TimeOutError: return "Le délai de lecture est écoulé. Placez le haut de l’iPhone contre le document et réessayez."
            case .MoreThanOneTagFound: return "Éloignez les autres passeports et cartes, puis réessayez."
            case .NFCNotSupported: return NFCReadError.unavailable.localizedDescription
            case .ConnectionError, .NoConnectedTag: return "La connexion a été interrompue. Maintenez le haut de l’iPhone contre le document."
            default: break
            }
        }
        return "La lecture n’a pas abouti. Vérifiez les informations saisies, retirez la coque si nécessaire et gardez l’iPhone contre le document."
    }
}

enum NFCReadError: Error, LocalizedError {
    case unavailable, incomplete, documentMismatch, noChipDetected
    var errorDescription: String? {
        switch self {
        case .noChipDetected: "Le lecteur n’a pas détecté le document avant la fin du délai. Cela ne signifie pas que la carte est dépourvue de puce. Retirez son étui et posez le haut du dos de l’iPhone contre elle, loin des autres cartes."
        case .unavailable: "La lecture NFC nécessite un iPhone compatible. Elle n’est pas disponible sur iPad ou dans le simulateur."
        case .incomplete: "La lecture est incomplète. Aucun document n’a été enregistré. Réessayez en gardant l’iPhone immobile."
        case .documentMismatch: "Les données de la puce ne correspondent pas aux informations saisies. Aucun document n’a été enregistré."
        }
    }
}

/// Non-sensitive progress only; callbacks may arrive from the NFC session queue.
private final class NFCDetection: PassportReaderTrackingDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var detected: Bool { lock.withLock { value } }
    func nfcTagDetected() { lock.withLock { value = true } }
    func readCardAccess(cardAccess: CardAccess) { }
    func paceStarted() { }
    func paceSucceeded() { }
    func paceFailed() { }
    func bacStarted() { }
    func bacSucceeded() { }
    func bacFailed() { }
}
