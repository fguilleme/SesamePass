import Foundation
import CryptoKit
import Security
import CommonCrypto

struct EncryptedEnvelope: Codable, Sendable {
    let version: Int
    let id: UUID
    let keyID: UUID
    let sealed: Data
}

enum Cipher {
    static func seal(_ data: Data, id: UUID, keyID: UUID, key: SymmetricKey) throws -> Data {
        let aad = Data("sesame:1:\(id.uuidString):\(keyID.uuidString)".utf8)
        let box = try AES.GCM.seal(data, using: key, authenticating: aad)
        guard let combined = box.combined else { throw VaultError.invalidData }
        return try JSONEncoder().encode(EncryptedEnvelope(version: 1, id: id, keyID: keyID, sealed: combined))
    }
    static func open(_ data: Data, key: SymmetricKey, expectedID: UUID? = nil) throws -> (EncryptedEnvelope, Data) {
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: data)
        guard envelope.version == 1, expectedID == nil || expectedID == envelope.id else { throw VaultError.invalidData }
        let aad = Data("sesame:1:\(envelope.id.uuidString):\(envelope.keyID.uuidString)".utf8)
        return (envelope, try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.sealed), using: key, authenticating: aad))
    }
}

enum Keys {
    private static let service = "app.sesame.passports.keys.v1"
    static func read(_ name: String, sync: Bool) throws -> SymmetricKey? {
        var query = base(name, sync: sync)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else { throw VaultError.keychain(status) }
        return SymmetricKey(data: data)
    }
    static func create(_ name: String, sync: Bool) throws -> SymmetricKey {
        if let existing = try read(name, sync: sync) { return existing }
        let key = SymmetricKey(size: .bits256)
        var query = base(name, sync: sync)
        query[kSecAttrAccessible as String] = sync ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try read(name, sync: sync) { return existing }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        return key
    }
    private static func base(_ name: String, sync: Bool) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: name, kSecAttrSynchronizable as String: sync]
    }
}

// Portable archive: independent of the Apple account and of the local device key.
enum ArchiveCipher {
    struct Archive: Codable {
        let format: String
        let version: Int
        let rounds: Int
        let salt: Data
        let box: Data
    }
    static func export(_ record: PassportRecord, password: String) throws -> Data {
        guard password.count >= 12 else { throw VaultError.weakPassword }
        var salt = Data(count: 32)
        let result = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard result == errSecSuccess else { throw VaultError.keychain(result) }
        let key = try derive(password, salt: salt)
        let box = try AES.GCM.seal(JSONEncoder().encode(record), using: key, authenticating: Data("sesame-archive:1:600000".utf8))
        return try JSONEncoder().encode(Archive(format: "sesame-archive", version: 1, rounds: 600_000, salt: salt, box: box.combined!))
    }
    static func restore(_ data: Data, password: String) throws -> PassportRecord {
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.format == "sesame-archive", archive.version == 1, archive.rounds == 600_000, archive.salt.count == 32 else { throw VaultError.invalidData }
        let key = try derive(password, salt: archive.salt)
        let bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: archive.box), using: key, authenticating: Data("sesame-archive:1:600000".utf8))
        return try JSONDecoder().decode(PassportRecord.self, from: bytes)
    }
    private static func derive(_ password: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        guard !passwordBytes.isEmpty else { throw VaultError.invalidData }
        var output = Data(count: 32)
        let status = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { s in
                passwordBytes.withUnsafeBytes { p in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress!.assumingMemoryBound(to: Int8.self), p.count,
                        s.baseAddress!.assumingMemoryBound(to: UInt8.self), s.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        600_000, out.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw VaultError.invalidData }
        return SymmetricKey(data: output)
    }
}
