import AppKit
import SwiftUI
import SwiftWABackupAPI

@available(macOS 14.0, *)
struct ChatSidebarView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            List(selection: $store.selectedChatID) {
                ForEach(store.visibleChats, id: \.id) { chat in
                    ChatSidebarRow(
                        chat: chat,
                        state: store.exportStates[chat.id] ?? .checking,
                        photoURL: store.profilePhotoURL(for: chat)
                    )
                    .tag(chat.id)
                    .contextMenu {
                        if store.exportStates[chat.id]?.isPhysicallyExported == true,
                           store.selectedChatID == chat.id,
                           store.selectedExport != nil {
                            Button("Abrir carpeta en Finder") {
                                store.revealSelectedChat()
                            }
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
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chats")
                        .font(.title2.bold())
                    Text("\(store.visibleChats.count) de \(store.chats.count) en la biblioteca")
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

            Text("Leídos de la copia local de WhatsApp")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

private struct ChatSidebarRow: View {
    let chat: ChatInfo
    let state: ChatExportDisplayState
    let photoURL: URL?

    var body: some View {
        HStack(spacing: 10) {
            ChatAvatar(photoURL: photoURL, name: chat.name)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(chat.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    exportIndicator
                }

                HStack(spacing: 4) {
                    Text(detail)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.shortDateFormatter.string(from: chat.lastMessageDate))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var exportIndicator: some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .help("Comprobando exportación")
        case .notExported:
            EmptyView()
        case .exported:
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
                .help("Chat exportado")
        case .stale:
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(.orange)
                .help("La exportación está desactualizada")
        case .invalid:
            Image(systemName: "folder.badge.minus")
                .foregroundStyle(.red)
                .help("La exportación no es válida")
        }
    }

    private var detail: String {
        var parts: [String] = []
        if chat.chatType == .group { parts.append("Grupo") }
        if chat.isArchived { parts.append("Archivado") }
        parts.append("\(chat.numberMessages.formatted()) mensajes")
        return parts.joined(separator: " · ")
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
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
