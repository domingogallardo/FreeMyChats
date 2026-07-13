import SwiftUI

@available(macOS 14.0, *)
struct LibraryView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 470)
        } detail: {
            ConversationView(store: store)
                .navigationTitle("Exportaciones")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.showBackupImporter()
                } label: {
                    Label("Añadir copia…", systemImage: "plus")
                }
                .help("Añadir otra copia de WhatsApp a esta biblioteca")
                .disabled(store.operation != nil)

                Menu {
                    Button("Volver a leer la biblioteca") {
                        store.reloadLibrary()
                    }
                    Divider()
                    Button("Abrir biblioteca en Finder") {
                        store.revealLibrary()
                    }
                    Button("Abrir otra biblioteca…") {
                        if let url = DirectoryPicker.chooseExistingLibrary(
                            startingAt: store.session?.paths.rootURL.path
                        ) {
                            store.openLibrary(at: url)
                        }
                    }
                    Button("Cerrar biblioteca") {
                        store.closeLibrary()
                    }
                } label: {
                    Label("Opciones de la biblioteca", systemImage: "ellipsis.circle")
                }
                .disabled(store.operation != nil)
            }
        }
        .sheet(isPresented: $store.isShowingBackupImporter) {
            BackupDiscoveryView(store: store)
                .frame(minWidth: 780, minHeight: 580)
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
        case .openingLibrary, .deletingBackup, .loadingChats:
            return operation
        case .discovering, .creatingLibrary, .addingBackup, .exportingChat:
            return nil
        }
    }
}
