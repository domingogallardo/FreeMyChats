import SwiftUI

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
                .help("Cerrar esta ventana")
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
            .help("Elegir la carpeta que contiene las copias del iPhone")
            Button("Analizar") {
                store.inspectBackups()
            }
            .keyboardShortcut("r", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(store.operation != nil)
            .help("Buscar copias de WhatsApp en la carpeta seleccionada")
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
            discoveryIssueView(issue)
        } else if store.backupRows.isEmpty {
            UnavailableContentView(
                "Sin copias disponibles",
                systemImage: "externaldrive.badge.questionmark",
                description:
                    "Analiza la carpeta de MobileSync o elige otra ubicación. "
                    + "macOS puede exigir acceso total al disco."
            )
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

    @ViewBuilder
    private func discoveryIssueView(_ issue: BackupDiscoveryIssue) -> some View {
        switch issue {
        case .permissionRequired:
            UnavailableContentView(
                "Free My Chats necesita permiso",
                systemImage: "lock.trianglebadge.exclamationmark",
                description: permissionDescription
            ) {
                HStack {
                    Button("Abrir Ajustes del Sistema") {
                        WorkspaceService.openFullDiskAccessSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Abrir los ajustes de Acceso total al disco")

                    Button("Salir de Free My Chats") {
                        WorkspaceService.quitApplication()
                    }
                    .help("Cerrar Free My Chats para aplicar el permiso")
                }
            }

        case .unreadableDirectory(let detail):
            UnavailableContentView(
                "No se pudo leer la carpeta de copias",
                systemImage: "externaldrive.badge.exclamationmark",
                description: detail
            ) {
                HStack {
                    Button("Elegir otra carpeta…") {
                        if let url = DirectoryPicker.choose(startingAt: store.backupSearchPath) {
                            store.backupSearchPath = url.path
                            store.inspectBackups()
                        }
                    }
                    .help("Elegir otra carpeta que contenga copias del iPhone")
                    Button("Volver a intentar") {
                        store.inspectBackups()
                    }
                    .help("Analizar de nuevo la carpeta seleccionada")
                }
            }
        }
    }

    private var permissionDescription: String {
        let instructions =
            "En Ajustes del Sistema, abre Privacidad y seguridad > Acceso total al disco "
            + "y activa Free My Chats. Después sal completamente de la app y vuelve a abrirla. "
        if store.versions.isEmpty {
            return instructions + "La comprobación continuará automáticamente al reiniciar."
        }
        return instructions + "Pulsa Añadir copia para volver a intentarlo."
    }
}
