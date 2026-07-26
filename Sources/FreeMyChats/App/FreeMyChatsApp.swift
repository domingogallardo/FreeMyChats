import AppKit
import SwiftUI

@main
struct FreeMyChatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = FreeMyChatsStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Crear biblioteca…") {
                    if let url = DirectoryPicker.chooseNewLibrary() {
                        store.createLibrary(at: url)
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store.operation != nil)

                Button("Abrir biblioteca…") {
                    if let url = DirectoryPicker.chooseExistingLibrary(
                        startingAt: store.session?.paths.rootURL.path
                    ) {
                        store.openLibrary(at: url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(store.operation != nil)

                if store.session != nil {
                    Divider()
                    Button("Añadir copia de WhatsApp…") {
                        store.showBackupImporter()
                    }
                    .disabled(store.operation != nil)

                    Button("Importar chat…") {
                        store.chooseAndImportChat()
                    }
                    .disabled(store.operation != nil)

                    Button("Cerrar biblioteca") {
                        store.closeLibrary()
                    }
                    .disabled(store.operation != nil)
                    Divider()
                    Button("Abrir biblioteca en Finder") {
                        store.revealLibrary()
                    }
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
