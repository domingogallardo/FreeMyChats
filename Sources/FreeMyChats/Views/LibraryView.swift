import SwiftUI

struct LibraryView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 470)
        } detail: {
            ConversationView(store: store)
                .navigationTitle("")
        }
        .sheet(isPresented: $store.isShowingBackupImporter) {
            BackupDiscoveryView(store: store)
                .frame(minWidth: 780, minHeight: 580)
        }
        .alert(
            "WhatsApp se ha extraído correctamente",
            isPresented: Binding(
                get: { store.importedBackupCleanupPrompt != nil },
                set: { if !$0 { store.dismissImportedBackupCleanupPrompt() } }
            )
        ) {
            Button("Conservar la copia", role: .cancel) {
                store.dismissImportedBackupCleanupPrompt()
            }
            Button("Mover a la Papelera", role: .destructive) {
                store.moveImportedIPhoneBackupToTrash()
            }
        } message: {
            Text(cleanupPromptMessage)
        }
        .overlay {
            if let operation = blockingOperation {
                OperationProgressView(operation: operation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    private var blockingOperation: AppOperation? {
        guard let operation = store.operation else { return nil }
        switch operation.kind {
        case .openingLibrary, .deletingBackup, .deletingOriginalIPhoneBackup,
             .deletingStoredContribution, .preparingStoredCopyDeletion:
            return operation
        case .discovering, .creatingLibrary, .addingBackup, .storingChat, .loadingChats:
            return nil
        }
    }

    private var cleanupPromptMessage: String {
        guard let prompt = store.importedBackupCleanupPrompt else { return "" }
        let date = prompt.creationDate.map(Self.dateFormatter.string) ?? "seleccionada"
        return "La copia de WhatsApp ya está guardada en la biblioteca. Cuando hayas copiado aquí los chats que quieres conservar, puedes usar “Vaciar chat” en WhatsApp para recuperar espacio en el iPhone. También puedes conservar la copia completa del iPhone correspondiente al \(date), borrarla más tarde desde Finder (Gestionar copias…) o moverla ahora a la Papelera."
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}
