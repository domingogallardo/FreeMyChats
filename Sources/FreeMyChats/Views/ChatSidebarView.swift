import AppKit
import SwiftUI
import SwiftWABackupAPI

struct ChatSidebarView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var expandedVersionIDs: Set<String> = []
    @State private var versionPendingDeletion: LibraryVersionSession?
    @State private var exportPendingDeletion: ExportDeletionRequest?

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            List(selection: $store.selectedChatID) {
                ForEach(store.versions) { version in
                    DisclosureGroup(isExpanded: expansionBinding(for: version.id)) {
                        let chats = store.visibleChats(in: version)
                        if store.isLoadingSourceChats, chats.isEmpty, version.hasSourceBackup {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.small)
                                Text("Leyendo conversaciones…")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 27)
                            .padding(.vertical, 5)
                        } else if chats.isEmpty {
                            Text(emptyMessage(for: version))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 27)
                                .padding(.vertical, 5)
                        } else {
                            ForEach(chats, id: \.id) { chat in
                                let selection = VersionChatID(versionID: version.id, chatID: chat.id)
                                ChatSidebarRow(
                                    chat: chat,
                                    photoURL: store.profilePhotoURL(for: chat, in: version),
                                    isExpanded: store.selectedChatID == selection,
                                    detailsState: store.chatDetails[selection],
                                    exportState: store.exportStates[selection] ?? .checking,
                                    isExporting: store.exportingChatID == selection,
                                    canExport: version.hasSourceBackup,
                                    toggleExpansion: {
                                        store.selectedChatID = store.selectedChatID == selection
                                            ? nil
                                            : selection
                                    },
                                    export: { store.exportChat(selection) },
                                    replaceExport: { store.replaceExport(selection) },
                                    revealExport: { store.revealExport(selection) },
                                    deleteExport: {
                                        exportPendingDeletion = ExportDeletionRequest(
                                            selection: selection,
                                            chatName: chat.name,
                                            versionTitle: version.record.title
                                        )
                                    }
                                )
                                .tag(selection)
                            }
                        }
                    } label: {
                        BackupVersionRow(
                            version: version,
                            isExporting: store.exportingChatID?.versionID == version.id,
                            isLoading: store.isLoadingSourceChats && version.hasSourceBackup
                        ) {
                            versionPendingDeletion = version
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .disabled(store.operation != nil)
        }
        .onChange(of: store.selectedChatID) { chatID in
            store.selectChat(chatID)
        }
        .onChange(of: store.versions.map(\.id)) { ids in
            expandedVersionIDs.formIntersection(Set(ids))
            if expandedVersionIDs.isEmpty, let first = ids.first {
                expandedVersionIDs.insert(first)
            }
        }
        .onAppear {
            if let first = store.versions.first?.id {
                expandedVersionIDs.insert(first)
            }
        }
        .confirmationDialog(
            "¿Eliminar esta copia fuente?",
            isPresented: Binding(
                get: { versionPendingDeletion != nil },
                set: { if !$0 { versionPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar copia fuente", role: .destructive) {
                if let version = versionPendingDeletion {
                    store.deleteSourceBackup(versionID: version.id)
                }
                versionPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                versionPendingDeletion = nil
            }
        } message: {
            Text(
                "Se liberará el espacio ocupado por el backup. Las conversaciones ya exportadas "
                + "seguirán disponibles, pero no se podrán exportar otros chats de esta versión."
            )
        }
        .confirmationDialog(
            "¿Borrar esta exportación?",
            isPresented: Binding(
                get: { exportPendingDeletion != nil },
                set: { if !$0 { exportPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Borrar exportación", role: .destructive) {
                if let request = exportPendingDeletion {
                    store.deleteExportedContribution(request.selection)
                }
                exportPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                exportPendingDeletion = nil
            }
        } message: {
            if let request = exportPendingDeletion {
                Text(
                    "Se borrarán los mensajes y archivos de “\(request.chatName)” exportados "
                    + "desde la copia \(request.versionTitle). La conversación del catálogo se "
                    + "reconstruirá con las demás exportaciones; si esta es la última, desaparecerá."
                )
            }
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copias de WhatsApp")
                        .font(.title2.bold())
                    Text("\(store.versions.count) versiones en la biblioteca")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                libraryActions
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Despliega una copia para navegar por sus chats")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                Menu {
                    Picker("Ordenar chats", selection: $store.chatSortOrder) {
                        ForEach(ChatListSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                } label: {
                    Label("Ordenar chats", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Ordenar chats: \(store.chatSortOrder.title)")

                Picker("Filtro", selection: $store.chatFilter) {
                    ForEach(ChatListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 105)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var libraryActions: some View {
        HStack(spacing: 6) {
            Button {
                store.showBackupImporter()
            } label: {
                Label("Añadir copia…", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
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
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Opciones de la biblioteca")
            .disabled(store.operation != nil)
        }
        .controlSize(.regular)
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedVersionIDs.contains(id) },
            set: { expanded in
                if expanded {
                    expandedVersionIDs.insert(id)
                } else {
                    expandedVersionIDs.remove(id)
                }
            }
        )
    }

    private func emptyMessage(for version: LibraryVersionSession) -> String {
        version.hasSourceBackup ? "No hay chats con este filtro" : "No quedaron chats exportados"
    }
}

private struct ExportDeletionRequest {
    let selection: VersionChatID
    let chatName: String
    let versionTitle: String
}

private struct BackupVersionRow: View {
    let version: LibraryVersionSession
    let isExporting: Bool
    let isLoading: Bool
    let deleteSource: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 17)
            } else {
                Image(systemName: version.hasSourceBackup ? "externaldrive.fill" : "externaldrive.badge.xmark")
                    .foregroundStyle(version.hasSourceBackup ? Color.secondary : Color.orange)
                    .frame(width: 17)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(version.record.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if version.hasSourceBackup {
                Menu {
                    Button("Eliminar copia fuente…", role: .destructive, action: deleteSource)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Gestionar copia")
            }
        }
        .padding(.vertical, 3)
    }

    private var detail: String {
        if isLoading {
            return "Leyendo conversaciones…"
        }
        if version.hasSourceBackup {
            let size = ByteCountFormatter.string(
                fromByteCount: version.backupByteCount,
                countStyle: .file
            )
            return "\(size) · \(version.chats.count) chats"
        }
        return "Copia eliminada · \(version.chats.count) exportados"
    }
}

private struct ChatSidebarRow: View {
    let chat: ChatInfo
    let photoURL: URL?
    let isExpanded: Bool
    let detailsState: ChatDetailsState?
    let exportState: ChatExportDisplayState
    let isExporting: Bool
    let canExport: Bool
    let toggleExpansion: () -> Void
    let export: () -> Void
    let replaceExport: () -> Void
    let revealExport: () -> Void
    let deleteExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleExpansion) {
                HStack(spacing: 10) {
                    ChatAvatar(photoURL: photoURL, name: chat.name)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(chat.name)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(sizeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 4) {
                            Text(summary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Self.shortDateFormatter.string(from: chat.lastMessageDate))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(isExpanded ? "Cerrar detalles del chat" : "Mostrar detalles del chat")

            if isExpanded {
                expandedDetails
                    .padding(.leading, 48)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 18)
        .padding(.vertical, isExpanded ? 7 : 3)
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
    }

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailLine("Mensajes", value: chat.numberMessages.formatted())
            detailLine("Tamaño", value: sizeDescription)
            detailLine("Primero", value: firstMessageDescription)
            detailLine("Último", value: Self.detailDateFormatter.string(from: chat.lastMessageDate))

            HStack {
                exportStatus
                Spacer(minLength: 8)
            }
            .padding(.top, 3)

            if exportState.isPhysicallyExported, !isExporting {
                HStack(spacing: 6) {
                    actionButton(
                        "Abrir carpeta",
                        systemImage: "folder",
                        action: revealExport
                    )
                    .help("Abrir esta exportación en Finder")
                    actionButton(
                        "Borrar",
                        systemImage: "trash",
                        tint: .red,
                        action: deleteExport
                    )
                    .help("Borrar únicamente la exportación de esta copia")
                }
            }
        }
        .font(.caption)
    }

    private func detailLine(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var exportStatus: some View {
        if isExporting {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Exportando…")
                    .foregroundStyle(.secondary)
            }
        } else {
            exportStateView
        }
    }

    @ViewBuilder
    private var exportStateView: some View {
        switch exportState {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Comprobando exportación…")
                    .foregroundStyle(.secondary)
            }
        case .notExported:
            if canExport {
                actionButton("Exportar", action: export)
                .help("Exportar y crear una conversación en el catálogo")
            } else {
                Label("Copia fuente no disponible", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        case .updateAvailable:
            if canExport {
                actionButton(
                    "Añadir a conversación",
                    systemImage: "plus",
                    action: export
                )
                .help("Exportar este chat y añadirlo a la conversación del catálogo")
            } else {
                Label("Guardado · fuente no disponible", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            }
        case .exported:
            Label("Exportado", systemImage: "checkmark")
                .foregroundStyle(.secondary)
        case .stale:
            if canExport {
                actionButton(
                    "Volver a exportar",
                    systemImage: "arrow.clockwise",
                    action: replaceExport
                )
                .help("Recrear esta exportación y actualizar la vista unificada")
            } else {
                Label("Exportado · fuente no disponible", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            }
        case .invalid:
            if canExport {
                actionButton(
                    "Volver a exportar",
                    systemImage: "arrow.clockwise",
                    action: replaceExport
                )
                .help("Reemplazar la exportación no válida y actualizar la vista unificada")
            } else {
                Label("Exportación no válida", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = Color.accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private var summary: String {
        var parts: [String] = []
        if chat.chatType == .group { parts.append("Grupo") }
        if chat.isArchived { parts.append("Archivado") }
        if parts.isEmpty { parts.append("Conversación") }
        return parts.joined(separator: " · ")
    }

    private var sizeDescription: String {
        guard chat.mediaByteCount > 0 else { return "0 GB" }
        return Self.gigabyteFormatter.string(fromByteCount: chat.mediaByteCount)
    }

    private var firstMessageDescription: String {
        switch detailsState {
        case .loading:
            return "Calculando…"
        case .loaded(let date):
            return date.map(Self.detailDateFormatter.string) ?? "Sin mensajes"
        case .failed:
            return "No disponible"
        case nil:
            return "—"
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let gigabyteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .decimal
        formatter.isAdaptive = false
        return formatter
    }()
}

private struct ChatAvatar: View {
    let photoURL: URL?
    let name: String

    var body: some View {
        Group {
            if let photoURL, let image = NSImage(contentsOf: photoURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(.quaternary)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
    }
}
