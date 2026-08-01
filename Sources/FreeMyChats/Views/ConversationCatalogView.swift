import SwiftUI

struct ConversationCatalogView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var searchText = ""
    @State private var isShowingUnifiedViewHelp = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.isLoadingConversationCatalog, store.conversationCatalog.isEmpty {
                ProgressView("Leyendo el catálogo de conversaciones…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.conversationPanelError, store.conversationCatalog.isEmpty {
                UnavailableContentView(
                    "No se puede leer el catálogo de conversaciones",
                    systemImage: "exclamationmark.folder",
                    description: error
                )
            } else if store.conversationCatalog.isEmpty {
                UnavailableContentView(
                    "Todavía no hay conversaciones en el catálogo",
                    systemImage: "tray",
                    description:
                        "Despliega un chat en el panel izquierdo y pulsa Añadir al catálogo. "
                        + "Aparecerá aquí como una conversación guardada."
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
                        store.openConversation(item.id)
                    } label: {
                        ConversationCatalogRow(
                            item: item,
                            photoURL: store.profilePhotoURL(for: item)
                        )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Abrir la conversación \(item.chat.name)")
                }
                .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("Catálogo de conversaciones")
                        .font(.title2.bold())

                    Button {
                        isShowingUnifiedViewHelp.toggle()
                    } label: {
                        Label("Qué es una Vista unificada", systemImage: "info.circle")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Qué es una Vista unificada")
                    .popover(isPresented: $isShowingUnifiedViewHelp) {
                        UnifiedViewHelpView()
                    }
                }
                Text(conversationCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Buscar conversaciones", text: $searchText)
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
                    .accessibilityLabel("Borrar búsqueda")
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

    private var conversationCountDescription: String {
        let count = filteredChats.count
        if !normalizedSearchText.isEmpty {
            return count == 1 ? "1 resultado" : "\(count) resultados"
        }
        return count == 1 ? "1 conversación" : "\(count) conversaciones"
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredChats: [ConversationCatalogItem] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return store.conversationCatalog }

        return store.conversationCatalog.filter { item in
            item.chat.name.localizedCaseInsensitiveContains(query)
                || item.chat.contactJid.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct ConversationCatalogRow: View {
    let item: ConversationCatalogItem
    let photoURL: URL?

    var body: some View {
        HStack(spacing: 11) {
            LocalImageAvatar(photoURL: photoURL, name: item.chat.name, size: 42)

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
                Text(Self.updatedDateFormatter.string(from: item.updatedAt))
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
        let type = ConversationPresentation.cellTypeLabel(chatType: item.chat.chatType)
        let savedCopies = item.localContributionCount == 1
            ? "1 chat guardado"
            : "\(item.localContributionCount) chats guardados"
        let importedChats: String? = switch item.importedContributionCount {
        case 0: nil
        case 1: "1 chat importado"
        default: "\(item.importedContributionCount) chats importados"
        }
        let unified = item.contributionCount > 1 ? "Vista unificada" : nil
        return [
            unified,
            type,
            "\(item.chat.numberMessages.formatted()) mensajes",
            savedCopies,
            importedChats
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static let updatedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
