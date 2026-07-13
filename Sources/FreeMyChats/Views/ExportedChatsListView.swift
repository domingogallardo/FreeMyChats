import AppKit
import SwiftUI

@available(macOS 14.0, *)
struct ExportedChatsListView: View {
    @ObservedObject var store: FreeMyChatsStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.isLoadingExportCatalog, store.exportedChats.isEmpty {
                ProgressView("Leyendo chats exportados…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.exportPanelError, store.exportedChats.isEmpty {
                ContentUnavailableView {
                    Label("No se pueden leer las exportaciones", systemImage: "exclamationmark.folder")
                } description: {
                    Text(error)
                }
            } else if store.exportedChats.isEmpty {
                ContentUnavailableView(
                    "Todavía no hay chats exportados",
                    systemImage: "tray",
                    description: Text(
                        "Despliega un chat en el panel izquierdo y pulsa Exportar. "
                        + "Aparecerá aquí sin cambiar automáticamente esta pantalla."
                    )
                )
            } else {
                List(store.exportedChats) { item in
                    Button {
                        store.openExport(item.id)
                    } label: {
                        ExportedChatRow(item: item)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Chats exportados")
                    .font(.title2.bold())
                Text(exportCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var exportCountDescription: String {
        let count = store.exportedChats.count
        return count == 1 ? "1 chat disponible" : "\(count) chats disponibles"
    }
}

private struct ExportedChatRow: View {
    let item: ExportedChatListItem

    var body: some View {
        HStack(spacing: 11) {
            ExportedChatAvatar(photoURL: item.photoURL, name: item.chat.name)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.chat.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Self.exportDateFormatter.string(from: item.exportedAt))
                Text(item.versionTitle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    private var detail: String {
        let type = item.chat.chatType == .group ? "Grupo" : "Conversación"
        return "\(type) · \(item.chat.numberMessages.formatted()) mensajes"
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

private struct ExportedChatAvatar: View {
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
        .frame(width: 42, height: 42)
        .clipShape(Circle())
    }
}
