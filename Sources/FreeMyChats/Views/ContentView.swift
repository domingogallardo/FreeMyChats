import SwiftUI

@available(macOS 14.0, *)
struct ContentView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        Group {
            if store.session == nil {
                BackupDiscoveryView(store: store)
            } else {
                LibraryView(store: store)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .task {
            store.start()
        }
        .alert(
            "No se pudo completar la operación",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.dismissError() } }
            )
        ) {
            Button("Aceptar", role: .cancel) {
                store.dismissError()
            }
        } message: {
            Text(store.errorMessage ?? "Error desconocido")
        }
    }
}
