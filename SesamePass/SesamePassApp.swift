import SwiftUI
import CloudKit

@main
struct SesamePassApp: App {
    @State private var store = PassportStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ZStack {
                if store.unlocked {
                    ContentView()
                } else if store.appLockEnabled {
                    VStack(spacing: 24) {
                        Image(systemName: "lock").font(.system(size: 56, weight: .ultraLight))
                        Text("SesamePass").font(.system(size: 44, weight: .medium, design: .serif))
                        Text("L’accès à vos passeports est protégé.").foregroundStyle(.secondary)
                        Button("Déverrouiller") { Task { await store.unlock() } }.buttonStyle(SesamePassPrimaryButtonStyle())
                    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color("Canvas"))
                } else {
                    VStack(spacing: 20) {
                        if store.loadFailed {
                            Text("Les passeports ne sont pas disponibles.").font(.headline)
                            Button("Réessayer") { Task { await store.openIfAllowed() } }.buttonStyle(SesamePassPrimaryButtonStyle())
                        } else {
                            ProgressView("Chargement des passeports…")
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color("Canvas"))
                }
                if phase != .active {
                    Color(red: 0.04, green: 0.11, blue: 0.18).ignoresSafeArea()
                    Text("SesamePass").font(.title).foregroundStyle(.white)
                }
            }
            .environment(store)
            .tint(Color("InterfaceAccent"))
            .alert("SesamePass", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: { Text(store.message ?? "") }
            .onChange(of: phase) { _, phase in
                if phase == .background { store.lock() }
                if phase == .active {
                    Task { await store.openIfAllowed(); store.schedule() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
                store.lock()
                if phase == .active { Task { await store.openIfAllowed() } }
            }
            .task {
                await store.openIfAllowed()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(45)) } catch { break }
                    if phase == .active { store.schedule() }
                }
            }
        }
    }
}
