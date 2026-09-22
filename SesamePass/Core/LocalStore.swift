import Foundation
import CryptoKit

struct LocalStore {
    private let directory: URL
    private let file: URL
    private let vaultID = UUID(uuidString: "E42543A3-642B-4763-9E65-755C07873388")!
    init() throws {
        directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Sesame", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        file = directory.appendingPathComponent("vault.sealed")
    }
    func load() throws -> Vault {
        guard FileManager.default.fileExists(atPath: file.path) else { return Vault() }
        guard let key = try Keys.read("local-vault", sync: false) else { throw VaultError.missingKey }
        let (_, plaintext) = try Cipher.open(Data(contentsOf: file), key: key, expectedID: vaultID)
        return try JSONDecoder().decode(Vault.self, from: plaintext)
    }
    func save(_ vault: Vault) throws {
        let key: SymmetricKey
        if FileManager.default.fileExists(atPath: file.path) {
            guard let existing = try Keys.read("local-vault", sync: false) else { throw VaultError.missingKey }
            key = existing
        } else { key = try Keys.create("local-vault", sync: false) }
        let encrypted = try Cipher.seal(JSONEncoder().encode(vault), id: vaultID, keyID: vaultID, key: key)
        try encrypted.write(to: file, options: [.atomic, .completeFileProtection])
    }
}
