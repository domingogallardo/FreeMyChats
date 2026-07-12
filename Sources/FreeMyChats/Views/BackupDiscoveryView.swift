import SwiftUI

@available(macOS 14.0, *)
struct BackupDiscoveryView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            sourceBar
            content
        }
        .padding(20)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Free My Chats")
                    .font(.largeTitle.bold())
                Text("Convierte una copia de WhatsApp en una biblioteca local de conversaciones.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir biblioteca…") {
                if let url = DirectoryPicker.chooseExistingLibrary() {
                    store.openLibrary(at: url)
                }
            }
        }
    }

    private var sourceBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)
            Text(store.backupSearchPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button("Elegir carpeta…") {
                if let url = DirectoryPicker.choose(startingAt: store.backupSearchPath) {
                    store.backupSearchPath = url.path
                    store.inspectBackups()
                }
            }
            Button("Analizar") {
                store.inspectBackups()
            }
            .keyboardShortcut("r", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(store.operation != nil)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var content: some View {
        if let operation = store.operation {
            OperationProgressView(operation: operation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let issue = store.discoveryIssue {
            ContentUnavailableView {
                Label("No se pudo acceder a las copias", systemImage: "lock.trianglebadge.exclamationmark")
            } description: {
                Text(issue + "\nPuede ser necesario conceder acceso total al disco.")
            } actions: {
                Button("Elegir otra carpeta…") {
                    if let url = DirectoryPicker.choose(startingAt: store.backupSearchPath) {
                        store.backupSearchPath = url.path
                        store.inspectBackups()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.backupRows.isEmpty {
            ContentUnavailableView(
                "Sin copias disponibles",
                systemImage: "externaldrive.badge.questionmark",
                description: Text(
                    "Analiza la carpeta de MobileSync o elige otra ubicación. "
                    + "macOS puede exigir acceso total al disco."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.backupRows) { row in
                        BackupRowView(row: row) {
                            guard let destination = DirectoryPicker.chooseNewLibrary() else { return }
                            store.createLibrary(from: row, at: destination)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
