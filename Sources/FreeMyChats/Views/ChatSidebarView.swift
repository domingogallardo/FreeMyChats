import AppKit
import SwiftUI
import SwiftWABackupAPI

private enum SidebarChatLocation: Hashable {
    case sourceBackup(VersionChatID)
    case extracted(VersionChatID)

    var selection: VersionChatID {
        switch self {
        case .sourceBackup(let selection), .extracted(let selection):
            return selection
        }
    }
}

private enum ChatSidebarRowContext: Equatable {
    case sourceBackup
    case extracted
}

private enum SidebarContributionHighlight: Equatable {
    case none
    case contributing
    case redundant

    var color: Color? {
        switch self {
        case .none: return nil
        case .contributing: return .accentColor
        case .redundant: return Color(nsColor: .systemGray)
        }
    }
}

private enum SidebarScrollTarget: Hashable {
    case top
}

struct ChatSidebarView: View {
    @ObservedObject var store: FreeMyChatsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedVersionIDs: Set<String> = []
    @State private var expandedSourceVersionIDs: Set<String> = []
    @State private var expandedExtractedVersionIDs: Set<String> = []
    @State private var selectedChatLocation: SidebarChatLocation?
    @State private var isImportedChatsExpanded = false
    @State private var expandedImportedChatID: String?
    @State private var versionPendingDeletion: LibraryVersionSession?
    @State private var importedChatPendingDetachment: ImportedChatSidebarItem?
    @State private var importedChatPendingDeletion: ImportedChatSidebarItem?
    @State private var recentExtraction: ChatExtractionCompletion?

    var body: some View {
        storedCopyDeletionDialog
    }

