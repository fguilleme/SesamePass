import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PassportStore.self) private var store
    @State private var settings = false
    @State private var adding = false
    @State private var path: [UUID] = []
    @State private var importing = false
    @State private var importData: Data?
    @State private var importPassword = ""
    @State private var importBusy = false
    @State private var importSheet = false
    private let navy = Color(red: 0.04, green: 0.11, blue: 0.18)

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label("VOS DOCUMENTS", systemImage: "book.closed")
                            .font(.caption.weight(.semibold)).tracking(1.5)
                        Spacer()
                    }.foregroundStyle(.secondary)
                    Text("Vos voyages.\nVos données.").font(.system(size: 39, weight: .semibold, design: .serif))
                    Text("Vos documents conservés avec soin, accessibles même hors ligne.")
                        .foregroundStyle(.secondary)
                    if !store.candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Une sauvegarde a été trouvée", systemImage: "icloud.and.arrow.down").font(.headline)
                            Text(L10n.format(store.candidates.count == 1 ? "%d document" : "%d documents", store.candidates.count))
                            if let date = store.candidates.first?.date { Text(L10n.format("Dernière sauvegarde : %@", date.formatted(date: .abbreviated, time: .shortened))).font(.caption) }
                            Button("Restaurer") { Task { await store.restore() } }.buttonStyle(SesamePassPrimaryButtonStyle()).disabled(store.busy)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if store.passports.isEmpty {
                        VStack(spacing: 18) {
                            Image(systemName: "book.closed").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Color("PassportSymbol"))
                            Text("Ajoutez votre premier document").font(.title2.weight(.semibold))
                            Text("Lisez sa puce avec votre iPhone pour retrouver ici ses informations et sa photographie.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                            Button("Ajouter un document", systemImage: "wave.3.right") { adding = true }.buttonStyle(SesamePassPrimaryButtonStyle())
                            Button("Importer une archive", systemImage: "square.and.arrow.down") { importing = true }
                        }.padding(28).frame(maxWidth: .infinity).background(Color("CardSurface"), in: RoundedRectangle(cornerRadius: 24))
                    } else {
                        ForEach(store.passports) { passport in
                            NavigationLink { PassportDetail(id: passport.id) } label: {
                                VStack(alignment: .leading, spacing: 18) {
                                    HStack {
                                        Image(systemName: passport.kind.symbol).font(.title)
                                        Spacer()
                                        Text(passport.kind.title.uppercased()).font(.caption).tracking(3)
                                    }
                                    Text("\(passport.givenNames)\n\(passport.surname)").font(.title2.weight(.medium))
                                    Text(store.status(passport)).font(.caption).opacity(0.8)
                                }.padding(25).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).background(navy.gradient, in: RoundedRectangle(cornerRadius: 24))
                            }.buttonStyle(.plain)
                        }
                        Button("Ajouter un document", systemImage: "wave.3.right") { adding = true }.buttonStyle(SesamePassPrimaryButtonStyle())
                        Button("Importer une archive", systemImage: "square.and.arrow.down") { importing = true }
                    }
                    Label("Sans publicité. Sans suivi. Sans serveur tiers.", systemImage: "checkmark.shield").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(Color("Canvas"))
                .navigationTitle("SesamePass").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Réglages", systemImage: "gearshape") { settings = true } } }
                .navigationDestination(for: UUID.self) { PassportDetail(id: $0) }
                .sheet(isPresented: $adding) { AddPassportView { id in path.append(id) } }
                .sheet(isPresented: $settings) { SettingsView() }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                    do {
                        let url = try result.get()
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 64 * 1024 * 1024 else { throw VaultError.invalidData }
                        importData = try Data(contentsOf: url)
                        importSheet = true
                    } catch { store.message = L10n.string("Impossible d’ouvrir cette archive chiffrée.") }
                }
                .sheet(isPresented: $importSheet, onDismiss: { importPassword = ""; importData = nil }) {
                    NavigationStack {
                        Form {
                            Text("L’archive est déchiffrée uniquement sur cet iPhone.")
                            SecureField("Mot de passe de l’archive", text: $importPassword)
                            Button(L10n.string(importBusy ? "Déchiffrement…" : "Importer")) {
                                guard let data = importData else { return }
                                let password = importPassword
                                importBusy = true
                                Task {
                                    defer { importBusy = false }
                                    do {
                                        var record = try await Task.detached { try ArchiveCipher.restore(data, password: password) }.value
                                        // An explicit archive import is a new local copy, never an overwrite.
                                        record.id = UUID()
                                        try store.save(record)
                                        importSheet = false
                                    } catch { store.message = VaultError.invalidData.localizedDescription }
                                }
                            }.disabled(importBusy || importPassword.isEmpty)
                        }.navigationTitle("Archive chiffrée")
                    }.presentationDetents([.medium])
                }
        }
    }
}

