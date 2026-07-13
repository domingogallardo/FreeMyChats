import SwiftUI

@available(macOS 14.0, *)
struct BackupDiscoveryView: View {
    @ObservedObject var store: FreeMyChatsStore
    @Environment(\.dismiss) private var dismiss

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
                Text("Añadir una copia de WhatsApp")
                    .font(.largeTitle.bold())
                Text("Selecciona otra copia del iPhone para incorporarla como una versión independiente.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cerrar") { dismiss() }
                .keyboardShortcut(.cancelAction)
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
                            store.addBackup(from: row)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