    private var importedChatDetachmentDialog: some View {
        sidebarContent
        .confirmationDialog(
            UnifiedViewPresentation.catalogRemovalConfirmationTitle,
            isPresented: Binding(
                get: { importedChatPendingDetachment != nil },
                set: { if !$0 { importedChatPendingDetachment = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(UnifiedViewPresentation.catalogRemovalActionTitle) {
                if let item = importedChatPendingDetachment {
                    store.detachImportedChat(item)
                }
                importedChatPendingDetachment = nil
            }
            Button("Cancelar", role: .cancel) {
                importedChatPendingDetachment = nil
            }
        } message: {
            if let item = importedChatPendingDetachment,
               store.contributionCount(containing: item) == 1 {
                Text(
                    UnifiedViewPresentation.standaloneDetachmentMessage(
                        chatName: item.conversationName
                    )
                )
            } else {
                Text(
                    "El chat importado se conservará en la columna izquierda, dejará de aportar "
                        + "mensajes a la conversación y podrás volver a incorporarlo con "
                        + "“Añadir al catálogo”."
                )
            }
        }
    }

    private var importedChatDeletionDialog: some View {
        importedChatDetachmentDialog
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
    }

    private var storedCopyDetachmentDialog: some View {
        importedChatDeletionDialog
        .confirmationDialog(
            store.storedCopyDetachmentPreview.map {
                UnifiedViewPresentation.detachmentTitle(
                    contributionCount: $0.impact.contributionCount
                )
            } ?? UnifiedViewPresentation.catalogRemovalConfirmationTitle,
            isPresented: Binding(
                get: { store.storedCopyDetachmentPreview != nil },
                set: { if !$0 { store.dismissStoredCopyDetachmentPreview() } }
            ),
            titleVisibility: .visible
        ) {
            if let preview = store.storedCopyDetachmentPreview {
                Button(UnifiedViewPresentation.catalogRemovalActionTitle) {
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
    }

    private var sourceBackupDeletionDialog: some View {
        storedCopyDetachmentDialog
        .confirmationDialog(
            "¿Eliminar esta copia de WhatsApp?",
            isPresented: Binding(
                get: { versionPendingDeletion != nil },
                set: { if !$0 { versionPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar copia de WhatsApp", role: .destructive) {
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
                "Se eliminará la copia completa de WhatsApp. Los chats ya extraídos seguirán "
                    + "disponibles, pero no podrás extraer otros chats de esta copia."
            )
        }
    }

    private var unifiedViewAdditionDialog: some View {
        sourceBackupDeletionDialog
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
                        existingContributionCount: preview.existingContributionCount,
                        requiresExtraction: preview.requiresExtraction
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
                        sourceMessageCount: preview.sourceMessageCount,
                        requiresExtraction: preview.requiresExtraction
                    )
                )
            }
        }
    }

    private var storedCopyDeletionDialog: some View {
        unifiedViewAdditionDialog
        .confirmationDialog(
            store.storedCopyDeletionPreview.map {
                UnifiedViewPresentation.deletionTitle(
                    contributionCount: $0.impact.contributionCount,
                    hasSourceBackup: $0.hasSourceBackup
                )
            } ?? "¿Borrar este chat guardado?",
            isPresented: Binding(
                get: { store.storedCopyDeletionPreview != nil },
                set: { if !$0 { store.dismissStoredCopyDeletionPreview() } }
            ),
            titleVisibility: .visible
        ) {
            if let preview = store.storedCopyDeletionPreview {
                Button(
                    UnifiedViewPresentation.deletionButtonTitle(
                        contributionCount: preview.impact.contributionCount,
                        hasSourceBackup: preview.hasSourceBackup
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
                        hasSourceBackup: preview.hasSourceBackup,
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
        .onChange(of: selectedChatLocation, perform: selectChatLocation)
        .onChange(of: store.selectedChatID, perform: selectedChatDidChange)
        .onChange(of: store.highlightedChatIDs, perform: updateConversationExpansion)
        .onChange(of: store.selectedConversationID, perform: updateConversationExpansion)
        .onChange(of: isImportedChatsExpanded, perform: collapseImportedChatDetails)
        .onChange(of: versionIDs, perform: updateExpandedVersionIDs)
        .onChange(of: store.latestExtractionCompletion, perform: showExtractionCompletion)
        .onAppear(perform: initializeExpandedVersions)
    }

    private func showExtractionCompletion(_ completion: ChatExtractionCompletion?) {
        guard let completion else { return }
        let versionID = completion.selection.versionID

        withAnimation(extractionClosingAnimation) {
            expandedSourceVersionIDs.remove(versionID)
        }

        let openingDelay = reduceMotion ? 0 : 0.22
        DispatchQueue.main.asyncAfter(deadline: .now() + openingDelay) {
            guard store.latestExtractionCompletion?.id == completion.id else { return }
            withAnimation(extractionAnimation) {
                expandedVersionIDs.insert(versionID)
                expandedExtractedVersionIDs.insert(versionID)
                recentExtraction = completion
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                guard recentExtraction?.id == completion.id else { return }
                withAnimation(extractionAnimation) {
                    recentExtraction = nil
                }
            }
        }
    }

    private var extractionClosingAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .easeInOut(duration: 0.24)
    }

    private var extractionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.46, dampingFraction: 0.78)
    }

    private var sidebarList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedChatLocation) {
                importedChatsSection
                    .id(SidebarScrollTarget.top)
                backupVersionsSection
            }
            .listStyle(.sidebar)
            .disabled(store.operation != nil)
            .onChange(of: store.selectedConversationID) { _ in
                scrollSidebarToTop(using: proxy)
            }
        }
    }

    private func scrollSidebarToTop(using proxy: ScrollViewProxy) {
        // Wait until disclosure groups have adopted their new expansion state.
        DispatchQueue.main.async {
            if reduceMotion {
                proxy.scrollTo(SidebarScrollTarget.top, anchor: .top)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(SidebarScrollTarget.top, anchor: .top)
                }
            }
        }
    }

    private var versionIDs: [String] {
        store.versions.map(\.id)
    }

    private func updateExpandedVersionIDs(_ ids: [String]) {
        expandedVersionIDs.formIntersection(Set(ids))
        expandedSourceVersionIDs.formIntersection(Set(ids))
        expandedExtractedVersionIDs.formIntersection(Set(ids))
        if expandedVersionIDs.isEmpty, let first = ids.first {
            expandedVersionIDs.insert(first)
            expandedExtractedVersionIDs.insert(first)
        }
    }

    private func updateConversationExpansion(_ chatIDs: Set<VersionChatID>) {
        guard let conversationID = store.selectedConversationID else { return }
        focusSidebar(on: conversationID, highlightedChatIDs: chatIDs)
    }

    private func updateConversationExpansion(_ conversationID: ConversationArchiveID?) {
        guard let conversationID else {
            collapseAllSidebarLevels()
            return
        }
        focusSidebar(on: conversationID, highlightedChatIDs: store.highlightedChatIDs)
    }

    private func focusSidebar(
        on conversationID: ConversationArchiveID,
        highlightedChatIDs: Set<VersionChatID>
    ) {
        // Highlighted IDs contain every stored contribution, including the gray
        // contributions that add zero exclusive messages to the unified view.
        let contributingVersionIDs = Set(highlightedChatIDs.map(\.versionID))
        expandedVersionIDs = contributingVersionIDs
        expandedSourceVersionIDs = []
        expandedExtractedVersionIDs = contributingVersionIDs
        isImportedChatsExpanded = store.importedChats.contains {
            $0.isInConversation && $0.conversationID == conversationID
        }
        collapseExpandedChatDetails()
    }

    private func collapseAllSidebarLevels() {
        expandedVersionIDs = []
        expandedSourceVersionIDs = []
        expandedExtractedVersionIDs = []
        isImportedChatsExpanded = false
        collapseExpandedChatDetails()
    }

    private func collapseExpandedChatDetails() {
        selectedChatLocation = nil
        expandedImportedChatID = nil
    }

    private func collapseImportedChatDetails(_ isExpanded: Bool) {
        if isExpanded {
            expandedImportedChatID = nil
        }
    }

    private func initializeExpandedVersions() {
        if let first = store.versions.first?.id {
            expandedVersionIDs.insert(first)
            expandedExtractedVersionIDs.insert(first)
        }
        expandedVersionIDs.formUnion(store.highlightedChatIDs.map(\.versionID))
        expandedExtractedVersionIDs.formUnion(store.highlightedChatIDs.map(\.versionID))
    }

    private func selectChatLocation(_ location: SidebarChatLocation?) {
        store.selectedChatID = location?.selection
    }

    private func selectedChatDidChange(_ selection: VersionChatID?) {
        store.selectChat(selection)
        if selection == nil {
            selectedChatLocation = nil
        }
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
                backupVersionContents(version)
            } label: {
                BackupVersionRow(
                    version: version,
                    extractedChatCount: extractedChatCount(in: version)
                )
            }
        }
    }

    @ViewBuilder
    private func backupVersionContents(_ version: LibraryVersionSession) -> some View {
        if version.hasSourceBackup {
            DisclosureGroup(isExpanded: sourceExpansionBinding(for: version.id)) {
                sourceBackupChats(version)
            } label: {
                SourceBackupGroupRow(
                    version: version,
                    isLoading: store.isLoadingSourceChats
                        && store.storingChatID?.versionID != version.id
                ) {
                    versionPendingDeletion = version
                }
            }
        }

        DisclosureGroup(isExpanded: extractedExpansionBinding(for: version.id)) {
            extractedChats(version)
        } label: {
            ExtractedChatsGroupRow(
                count: extractedChatCount(in: version),
                isStoring: store.storingChatID?.versionID == version.id
            )
        }
    }

    @ViewBuilder
    private func sourceBackupChats(_ version: LibraryVersionSession) -> some View {
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
            Text("No hay chats en la copia con este filtro")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 27)
                .padding(.vertical, 5)
        } else {
            ForEach(chats, id: \.id) { chat in
                chatSidebarRow(chat, in: version, context: .sourceBackup)
            }
        }
    }

    @ViewBuilder
    private func extractedChats(_ version: LibraryVersionSession) -> some View {
        let chats = store.visibleChats(in: version).filter {
            isExtracted($0, in: version)
        }
        if chats.isEmpty {
            Text(extractedChatsEmptyMessage(in: version))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 27)
                .padding(.vertical, 5)
        } else {
            ForEach(chats, id: \.id) { chat in
                chatSidebarRow(chat, in: version, context: .extracted)
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
        let highlight: SidebarContributionHighlight = if isHighlighted {
            store.contributedMessageCount(for: item) == 0 ? .redundant : .contributing
        } else {
            .none
        }
        return ImportedChatSidebarRow(
            item: item,
            isExpanded: isExpanded,
            highlight: highlight,
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
            highlight: highlight
        ))
    }

    @ViewBuilder
    private func importedChatRowBackground(
        isExpanded: Bool,
        highlight: SidebarContributionHighlight
    ) -> some View {
        if isExpanded {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                .padding(.horizontal, 2)
        } else if let color = highlight.color {
            color.opacity(0.14)
        } else {
            Color.clear
        }
    }

    private func chatSidebarRow(
        _ chat: ChatInfo,
        in version: LibraryVersionSession,
        context: ChatSidebarRowContext
    ) -> some View {
        let selection = VersionChatID(versionID: version.id, chatID: chat.id)
        let location: SidebarChatLocation = context == .sourceBackup
            ? .sourceBackup(selection)
            : .extracted(selection)
        let isExtractedContext = context == .extracted
        let isRecentlyExtracted = isExtractedContext
            && recentExtraction?.selection == selection
        let isHighlighted = isExtractedContext && store.highlightedChatIDs.contains(selection)
        let contributedMessageCount = isExtractedContext
            && store.isStoredChatInConversation(selection)
            ? store.contributedMessageCount(for: selection)
            : nil
        let highlight: SidebarContributionHighlight = if isHighlighted {
            contributedMessageCount == 0 ? .redundant : .contributing
        } else {
            .none
        }
        return ChatSidebarRow(
            chat: chat,
            photoURL: store.profilePhotoURL(for: chat, in: version),
            context: context,
            isExpanded: selectedChatLocation == location,
            highlight: highlight,
            detailsState: store.chatDetails[selection],
            storedChatState: store.storedChatStates[selection] ?? .checking,
            contributedMessageCount: contributedMessageCount,
            isInConversation: store.isStoredChatInConversation(selection),
            additionTargetsUnifiedView: store.additionTargetsUnifiedView(selection),
            isStoring: store.storingChatID == selection,
            isRecentlyExtracted: isRecentlyExtracted,
            hasSourceBackup: version.hasSourceBackup,
            toggleExpansion: {
                selectedChatLocation = selectedChatLocation == location ? nil : location
            },
            addToLibrary: { requestAddition(selection) },
            revealStoredChat: { store.revealStoredChat(selection) },
            detachStoredChat: { store.prepareStoredCopyDetachment(selection) },
            deleteStoredChat: { store.prepareStoredCopyDeletion(selection) }
        )
        .tag(location)
        .listRowBackground(
            chatRowBackground(
                highlight: highlight,
                isNewEntry: isExtractedContext && isRecentlyExtracted
            )
        )
        .transition(
            isExtractedContext && !reduceMotion
                ? .move(edge: .top).combined(with: .opacity)
                : .opacity
        )
    }

    @ViewBuilder
    private func chatRowBackground(
        highlight: SidebarContributionHighlight,
        isNewEntry: Bool
    ) -> some View {
        if isNewEntry {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
                }
                .padding(.horizontal, 2)
        } else if let color = highlight.color {
            color.opacity(0.14)
        } else {
            Color.clear
        }
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
                Text("Despliega una copia para explorarla o ver sus chats extraídos")
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
                    expandedExtractedVersionIDs.insert(id)
                } else {
                    expandedVersionIDs.remove(id)
                    expandedExtractedVersionIDs.remove(id)
                }
            }
        )
    }

    private func sourceExpansionBinding(for id: String) -> Binding<Bool> {
        expansionBinding(for: id, in: $expandedSourceVersionIDs)
    }

    private func extractedExpansionBinding(for id: String) -> Binding<Bool> {
        expansionBinding(for: id, in: $expandedExtractedVersionIDs)
    }

    private func expansionBinding(
        for id: String,
        in expandedIDs: Binding<Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: { expandedIDs.wrappedValue.contains(id) },
            set: { expanded in
                if expanded {
                    expandedIDs.wrappedValue.insert(id)
                } else {
                    expandedIDs.wrappedValue.remove(id)
                }
            }
        )
    }

    private func isExtracted(_ chat: ChatInfo, in version: LibraryVersionSession) -> Bool {
        let selection = VersionChatID(versionID: version.id, chatID: chat.id)
        return store.storedChatStates[selection]?.isPhysicallyStored == true
    }

    private func extractedChatCount(in version: LibraryVersionSession) -> Int {
        version.chats.filter { isExtracted($0, in: version) }.count
    }

    private func extractedChatsEmptyMessage(in version: LibraryVersionSession) -> String {
        if extractedChatCount(in: version) == 0 {
            return "Todavía no hay chats extraídos"
        }
        return "No hay chats extraídos con este filtro"
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
    let highlight: SidebarContributionHighlight
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
            if let color = highlight.color {
                Capsule()
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: highlight)
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
                    } else if let messageCount = item.contribution.contributedMessageCount
                        ?? item.contribution.exclusiveMessageCount {
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
                        UnifiedViewPresentation.catalogRemovalActionTitle,
                        systemImage: "minus",
                        action: detachFromConversation
                    )
                    .help(UnifiedViewPresentation.catalogRemovalActionTitle)
                } else {
                    actionButton(
                        UnifiedViewPresentation.catalogAdditionActionTitle,
                        systemImage: "plus",
                        action: addToConversation
                    )
                    .help("Volver a añadir este chat importado al catálogo")
                    actionButton(
                        "Borrar",
                        systemImage: "trash",
                        tint: .red,
                        action: delete
                    )
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
    let extractedChatCount: Int

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 2) {
                Text(version.record.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var summary: String {
        let source = version.hasSourceBackup ? "Copia disponible" : "Copia eliminada"
        let extracted = extractedChatCount == 1
            ? "1 chat extraído"
            : "\(extractedChatCount) chats extraídos"
        return "\(source) · \(extracted)"
    }
}

private struct SourceBackupGroupRow: View {
    let version: LibraryVersionSession
    let isLoading: Bool
    let deleteSource: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 17)
            } else {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 17)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Copia de WhatsApp")
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                Button("Eliminar copia de WhatsApp…", role: .destructive, action: deleteSource)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Gestionar la copia de WhatsApp")
        }
        .padding(.vertical, 3)
    }

    private var detail: String {
        if isLoading {
            return "Leyendo chats…"
        }
        let size = ByteCountFormatter.string(
            fromByteCount: version.backupByteCount,
            countStyle: .file
        )
        let chats = version.chats.count == 1 ? "1 chat" : "\(version.chats.count) chats"
        return "\(size) · \(chats)"
    }
}

