import SwiftUI

@available(macOS 14.0, *)
struct ContentView: View {
    @StateObject private var store = BackupInspectionStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Free my chats")
                    .font(.largeTitle.bold())
                Text("Encuentra las copias de iPhone que contienen tus chats de WhatsApp.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(store.rootPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button("Elegir carpeta…") {
                    if let url = DirectoryPicker.choose(startingAt: store.rootPath) {
                        store.rootPath = url.path
                        store.inspect()
                    }
                }
                Button("Analizar") {
                    store.inspect()
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(store.isInspecting)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            Group {
                if store.isInspecting {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analizando copias…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.errorMessage {
                    ContentUnavailableView(
                        "No se pudo acceder a las copias",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error + "\nPuede ser necesario conceder acceso total al disco.")
                    )
                } else if store.rows.isEmpty {
                    ContentUnavailableView(
                        "Sin resultados",
                        systemImage: "externaldrive",
                        description: Text("Pulsa Analizar o elige otra carpeta de copias de seguridad.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.rows) { row in
                                BackupRowView(row: row)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 440)
        .task {
            store.inspect()
        }
    }
}
