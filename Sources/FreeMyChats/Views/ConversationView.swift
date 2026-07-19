import SwiftUI
import SwiftWABackupAPI

struct ConversationView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var isSearching = false
    @State private var messageSearchText = ""
    @State private var appliedMessageSearchText = ""

    var body: some View {
        Group {
            if store.selectedExportID == nil {
                ExportedChatsListView(store: store)
            } else if store.isOpeningExport {
                exportLoadingView
            } else if let reason = store.exportPanelError {
                exportErrorView(reason)
            } else if let exported = store.selectedExport,
                      let selection = store.selectedExportID {
                conversation(exported, selection: selection)
            } else {
                exportLoadingView
            }
        }
    }

    private var exportLoadingView: some View {
        VStack(spacing: 0) {
            ExportBackHeader(title: "Abriendo chat", action: store.showExportList)
            Divider()
            ProgressView("Abriendo la conversación…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func exportErrorView(_ reason: String) -> some View {
        VStack(spacing: 0) {
            ExportBackHeader(
                title: ConversationPresentation.headerTitle(
                    contributionCount: selectedContributionCount
                ),
                action: store.showExportList
            )
            Divider()
            UnavailableContentView(
                "La exportación no es válida",
                systemImage: "exclamationmark.folder",
                description: reason
            )
        }
    }

    private var selectedContributionCount: Int {
        if let selected = store.selectedExport {
            return selected.record.contributions.count
        }
        guard let selection = store.selectedExportID else { return 1 }
        return store.exportedChats.first(where: { $0.id == selection })?.contributionCount ?? 1
    }

    private func conversation(
        _ exported: ArchivedConversation,
        selection: ConversationArchiveID
    ) -> some View {
        VStack(spacing: 0) {
            ConversationHeaderView(
                exported: exported,
                sourceTitles: exported.record.contributions.compactMap { contribution in
                    store.session?.version(id: contribution.source.versionID)?.record.title
                },
                isSearching: $isSearching,
                searchText: $messageSearchText,
                goBack: store.showExportList,
                revealInFinder: store.revealSelectedChat
            )
            Divider()
            MessageListView(
                exported: exported,
                searchText: appliedMessageSearchText,
                initialMessageID: store.readingPosition(for: selection),
                saveReadingPosition: { messageID in
                    store.saveReadingPosition(messageID, for: selection)
                }
            )
            .id(selection)
        }
        .task(id: messageSearchText) {
            let query = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                appliedMessageSearchText = ""
                return
            }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            appliedMessageSearchText = query
        }
        .onChange(of: store.selectedExportID) { _ in
            messageSearchText = ""
            appliedMessageSearchText = ""
            isSearching = false
        }
    }
}

private struct ExportBackHeader: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Label("Volver al catálogo de conversaciones", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .help("Volver al catálogo de conversaciones")

            Text(title)
                .font(.title2.bold())
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct ConversationHeaderView: View {
    let exported: ArchivedConversation
    let sourceTitles: [String]
    @Binding var isSearching: Bool
    @Binding var searchText: String
    @State private var isShowingUnifiedViewHelp = false
    let goBack: () -> Void
    let revealInFinder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: goBack) {
                    Label("Volver al catálogo de conversaciones", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .help("Volver al catálogo de conversaciones")

                VStack(alignment: .leading, spacing: 3) {
                    Text(exported.document.chat.name)
                        .font(.title2.bold())
                    HStack(spacing: 5) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if exported.record.contributions.count > 1 {
                            Button {
                                isShowingUnifiedViewHelp.toggle()
                            } label: {
                                Label(
                                    "Cómo funciona esta Vista unificada",
                                    systemImage: "info.circle"
                                )
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Ver las exportaciones incluidas en esta Vista unificada")
                            .popover(isPresented: $isShowingUnifiedViewHelp) {
                                UnifiedViewHelpView(sourceTitles: sourceTitles)
                            }
                        }
                    }
                }
                Spacer()
                Button {
                    withAnimation {
                        isSearching.toggle()
                        if !isSearching { searchText = "" }
                    }
                } label: {
                    Label("Buscar en la conversación", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .help(
                    isSearching
                        ? "Cerrar búsqueda en la conversación"
                        : "Buscar en la conversación"
                )
                .accessibilityLabel(
                    isSearching
                        ? "Cerrar búsqueda en la conversación"
                        : "Buscar en la conversación"
                )

                Button(action: revealInFinder) {
                    Label("Abrir conversación en Finder", systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .help("Abrir la carpeta de esta conversación en Finder")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if isSearching {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar mensajes", text: $searchText)
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
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
    }

    private var subtitle: String {
        let chat = exported.document.chat
        let date = Self.dateFormatter.string(from: exported.record.updatedAt)
        return ConversationPresentation.subtitle(
            chatType: chat.chatType,
            messageCount: chat.numberMessages,
            contributionCount: exported.record.contributions.count,
            date: date
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

enum ConversationPresentation {
    static func cellTypeLabel(chatType: ChatInfo.ChatType) -> String {
        chatType == .group ? "Grupo" : "Individual"
    }

    static func headerTitle(contributionCount: Int) -> String {
        contributionCount > 1 ? "Vista unificada" : "Conversación"
    }

    static func subtitle(
        chatType: ChatInfo.ChatType,
        messageCount: Int,
        contributionCount: Int,
        date: String
    ) -> String {
        let type = chatType == .group ? "Grupo" : "Conversación individual"
        let exports = contributionCount == 1
            ? "1 exportación"
            : "\(contributionCount) exportaciones"
        let unified = contributionCount > 1 ? "Vista unificada" : nil
        return [
            unified,
            type,
            "\(messageCount.formatted()) mensajes",
            exports,
            date
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