private struct ExtractedChatsGroupRow: View {
    let count: Int
    let isStoring: Bool

    var body: some View {
        HStack(spacing: 9) {
            if isStoring {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 17)
            } else {
                Image(systemName: "archivebox.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 17)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Chats extraídos")
                    .fontWeight(.medium)
                Text(count == 1 ? "1 chat extraído" : "\(count) chats extraídos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ChatSidebarRow: View {
    let chat: ChatInfo
    let photoURL: URL?
    let context: ChatSidebarRowContext
    let isExpanded: Bool
    let highlight: SidebarContributionHighlight
    let detailsState: ChatDetailsState?
    let storedChatState: StoredChatDisplayState
    let contributedMessageCount: Int?
    let isInConversation: Bool
    let additionTargetsUnifiedView: Bool
    let isStoring: Bool
    let isRecentlyExtracted: Bool
    let hasSourceBackup: Bool
    let toggleExpansion: () -> Void
    let addToLibrary: () -> Void
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

                            if context == .extracted, isRecentlyExtracted {
                                Label("Nuevo", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Text(sizeDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
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
            if let color = highlight.color {
                Capsule()
                    .fill(color)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: highlight)
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

            if context == .extracted, storedChatState.isPhysicallyStored, !isStoring {
                VStack(alignment: .leading, spacing: 6) {
                    actionButton(
                        "Abrir carpeta",
                        systemImage: "folder",
                        action: revealStoredChat
                    )
                    .help("Abrir este chat guardado en Finder")
                    if isInConversation {
                        actionButton(
                            UnifiedViewPresentation.catalogRemovalActionTitle,
                            systemImage: "minus",
                            action: detachStoredChat
                        )
                        .help(UnifiedViewPresentation.catalogRemovalActionTitle)
                    }
                    if !isInConversation {
                        actionButton(
                            UnifiedViewPresentation.deletionButtonTitle(
                                contributionCount: 0,
                                hasSourceBackup: hasSourceBackup
                            ),
                            systemImage: "trash",
                            tint: .red,
                            action: deleteStoredChat
                        )
                        .help("Borrar este chat guardado de la biblioteca")
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
                Text(
                    context == .sourceBackup
                        ? "Extrayendo y añadiendo al catálogo…"
                        : "Añadiendo al catálogo…"
                )
                    .foregroundStyle(.secondary)
            }
        } else {
            if context == .sourceBackup {
                sourceBackupStateView
            } else {
                extractedChatStateView
            }
        }
    }

    @ViewBuilder
    private var sourceBackupStateView: some View {
        switch storedChatState {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Comprobando si está extraído…")
                    .foregroundStyle(.secondary)
            }
        case .notStored:
            actionButton(
                "Extraer y añadir al catálogo",
                systemImage: "plus",
                action: addToLibrary
            )
            .help("Extraer los mensajes y archivos de este chat y añadirlo al catálogo")
        case .updateAvailable:
            actionButton(
                "Extraer y añadir al catálogo",
                systemImage: "plus",
                action: addToLibrary
            )
            .help(
                additionTargetsUnifiedView
                    ? "Extraer este chat y añadirlo a la Vista unificada"
                    : "Extraer este chat y añadirlo al catálogo"
            )
        case .extracted:
            Label("Extraído · fuera del catálogo", systemImage: "archivebox")
                .foregroundStyle(.secondary)
        case .stored:
            Label("Extraído · en el catálogo", systemImage: "checkmark")
                .foregroundStyle(.secondary)
        case .stale:
            Label(
                "El chat extraído no coincide con esta copia",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        case .invalid:
            Label("Chat extraído no válido", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var extractedChatStateView: some View {
        switch storedChatState {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Comprobando el chat extraído…")
                    .foregroundStyle(.secondary)
            }
        case .notStored, .updateAvailable:
            Label("El chat extraído ya no está disponible", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        case .extracted:
            actionButton(
                UnifiedViewPresentation.catalogAdditionActionTitle,
                systemImage: "plus",
                action: addToLibrary
            )
            .help("Añadir este chat extraído al catálogo")
        case .stored:
            Label("En el catálogo", systemImage: "checkmark")
                .foregroundStyle(.secondary)
        case .stale:
            Label(
                "El chat extraído no coincide con la copia",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
        case .invalid:
            Label("Chat extraído no válido", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
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
