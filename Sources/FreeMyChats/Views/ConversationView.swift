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
            if let chat = store.selectedChat {
                selectedChatContent(chat)
            } else {
                ContentUnavailableView(
                    "Selecciona un chat",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(
                        "Despliega una copia de WhatsApp a la izquierda y selecciona un chat. "
                        + "Podrás revisar sus datos antes de decidir si quieres exportarlo."
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func selectedChatContent(_ chat: ChatInfo) -> some View {
        if let selection = store.selectedChatID,
           let operation = store.operation,
           operation.kind == .exportingChat(selection)
            || operation.kind == .openingChat(selection) {
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
        } else if case .notExported = store.selectedExportState {
            ContentUnavailableView(
                "Chat sin exportar",
                systemImage: "arrow.right.circle",
                description: Text(
                    "Revisa la información desplegada en el panel izquierdo y pulsa Exportar "
                    + "para abrir aquí la conversación completa."
                )
            )
        } else {
            OperationProgressView(
                operation: AppOperation(
                    id: UUID(),
                    kind: .openingChat(
                        store.selectedChatID
                            ?? VersionChatID(versionID: "", chatID: chat.id)
                    ),
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
            MessageListView(exported: exported, searchText: appliedMessageSearchText)
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
        .onChange(of: exported.document.chat.id) { _, _ in
            messageSearchText = ""
            appliedMessageSearchText = ""
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
                    Label("La copia fuente contiene una versión más reciente de este chat.", systemImage: "clock.arrow.circlepath")
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
            ScrollViewReader { proxy in
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
