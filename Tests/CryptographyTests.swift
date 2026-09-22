import Foundation
import CryptoKit
import Testing
@testable import SesamePassSecurity

private func fixture() -> PassportRecord {
    PassportRecord(givenNames: "TEST ONLY", surname: "SPECIMEN", documentNumber: "FAKE00000", nationality: "UTO", birthDate: "2000-01-01", expiryDate: "2030-01-01", mrz: "SYNTHETIC MRZ", photograph: Data([1,2,3]), readAt: Date(timeIntervalSince1970: 1_700_000_000), dataGroups: ["DG1": Data([4,5,6]), "DG2": Data([7,8,9])], sod: Data([10,11]), checks: [.init(name: "Test fixture", result: .notPerformed, detail: "No real verification")])
}

@Test func completePassportRoundTrip() throws {
    let passport = fixture()
    let key = SymmetricKey(size: .bits256)
    let id = UUID()
    let encrypted = try Cipher.seal(JSONEncoder().encode(passport), id: id, keyID: UUID(), key: key)
    let (_, plaintext) = try Cipher.open(encrypted, key: key, expectedID: id)
    #expect(try JSONDecoder().decode(PassportRecord.self, from: plaintext) == passport)
    #expect(!String(decoding: encrypted, as: UTF8.self).contains("SPECIMEN"))
    #expect(!String(decoding: encrypted, as: UTF8.self).contains("FAKE00000"))
}
@Test func freshNonces() throws {
    let key = SymmetricKey(size: .bits256), id = UUID(), keyID = UUID()
    let data = Data("same data".utf8)
    #expect(try Cipher.seal(data, id: id, keyID: keyID, key: key) != Cipher.seal(data, id: id, keyID: keyID, key: key))
}
@Test func wrongKeyRejected() throws {
    let bytes = try Cipher.seal(Data("secret".utf8), id: UUID(), keyID: UUID(), key: SymmetricKey(size: .bits256))
    #expect(throws: (any Error).self) { try Cipher.open(bytes, key: SymmetricKey(size: .bits256)) }
}
@Test func payloadTamperingRejected() throws {
    let key = SymmetricKey(size: .bits256)
    let bytes = try Cipher.seal(Data("secret".utf8), id: UUID(), keyID: UUID(), key: key)
    let original = try JSONDecoder().decode(EncryptedEnvelope.self, from: bytes)
    var sealed = original.sealed
    sealed[sealed.count - 1] ^= 1
    let tampered = try JSONEncoder().encode(EncryptedEnvelope(version: 1, id: original.id, keyID: original.keyID, sealed: sealed))
    #expect(throws: (any Error).self) { try Cipher.open(tampered, key: key) }
}
@Test func recordSubstitutionRejected() throws {
    let key = SymmetricKey(size: .bits256)
    let bytes = try Cipher.seal(Data("secret".utf8), id: UUID(), keyID: UUID(), key: key)
    #expect(throws: (any Error).self) { try Cipher.open(bytes, key: key, expectedID: UUID()) }
    let original = try JSONDecoder().decode(EncryptedEnvelope.self, from: bytes)
    let tampered = try JSONEncoder().encode(EncryptedEnvelope(version: 1, id: UUID(), keyID: original.keyID, sealed: original.sealed))
    #expect(throws: (any Error).self) { try Cipher.open(tampered, key: key) }
}
@Test func keyIdentifierTamperingRejected() throws {
    let key = SymmetricKey(size: .bits256)
    let bytes = try Cipher.seal(Data("secret".utf8), id: UUID(), keyID: UUID(), key: key)
    let original = try JSONDecoder().decode(EncryptedEnvelope.self, from: bytes)
    let tampered = try JSONEncoder().encode(EncryptedEnvelope(version: 1, id: original.id, keyID: UUID(), sealed: original.sealed))
    #expect(throws: (any Error).self) { try Cipher.open(tampered, key: key) }
}
@Test func unsupportedEnvelopeRejected() throws {
    let data = try JSONEncoder().encode(EncryptedEnvelope(version: 2, id: UUID(), keyID: UUID(), sealed: Data()))
    #expect(throws: (any Error).self) { try Cipher.open(data, key: SymmetricKey(size: .bits256)) }
}
@Test func portableArchiveRoundTrip() throws {
    let passport = fixture()
    let encrypted = try ArchiveCipher.export(passport, password: "test-only-long-passphrase")
    #expect(try ArchiveCipher.restore(encrypted, password: "test-only-long-passphrase") == passport)
}
@Test func archiveWrongPasswordRejected() throws {
    let encrypted = try ArchiveCipher.export(fixture(), password: "test-only-long-passphrase")
    #expect(throws: (any Error).self) { try ArchiveCipher.restore(encrypted, password: "a-different-passphrase") }
}
@Test func weakPasswordRejected() {
    #expect(throws: (any Error).self) { try ArchiveCipher.export(fixture(), password: "short") }
}
@Test func archiveTamperingRejected() throws {
    let encrypted = try ArchiveCipher.export(fixture(), password: "test-only-long-passphrase")
    let value = try JSONDecoder().decode(ArchiveCipher.Archive.self, from: encrypted)
    var box = value.box
    box[box.count - 1] ^= 1
    let corrupt = ArchiveCipher.Archive(format: value.format, version: value.version, rounds: value.rounds, salt: value.salt, box: box)
    #expect(throws: (any Error).self) { try ArchiveCipher.restore(JSONEncoder().encode(corrupt), password: "test-only-long-passphrase") }
}
@Test func hostileKDFParametersRejected() throws {
    let value = ArchiveCipher.Archive(format: "sesame-archive", version: 1, rounds: Int.max, salt: Data(repeating: 1, count: 32), box: Data())
    #expect(throws: (any Error).self) { try ArchiveCipher.restore(JSONEncoder().encode(value), password: "test-only-long-passphrase") }
}
