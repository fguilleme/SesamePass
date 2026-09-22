import SwiftUI
import VisionKit
import AVFoundation

struct AddPassportView: View {
    @Environment(PassportStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: DocumentKind = .passport
    @State private var number = ""
    @State private var birth = ""
    @State private var expiry = ""
    @State private var camera = false
    @State private var recognizing = false
    @State private var reading = false
    @State private var message: String?
    @State private var scanMessage: String?
    @State private var scanFailed = false
    @State private var pendingRecord: PassportRecord?
    @FocusState private var focused: Bool
    let saved: (UUID) -> Void

    private var access: MRZAccess? { try? MRZAccess(documentNumber: number, typedBirthDate: birth, typedExpiryDate: expiry) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Type de document") {
                    Picker("Document", selection: $kind) {
                        ForEach(DocumentKind.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }.disabled(reading || recognizing || camera || pendingRecord != nil)
                Section {
                    Label(kind == .passport ? "Lire votre passeport" : "Lire votre carte d’identité", systemImage: "wave.3.right").font(.title2.weight(.semibold))
                    Text(kind == .passport ? "Munissez-vous de votre passeport biométrique. Les informations de sa page d’identité permettent d’ouvrir la connexion avec sa puce." : "Utilisez une carte avec puce et trois lignes de caractères au verso (format TD1). Les anciennes cartes françaises sans puce ne sont pas compatibles. La lecture dépend des protocoles de la carte ; les cartes nécessitant un CAN ou un code PIN ne sont pas prises en charge.")
                        .foregroundStyle(.secondary)
                }
                if VNDocumentCameraViewController.isSupported {
                    Section {
                        Button(recognizing ? "Lecture de la page…" : (kind == .passport ? "Scanner la page d’identité" : "Scanner le verso de la carte"), systemImage: "viewfinder") { requestCamera() }
                            .disabled(reading || recognizing || pendingRecord != nil)
                        Text(kind == .passport ? "Cadrez la page d’identité et les deux lignes en bas, sans reflet. Confirmez la photo puis enregistrez le scan." : "Cadrez entièrement les trois lignes de caractères au verso de la carte, sans reflet. Confirmez la photo puis enregistrez le scan.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let scanMessage {
                    Section {
                        if recognizing { ProgressView(scanMessage) }
                        else {
                            Label(scanMessage, systemImage: scanFailed ? "exclamationmark.triangle" : "checkmark.circle")
                                .font(.callout).accessibilityIdentifier("scanMessage")
                        }
                    }
                }
                Section("Informations du document") {
                    TextField("Numéro du document", text: $number)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().focused($focused)
                        .privacySensitive()
                    TextField("Naissance · JJ/MM/AAAA", text: $birth)
                        .keyboardType(.numbersAndPunctuation).focused($focused).privacySensitive()
                    TextField("Expiration · JJ/MM/AAAA", text: $expiry)
                        .keyboardType(.numbersAndPunctuation).focused($focused).privacySensitive()
                }.disabled(reading || recognizing || pendingRecord != nil)
                Section {
                    Label("Posez le haut de l’iPhone contre le document.", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    Text(kind == .passport ? "L’emplacement de la puce varie selon le passeport : essayez la couverture ou la page d’identité. Restez immobile jusqu’à la fin de la lecture." : "Sortez la carte de son étui, posez-la seule sur une table et maintenez le haut du dos de l’iPhone contre elle.").font(.footnote).foregroundStyle(.secondary)
                    if reading { ProgressView("Lecture en cours…") }
                    Button(pendingRecord == nil ? "Lire la puce NFC" : "Enregistrer le document", systemImage: pendingRecord == nil ? "wave.3.right" : "checkmark") {
                        focused = false
                        if let pendingRecord { persist(pendingRecord) } else { startReading() }
                    }.buttonStyle(SesamePassPrimaryButtonStyle())
                        .disabled(reading || recognizing || (pendingRecord == nil && (access == nil || !NFCReadingService.available)))
                    if !NFCReadingService.available { Text(NFCReadError.unavailable.localizedDescription).font(.footnote).foregroundStyle(.secondary) }
                    if let message { Text(message).font(.callout).foregroundStyle(.primary).accessibilityIdentifier("nfcMessage") }
                }
                Section {
                    Text("La lecture et le scan de la page sont traités sur cet iPhone. Le document est enregistré localement avant toute sauvegarde iCloud chiffrée.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .onChange(of: kind) { _, _ in
                number = ""; birth = ""; expiry = ""; scanMessage = nil; message = nil
            }
            .navigationTitle("Ajouter un document").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(reading || recognizing) } }
            .interactiveDismissDisabled(reading || recognizing)
            .sheet(isPresented: $camera) {
                MRZCamera { data in
                    camera = false
                    guard let data else { return }
                    recognizing = true
                    scanFailed = false
                    scanMessage = "Analyse de la page en cours…"
                    let session = store.sessionIdentity
                    let scannedKind = kind
                    Task {
                        defer { recognizing = false }
                        do {
                            let recognized = try await MRZRecognition().recognize(data, kind: scannedKind)
                            guard store.unlocked, store.sessionIdentity == session else {
                                scanFailed = true
                                scanMessage = "La session a changé pendant le scan. Relancez le scan pour remplir les informations."
                                return
                            }
                            number = recognized.documentNumber
                            birth = MRZAccess.displayedDate(recognized.birthDate, birth: true)
                            expiry = MRZAccess.displayedDate(recognized.expiryDate, birth: false)
                            scanMessage = "Page lue. Vérifiez les trois champs ci-dessous, puis touchez Lire la puce NFC. La photo seule n’ajoute pas le document."
                        } catch {
                            guard store.unlocked, store.sessionIdentity == session else { return }
                            scanFailed = true
                            scanMessage = (error as? MRZError)?.localizedDescription ?? MRZError.unreadable.localizedDescription
                        }
                    }
                }.ignoresSafeArea()
            }
        }
    }
    private func requestCamera() {
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed { camera = true }
            else { message = "Autorisez l’appareil photo dans les réglages iOS de SesamePass, ou saisissez les informations manuellement." }
        }
    }
    private func startReading() {
        do {
            let input = try MRZAccess(documentNumber: number, typedBirthDate: birth, typedExpiryDate: expiry)
            let session = store.sessionIdentity
            reading = true
            message = nil
            Task {
                defer { reading = false }
                do {
                    let record = try await NFCReadingService.read(input, kind: kind)
                    guard store.unlocked, store.sessionIdentity == session else { return }
                    pendingRecord = record
                    persist(record)
                } catch {
                    message = NFCReadingService.isCancellation(error) ? "Lecture annulée. Aucun document ajouté." : NFCReadingService.userMessage(error)
                }
            }
        } catch { message = error.localizedDescription }
    }
    private func persist(_ record: PassportRecord) {
        do {
            try store.save(record)
            pendingRecord = nil
            number = ""; birth = ""; expiry = ""
            dismiss()
            saved(record.id)
        } catch {
            message = "Le document a été lu mais n’a pas pu être enregistré. Vérifiez le code de verrouillage de l’iPhone et l’espace disponible, puis réessayez sans relire la puce."
        }
    }
}