struct SettingsView: View {
    @Environment(PassportStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    Toggle("Sauvegarde iCloud", isOn: $store.backupEnabled)
                    if store.backupEnabled {
                        Text(L10n.string(store.cloudAccount == nil ? "En attente d’iCloud" : "Chiffrement AES-GCM avant chaque envoi")).font(.footnote)
                        if let message = store.cloudMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    }
                } footer: { Text("Désactivée : aucune nouvelle communication CloudKit et aucune nouvelle clé synchronisable créée par SesamePass. Les sauvegardes et clés déjà présentes dans iCloud restent conservées.") }
                Section("Récupération sur un autre iPhone") {
                    Text("Activez Mots de passe et Trousseau dans les réglages iCloud, puis utilisez le même compte Apple sur le nouvel iPhone.")
                    Text("SesamePass ne peut pas vérifier que la synchronisation du Trousseau a abouti. Pour une récupération indépendante d’iCloud, conservez aussi une archive chiffrée et son mot de passe en lieu sûr.").font(.footnote).foregroundStyle(.secondary)
                }
                if store.pendingDeletions > 0 {
                    Section("Suppressions en attente") {
                        Text(L10n.format(store.pendingDeletions == 1 ? "%d suppression iCloud à effectuer." : "%d suppressions iCloud à effectuer.", store.pendingDeletions))
                        Text("La sauvegarde iCloud doit être activée et le compte d’origine connecté. Ne désinstallez pas l’application avant la fin.").font(.footnote)
                    }
                }
                Section {
                    Toggle("Verrouiller SesamePass", isOn: Binding(
                        get: { store.appLockEnabled },
                        set: { enabled in Task { await store.setAppLockEnabled(enabled) } }
                    )).disabled(store.changingProtection)
                    if store.changingProtection { ProgressView("Vérification…") }
                } header: { Text("Protection de l’accès") }
                  footer: { Text("Option désactivée par défaut. Si activée, Face ID, Touch ID ou le code appareil sera demandé au retour dans l’application. Les données restent chiffrées dans les deux cas.") }
                Section("Confidentialité") {
                    Label("Aucun analytics ni tracking", systemImage: "hand.raised")
                    Label("Services Apple uniquement", systemImage: "icloud")
                    Text("Le PDF est lisible par ses destinataires. Une archive reste chiffrée avec le mot de passe choisi.").font(.footnote)
                }
                Section("Projet") { Text("SesamePass · version 0.2\nLecture NFC sur iPhone compatible.").font(.footnote) }
            }.navigationTitle("Réglages").toolbar { Button("Terminé") { dismiss() } }
        }
    }
}

