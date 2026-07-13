import AppKit
import SwiftUI
import SwiftWABackupAPI

@available(macOS 14.0, *)
struct ChatSidebarView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var expandedVersionIDs: Set<String> = []
    @State private var versionPendingDeletion: LibraryVersionSession?

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            List(selection: $store.selectedChatID) {
                ForEach(store.versions) { version in
                    DisclosureGroup(isExpanded: expansionBinding(for: version.id)) {
                        let chats = store.visibleChats(in: version)
                        if chats.isEmpty {
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
                                    canExport: version.hasSourceBackup,
                                    export: { store.exportChat(selection) }
                                )
                                .tag(selection)
                                .contextMenu {
                                    if store.selectedChatID == selection, store.selectedExport != nil {
                                        Button("Abrir exportación en Finder") {
                                            store.revealSelectedChat()
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        BackupVersionRow(version: version) {
                            versionPendingDeletion = version
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .disabled(store.operation != nil)
        }
        .searchable(text: $store.chatSearchText, prompt: "Buscar chats")
        .onChange(of: store.selectedChatID) { _, chatID in
            store.selectChat(chatID)
        }
        .onChange(of: store.versions.map(\.id)) { _, ids in
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
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Copias de WhatsApp")
                        .font(.title2.bold())
                    Text("\(store.versions.count) versiones en la biblioteca")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Filtro", selection: $store.chatFilter) {
                    ForEach(ChatListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 105)
            }

            Text("Despliega una copia para navegar por sus chats")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
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

private struct BackupVersionRow: View {
    let version: LibraryVersionSession
    let deleteSource: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: version.hasSourceBackup ? "externaldrive.fill" : "externaldrive.badge.xmark")
                .foregroundStyle(version.hasSourceBackup ? Color.secondary : Color.orange)
                .frame(width: 17)

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
    let canExport: Bool
    let export: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ChatAvatar(photoURL: photoURL, name: chat.name)

                VStack(alignment: .leading, spacing: 3) {
                    Text(chat.name)
                        .fontWeight(.medium)
                        .lineLimit(1)

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
            detailLine("Primero", value: firstMessageDescription)
            detailLine("Último", value: Self.detailDateFormatter.string(from: chat.lastMessageDate))

            HStack {
                exportStatus
                Spacer(minLength: 8)
            }
            .padding(.top, 3)
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
        switch exportState {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Comprobando exportación…")
                    .foregroundStyle(.secondary)
            }
        case .notExported:
            if canExport {
                Button(action: export) {
                    HStack(spacing: 5) {
                        Text("Exportar")
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help("Exportar y abrir en el panel derecho")
            } else {
                Label("Copia fuente no disponible", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        case .exported:
            Label("Exportado", systemImage: "checkmark")
                .foregroundStyle(.secondary)
        case .stale:
            Label("Exportado · actualización disponible", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
        case .invalid:
            Label("Exportación no válida", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var summary: String {
        var parts: [String] = []
        if chat.chatType == .group { parts.append("Grupo") }
        if chat.isArchived { parts.append("Archivado") }
        if parts.isEmpty { parts.append("Conversación") }
        return parts.joined(separator: " · ")
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
