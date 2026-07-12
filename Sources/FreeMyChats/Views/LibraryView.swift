import SwiftUI

@available(macOS 14.0, *)
struct LibraryView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        NavigationSplitView {
            ChatSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            ConversationView(store: store)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    store.reloadChats()
                } label: {
                    Label("Actualizar biblioteca", systemImage: "arrow.clockwise")
                }
                .disabled(store.operation != nil)

                Menu {
                    Button("Abrir biblioteca en Finder") {
                        store.revealLibrary()
                    }
                    Divider()
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
    }
}
