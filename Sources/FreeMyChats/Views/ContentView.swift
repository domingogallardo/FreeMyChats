import SwiftUI

struct ContentView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        Group {
            if store.session == nil {
                LibraryWelcomeView(store: store)
            } else {
                LibraryView(store: store)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
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
        .alert(
            "Operación completada",
            isPresented: Binding(
                get: { store.informationMessage != nil },
                set: { if !$0 { store.dismissInformation() } }
            )
        ) {
            Button("Aceptar", role: .cancel) {
                store.dismissInformation()
            }
        } message: {
            informationAlertMessage
        }
    }

    private var informationAlertMessage: Text {
        let message = Text(store.informationMessage ?? "")
        guard let emphasis = store.informationEmphasisMessage else { return message }
        return message + Text("\n\n") + Text(emphasis).bold()
    }
}
