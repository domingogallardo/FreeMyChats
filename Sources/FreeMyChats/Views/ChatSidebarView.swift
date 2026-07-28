import AppKit
import SwiftUI
import SwiftWABackupAPI

struct ChatSidebarView: View {
    @ObservedObject var store: FreeMyChatsStore
    @State private var expandedVersionIDs: Set<String> = []
    @State private var isImportedChatsExpanded = false
    @State private var expandedImportedChatID: String?
    @State private var versionPendingDeletion: LibraryVersionSession?
    @State private var importedChatPendingDetachment: ImportedChatSidebarItem?
    @State private var importedChatPendingDeletion: ImportedChatSidebarItem?

    var body: some View {
        sidebarContent
        .confirmationDialog(
            "¿Eliminar este chat importado de la conversación?",
            isPresented: Binding(
                get: { importedChatPendingDetachment != nil },
                set: { if !$0 { importedChatPendingDetachment = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar de la conversación") {
                if let item = importedChatPendingDetachment {
                    store.detachImportedChat(item)
                }
                importedChatPendingDetachment = nil
            }
            Button("Cancelar", role: .cancel) {
                importedChatPendingDetachment = nil
            }
        } message: {
            Text(
                "El chat importado se conservará en la columna izquierda, dejará de aportar "
                    + "mensajes a la conversación y podrás volver a incorporarlo con "
                    + "“Añadir a la conversación”."
            )
        }
        .confirmationDialog(
            "¿Borrar este chat importado?",
            isPresented: Binding(
                get: { importedChatPendingDeletion != nil },
                set: { if !$0 { importedChatPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) {
                if let item = importedChatPendingDeletion {
                    store.deleteImportedChat(item)
                }
                importedChatPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                importedChatPendingDeletion = nil
            }
        } message: {
            Text(
                "Este chat no forma parte de ninguna conversación. Se eliminará "
                    + "definitivamente de Chats importados."
            )
        }
        .confirmationDialog(
            store.storedCopyDetachmentPreview.map {
                UnifiedViewPresentation.detachmentTitle(
                    contributionCount: $0.impact.contributionCount
                )
            } ?? "¿Eliminar de la conversación?",
            isPresented: Binding(
                get: { store.storedCopyDetachmentPreview != nil },
                set: { if !$0 { store.dismissStoredCopyDetachmentPreview() } }
            ),
            titleVisibility: .visible
        ) {
            if let preview = store.storedCopyDetachmentPreview {
                Button("Eliminar de la conversación") {
                    store.detachStoredContribution(preview.selection)
                }
            }
            Button("Cancelar", role: .cancel) {
                store.dismissStoredCopyDetachmentPreview()
            }
        } message: {
            if let preview = store.storedCopyDetachmentPreview {
                Text(
                    UnifiedViewPresentation.detachmentMessage(
                        chatName: preview.chatName,
                        versionTitle: preview.versionTitle,
                        impact: preview.impact
                    )
                )
            }
        }
        .confirmationDialog(
            "¿Eliminar esta copia fuente?",
            isPresented: Binding(
                get: { versionPendingDeletion != nil },
                set: { if !$0 { versionPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar copia fuente", role: .destructive) {
                if let version = versionPendingDeletion {
                    store.deleteSourceBackup(versionID: version.id)
                }
                versionPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {
                versionPendingDeletion = nil
            }
        } message: {
            Text(
                "Se liberará el espacio ocupado por el backup. Las conversaciones ya guardadas "
                + "seguirán disponibles, pero no se podrán añadir otros chats de esta copia a la biblioteca."
            )
        }
        .confirmationDialog(
            store.unifiedViewAdditionPreview.map {
                UnifiedViewPresentation.additionTitle(
                    chatName: $0.chatName,
                    existingContributionCount: $0.existingContributionCount
                )
            } ?? "¿Crear una Vista unificada?",
            isPresented: Binding(
                get: { store.unifiedViewAdditionPreview != nil },
                set: { if !$0 { store.dismissUnifiedViewAdditionPreview() } }
            ),
            titleVisibility: .visible
        ) {
            if let preview = store.unifiedViewAdditionPreview {
                Button(
                    UnifiedViewPresentation.additionButtonTitle(
                        existingContributionCount: preview.existingContributionCount
                    )
                ) {
                    store.commitUnifiedViewAddition(id: preview.id)
                }
            }
            Button("Cancelar", role: .cancel) {
                store.dismissUnifiedViewAdditionPreview()
            }
        } message: {
            if let preview = store.unifiedViewAdditionPreview {
                Text(
                    UnifiedViewPresentation.additionMessage(
                        existingContributionCount: preview.existingContributionCount,
                        sourceMessageCount: preview.sourceMessageCount
                    )
                )
            }
        }
        .confirmationDialog(
            store.storedCopyDeletionPreview.map {
                UnifiedViewPresentation.deletionTitle(
                    contributionCount: $0.impact.contributionCount
                )
            } ?? "¿Borrar esta copia guardada?",
            isPresented: Binding(
                get: { store.storedCopyDeletionPreview != nil },
                set: { if !$0 { store.dismissStoredCopyDeletionPreview() } }
            ),
            titleVisibility: .visible
        ) {
            if let preview = store.storedCopyDeletionPreview {
                Button(
                    UnifiedViewPresentation.deletionButtonTitle(
                        contributionCount: preview.impact.contributionCount
                    ),
                    role: .destructive
                ) {
                    store.deleteStoredContribution(preview.selection)
                }
            }
            Button("Cancelar", role: .cancel) {
                store.dismissStoredCopyDeletionPreview()
            }
        } message: {
            if let preview = store.storedCopyDeletionPreview {
                Text(
                    UnifiedViewPresentation.deletionMessage(
                        chatName: preview.chatName,
                        versionTitle: preview.versionTitle,
                        impact: preview.impact
                    )
                )
            }
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            sidebarHeader
            sidebarList
        }
        .onChange(of: store.selectedChatID, perform: store.selectChat)
        .onChange(of: store.highlightedChatIDs, perform: updateExpandedVersions)
        .onChange(of: store.selectedConversationID, perform: updateImportedChatExpansion)
        .onChange(of: isImportedChatsExpanded, perform: collapseImportedChatDetails)
        .onChange(of: versionIDs, perform: updateExpandedVersionIDs)
        .onAppear(perform: initializeExpandedVersions)
    }

    private var sidebarList: some View {
        List(selection: $store.selectedChatID) {
            importedChatsSection
            backupVersionsSection
        }
        .listStyle(.sidebar)
        .disabled(store.operation != nil)
    }

    private var versionIDs: [String] {
        store.versions.map(\.id)
    }

    private func updateExpandedVersionIDs(_ ids: [String]) {
        expandedVersionIDs.formIntersection(Set(ids))
        if expandedVersionIDs.isEmpty, let first = ids.first {
            expandedVersionIDs.insert(first)
        }
    }

    private func updateExpandedVersions(_ chatIDs: Set<VersionChatID>) {
        expandedVersionIDs.formUnion(chatIDs.map(\.versionID))
    }

    private func updateImportedChatExpansion(_ conversationID: ConversationArchiveID?) {
        guard let conversationID,
              store.importedChats.contains(where: {
                  $0.isInConversation && $0.conversationID == conversationID
              }) else {
            return
        }
        isImportedChatsExpanded = true
    }

    private func collapseImportedChatDetails(_ isExpanded: Bool) {
        if isExpanded {
            expandedImportedChatID = nil
        }
    }

    private func initializeExpandedVersions() {
        if let first = store.versions.first?.id {
            expandedVersionIDs.insert(first)
        }
        expandedVersionIDs.formUnion(store.highlightedChatIDs.map(\.versionID))
    }

    private var importedChatsSection: some View {
        DisclosureGroup(isExpanded: $isImportedChatsExpanded) {
            if store.importedChats.isEmpty {
                Text("Todavía no hay chats importados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 27)
                    .padding(.vertical, 5)
            } else {
                ForEach(store.importedChats) { item in
                    importedChatSidebarRow(item)
                }
            }
        } label: {
            ImportedChatsGroupRow(
                count: store.importedChats.count,
                importChat: store.chooseAndImportChat
            )
        }
    }

    private var backupVersionsSection: some View {
        ForEach(store.versions) { version in
            DisclosureGroup(isExpanded: expansionBinding(for: version.id)) {
                backupVersionChats(version)
            } label: {
                BackupVersionRow(
                    version: version,
                    isStoring: store.storingChatID?.versionID == version.id,
                    isLoading: store.isLoadingSourceChats && version.hasSourceBackup
                ) {
                    versionPendingDeletion = version
                }
            }
        }
    }

    @ViewBuilder
    private func backupVersionChats(_ version: LibraryVersionSession) -> some View {
        let chats = store.visibleChats(in: version)
        if store.isLoadingSourceChats, chats.isEmpty, version.hasSourceBackup {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Leyendo conversaciones…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 27)
            .padding(.vertical, 5)
        } else if chats.isEmpty {
            Text(emptyMessage(for: version))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 27)
                .padding(.vertical, 5)
        } else {
            ForEach(chats, id: \.id) { chat in
                chatSidebarRow(chat, in: version)
            }
        }
    }

    private func requestAddition(_ selection: VersionChatID) {
        guard let state = store.storedChatStates[selection] else { return }
        guard case .updateAvailable = state else {
            if state.isExtracted {
                store.prepareUnifiedViewAddition(selection)
                return
            }
            store.addChatToLibrary(selection)
            return
        }
        store.prepareUnifiedViewAddition(selection)
    }

    private func importedChatSidebarRow(_ item: ImportedChatSidebarItem) -> some View {
        let isExpanded = expandedImportedChatID == item.id
        let isHighlighted = item.isInConversation
            && store.selectedConversationID == item.conversationID
        return ImportedChatSidebarRow(
            item: item,
            isExpanded: isExpanded,
            isHighlighted: isHighlighted,
            detailsState: store.importedChatDetails[item.id],
            toggleExpansion: {
                if isExpanded {
                    expandedImportedChatID = nil
                } else {
                    expandedImportedChatID = item.id
                    store.loadImportedChatDetails(item)
                }
            },
            reveal: { store.revealImportedChat(item) },
            addToConversation: { store.incorporateImportedChat(item) },
            detachFromConversation: { importedChatPendingDetachment = item },
            delete: { importedChatPendingDeletion = item }
        )
        .listRowBackground(importedChatRowBackground(
            isExpanded: isExpanded,
            isHighlighted: isHighlighted
        ))
    }

    @ViewBuilder
    private func importedChatRowBackground(
        isExpanded: Bool,
        isHighlighted: Bool
    ) -> some View {
        if isExpanded {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                .padding(.horizontal, 2)
        } else if isHighlighted {
            Color.accentColor.opacity(0.14)
        } else {
            Color.clear
        }
    }

    private func chatSidebarRow(
        _ chat: ChatInfo,
        in version: LibraryVersionSession
    ) -> some View {
        let selection = VersionChatID(versionID: version.id, chatID: chat.id)
        let isHighlighted = store.highlightedChatIDs.contains(selection)
        return ChatSidebarRow(
            chat: chat,
            photoURL: store.profilePhotoURL(for: chat, in: version),
            isExpanded: store.selectedChatID == selection,
            isHighlighted: isHighlighted,
            detailsState: store.chatDetails[selection],
            storedChatState: store.storedChatStates[selection] ?? .checking,
            contributedMessageCount: store.contributedMessageCount(for: selection),
            isInConversation: store.isStoredChatInConversation(selection),
            additionTargetsUnifiedView: store.additionTargetsUnifiedView(selection),
            isStoring: store.storingChatID == selection,
            canAddToLibrary: version.hasSourceBackup,
            toggleExpansion: {
                store.selectedChatID = store.selectedChatID == selection ? nil : selection
            },
            addToLibrary: { requestAddition(selection) },
            refreshStoredChat: { store.refreshStoredChat(selection) },
            revealStoredChat: { store.revealStoredChat(selection) },
            detachStoredChat: { store.prepareStoredCopyDetachment(selection) },
            deleteStoredChat: { store.prepareStoredCopyDeletion(selection) }
        )
        .tag(selection)
        .listRowBackground(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Biblioteca")
                        .font(.title2.bold())
                    Text(
                        "\(store.importedChats.count) chats importados · "
                            + "\(store.versions.count) copias de WhatsApp"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                libraryActions
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Importa chats o despliega una copia para navegar")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 4)

                Menu {
                    Picker("Ordenar chats", selection: $store.chatSortOrder) {
                        ForEach(ChatListSortOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                } label: {
                    Label("Ordenar chats", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Ordenar chats: \(store.chatSortOrder.title)")

                Picker("Filtro", selection: $store.chatFilter) {
                    ForEach(ChatListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 105)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var libraryActions: some View {
        HStack(spacing: 6) {
            Button {
                store.showBackupImporter()
            } label: {
                Label("Añadir copia…", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Añadir otra copia de WhatsApp a esta biblioteca")
            .disabled(store.operation != nil)

            Menu {
                Button("Volver a leer la biblioteca") {
                    store.reloadLibrary()
                }
                Divider()
                Button("Abrir biblioteca en Finder") {
                    store.revealLibrary()
                }
                Button("Abrir otra biblioteca…") {
                    if let url = DirectoryPicker.chooseExistingLibrary(
                        startingAt: store.session?.paths.rootURL.path
                    ) {
                        store.openLibrary(at: url)
                    }
                }
                Button("Cerrar biblioteca") {
                    store.closeLibrary()
                }
            } label: {
                Label("Opciones de la biblioteca", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Opciones de la biblioteca")
            .disabled(store.operation != nil)
        }
        .controlSize(.regular)
    }

    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedVersionIDs.contains(id) },
            set: { expanded in
                if expanded {
                    expandedVersionIDs.insert(id)
                } else {
                    expandedVersionIDs.remove(id)
                }
            }
        )
    }

    private func emptyMessage(for version: LibraryVersionSession) -> String {
        version.hasSourceBackup ? "No hay chats con este filtro" : "No quedaron chats guardados"
    }
}

private struct ImportedChatsGroupRow: View {
    let count: Int
    let importChat: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(.secondary)
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 2) {
                Text("Chats importados")
                    .fontWeight(.medium)
                Text(countDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: importChat) {
                Label("Importar chat…", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Importar un archivo .fmcchat y buscar su conversación en la biblioteca")
        }
        .padding(.vertical, 3)
    }

    private var countDescription: String {
        switch count {
        case 0: return "Ningún chat importado"
        case 1: return "1 chat importado"
        default: return "\(count) chats importados"
        }
    }
}

private struct ImportedChatSidebarRow: View {
    let item: ImportedChatSidebarItem
    let isExpanded: Bool
    let isHighlighted: Bool
    let detailsState: ImportedChatDetailsState?
    let toggleExpansion: () -> Void
    let reveal: () -> Void
    let addToConversation: () -> Void
    let detachFromConversation: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleExpansion) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(.quaternary)
                        Image(systemName: "arrow.down.message")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.contribution.displayName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(
                            [
                                "Chat importado",
                                item.contribution.messageCount.map { "\($0.formatted()) mensajes" }
                            ]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Cerrar detalles del chat importado" : "Mostrar detalles del chat importado")

            if isExpanded {
                expandedDetails
                    .padding(.leading, 48)
                    .padding(.top, 8)
            }
        }
        .padding(.leading, 18)
        .padding(.vertical, isExpanded ? 7 : 3)
        .overlay(alignment: .leading) {
            if isHighlighted {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isHighlighted)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggleExpansion) {
                VStack(alignment: .leading, spacing: 6) {
                    detailLine(
                        "Mensajes",
                        value: item.contribution.messageCount?.formatted() ?? "No disponible"
                    )
                    detailLine(
                        "Importado",
                        value: Self.dateFormatter.string(from: item.contribution.importedAt)
                    )
                    detailLine("Primero", value: firstMessageDescription)
                    detailLine("Último", value: lastMessageDescription)
                    if !item.isInConversation {
                        Text("No está en ninguna conversación")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let messageCount = item.contribution.exclusiveMessageCount {
                        Text(
                            UnifiedViewPresentation.contributionDescription(
                                messageCount: messageCount
                            )
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cerrar detalles del chat importado")
            .accessibilityLabel("Cerrar detalles del chat importado")

            VStack(alignment: .leading, spacing: 6) {
                actionButton("Abrir carpeta", systemImage: "folder", action: reveal)
                    .help("Abrir la carpeta del chat importado en Finder")
                if item.isInConversation {
                    actionButton(
                        "Eliminar de la conversación",
                        systemImage: "arrow.right",
                        action: detachFromConversation
                    )
                    .help("Retirar este chat importado y conservarlo en Chats importados")
                } else {
                    actionButton(
                        "Añadir a la conversación",
                        systemImage: "plus",
                        action: addToConversation
                    )
                    .help("Volver a incorporar este chat importado a su conversación")
                    actionButton("Borrar", systemImage: "trash", tint: .red, action: delete)
                        .help("Borrar definitivamente este chat importado")
                }
            }
        }
        .font(.caption)
    }

    private func detailLine(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .lineLimit(1)
        }
    }

    private var firstMessageDescription: String {
        switch detailsState {
        case .loading:
            return "Calculando…"
        case .loaded(let firstMessageDate, _):
            return firstMessageDate.map(Self.dateFormatter.string) ?? "Sin mensajes"
        case .failed:
            return "No disponible"
        case nil:
            return "—"
        }
    }

    private var lastMessageDescription: String {
        switch detailsState {
        case .loading:
            return "Calculando…"
        case .loaded(_, let lastMessageDate):
            return lastMessageDate.map(Self.dateFormatter.string) ?? "Sin mensajes"
        case .failed:
            return "No disponible"
        case nil:
            return "—"
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = Color.accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct BackupVersionRow: View {
    let version: LibraryVersionSession
    let isStoring: Bool
    let isLoading: Bool
    let deleteSource: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if isStoring {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 17)
            } else {
                Image(systemName: version.hasSourceBackup ? "externaldrive.fill" : "externaldrive.badge.xmark")
                    .foregroundStyle(version.hasSourceBackup ? Color.secondary : Color.orange)
                    .frame(width: 17)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(version.record.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if version.hasSourceBackup {
                Menu {
                    Button("Eliminar copia fuente…", role: .destructive, action: deleteSource)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Gestionar copia")
            }
        }
        .padding(.vertical, 3)
    }

    private var detail: String {
        if isLoading {
            return "Leyendo conversaciones…"
        }
        if version.hasSourceBackup {
            let size = ByteCountFormatter.string(
                fromByteCount: version.backupByteCount,
                countStyle: .file
            )
            return "\(size) · \(version.chats.count) chats"
        }
        return "Copia eliminada · \(version.chats.count) guardados"
    }
}

private struct ChatSidebarRow: View {
    let chat: ChatInfo
    let photoURL: URL?
    let isExpanded: Bool
    let isHighlighted: Bool
    let detailsState: ChatDetailsState?
    let storedChatState: StoredChatDisplayState
    let contributedMessageCount: Int?
    let isInConversation: Bool
    let additionTargetsUnifiedView: Bool
    let isStoring: Bool
    let canAddToLibrary: Bool
    let toggleExpansion: () -> Void
    let addToLibrary: () -> Void
    let refreshStoredChat: () -> Void
    let revealStoredChat: () -> Void
    let detachStoredChat: () -> Void
    let deleteStoredChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleExpansion) {
                HStack(spacing: 10) {
                    LocalImageAvatar(photoURL: photoURL, name: chat.name, size: 38)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(chat.name)
                                .fontWeight(.medium)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(sizeDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 4) {
                            Text(summary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Self.shortDateFormatter.string(from: chat.lastMessageDate))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Cerrar detalles del chat" : "Mostrar detalles del chat")

            if isExpanded {
                expandedDetails
                    .padding(.leading, 48)
                    .padding(.top, 8)
            }
        }
        .padding(.leading, 18)
        .padding(.vertical, isExpanded ? 7 : 3)
        .overlay(alignment: .leading) {
            if isHighlighted {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isHighlighted)
    }

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggleExpansion) {
                VStack(alignment: .leading, spacing: 6) {
                    detailLine("Mensajes", value: chat.numberMessages.formatted())
                    detailLine("Tamaño", value: sizeDescription)
                    detailLine("Primero", value: firstMessageDescription)
                    detailLine(
                        "Último",
                        value: Self.detailDateFormatter.string(from: chat.lastMessageDate)
                    )
                    if let contributedMessageCount {
                        Text(
                            UnifiedViewPresentation.contributionDescription(
                                messageCount: contributedMessageCount
                            )
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cerrar detalles del chat")
            .accessibilityLabel("Cerrar detalles del chat")

            HStack {
                storedChatStatus
                Spacer(minLength: 8)
            }
            .padding(.top, 3)

            if storedChatState.isPhysicallyStored, !isStoring {
                VStack(alignment: .leading, spacing: 6) {
                    actionButton(
                        "Abrir carpeta",
                        systemImage: "folder",
                        action: revealStoredChat
                    )
                    .help("Abrir la copia guardada de este chat en Finder")
                    if isInConversation {
                        actionButton(
                            "Eliminar de la conversación",
                            systemImage: "arrow.right",
                            action: detachStoredChat
                        )
                        .help(
                            "Retirar esta copia de la conversación y conservar el chat "
                                + "extraído en su copia de WhatsApp"
                        )
                    }
                    if !isInConversation {
                        actionButton(
                            "Borrar",
                            systemImage: "trash",
                            tint: .red,
                            action: deleteStoredChat
                        )
                        .help("Borrar esta copia guardada de la biblioteca")
                    }
                }
            }

        }
        .font(.caption)
    }

    private func detailLine(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var storedChatStatus: some View {
        if isStoring {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Añadiendo a la biblioteca…")
                    .foregroundStyle(.secondary)
            }
        } else {
            storedChatStateView
        }
    }

    @ViewBuilder
    private var storedChatStateView: some View {
        switch storedChatState {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Comprobando la biblioteca…")
                    .foregroundStyle(.secondary)
            }
        case .notStored:
            if canAddToLibrary {
                actionButton(
                    UnifiedViewPresentation.additionActionTitle(
                        addsToExistingConversation: false
                    ),
                    action: addToLibrary
                )
                .help("Guardar esta conversación con sus mensajes y archivos en la biblioteca")
            } else {
                Label("Copia fuente no disponible", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        case .updateAvailable:
            if canAddToLibrary {
                actionButton(
                    UnifiedViewPresentation.additionActionTitle(
                        addsToExistingConversation: additionTargetsUnifiedView
                    ),
                    systemImage: "plus",
                    action: addToLibrary
                )
                .help("Guardar esta copia del chat y añadir sus mensajes a una Vista unificada")
            } else {
                Label("Guardado · fuente no disponible", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            }
        case .extracted:
            actionButton(
                "Añadir a la conversación",
                systemImage: "plus",
                action: addToLibrary
            )
            .help(
                "Incorporar los mensajes de esta copia ya extraída a la Vista unificada"
            )
        case .stored:
            Label("En la biblioteca", systemImage: "checkmark")
                .foregroundStyle(.secondary)
        case .stale:
            if canAddToLibrary {
                actionButton(
                    "Actualizar en la biblioteca",
                    systemImage: "arrow.clockwise",
                    action: refreshStoredChat
                )
                .help("Actualizar la copia guardada y la conversación de la biblioteca")
            } else {
                Label("En la biblioteca · fuente no disponible", systemImage: "checkmark")
                    .foregroundStyle(.secondary)
            }
        case .invalid:
            if canAddToLibrary {
                actionButton(
                    "Reparar en la biblioteca",
                    systemImage: "arrow.clockwise",
                    action: refreshStoredChat
                )
                .help("Reemplazar la copia no válida y actualizar la conversación guardada")
            } else {
                Label("Copia guardada no válida", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = Color.accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption2.weight(.semibold))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.22), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private var summary: String {
        var parts = [ConversationPresentation.cellTypeLabel(chatType: chat.chatType)]
        if chat.isArchived { parts.append("Archivado") }
        return parts.joined(separator: " · ")
    }

    private var sizeDescription: String {
        guard chat.mediaByteCount > 0 else { return "0 GB" }
        return Self.gigabyteFormatter.string(fromByteCount: chat.mediaByteCount)
    }

    private var firstMessageDescription: String {
        switch detailsState {
        case .loading:
            return "Calculando…"
        case .loaded(let date):
            return date.map(Self.detailDateFormatter.string) ?? "Sin mensajes"
        case .failed:
            return "No disponible"
        case nil:
            return "—"
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let gigabyteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .decimal
        formatter.isAdaptive = false
        return formatter
    }()
}
