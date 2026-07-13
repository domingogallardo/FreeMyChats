import SwiftUI
import SwiftWABackupAPI

@available(macOS 14.0, *)
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
            ProgressView("Abriendo el chat exportado…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func exportErrorView(_ reason: String) -> some View {
        VStack(spacing: 0) {
            ExportBackHeader(title: "Chat exportado", action: store.showExportList)
            Divider()
            ContentUnavailableView {
                Label("La exportación no es válida", systemImage: "exclamationmark.folder")
            } description: {
                Text(reason)
            }
        }
    }

    private func conversation(_ exported: ExportedChat, selection: VersionChatID) -> some View {
        VStack(spacing: 0) {
            ConversationHeaderView(
                exported: exported,
                state: store.openedExportState,
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
        .onChange(of: store.selectedExportID) { _, _ in
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
                Label("Volver a chats exportados", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .help("Volver a chats exportados")

            Text(title)
                .font(.title2.bold())
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct ConversationHeaderView: View {
    let exported: ExportedChat
    let state: ChatExportDisplayState
    @Binding var isSearching: Bool
    @Binding var searchText: String
    let goBack: () -> Void
    let revealInFinder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: goBack) {
                    Label("Volver a chats exportados", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .help("Volver a chats exportados")

                VStack(alignment: .leading, spacing: 3) {
                    Text(exported.document.chat.name)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                Menu {
                    Button("Abrir carpeta en Finder", action: revealInFinder)
                } label: {
                    Label("Opciones del chat", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if case .stale = state {
                HStack {
                    Label("La copia fuente contiene una versión más reciente de este chat.", systemImage: "clock.arrow.circlepath")
                    Spacer()
                }
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(.orange.opacity(0.12))
            }

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
        let type = chat.chatType == .group ? "Grupo" : "Conversación individual"
        let date = Self.dateFormatter.string(from: exported.document.exportedAt)
        return "Chat exportado · \(type) · \(chat.numberMessages.formatted()) mensajes · \(date)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

private struct MessageListView: View {
    let exported: ExportedChat
    let searchText: String
    let initialMessageID: Int?
    let saveReadingPosition: (Int) -> Void

    @State private var scrollPosition: Int?
    @State private var lastReadingPosition: Int?

    init(
        exported: ExportedChat,
        searchText: String,
        initialMessageID: Int?,
        saveReadingPosition: @escaping (Int) -> Void
    ) {
        self.exported = exported
        self.searchText = searchText
        self.initialMessageID = initialMessageID
        self.saveReadingPosition = saveReadingPosition
        _scrollPosition = State(initialValue: initialMessageID)
        _lastReadingPosition = State(initialValue: initialMessageID)
    }

    private var filteredMessages: [MessageInfo] {
        MessageSearch.filter(exported.document.messages, query: searchText)
    }

    var body: some View {
        let messages = filteredMessages

        if messages.isEmpty {
            ContentUnavailableView(
                "No hay resultados",
                systemImage: "magnifyingglass",
                description: Text("No se han encontrado mensajes que contengan “\(searchText)”.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if beginsNewDay(at: index, in: messages) {
                            Text(Self.dayFormatter.string(from: message.date))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                        MessageRowView(
                            message: message,
                            mediaDirectoryURL: exported.mediaDirectoryURL
                        )
                        .id(message.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .onAppear {
                if searchText.isEmpty {
                    restoreReadingPosition(in: messages)
                }
            }
            .onChange(of: searchText) { _, query in
                if query.isEmpty {
                    restoreReadingPosition(in: filteredMessages)
                } else {
                    scrollPosition = filteredMessages.first?.id
                }
            }
            .onChange(of: scrollPosition) { _, messageID in
                guard searchText.isEmpty, let messageID else { return }
                lastReadingPosition = messageID
            }
            .task(id: lastReadingPosition) {
                guard let messageID = lastReadingPosition else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                saveReadingPosition(messageID)
            }
            .onDisappear {
                if let messageID = lastReadingPosition {
                    saveReadingPosition(messageID)
                }
            }
        }
    }

    private func restoreReadingPosition(in messages: [MessageInfo]) {
        let savedPosition = lastReadingPosition ?? initialMessageID
        let target = savedPosition.flatMap { savedID in
            messages.contains(where: { $0.id == savedID }) ? savedID : nil
        } ?? messages.last?.id

        scrollPosition = target
        lastReadingPosition = target
    }

    private func beginsNewDay(at index: Int, in messages: [MessageInfo]) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].date, inSameDayAs: messages[index - 1].date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