struct PassportDetail: View {
    @Environment(PassportStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var deleting = false
    @State private var warnPDF = false
    @State private var archive = false
    @State private var password = ""
    @State private var confirmation = ""
    @State private var exporting = false
    @State private var share: SharedFile?
    struct SharedFile: Identifiable { let id = UUID(); let url: URL }
    var body: some View {
        if let record = store.passports.first(where: { $0.id == id }) {
            List {
                Section {
                    if let bytes = record.photograph, let image = UIImage(data: bytes) {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 170).frame(maxWidth: .infinity)
                    }
                    Text("\(record.givenNames) \(record.surname)").font(.title2.weight(.semibold))
                    Text(store.status(record)).font(.caption).foregroundStyle(.secondary)
                }
                Section("Document") {
                    LabeledContent("Type", value: record.kind.title)
                    LabeledContent("Numéro", value: record.documentNumber)
                    LabeledContent("Nationalité", value: record.nationality)
                    LabeledContent("Naissance", value: record.birthDate)
                    LabeledContent("Expiration", value: record.expiryDate)
                    LabeledContent("Lecture NFC", value: record.readAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Vérifications cryptographiques") {
                    if record.checks.contains(where: { $0.result == .failed }) {
                        Label("Certains contrôles ont échoué. Consultez les résultats ci-dessous.", systemImage: "exclamationmark.triangle").font(.callout)
                    }
                    if record.checks.isEmpty { Text("Aucune vérification enregistrée") }
                    ForEach(Array(record.checks.enumerated()), id: \.offset) { _, check in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(L10n.string(check.name), systemImage: check.result == .passed ? "checkmark.shield" : check.result == .failed ? "exclamationmark.shield" : "questionmark.circle")
                            Text(L10n.string(check.result == .passed ? "Réussie" : check.result == .failed ? "Échec" : "Non effectuée")).font(.caption.weight(.semibold))
                            Text(L10n.string(check.detail)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Menu("Exporter", systemImage: "square.and.arrow.up") {
                        Button("PDF lisible") { warnPDF = true }
                        Button("Archive chiffrée") { archive = true }
                    }
                    Button("Supprimer", role: .destructive) { deleting = true }
                }
            }.navigationTitle(record.kind.title).navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("Supprimer ce document", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Supprimer de cet iPhone", role: .destructive) { remove(record, cloud: false) }
                    Button("Supprimer de cet iPhone et d’iCloud", role: .destructive) { remove(record, cloud: true) }
                } message: { Text("Hors ligne, la suppression iCloud restera en attente. Si iCloud est désactivé, réactivez-le pour terminer cette suppression.") }
                .alert("Exporter des données lisibles ?", isPresented: $warnPDF) {
                    Button("Annuler", role: .cancel) { }
                    Button("Créer le PDF") {
                        do { share = SharedFile(url: try Exporter.pdf(record)) }
                        catch { store.message = L10n.string("Impossible de créer le PDF.") }
                    }
                } message: { Text("Le PDF contient votre identité, votre photographie et les informations du document sans chiffrement. Toute personne disposant du fichier pourra les lire. Copie numérique — ne remplace pas un document de voyage.") }
                .sheet(item: $share, onDismiss: { Exporter.cleanExpiredFiles() }) { file in ShareSheet(url: file.url) { share = nil } }
                .sheet(isPresented: $archive, onDismiss: { password = ""; confirmation = "" }) {
                    NavigationStack {
                        Form {
                            Text("Toutes les données conservées, y compris MRZ, Data Groups et SOD, seront chiffrées. Ce mot de passe sera indispensable à la restauration.")
                            SecureField("Mot de passe · 12 caractères minimum", text: $password)
                            SecureField("Confirmer le mot de passe", text: $confirmation)
                            Button(L10n.string(exporting ? "Chiffrement…" : "Créer l’archive")) {
                                let secret = password
                                exporting = true
                                Task {
                                    defer { exporting = false }
                                    do {
                                        let data = try await Task.detached { try ArchiveCipher.export(record, password: secret) }.value
                                        guard store.unlocked else { return }
                                        let url = try Exporter.write(data, extension: "sesame")
                                        archive = false
                                        // Present after the password sheet has dismissed.
                                        try? await Task.sleep(for: .milliseconds(400))
                                        guard store.unlocked else { try? FileManager.default.removeItem(at: url); return }
                                        share = SharedFile(url: url)
                                    } catch { store.message = L10n.string("Impossible de créer l’archive.") }
                                }
                            }.disabled(exporting || password.count < 12 || password != confirmation)
                        }.navigationTitle("Archive chiffrée")
                    }.presentationDetents([.medium, .large])
                }
        }
    }
    private func remove(_ record: PassportRecord, cloud: Bool) {
        do { try store.delete(record, fromCloud: cloud); dismiss() }
        catch { store.message = L10n.string("La suppression locale a échoué. Réessayez après déverrouillage.") }
    }
}
