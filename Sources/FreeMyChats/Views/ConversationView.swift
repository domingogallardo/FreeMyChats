import SwiftUI
import SwiftWABackupAPI

@available(macOS 14.0, *)
struct ConversationView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var isSearching = false
    @State private var messageSearchText = ""

    var body: some View {
        Group {
            if let chat = store.selectedChat {
                selectedChatContent(chat)
            } else {
                ContentUnavailableView(
                    "Selecciona un chat",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(
                        "La lista de la izquierda representa la biblioteca. "
                        + "Al abrir un chat por primera vez se crea su carpeta exportada."
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func selectedChatContent(_ chat: ChatInfo) -> some View {
        if let operation = store.operation, operation.kind == .exportingChat(chat.id)
            || operation.kind == .openingChat(chat.id) {
            OperationProgressView(operation: operation)
        } else if case .invalid(let reason) = store.selectedExportState {
            ContentUnavailableView {
                Label("La exportación no es válida", systemImage: "exclamationmark.folder")
            } description: {
                Text(reason)
            } actions: {
                Button("Volver a exportar") {
                    store.updateSelectedExport()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let exported = store.selectedExport {
            conversation(exported)
        } else {
            OperationProgressView(
                operation: AppOperation(
                    id: UUID(),
                    kind: .openingChat(chat.id),
                    title: "Abriendo el chat…",
                    detail: nil,
                    fractionCompleted: nil
                )
            )
        }
    }

    private func conversation(_ exported: ExportedChat) -> some View {
        VStack(spacing: 0) {
            ConversationHeaderView(
                exported: exported,
                state: store.selectedExportState,
                isSearching: $isSearching,
                searchText: $messageSearchText,
                revealInFinder: store.revealSelectedChat,
                updateExport: store.updateSelectedExport
            )
            Divider()
            MessageListView(exported: exported, searchText: messageSearchText)
        }
        .onChange(of: exported.document.chat.id) { _, _ in
            messageSearchText = ""
            isSearching = false
        }
    }
}

private struct ConversationHeaderView: View {
    let exported: ExportedChat
    let state: ChatExportDisplayState
    @Binding var isSearching: Bool
    @Binding var searchText: String
    let revealInFinder: () -> Void
    let updateExport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
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
                    if case .stale = state {
                        Divider()
                        Button("Actualizar exportación", action: updateExport)
                    }
                } label: {
                    Label("Opciones del chat", systemImage: "ellipsis.circle")
                }
                .labelStyle(.iconOnly)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if case .stale = state {
                HStack {
                    Label("La biblioteca contiene una versión más reciente de este chat.", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Button("Actualizar", action: updateExport)
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

    private var messages: [MessageInfo] {
        guard !searchText.isEmpty else { return exported.document.messages }
        return exported.document.messages.filter { message in
            [message.message, message.caption, message.author?.displayName, message.mediaFilename]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        if messages.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            if beginsNewDay(at: index) {
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onAppear {
                    if searchText.isEmpty, let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func beginsNewDay(at index: Int) -> Bool {
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
