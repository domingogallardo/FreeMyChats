import SwiftUI
import SwiftWABackupAPI

struct ConversationView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var isSearching = false
    @State private var messageSearchText = ""
    @State private var appliedMessageSearchText = ""
    @State private var isConfirmingExportDeletion = false

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
        .confirmationDialog(
            "¿Borrar este chat exportado?",
            isPresented: $isConfirmingExportDeletion,
            titleVisibility: .visible
        ) {
            Button("Borrar chat exportado", role: .destructive) {
                store.deleteSelectedExportedChat()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(
                "Se borrarán permanentemente sus mensajes y archivos exportados. "
                + "Si es el último chat de una copia cuya fuente ya fue eliminada, "
                + "también se borrará esa copia de la biblioteca."
            )
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
            UnavailableContentView(
                "La exportación no es válida",
                systemImage: "exclamationmark.folder",
                description: reason
            )
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
                revealInFinder: store.revealSelectedChat,
                deleteExport: { isConfirmingExportDeletion = true }
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
    let deleteExport: () -> Void

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
                    Divider()
                    Button("Borrar chat exportado…", role: .destructive, action: deleteExport)
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
