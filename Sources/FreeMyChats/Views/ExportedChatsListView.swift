import AppKit
import SwiftUI

struct ExportedChatsListView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.isLoadingExportCatalog, store.exportedChats.isEmpty {
                ProgressView("Leyendo el catálogo de conversaciones…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.exportPanelError, store.exportedChats.isEmpty {
                UnavailableContentView(
                    "No se pueden leer las exportaciones",
                    systemImage: "exclamationmark.folder",
                    description: error
                )
            } else if store.exportedChats.isEmpty {
                UnavailableContentView(
                    "Todavía no hay conversaciones en el catálogo",
                    systemImage: "tray",
                    description:
                        "Despliega un chat en el panel izquierdo y pulsa Exportar. "
                        + "Aparecerá aquí como una vista unificada de sus exportaciones."
                )
            } else if filteredChats.isEmpty {
                UnavailableContentView(
                    "No hay resultados",
                    systemImage: "magnifyingglass",
                    description: "No se han encontrado conversaciones que coincidan con la búsqueda."
                )
            } else {
                List(filteredChats) { item in
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
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Catálogo de conversaciones")
                    .font(.title2.bold())
                Text(exportCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Buscar chats", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Borrar búsqueda")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .frame(minWidth: 190, idealWidth: 280, maxWidth: 360)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var exportCountDescription: String {
        let count = filteredChats.count
        if !normalizedSearchText.isEmpty {
            return count == 1 ? "1 resultado" : "\(count) resultados"
        }
        return count == 1 ? "1 conversación" : "\(count) conversaciones"
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredChats: [ExportedChatListItem] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return store.exportedChats }

        return store.exportedChats.filter { item in
            item.chat.name.localizedCaseInsensitiveContains(query)
                || item.chat.contactJid.localizedCaseInsensitiveContains(query)
        }
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
                Text("Actualizada")
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
        let exports = item.contributionCount == 1
            ? "1 exportación"
            : "\(item.contributionCount) exportaciones"
        return "\(type) · \(item.chat.numberMessages.formatted()) mensajes · \(exports)"
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
