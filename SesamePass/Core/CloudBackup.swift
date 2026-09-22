import Foundation
import CloudKit
import CryptoKit

struct BackupCandidate: Identifiable, Equatable {
    let id: UUID
    let date: Date
}

@MainActor
final class CloudBackup {
    var enabled = false
    private lazy var container = CKContainer(identifier: "iCloud.app.sesame.passports")
    private var database: CKDatabase { container.privateCloudDatabase }
    func account() async throws -> String {
        try allowed()
        #if targetEnvironment(simulator)
        // Simulator builds may have no CloudKit entitlement; avoid CKContainer's fatal assertion.
        throw VaultError.unavailable
        #else
        guard try await container.accountStatus() == .available else { throw VaultError.unavailable }
        try allowed()
        let id = try await container.userRecordID().recordName
        try allowed()
        return id
        #endif
    }
    func verify(_ expected: String) async throws {
        guard try await account() == expected else { throw VaultError.accountChanged }
    }
    func discover(account: String) async throws -> [BackupCandidate] {
        try await verify(account)
        let query = CKQuery(recordType: "EncryptedPassport", predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, desiredKeys: [], resultsLimit: 100)
        var result: [BackupCandidate] = []
        while true {
            for (id, value) in page.matchResults {
                let record = try value.get()
                guard let uuid = UUID(uuidString: id.recordName) else { continue }
                result.append(BackupCandidate(id: uuid, date: record.modificationDate ?? .distantPast))
            }
            guard let cursor = page.queryCursor else { break }
            try allowed()
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: [], resultsLimit: 100)
        }
        try await verify(account)
        return result.sorted { $0.date > $1.date }
    }
    func restore(_ id: UUID, account: String) async throws -> (PassportRecord, UUID) {
        try await verify(account)
        let record = try await database.record(for: CKRecord.ID(recordName: id.uuidString))
        try await verify(account)
        return try decode(record, expectedID: id)
    }
    func upload(_ passport: PassportRecord, reference: BackupReference) async throws {
        try await verify(reference.account)
        try Task.checkCancellation()
        let id = CKRecord.ID(recordName: reference.recordID.uuidString)
        var record: CKRecord
        do {
            record = try await database.record(for: id)
            let (existing, _) = try decode(record, expectedID: reference.recordID)
            guard existing.revision == reference.uploadedRevision || existing.revision == passport.revision else { throw VaultError.newerBackup }
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: "EncryptedPassport", recordID: id)
        }
        guard let key = try Keys.read(reference.keyID.uuidString, sync: true) else { throw VaultError.missingKey }
        let payload = try Cipher.seal(JSONEncoder().encode(passport), id: reference.recordID, keyID: reference.keyID, key: key)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sealed")
        try payload.write(to: file, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: file) }
        record["payload"] = CKAsset(fileURL: file)
        try await verify(reference.account)
        try Task.checkCancellation()
        let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        guard let saved = result.saveResults[id] else { throw VaultError.unavailable }
        _ = try saved.get()
        try await verify(reference.account)
    }
    func delete(_ deletion: Deletion) async throws {
        try await verify(deletion.account)
        try Task.checkCancellation()
        do { _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: deletion.recordID.uuidString)) }
        catch let error as CKError where error.code == .unknownItem { /* Already deleted. */ }
        try await verify(deletion.account)
    }
    private func allowed() throws {
        try Task.checkCancellation()
        guard enabled else { throw CancellationError() }
    }
    private func decode(_ record: CKRecord, expectedID: UUID) throws -> (PassportRecord, UUID) {
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { throw VaultError.invalidData }
        let bytes = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: bytes)
        guard let key = try Keys.read(envelope.keyID.uuidString, sync: true) else { throw VaultError.missingKey }
        let (_, plaintext) = try Cipher.open(bytes, key: key, expectedID: expectedID)
        return (try JSONDecoder().decode(PassportRecord.self, from: plaintext), envelope.keyID)
    }
}
