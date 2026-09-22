import Foundation

struct PassportRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var revision: UUID = UUID()
    var givenNames: String
    var surname: String
    var documentNumber: String
    var nationality: String
    var birthDate: String
    var expiryDate: String
    var mrz: String
    var photograph: Data?
    var readAt: Date
    var updatedAt: Date = Date()
    var dataGroups: [String: Data]
    var sod: Data?
    var checks: [Verification]
    var nfcEvidence: NFCEvidence? = nil
    // Optional on disk to keep existing passports and archives readable.
    var documentKind: DocumentKind? = nil
    var kind: DocumentKind { documentKind ?? .passport }

    struct Verification: Codable, Equatable, Sendable {
        var name: String
        var result: Result
        var detail: String
        enum Result: String, Codable, Sendable { case passed, failed, notPerformed }
    }
}

struct BackupReference: Codable, Equatable {
    var account: String
    var recordID: UUID
    var keyID: UUID
    var uploadedRevision: UUID?
}
struct Deletion: Codable, Equatable {
    var account: String
    var recordID: UUID
}
struct Vault: Codable {
    var passports: [PassportRecord] = []
    var backups: [UUID: BackupReference] = [:]
    var deletions: [Deletion] = []
}

enum VaultError: Error, LocalizedError {
    case missingKey, invalidData, keychain(Int32), unavailable, accountChanged, newerBackup, weakPassword
    var errorDescription: String? {
        switch self {
        case .missingKey: "La clé de chiffrement est indisponible. Activez le Trousseau iCloud avec le compte Apple d’origine et réessayez. Ne réinitialisez pas vos données chiffrées."
        case .invalidData: "Le fichier est endommagé, incompatible, ou le mot de passe est incorrect."
        case .keychain: "Le Trousseau est indisponible. Déverrouillez l’iPhone puis réessayez."
        case .unavailable: "iCloud est indisponible. Vos passeports restent enregistrés sur cet iPhone."
        case .accountChanged: "Le compte iCloud a changé. La sauvegarde liée à l’ancien compte reste suspendue."
        case .newerBackup: "Une version différente existe dans iCloud. Restaurez-la avant de modifier ce passeport."
        case .weakPassword: "Utilisez un mot de passe d’au moins 12 caractères."
        }
    }
}

enum DocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case passport, identityCard
    var id: String { rawValue }
    var title: String { self == .passport ? "Passeport" : "Carte d’identité" }
    var symbol: String { self == .passport ? "book.closed" : "person.text.rectangle" }
}
