import SwiftUI
import SwiftWABackupAPI

struct ConversationView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var isSearching = false
    @State private var messageSearchText = ""
    @State private var appliedMessageSearchText = ""
    @State private var selectedSearchResultNumber: Int?
    @State private var searchResultCount = 0
    @State private var searchNavigationRequest: MessageSearchNavigationRequest?
    @State private var searchExitRequest: MessageSearchExitRequest?

    var body: some View {
        Group {
            if store.selectedConversationID == nil {
                ConversationCatalogView(store: store)
            } else if store.isOpeningConversation {
                conversationLoadingView
            } else if let reason = store.conversationPanelError {
                conversationErrorView(reason)
            } else if let conversation = store.selectedConversation,
                      let selection = store.selectedConversationID {
                conversationContent(conversation, selection: selection)
            } else {
                conversationLoadingView
            }
        }
    }

    private var conversationLoadingView: some View {
        VStack(spacing: 0) {
            ConversationBackHeader(title: "Abriendo chat", action: store.showConversationCatalog)
            Divider()
            ProgressView("Abriendo la conversación…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func conversationErrorView(_ reason: String) -> some View {
        VStack(spacing: 0) {
            ConversationBackHeader(
                title: ConversationPresentation.headerTitle(
                    contributionCount: selectedContributionCount
                ),
                action: store.showConversationCatalog
            )
            Divider()
            UnavailableContentView(
                "La conversación guardada no es válida",
                systemImage: "exclamationmark.folder",
                description: reason
            )
        }
    }

    private var selectedContributionCount: Int {
        if let selected = store.selectedConversation {
            return selected.record.contributions.count
        }
        guard let selection = store.selectedConversationID else { return 1 }
        return store.conversationCatalog.first(where: { $0.id == selection })?.contributionCount ?? 1
    }

    private func conversationContent(
        _ conversation: ArchivedConversation,
        selection: ConversationArchiveID
    ) -> some View {
        VStack(spacing: 0) {
            ConversationHeaderView(
                conversation: conversation,
                sourceTitles: conversation.record.contributions.compactMap { contribution in
                    store.session?.version(id: contribution.source.versionID)?.record.title
                },
                isSearching: $isSearching,
                searchText: $messageSearchText,
                isSearchPending: isMessageSearchPending,
                selectedResultNumber: selectedSearchResultNumber,
                resultCount: searchResultCount,
                navigateSearch: navigateSearch,
                finishSearch: finishMessageSearch,
                cancelSearch: cancelMessageSearch,
                goBack: store.showConversationCatalog,
                revealInFinder: store.revealSelectedChat
            )
            Divider()
            MessageListView(
                conversation: conversation,
                searchText: appliedMessageSearchText,
                initialMessageID: store.readingPosition(for: selection),
                searchNavigationRequest: searchNavigationRequest,
                searchExitRequest: searchExitRequest,
                searchSelectionChanged: { resultNumber, resultCount in
                    selectedSearchResultNumber = resultNumber
                    searchResultCount = resultCount
                },
                saveReadingPosition: { messageID in
                    store.saveReadingPosition(messageID, for: selection)
                }
            )
            .id(conversation.contentRevisionID)
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
        .onChange(of: store.selectedConversationID) { _ in
            messageSearchText = ""
            appliedMessageSearchText = ""
            selectedSearchResultNumber = nil
            searchResultCount = 0
            searchNavigationRequest = nil
            searchExitRequest = nil
            isSearching = false
        }
    }

    private var isMessageSearchPending: Bool {
        let query = messageSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && query != appliedMessageSearchText
    }

    private func navigateSearch(_ direction: MessageSearchDirection) {
        searchNavigationRequest = MessageSearchNavigationRequest(
            id: UUID(),
            direction: direction
        )
    }

    private func finishMessageSearch() {
        closeMessageSearch(behavior: .keepSelectedMessage)
    }

    private func cancelMessageSearch() {
        closeMessageSearch(behavior: .restoreInitialPosition)
    }

    private func closeMessageSearch(behavior: MessageSearchExitBehavior) {
        searchExitRequest = MessageSearchExitRequest(id: UUID(), behavior: behavior)
        withAnimation {
            messageSearchText = ""
            appliedMessageSearchText = ""
            isSearching = false
        }
    }
}

struct MessageSearchNavigationRequest: Equatable {
    let id: UUID
    let direction: MessageSearchDirection
}

enum MessageSearchExitBehavior: Equatable {
    case keepSelectedMessage
    case restoreInitialPosition
}

struct MessageSearchExitRequest: Equatable {
    let id: UUID
    let behavior: MessageSearchExitBehavior
}

private struct ConversationBackHeader: View {
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
    let conversation: ArchivedConversation
    let sourceTitles: [String]
    @Binding var isSearching: Bool
    @Binding var searchText: String
    @State private var isShowingUnifiedViewHelp = false
    @FocusState private var isSearchFieldFocused: Bool
    let isSearchPending: Bool
    let selectedResultNumber: Int?
    let resultCount: Int
    let navigateSearch: (MessageSearchDirection) -> Void
    let finishSearch: () -> Void
    let cancelSearch: () -> Void
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
                    Text(conversation.document.chat.name)
                        .font(.title2.bold())
                    HStack(spacing: 5) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if conversation.record.contributions.count > 1 {
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
                            .help("Ver las copias incluidas en esta Vista unificada")
                            .popover(isPresented: $isShowingUnifiedViewHelp) {
                                UnifiedViewHelpView(sourceTitles: sourceTitles)
                            }
                        }
                    }
                }
                Spacer()
                Button {
                    if isSearching {
                        isSearchFieldFocused = true
                    } else {
                        withAnimation {
                            isSearching = true
                        }
                    }
                } label: {
                    Label("Buscar en la conversación", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("f", modifiers: .command)
                .help(
                    isSearching
                        ? "Enfocar búsqueda en la conversación"
                        : "Buscar en la conversación"
                )
                .accessibilityLabel(
                    isSearching
                        ? "Enfocar búsqueda en la conversación"
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
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            if canMoveToNextResult {
                                navigateSearch(.next)
                            }
                        }
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

                    Spacer(minLength: 12)

                    searchStatus

                    Button {
                        navigateSearch(.previous)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canMoveToPreviousResult)
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .help("Resultado anterior")
                    .accessibilityLabel("Resultado anterior")

                    Button {
                        navigateSearch(.next)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canMoveToNextResult)
                    .keyboardShortcut("g", modifiers: .command)
                    .help("Resultado siguiente")
                    .accessibilityLabel("Resultado siguiente")

                    Button("Listo", action: finishSearch)
                        .help("Cerrar la búsqueda y conservar el mensaje seleccionado")

                    Button("Cancelar", role: .cancel, action: cancelSearch)
                        .help("Cancelar la búsqueda y volver a la posición inicial")
                }
                .controlSize(.small)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .onChange(of: isSearching) { searching in
            guard searching else {
                isSearchFieldFocused = false
                return
            }
            Task { @MainActor in
                await Task.yield()
                isSearchFieldFocused = true
            }
        }
        .onExitCommand {
            if isSearching {
                cancelSearch()
            }
        }
    }

    @ViewBuilder
    private var searchStatus: some View {
        if !normalizedSearchText.isEmpty {
            if isSearchPending {
                ProgressView()
                    .controlSize(.small)
                Text("Buscando…")
                    .foregroundStyle(.secondary)
            } else if let selectedResultNumber, resultCount > 0 {
                Text("\(selectedResultNumber) de \(resultCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Sin resultados")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canMoveToPreviousResult: Bool {
        guard !isSearchPending, let selectedResultNumber else { return false }
        return selectedResultNumber > 1
    }

    private var canMoveToNextResult: Bool {
        guard !isSearchPending, let selectedResultNumber else { return false }
        return selectedResultNumber < resultCount
    }

    private var subtitle: String {
        let chat = conversation.document.chat
        let date = Self.dateFormatter.string(from: conversation.record.updatedAt)
        return ConversationPresentation.subtitle(
            chatType: chat.chatType,
            messageCount: chat.numberMessages,
            contributionCount: conversation.record.contributions.count,
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
        let savedCopies = contributionCount == 1
            ? "1 copia guardada"
            : "\(contributionCount) copias guardadas"
        let unified = contributionCount > 1 ? "Vista unificada" : nil
        return [
            unified,
            type,
            "\(messageCount.formatted()) mensajes",
            savedCopies,
            date
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
