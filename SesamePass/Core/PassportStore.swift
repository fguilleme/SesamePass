import Foundation
import SwiftUI
import LocalAuthentication
import CloudKit

@MainActor @Observable
final class PassportStore {
    #if DEBUG
    static let screenshotRecordID = UUID(uuidString: "E119F86C-2C63-43EE-A8E8-58B48A6D0A31")!
    #endif
    private(set) var vault = Vault()
    private(set) var unlocked = false
    private(set) var appLockEnabled: Bool
    private(set) var loadFailed = false
    private(set) var changingProtection = false
    private(set) var busy = false
    private(set) var candidates: [BackupCandidate] = []
    private(set) var cloudAccount: String?
    private(set) var failures: Set<UUID> = []
    var message: String?
    var cloudMessage: String?
    private let cloud = CloudBackup()
    private var rescheduleNeeded = false
    private var worker: Task<Void, Never>?
    private var epoch = UUID()
    private var authenticating = false
    private var restoreInProgress = false
    private var local: LocalStore?
    private let screenshotMode: Bool
    var backupEnabled: Bool {
        didSet {
            UserDefaults.standard.set(backupEnabled, forKey: "backupEnabled")
            epoch = UUID()
            worker?.cancel()
            cloud.enabled = backupEnabled && unlocked
            candidates = []
            if backupEnabled { schedule() }
        }
    }
    init() {
        #if DEBUG
        screenshotMode = ProcessInfo.processInfo.arguments.contains("--app-store-screenshot")
        #else
        screenshotMode = false
        #endif
        appLockEnabled = screenshotMode ? false : UserDefaults.standard.bool(forKey: "appLockEnabled")
        // No CloudKit operation occurs when the explicit preference is OFF.
        backupEnabled = screenshotMode ? true : (UserDefaults.standard.object(forKey: "backupEnabled") as? Bool ?? true)
        if !screenshotMode { Exporter.cleanExpiredFiles() }
    }
    var passports: [PassportRecord] { vault.passports.sorted { $0.readAt > $1.readAt } }
    var pendingDeletions: Int { vault.deletions.count }
    var sessionIdentity: UUID { epoch }
    /// Default entry: loads protected local data without an extra application lock.
    func openIfAllowed() async {
        #if DEBUG
        if screenshotMode {
            vault = Vault(passports: [Self.screenshotPassport()])
            unlocked = true
            return
        }
        #endif
        guard !appLockEnabled else { return }
        await unlock()
    }
    func unlock() async {
        guard !unlocked, !authenticating else { return }
        authenticating = true
        loadFailed = false
        let generation = epoch
        defer { authenticating = false }
        do {
            if appLockEnabled {
                guard try await authenticate(reason: L10n.string("Accéder à vos passeports")) else { return }
            }
            guard generation == epoch else { return }
            let storage = try LocalStore()
            let loaded = try storage.load()
            local = storage
            vault = loaded
            unlocked = true
            cloud.enabled = backupEnabled
            schedule()
        } catch {
            loadFailed = true
            if let la = error as? LAError, [.userCancel, .appCancel, .systemCancel].contains(la.code) { return }
            message = L10n.format("Impossible de charger les passeports. %@", (error as? VaultError)?.localizedDescription ?? L10n.string("Authentification indisponible ou données inaccessibles."))
        }
    }
    func setAppLockEnabled(_ enabled: Bool) async {
        guard unlocked, enabled != appLockEnabled, !changingProtection else { return }
        changingProtection = true
        let generation = epoch
        defer { changingProtection = false }
        do {
            guard try await authenticate(reason: L10n.string(enabled ? "Activer la protection de SesamePass" : "Désactiver la protection de SesamePass")), generation == epoch, unlocked else { return }
            appLockEnabled = enabled
            UserDefaults.standard.set(enabled, forKey: "appLockEnabled")
        } catch {
            if let la = error as? LAError, [.userCancel, .appCancel, .systemCancel].contains(la.code) { return }
            message = L10n.string("Configurez Face ID, Touch ID ou un code appareil pour utiliser cette protection.")
        }
    }
    private func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? NSError(domain: LAError.errorDomain, code: LAError.passcodeNotSet.rawValue)
        }
        return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
    func lock() {
        epoch = UUID()
        worker?.cancel()
        cloud.enabled = false
        loadFailed = false
        unlocked = false
        vault = Vault()
        candidates = []
        local = nil
    }
    /// Integration point for the NFC reader: accepts only its complete, verified result.
    func save(_ passport: PassportRecord) throws {
        guard unlocked, !restoreInProgress else { throw VaultError.unavailable }
        var next = vault
        var value = passport
        value.revision = UUID()
        value.updatedAt = Date()
        next.passports.removeAll { $0.id == value.id }
        next.passports.append(value)
        try commit(next)
        failures.remove(value.id)
        schedule()
    }
    func delete(_ passport: PassportRecord, fromCloud: Bool) throws {
        guard unlocked, !restoreInProgress else { throw VaultError.unavailable }
        var next = vault
        if fromCloud, let ref = next.backups[passport.id] {
            let deletion = Deletion(account: ref.account, recordID: ref.recordID)
            if !next.deletions.contains(deletion) { next.deletions.append(deletion) }
        }
        next.passports.removeAll { $0.id == passport.id }
        // Retain the reference for local-only deletion: a restored copy must reuse the same backup.
        if fromCloud { next.backups.removeValue(forKey: passport.id) }
        try commit(next)
        candidates.removeAll { candidate in next.deletions.contains { $0.recordID == candidate.id } }
        schedule()
    }
    func status(_ record: PassportRecord) -> String {
        #if DEBUG
        if screenshotMode {
            return Locale.preferredLanguages.first?.hasPrefix("fr") == true
                ? "Sauvegardé dans iCloud"
                : "Backed up to iCloud"
        }
        #endif
        if !backupEnabled { return L10n.string("Sauvegarde iCloud désactivée") }
        if failures.contains(record.id) { return L10n.string("⚠ Sauvegarde impossible") }
        if let ref = vault.backups[record.id], ref.account == cloudAccount, ref.uploadedRevision == record.revision { return L10n.string("☁︎ Sauvegardé dans iCloud") }
        return L10n.string("☁︎ Sauvegarde en attente")
    }

    #if DEBUG
    private static func screenshotPassport() -> PassportRecord {
        let french = Locale.preferredLanguages.first?.hasPrefix("fr") == true
        return PassportRecord(
            id: screenshotRecordID,
            revision: UUID(uuidString: "B4C9C2C9-12A0-4B4E-90E5-49581160625D")!,
            givenNames: french ? "Pierre" : "John",
            surname: french ? "Martin" : "Doe",
            documentNumber: french ? "FR00P2026" : "US00P2026",
            nationality: french ? "FRA" : "USA",
            birthDate: french ? "14/07/1988" : "Apr 12, 1988",
            expiryDate: french ? "31/12/2034" : "Dec 31, 2034",
            mrz: french
                ? "P<FRAMARTIN<<PIERRE<<<<<<<<<<<<<<<<<<<<<<<<\nFR00P2026<8FRA8807148M3412314<<<<<<<<<<<<<<02"
                : "P<USADOE<<JOHN<<<<<<<<<<<<<<<<<<<<<<<<<<<<\nUS00P2026<8USA8804128M3412314<<<<<<<<<<<<<<02",
            photograph: nil,
            readAt: Date(timeIntervalSince1970: 1_788_177_600),
            updatedAt: Date(timeIntervalSince1970: 1_788_177_600),
            dataGroups: ["DG1": Data("SYNTHETIC-DG1".utf8), "DG2": Data("SYNTHETIC-DG2".utf8)],
            sod: Data("SYNTHETIC-SOD".utf8),
            checks: [
                .init(name: "Accès sécurisé · PACE", result: .passed, detail: "Établissement de la session avec la puce. Un repli BAC peut être utilisé si PACE n’aboutit pas."),
                .init(name: "Signature du SOD", result: .passed, detail: "Signature des données de sécurité contrôlée avec le certificat inclus dans le document."),
                .init(name: "Intégrité des données lues", result: .passed, detail: "Comparaison des empreintes des groupes lus avec le SOD. Les groupes non lus ne sont pas vérifiés."),
                .init(name: "Confiance dans le pays émetteur", result: .notPerformed, detail: "Aucune liste de certificats nationaux de confiance n’est embarquée. L’authenticité du pays émetteur n’est pas certifiée.")
            ],
            documentKind: .passport
        )
    }
    #endif
    private func commit(_ next: Vault) throws {
        guard unlocked, let local else { throw VaultError.unavailable }
        try local.save(next)
        vault = next
    }
    func schedule() {
        guard unlocked, backupEnabled, !restoreInProgress else { return }
        if busy { rescheduleNeeded = true; return }
        rescheduleNeeded = false
        let generation = epoch
        busy = true
        worker = Task {
            defer {
                busy = false
                if (generation != epoch || rescheduleNeeded), unlocked, backupEnabled { schedule() }
            }
            do {
                let account = try await cloud.account()
                try ensureActive(generation)
                cloudAccount = account
                cloudMessage = nil
                for deletion in vault.deletions {
                    guard deletion.account == account else { cloudMessage = L10n.string("Une suppression attend le compte Apple d’origine."); continue }
                    try await cloud.delete(deletion)
                    try ensureActive(generation)
                    var next = vault
                    next.deletions.removeAll { $0 == deletion }
                    try commit(next)
                }
                // Discovery always precedes uploads; no automatic restoration of personal data.
                let found = try await cloud.discover(account: account)
                try ensureActive(generation)
                let present = Set(vault.passports.compactMap { vault.backups[$0.id]?.recordID })
                candidates = found.filter { !present.contains($0.id) && !vault.deletions.contains(Deletion(account: account, recordID: $0.id)) }
                for snapshot in vault.passports {
                    try ensureActive(generation)
                    guard let current = vault.passports.first(where: { $0.id == snapshot.id }) else { continue }
                    do {
                        var ref: BackupReference
                        if let existing = vault.backups[current.id] { ref = existing }
                        else {
                            let keyID = UUID()
                            _ = try Keys.create(keyID.uuidString, sync: true)
                            ref = BackupReference(account: account, recordID: UUID(), keyID: keyID)
                            var next = vault
                            next.backups[current.id] = ref
                            try commit(next)
                        }
                        guard ref.account == account else { throw VaultError.accountChanged }
                        if ref.uploadedRevision == current.revision { continue }
                        try await cloud.upload(current, reference: ref)
                        try ensureActive(generation)
                        // If deleted during upload, its persistent tombstone will remove the record next pass.
                        guard vault.passports.contains(where: { $0.id == current.id }) else { continue }
                        var next = vault
                        ref.uploadedRevision = current.revision
                        next.backups[current.id] = ref
                        try commit(next)
                        failures.remove(current.id)
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        try ensureActive(generation)
                        failures.insert(current.id)
                        cloudMessage = friendly(error)
                    }
                }
            } catch is CancellationError { }
            catch {
                guard generation == epoch, unlocked else { return }
                cloudMessage = friendly(error)
                // Network outages remain pending; configuration/key failures are displayed separately.
                if let ck = error as? CKError, [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited].contains(ck.code) { return }
                failures.formUnion(vault.passports.filter { vault.backups[$0.id]?.uploadedRevision != $0.revision }.map(\.id))
            }
        }
    }
    func restore() async {
        guard unlocked, backupEnabled, !busy, !restoreInProgress, let account = cloudAccount else { return }
        let generation = epoch
        restoreInProgress = true
        defer { restoreInProgress = false }
        do {
            for candidate in candidates {
                let (passport, keyID) = try await cloud.restore(candidate.id, account: account)
                try ensureActive(generation)
                var next = vault
                // Never silently replace local edits.
                guard !next.passports.contains(where: { $0.id == passport.id }) else { continue }
                next.passports.append(passport)
                next.backups[passport.id] = BackupReference(account: account, recordID: candidate.id, keyID: keyID, uploadedRevision: passport.revision)
                try commit(next)
                candidates.removeAll { $0.id == candidate.id }
            }
        } catch { if generation == epoch { message = friendly(error) } }
    }
    private func ensureActive(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard unlocked, backupEnabled, generation == epoch else { throw CancellationError() }
    }
    private func friendly(_ error: Error) -> String {
        if let error = error as? VaultError { return error.localizedDescription }
        return L10n.string("iCloud est temporairement indisponible ou non configuré. Nouvelle tentative automatique ; vos données locales sont conservées.")
    }
}
