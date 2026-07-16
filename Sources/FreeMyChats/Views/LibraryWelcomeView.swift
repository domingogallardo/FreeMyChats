import SwiftUI

struct LibraryWelcomeView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Free My Chats")
                    .font(.largeTitle.bold())
                Text("Abre una biblioteca o crea una vacía para empezar a añadir copias de WhatsApp.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button("Abrir biblioteca…") {
                    if let url = DirectoryPicker.chooseExistingLibrary() {
                        store.openLibrary(at: url)
                    }
                }

                Button("Crear biblioteca…") {
                    if let url = DirectoryPicker.chooseNewLibrary() {
                        store.createLibrary(at: url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let operation = store.operation {
                OperationProgressView(operation: operation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }
}
