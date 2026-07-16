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
            ProgressView("Abriendo la conversación guardada…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func exportErrorView(_ reason: String) -> some View {
        VStack(spacing: 0) {
            ExportBackHeader(title: "Conversación guardada", action: store.showExportList)
            Divider()
            UnavailableContentView(
                "La exportación no es válida",
                systemImage: "exclamationmark.folder",
                description: reason
            )
        }
    }

    private func conversation(
        _ exported: ArchivedConversation,
        selection: ConversationArchiveID
    ) -> some View {
        VStack(spacing: 0) {
            ConversationHeaderView(
                exported: exported,
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
                Label("Volver a conversaciones guardadas", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .help("Volver a conversaciones guardadas")

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
    @Binding var isSearching: Bool
    @Binding var searchText: String
    let goBack: () -> Void
    let revealInFinder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: goBack) {
                    Label("Volver a conversaciones guardadas", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .help("Volver a conversaciones guardadas")

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
        let date = Self.dateFormatter.string(from: exported.record.updatedAt)
        let count = exported.record.contributions.count
        let sources = count == 1 ? "1 copia" : "\(count) copias"
        return "Conversación guardada · \(type) · \(chat.numberMessages.formatted()) mensajes · \(sources) · \(date)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
