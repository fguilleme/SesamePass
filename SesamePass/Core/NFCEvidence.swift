import Foundation

struct NFCEvidence: Codable, Equatable, Sendable {
    var readerVersion: String = "NFCPassportReader 2.3.3 / SesamePass 1"
    var cardAccess: Data?
    var activeAuthenticationChallenge: Data
    var activeAuthenticationSignature: Data
    var hashes: [String: HashResult]
    var unreadGroups: [String]

    struct HashResult: Codable, Equatable, Sendable {
        var expected: String
        var computed: String
        var matches: Bool
    }
}

/// Separate trust in the issuing authority from SOD signature and hash consistency.
struct NFCVerification: Sendable {
    var pace: PassportRecord.Verification.Result
    var bac: PassportRecord.Verification.Result
    var chip: PassportRecord.Verification.Result
    var active: PassportRecord.Verification.Result
    var signatureValid: Bool
    var hashesValid: Bool
    var hashedGroups: Set<String>
    var readGroups: Set<String>

    var checks: [PassportRecord.Verification] {
        let covered = readGroups.isSubset(of: hashedGroups) && !readGroups.isEmpty
        return [
            .init(name: "Accès sécurisé · PACE", result: pace, detail: "Établissement de la session avec la puce. Un repli BAC peut être utilisé si PACE n’aboutit pas."),
            .init(name: "Accès sécurisé · BAC", result: bac, detail: "Accès à la puce à partir des informations du passeport ; ce contrôle ne certifie pas le pays émetteur."),
            .init(name: "Signature du SOD", result: signatureValid ? .passed : .failed, detail: "Signature des données de sécurité contrôlée avec le certificat inclus dans le document."),
            .init(name: "Intégrité des données lues", result: hashesValid && covered ? .passed : .failed, detail: "Comparaison des empreintes des groupes lus avec le SOD. Les groupes non lus ne sont pas vérifiés."),
            .init(name: "Confiance dans le pays émetteur", result: .notPerformed, detail: "Aucune liste de certificats nationaux de confiance n’est embarquée. L’authenticité du pays émetteur n’est pas certifiée."),
            .init(name: "Authentification de la puce", result: chip, detail: "Chip Authentication si la puce le permet. Ce contrôle ne remplace pas la validation du pays émetteur."),
            .init(name: "Authentification active", result: active, detail: "Réponse à un défi aléatoire si le passeport contient la clé publique nécessaire.")
        ]
    }
}
