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
    @State private var messageNavigationRequest: MessageNavigationRequest?
    @State private var isShowingMediaGallery = false
    @State private var currentConversationDate: Date?

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
            return selected.record.totalContributionCount
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
                sourceTitles:
                    conversation.record.contributions.compactMap { contribution in
                        store.session?.version(id: contribution.source.versionID)?.record.title
                    }
                    + conversation.record.importedContributions.map {
                        "Chat importado · \($0.displayName)"
                    },
                isSearching: $isSearching,
                searchText: $messageSearchText,
                isSearchPending: isMessageSearchPending,
                selectedResultNumber: selectedSearchResultNumber,
                resultCount: searchResultCount,
                navigateSearch: navigateSearch,
                finishSearch: finishMessageSearch,
                cancelSearch: cancelMessageSearch,
                currentDate: currentConversationDate
                    ?? initialConversationDate(in: conversation, selection: selection),
                navigateToMessage: navigateToMessage,
                showMediaGallery: {
                    isShowingMediaGallery = true
                },
                goBack: store.showConversationCatalog,
                revealInFinder: store.revealSelectedChat,
                exportConversation: store.exportSelectedConversation
            )
            Divider()
            MessageListView(
                conversation: conversation,
                searchText: appliedMessageSearchText,
                initialMessageID: store.readingPosition(for: selection),
                searchNavigationRequest: searchNavigationRequest,
                searchExitRequest: searchExitRequest,
                messageNavigationRequest: messageNavigationRequest,
                searchSelectionChanged: { resultNumber, resultCount in
                    selectedSearchResultNumber = resultNumber
                    searchResultCount = resultCount
                },
                readingDateChanged: { date in
                    currentConversationDate = date
                },
                saveReadingPosition: { messageID in
                    store.saveReadingPosition(messageID, for: selection)
                }
            )
            .id(
                "\(conversation.contentRevisionID.uuidString)-"
                    + (messageNavigationRequest?.id.uuidString ?? "reading-position")
            )
        }
        .sheet(isPresented: $isShowingMediaGallery) {
            ConversationMediaGalleryView(
                conversationName: conversation.document.chat.name,
                items: ConversationMediaItem.items(in: conversation),
                navigateToMessage: navigateToMessageFromGallery
            )
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
            messageNavigationRequest = nil
            isSearching = false
            isShowingMediaGallery = false
            currentConversationDate = nil
        }
    }

    private func initialConversationDate(
        in conversation: ArchivedConversation,
        selection: ConversationArchiveID
    ) -> Date? {
        if let messageID = store.readingPosition(for: selection),
           let message = conversation.document.messages.first(where: { $0.id == messageID }) {
            return message.date
        }
        return conversation.document.messages.last?.date
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

    private func navigateToMessageFromGallery(_ messageID: Int) {
        isShowingMediaGallery = false
        navigateToMessage(messageID)
    }

    private func navigateToMessage(_ messageID: Int) {
        if isSearching {
            closeMessageSearch(behavior: .restoreInitialPosition)
        }
        messageNavigationRequest = MessageNavigationRequest(
            id: UUID(),
            messageID: messageID
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

struct MessageNavigationRequest: Equatable {
    let id: UUID
    let messageID: Int
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
    let currentDate: Date?
    let navigateToMessage: (Int) -> Void
    let showMediaGallery: () -> Void
    let goBack: () -> Void
    let revealInFinder: () -> Void
    let exportConversation: () -> Void

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

                        if conversation.record.totalContributionCount > 1 {
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
                            .help("Ver los chats incluidos en esta Vista unificada")
                            .popover(isPresented: $isShowingUnifiedViewHelp) {
                                UnifiedViewHelpView(sourceTitles: sourceTitles)
                            }
                        }
                    }
                }
                Spacer()
                ConversationDateNavigationButton(
                    messages: conversation.document.messages,
                    currentDate: currentDate,
                    navigateToMessage: navigateToMessage
                )

                Button(action: showMediaGallery) {
                    Label("Fotos y vídeos", systemImage: "photo.on.rectangle.angled")
                }
                .help("Ver todas las fotos y vídeos de la conversación")
                .accessibilityLabel("Ver fotos y vídeos de la conversación")

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

                Menu {
                    Button("Abrir en Finder", systemImage: "folder", action: revealInFinder)
                    Divider()
                    Button(
                        "Exportar conversación…",
                        systemImage: "square.and.arrow.up",
                        action: exportConversation
                    )
                } label: {
                    Label("Acciones de la conversación", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Abrir o exportar esta conversación")
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
            localContributionCount: conversation.record.contributions.count,
            importedContributionCount: conversation.record.importedContributions.count,
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

private struct ConversationDateNavigationButton: View {
    let messages: [MessageInfo]
    let currentDate: Date?
    let navigateToMessage: (Int) -> Void

    @State private var isShowingDatePicker = false
    @State private var selectedDate = Date()

    var body: some View {
        Button {
            selectedDate = pickerInitialDate
            isShowingDatePicker = true
        } label: {
            Label("Ir a fecha", systemImage: "calendar")
        }
        .disabled(messages.isEmpty)
        .help("Ir al mensaje más cercano a una fecha")
        .accessibilityHint("Abre un calendario para escoger el día")
        .popover(isPresented: $isShowingDatePicker) {
            ConversationDateNavigationPopover(
                messages: messages,
                selectedDate: $selectedDate,
                navigateToMessage: { messageID in
                    isShowingDatePicker = false
                    navigateToMessage(messageID)
                },
                cancel: {
                    isShowingDatePicker = false
                }
            )
        }
    }

    private var pickerInitialDate: Date {
        guard let dateRange = MessageDateNavigation.dateRange(in: messages) else {
            return .now
        }

        let date = Calendar.autoupdatingCurrent.startOfDay(
            for: currentDate ?? dateRange.upperBound
        )
        return min(max(date, dateRange.lowerBound), dateRange.upperBound)
    }
}

private struct ConversationDateNavigationPopover: View {
    let messages: [MessageInfo]
    @Binding var selectedDate: Date
    let navigateToMessage: (Int) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ir a una fecha")
                .font(.headline)

            if let dateRange = MessageDateNavigation.dateRange(in: messages) {
                HStack(spacing: 8) {
                    Picker("Mes", selection: selectedMonth) {
                        ForEach(availableMonths, id: \.self) { month in
                            Text(Self.monthNames[month - 1])
                                .tag(month)
                        }
                    }
                    .frame(minWidth: 145)

                    Picker("Año", selection: selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(year.formatted(.number.grouping(.never)))
                                .tag(year)
                        }
                    }
                    .frame(width: 105)
                }
                .pickerStyle(.menu)

                DatePicker(
                    "Fecha",
                    selection: $selectedDate,
                    in: dateRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                if let selectedTarget, !selectedTarget.isExactDate {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No hay mensajes ese día.")
                                .foregroundStyle(.secondary)
                            Text(
                                "Se abrirá el \(selectedTarget.date.formatted(date: .long, time: .omitted))."
                            )
                            .foregroundStyle(.primary)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button("Cancelar", role: .cancel, action: cancel)
                    Button("Ir a la fecha") {
                        if let selectedTarget {
                            navigateToMessage(selectedTarget.messageID)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedTarget == nil)
                }
            }
        }
        .padding(14)
    }

    private var selectedTarget: MessageDateNavigation.Target? {
        MessageDateNavigation.target(closestTo: selectedDate, in: messages)
    }

    private var selectedMonth: Binding<Int> {
        Binding(
            get: {
                Calendar.autoupdatingCurrent.component(.month, from: selectedDate)
            },
            set: { month in
                updateSelectedDate(year: selectedYear.wrappedValue, month: month)
            }
        )
    }

    private var selectedYear: Binding<Int> {
        Binding(
            get: {
                Calendar.autoupdatingCurrent.component(.year, from: selectedDate)
            },
            set: { year in
                updateSelectedDate(year: year, month: selectedMonth.wrappedValue)
            }
        )
    }

    private var availableMonths: [Int] {
        guard let dateRange = MessageDateNavigation.dateRange(in: messages) else {
            return []
        }

        let calendar = Calendar.autoupdatingCurrent
        let year = calendar.component(.year, from: selectedDate)
        let firstYear = calendar.component(.year, from: dateRange.lowerBound)
        let lastYear = calendar.component(.year, from: dateRange.upperBound)
        let firstMonth = year == firstYear
            ? calendar.component(.month, from: dateRange.lowerBound)
            : 1
        let lastMonth = year == lastYear
            ? calendar.component(.month, from: dateRange.upperBound)
            : 12
        return Array(firstMonth...lastMonth)
    }

    private var availableYears: [Int] {
        guard let dateRange = MessageDateNavigation.dateRange(in: messages) else {
            return []
        }

        let calendar = Calendar.autoupdatingCurrent
        let firstYear = calendar.component(.year, from: dateRange.lowerBound)
        let lastYear = calendar.component(.year, from: dateRange.upperBound)
        return Array(firstYear...lastYear)
    }

    private func updateSelectedDate(year: Int, month: Int) {
        guard let dateRange = MessageDateNavigation.dateRange(in: messages),
              let updatedDate = MessageDateNavigation.date(
                bySelectingYear: year,
                month: month,
                preservingDayFrom: selectedDate,
                within: dateRange
              ) else {
            return
        }
        selectedDate = updatedDate
    }

    private static let monthNames: [String] = {
        let formatter = DateFormatter()
        return formatter.standaloneMonthSymbols.map {
            $0.capitalized(with: formatter.locale ?? .autoupdatingCurrent)
        }
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
        subtitle(
            chatType: chatType,
            messageCount: messageCount,
            localContributionCount: contributionCount,
            importedContributionCount: 0,
            date: date
        )
    }

    static func subtitle(
        chatType: ChatInfo.ChatType,
        messageCount: Int,
        localContributionCount: Int,
        importedContributionCount: Int,
        date: String
    ) -> String {
        let type = chatType == .group ? "Grupo" : "Conversación individual"
        let savedCopies = localContributionCount == 1
            ? "1 chat guardado"
            : "\(localContributionCount) chats guardados"
        let importedChats: String? = switch importedContributionCount {
        case 0: nil
        case 1: "1 chat importado"
        default: "\(importedContributionCount) chats importados"
        }
        let unified = localContributionCount + importedContributionCount > 1
            ? "Vista unificada"
            : nil
        return [
            unified,
            type,
            "\(messageCount.formatted()) mensajes",
            savedCopies,
            importedChats,
            date
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
