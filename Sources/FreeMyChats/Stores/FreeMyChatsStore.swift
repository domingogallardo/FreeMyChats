import Foundation
@preconcurrency import SwiftWABackupAPI

private let appProgressUpdateCoalescer = AppProgressUpdateCoalescer()

@MainActor
final class FreeMyChatsStore: ObservableObject {
    static let defaultBackupPath = NSString(
        string: "~/Library/Application Support/MobileSync/Backup/"
    ).expandingTildeInPath

    private enum DefaultsKey {
        static let lastLibraryPath = "lastLibraryPath"
        static let backupSearchPath = "backupSearchPath"
    }

    @Published var backupSearchPath: String
    @Published private(set) var backupRows: [BackupInspectionRow] = []
    @Published private(set) var session: LibrarySession?
    @Published var selectedChatID: VersionChatID?
    @Published private(set) var conversationCatalog: [ConversationCatalogItem] = []
    @Published private(set) var selectedConversationID: ConversationArchiveID?
    @Published private(set) var selectedConversation: ArchivedConversation?
    @Published private(set) var highlightedChatIDs: Set<VersionChatID> = []
    @Published private(set) var isLoadingConversationCatalog = false
    @Published private(set) var isOpeningConversation = false
    @Published private(set) var conversationPanelError: String?
    @Published private(set) var storedChatStates: [VersionChatID: StoredChatDisplayState] = [:]
    @Published private(set) var chatDetails: [VersionChatID: ChatDetailsState] = [:]
    @Published var chatFilter: ChatListFilter = .all
    @Published var chatSortOrder: ChatListSortOrder = .recent
    @Published private(set) var operation: AppOperation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var informationMessage: String?
    @Published private(set) var unifiedViewAdditionPreview: UnifiedViewAdditionPreview?
    @Published private(set) var storedCopyDeletionPreview: StoredCopyDeletionPreview?
    @Published private(set) var discoveryIssue: BackupDiscoveryIssue?
    @Published private(set) var importedBackupCleanupPrompt: ImportedIPhoneBackupCleanupPrompt?
    @Published var isShowingBackupImporter = false

    private let workQueue = DispatchQueue(
        label: "com.domingogallardo.FreeMyChats.library",
        qos: .userInitiated
    )
    private let sourceLoadQueue = DispatchQueue(
        label: "com.domingogallardo.FreeMyChats.source-chats",
        qos: .userInitiated
    )
    private var hasStarted = false
    private var conversationCatalogRequestID: UUID?
    private var openConversationRequestID: UUID?
    private let readingPositionStore = ChatReadingPositionStore()

    init() {
        backupSearchPath = UserDefaults.standard.string(forKey: DefaultsKey.backupSearchPath)
            ?? Self.defaultBackupPath
    }

    var versions: [LibraryVersionSession] {
        session?.versions ?? []
    }

    var importedChats: [ImportedChatSidebarItem] {
        conversationCatalog
            .flatMap { item in
                item.importedContributions.map {
                    ImportedChatSidebarItem(
                        contribution: $0,
                        conversationID: item.id,
                        conversationName: item.chat.name
                    )
                }
            }
            .sorted {
                if $0.contribution.importedAt != $1.contribution.importedAt {
                    return $0.contribution.importedAt > $1.contribution.importedAt
                }
                return $0.contribution.displayName.localizedStandardCompare(
                    $1.contribution.displayName
                ) == .orderedAscending
            }
    }

    nonisolated static func shouldPresentBackupImporter(
        for session: LibrarySession
    ) -> Bool {
        session.versions.isEmpty
    }

    var selectedVersion: LibraryVersionSession? {
        guard let selectedChatID else { return nil }
        return session?.version(id: selectedChatID.versionID)
    }

    var selectedChat: ChatInfo? {
        guard let selectedChatID else { return nil }
        return session?.chat(for: selectedChatID)
    }

    var storingChatID: VersionChatID? {
        guard case .storingChat(let selection) = operation?.kind else { return nil }
        return selection
    }

    var isLoadingSourceChats: Bool {
        guard case .loadingChats = operation?.kind else { return false }
        return true
    }

    func visibleChats(in version: LibraryVersionSession) -> [ChatInfo] {
        let filteredChats = version.chats.filter { chat in
            let selection = VersionChatID(versionID: version.id, chatID: chat.id)
            if highlightedChatIDs.contains(selection) { return true }

            switch chatFilter {
            case .all: return true
            case .groups: return chat.chatType == .group
            case .people: return chat.chatType == .individual
            case .archived: return chat.isArchived
            }
        }
        return chatSortOrder.sort(filteredChats)
    }

    func readingPosition(for selection: ConversationArchiveID) -> Int? {
        guard let libraryURL = session?.paths.rootURL else { return nil }
        return readingPositionStore.messageID(for: selection, in: libraryURL)
    }

    func saveReadingPosition(_ messageID: Int, for selection: ConversationArchiveID) {
        guard let libraryURL = session?.paths.rootURL else { return }
        readingPositionStore.save(messageID: messageID, for: selection, in: libraryURL)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        if let savedPath = UserDefaults.standard.string(forKey: DefaultsKey.lastLibraryPath) {
            openLibrary(at: URL(fileURLWithPath: savedPath), fallbackToWelcome: true)
        }
    }

    func createLibrary(at rootURL: URL) {
        let operationID = beginOperation(kind: .creatingLibrary, title: "Creando la biblioteca…")
        workQueue.async { [weak self] in
            let result = Result { try LibraryService.create(at: rootURL) }
            DispatchQueue.main.async {
                self?.finishOpening(result, operationID: operationID)
            }
        }
    }

    func openLibrary(at selectedURL: URL, fallbackToWelcome: Bool = false) {
        let operationID = beginOperation(kind: .openingLibrary, title: "Abriendo la biblioteca…")
        workQueue.async { [weak self] in
            let result = Result { try LibraryService.openMetadata(selectedURL: selectedURL) }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                if fallbackToWelcome, case .failure = result {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.lastLibraryPath)
                    self.operation = nil
                    return
                }
                switch result {
                case .success(let session):
                    self.operation = nil
                    self.install(session, preservingSelection: false)
                    self.loadSourceChats(in: session)
                case .failure(let error):
                    self.operation = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func closeLibrary() {
        unifiedViewAdditionPreview = nil
        storedCopyDeletionPreview = nil
        session = nil
        storedChatStates = [:]
        chatDetails = [:]
        selectedChatID = nil
        conversationCatalog = []
        selectedConversationID = nil
        selectedConversation = nil
        highlightedChatIDs = []
        isLoadingConversationCatalog = false
        isOpeningConversation = false
        conversationPanelError = nil
        conversationCatalogRequestID = nil
        openConversationRequestID = nil
        discoveryIssue = nil
        importedBackupCleanupPrompt = nil
        isShowingBackupImporter = false
        UserDefaults.standard.removeObject(forKey: DefaultsKey.lastLibraryPath)
    }

    func showBackupImporter() {
        guard session != nil else { return }
        isShowingBackupImporter = true
        inspectBackups()
    }

    func inspectBackups() {
        let path = backupSearchPath
        UserDefaults.standard.set(path, forKey: DefaultsKey.backupSearchPath)
        discoveryIssue = nil
        let operationID = beginOperation(kind: .discovering, title: "Analizando copias…")

        workQueue.async { [weak self] in
            let result = Result {
                try IPhoneBackupManager(iPhoneBackupsPath: path)
                    .inspectIPhoneBackups { progress in
                        self?.publish(progress, operationID: operationID, fallbackTitle: "Analizando copias…")
                    }
                    .map(BackupInspectionRow.init)
                    .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            }

            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let rows):
                    self.backupRows = rows
                    self.discoveryIssue = nil
                case .failure(let error):
                    self.backupRows = []
                    let issue = BackupDiscoveryIssue(error: error)
                    self.discoveryIssue = issue
                }
            }
        }
    }

    func addBackup(from row: BackupInspectionRow) {
        guard let backup = row.iPhoneBackup, let session else {
            errorMessage = "Esta copia no está disponible para añadirla a la biblioteca."
            return
        }

        let operationID = beginOperation(
            kind: .addingBackup,
            title: "Añadiendo la copia…",
            detail: row.creationDate.map { "Copia del \(Self.dateFormatter.string(from: $0))" }
        )

        workQueue.async { [weak self] in
            let result = Result {
                try LibraryService.addBackup(backup, to: session) { progress in
                    self?.publish(progress, operationID: operationID, fallbackTitle: "Añadiendo la copia…")
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                switch result {
                case .success(let newSession):
                    self.operation = nil
                    self.install(newSession, preservingSelection: false)
                    self.isShowingBackupImporter = false
                    self.importedBackupCleanupPrompt = ImportedIPhoneBackupCleanupPrompt(
                        sourceURL: URL(fileURLWithPath: row.path, isDirectory: true),
                        creationDate: row.creationDate
                    )
                case .failure(let error):
                    self.operation = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteSourceBackup(versionID: String) {
        guard let session else { return }
        let operationID = beginOperation(
            kind: .deletingBackup(versionID),
            title: "Eliminando la copia fuente…",
            detail: "Las conversaciones ya guardadas se conservarán."
        )

        workQueue.async { [weak self] in
            let result = Result {
                try LibraryService.deleteSourceBackup(versionID: versionID, from: session)
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let newSession):
                    self.install(newSession, preservingSelection: true)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func reloadLibrary() {
        guard let session else { return }
        openLibrary(at: session.paths.rootURL)
    }

    func selectChat(_ selection: VersionChatID?) {
        guard let selection,
              let version = session?.version(id: selection.versionID),
              version.chats.contains(where: { $0.id == selection.chatID }) else {
            return
        }

        // The filesystem is the source of truth. Re-check on every selection so a
        // removed or moved stored chat cannot leave a stale in-memory state.
        resolveSelectionState(selection)
        loadChatDetails(selection)
    }

    func addChatToLibrary(_ selection: VersionChatID) {
        guard storedChatStates[selection] == .notStored
                || isUpdateAvailable(storedChatStates[selection]) else { return }
        // Storing replaces an existing incomplete directory safely.
        storeChat(selection, overwriteExisting: true)
    }

    func prepareUnifiedViewAddition(_ selection: VersionChatID) {
        guard let session,
              let version = session.version(id: selection.versionID),
              let chat = version.chats.first(where: { $0.id == selection.chatID }),
              isUpdateAvailable(storedChatStates[selection]) else {
            return
        }
        do {
            guard let existingContributionCount = try ConversationArchiveService
                .existingContributionCount(for: chat, in: version, session: session) else {
                throw ConversationArchiveError.invalidArchive(
                    session.paths.rootURL,
                    "No se ha encontrado la conversación guardada que debía actualizarse."
                )
            }
            unifiedViewAdditionPreview = UnifiedViewAdditionPreview(
                id: UUID(),
                selection: selection,
                chatName: chat.name,
                existingContributionCount: existingContributionCount,
                sourceMessageCount: chat.numberMessages
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func commitUnifiedViewAddition(id: UUID) {
        guard let preview = unifiedViewAdditionPreview,
              preview.id == id else { return }
        unifiedViewAdditionPreview = nil
        addChatToLibrary(preview.selection)
    }

    func dismissUnifiedViewAdditionPreview() {
        unifiedViewAdditionPreview = nil
    }

    func prepareStoredCopyDeletion(_ selection: VersionChatID) {
        guard let session,
              let version = session.version(id: selection.versionID),
              storedChatStates[selection]?.isPhysicallyStored == true else { return }
        let chatName = session.chat(for: selection)?.name ?? "chat"
        do {
            if let impact = try ConversationArchiveService.storedRemovalMessageImpact(
                of: selection,
                in: session
            ) {
                storedCopyDeletionPreview = StoredCopyDeletionPreview(
                    id: UUID(),
                    selection: selection,
                    chatName: chatName,
                    versionTitle: version.record.title,
                    impact: impact
                )
                return
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Si una operación incompleta no dejó estos contadores disponibles, se
        // calculan de nuevo antes de confirmar el borrado.
        let operationID = beginOperation(
            kind: .preparingStoredCopyDeletion(selection),
            title: "Calculando los mensajes de “\(chatName)”…",
            detail: "Comprobando cuáles están también en otras copias guardadas."
        )
        workQueue.async { [weak self] in
            let result = Result {
                try ConversationArchiveService.removalMessageImpact(
                    of: selection,
                    in: session
                ) { progress in
                    self?.publish(
                        progress,
                        operationID: operationID,
                        fallbackTitle: "Calculando los mensajes de “\(chatName)”…"
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self,
                      self.operation?.id == operationID,
                      self.session === session else { return }
                self.operation = nil
                switch result {
                case .success(let impact):
                    self.storedCopyDeletionPreview = StoredCopyDeletionPreview(
                        id: UUID(),
                        selection: selection,
                        chatName: chatName,
                        versionTitle: version.record.title,
                        impact: impact
                    )
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func dismissStoredCopyDeletionPreview() {
        storedCopyDeletionPreview = nil
    }

    func contributionCount(containing selection: VersionChatID) -> Int? {
        guard let session else { return nil }
        do {
            guard let count = try ConversationArchiveService.contributionCount(
                containing: selection,
                in: session
            ) else {
                errorMessage = "No se ha encontrado la conversación a la que pertenece esta copia guardada."
                return nil
            }
            return count
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func refreshStoredChat(_ selection: VersionChatID) {
        storeChat(selection, overwriteExisting: true)
    }

    func openConversation(_ selection: ConversationArchiveID) {
        guard let session,
              let item = conversationCatalog.first(where: { $0.id == selection }) else { return }

        let requestID = UUID()
        highlightedChatIDs = Set(item.contributionSources)
        openConversationRequestID = requestID
        selectedConversationID = selection
        selectedConversation = nil
        isOpeningConversation = true
        conversationPanelError = nil

        workQueue.async { [weak self] in
            let result = Result {
                try ConversationArchiveService.openRepairing(item: item, in: session)
            }
            DispatchQueue.main.async {
                guard let self,
                      self.openConversationRequestID == requestID,
                      self.selectedConversationID == selection else { return }
                self.isOpeningConversation = false
                switch result {
                case .success(let stored):
                    self.selectedConversation = stored
                    self.highlightedChatIDs = Set(
                        stored.record.contributions.map(\.source)
                    )
                case .failure(let error):
                    self.conversationPanelError = error.localizedDescription
                }
            }
        }
    }

    func showConversationCatalog() {
        openConversationRequestID = nil
        selectedConversationID = nil
        selectedConversation = nil
        highlightedChatIDs = []
        isOpeningConversation = false
        conversationPanelError = nil
    }

    func revealLibrary() {
        guard let session else { return }
        WorkspaceService.reveal(session.paths.rootURL)
    }

    func revealSelectedChat() {
        guard let selectedConversation else { return }
        WorkspaceService.reveal(selectedConversation.directoryURL)
    }

    func revealStoredChat(_ selection: VersionChatID) {
        guard let version = session?.version(id: selection.versionID) else { return }
        let storedChatURL = version.storedChatsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(selection.chatID), isDirectory: true)
        guard FileManager.default.fileExists(atPath: storedChatURL.path) else {
            errorMessage = "La carpeta de esta copia guardada ya no está disponible."
            return
        }
        WorkspaceService.reveal(storedChatURL)
    }

    func exportSelectedConversation() {
        guard let session,
              let conversationID = selectedConversationID,
              let conversation = selectedConversation else {
            errorMessage = "Abre una conversación de la biblioteca para poder exportarla."
            return
        }
        let chat = conversation.document.chat
        let suggestedName = Self.portableFilename(for: chat.name)
        guard let destinationURL = DirectoryPicker.choosePortableConversationDestination(
            suggestedName: suggestedName,
            startingAt: session.paths.rootURL
        ) else { return }

        let operationTitle = "Exportando “\(chat.name)”…"
        let operationID = beginOperation(
            kind: .exportingConversation(conversationID),
            title: operationTitle,
            detail: destinationURL.lastPathComponent
        )
        let producerVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "2.1.4"
        workQueue.async { [weak self] in
            let result = Result {
                try ConversationArchiveService.createPortableConversationArchive(
                    from: conversation,
                    producerVersion: producerVersion,
                    destinationURL: destinationURL
                ) { progress in
                    self?.publish(
                        progress,
                        operationID: operationID,
                        fallbackTitle: operationTitle
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let archive):
                    let size = ByteCountFormatter.string(
                        fromByteCount: archive.archiveByteCount,
                        countStyle: .file
                    )
                    self.informationMessage = "Se ha exportado la conversación “"
                        + chat.name + "” como "
                        + "\(destinationURL.lastPathComponent) (\(size))."
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func chooseAndImportChat() {
        guard let session else { return }
        guard let archiveURL = DirectoryPicker.choosePortableConversationArchive(
            startingAt: session.paths.rootURL
        ) else { return }
        importChat(from: archiveURL)
    }

    func importChat(from archiveURL: URL) {
        guard let session else { return }
        let operationTitle = "Importando el chat…"
        let operationID = beginOperation(
            kind: .importingPortableConversation,
            title: operationTitle,
            detail: archiveURL.lastPathComponent
        )
        workQueue.async { [weak self] in
            let result = Result {
                try ConversationArchiveService.importPortableConversationArchive(
                    at: archiveURL,
                    into: session
                ) { progress in
                    self?.publish(
                        progress,
                        operationID: operationID,
                        fallbackTitle: operationTitle
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let imported):
                    self.install(imported.session, preservingSelection: true)
                    self.selectedConversationID = imported.conversation.record.id
                    self.selectedConversation = imported.conversation
                    self.highlightedChatIDs = Set(
                        imported.conversation.record.contributions.map(\.source)
                    )
                    let added = imported.addedMessageCount
                    let addedDescription = added == 1
                        ? "1 mensaje nuevo"
                        : "\(added.formatted()) mensajes nuevos"
                    self.informationMessage = "Se ha importado “"
                        + imported.importedContribution.displayName
                        + "” y se ha creado la nueva Vista unificada con "
                        + addedDescription + "."
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func revealImportedChat(_ item: ImportedChatSidebarItem) {
        guard let session else { return }
        let url = session.paths.importedChatsURL
            .appendingPathComponent(item.contribution.relativeDirectory, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "La carpeta de este chat importado ya no está disponible."
            return
        }
        WorkspaceService.reveal(url)
    }

    func removeImportedChat(_ item: ImportedChatSidebarItem) {
        guard let session else { return }
        let operationTitle = "Retirando “\(item.conversationName)”…"
        let operationID = beginOperation(
            kind: .removingImportedConversation(item.id),
            title: operationTitle,
            detail: "Reconstruyendo la Vista unificada sin este chat importado."
        )
        workQueue.async { [weak self] in
            let result = Result {
                try ConversationArchiveService.removeImportedContribution(
                    id: item.id,
                    from: session
                ) { progress in
                    self?.publish(
                        progress,
                        operationID: operationID,
                        fallbackTitle: operationTitle
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let removal):
                    if self.selectedConversationID == removal.conversation.record.id {
                        self.selectedConversation = removal.conversation
                        self.highlightedChatIDs = Set(
                            removal.conversation.record.contributions.map(\.source)
                        )
                    }
                    self.refreshConversationCatalog(in: session)
                    self.informationMessage = "Se ha retirado el chat importado de “"
                        + item.conversationName
                        + "” y se ha reconstruido su conversación."
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func deleteStoredContribution(_ selection: VersionChatID) {
        guard let session,
              storedChatStates[selection]?.isPhysicallyStored == true else { return }
        storedCopyDeletionPreview = nil
        let chatName = session.chat(for: selection)?.name ?? "chat"
        guard let contributionCount = contributionCount(containing: selection) else { return }
        let operationDetail: String
        switch contributionCount {
        case 2:
            operationDetail = "Retirando la Vista unificada y conservando la copia restante."
        case 3...:
            operationDetail = "Reconstruyendo la Vista unificada con las demás copias guardadas."
        default:
            operationDetail = "Retirando la conversación del catálogo."
        }
        let operationID = beginOperation(
            kind: .deletingStoredContribution(selection),
            title: "Borrando la copia guardada de “\(chatName)”…",
            detail: operationDetail
        )

        workQueue.async { [weak self] in
            let result = Result {
                try ConversationArchiveService.removeContribution(
                    source: selection,
                    from: session
                ) { progress in
                    self?.publish(
                        progress,
                        operationID: operationID,
                        fallbackTitle: "Borrando la copia guardada de “\(chatName)”…"
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let removal):
                    let previousConversationID = self.selectedConversationID
                    let previousConversation = self.selectedConversation
                    self.install(removal.session, preservingSelection: true)

                    if previousConversationID == removal.conversationID {
                        if let conversation = removal.conversation {
                            self.selectedConversationID = conversation.record.id
                            self.selectedConversation = conversation
                            self.highlightedChatIDs = Set(
                                conversation.record.contributions.map(\.source)
                            )
                        } else {
                            self.readingPositionStore.remove(
                                conversation: removal.conversationID,
                                in: session.paths.rootURL
                            )
                        }
                    } else if let previousConversationID, let previousConversation {
                        self.selectedConversationID = previousConversationID
                        self.selectedConversation = previousConversation
                        self.highlightedChatIDs = Set(
                            previousConversation.record.contributions.map(\.source)
                        )
                    }

                    if let conversation = removal.conversation {
                        let count = conversation.record.totalContributionCount
                        if count == 1 {
                            self.informationMessage = "Se ha borrado la copia guardada de “\(chatName)”. "
                                + "La Vista unificada ha desaparecido y el catálogo muestra "
                                + "directamente la copia restante."
                        } else {
                            self.informationMessage = "Se ha borrado la copia guardada de “\(chatName)”. "
                                + "La Vista unificada se ha reconstruido con las \(count) "
                                + "aportaciones restantes."
                        }
                    } else {
                        self.informationMessage = "Se ha borrado la última copia guardada de “\(chatName)” y la conversación ha salido del catálogo."
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func profilePhotoURL(for chat: ChatInfo, in version: LibraryVersionSession) -> URL? {
        guard let filename = chat.photoFilename else { return nil }
        let catalogURL = session?.paths
            .profilePhotosURL(for: version.id)
            .appendingPathComponent(filename)
        if let catalogURL, FileManager.default.fileExists(atPath: catalogURL.path) {
            return catalogURL
        }

        let storedChatURL = version.storedChatsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(chat.id), isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: storedChatURL.path) ? storedChatURL : nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func dismissInformation() {
        informationMessage = nil
    }

    func dismissImportedBackupCleanupPrompt() {
        importedBackupCleanupPrompt = nil
    }

    func moveImportedIPhoneBackupToTrash() {
        guard let prompt = importedBackupCleanupPrompt else { return }
        importedBackupCleanupPrompt = nil
        let operationID = beginOperation(
            kind: .deletingOriginalIPhoneBackup,
            title: "Moviendo la copia del iPhone a la Papelera…",
            detail: prompt.sourceURL.lastPathComponent
        )

        workQueue.async { [weak self] in
            let result = Result {
                try LibraryService.moveOriginalIPhoneBackupToTrash(at: prompt.sourceURL)
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success:
                    self.informationMessage = "La copia original del iPhone se ha movido a la Papelera. La copia extraída de WhatsApp sigue disponible en la biblioteca."
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func storeChat(_ selection: VersionChatID, overwriteExisting: Bool) {
        guard let session,
              let version = session.version(id: selection.versionID),
              let reader = version.reader,
              let chat = version.chats.first(where: { $0.id == selection.chatID }) else {
            errorMessage = "La copia fuente fue eliminada; este chat no se puede volver a añadir a la biblioteca."
            return
        }
        let chatName = chat.name
        let isUpdating = ConversationArchiveService.hasArchive(
            for: chat,
            in: version,
            paths: session.paths
        )
        let operationTitle: String
        let operationDetail: String
        switch storedChatStates[selection] {
        case .updateAvailable:
            let count = try? ConversationArchiveService.existingContributionCount(
                for: chat,
                in: version,
                session: session
            )
            if count == 1 {
                operationTitle = "Creando la Vista unificada de “\(chatName)”…"
                operationDetail = "Guardando ambas copias por separado y reuniendo sus mensajes."
            } else {
                operationTitle = "Actualizando la Vista unificada de “\(chatName)”…"
                operationDetail = "Guardando la nueva copia por separado y reuniendo todos sus mensajes."
            }
        case .stale:
            operationTitle = "Actualizando “\(chatName)” en la biblioteca…"
            operationDetail = "Recreando la copia y actualizando la conversación guardada."
        case .invalid:
            operationTitle = "Reparando “\(chatName)” en la biblioteca…"
            operationDetail = "Reemplazando la copia no válida y actualizando la conversación guardada."
        default:
            operationTitle = "Añadiendo “\(chatName)” a la biblioteca…"
            operationDetail = "Creando una conversación independiente con sus mensajes y archivos."
        }
        let operationID = beginOperation(
            kind: .storingChat(selection),
            title: operationTitle,
            detail: operationDetail
        )

        workQueue.async { [weak self] in
            let result = Result {
                let context = try ConversationArchiveService.prepareIncorporation(
                    for: chat,
                    in: version,
                    session: session
                )
                do {
                    let stored = try reader.storeChat(
                        chatId: selection.chatID,
                        overwriteExisting: overwriteExisting
                    ) { progress in
                        self?.publish(
                            progress,
                            operationID: operationID,
                            fallbackTitle: operationTitle
                        )
                    }
                    let update = try ConversationArchiveService.incorporate(
                        stored,
                        source: selection,
                        context: context,
                        in: session
                    ) { progress in
                        self?.publish(
                            progress,
                            operationID: operationID,
                            fallbackTitle: operationTitle
                        )
                    }
                    let previousContributionCount = context.record?.totalContributionCount ?? 0
                    let sourceWasAlreadyIncluded = context.record?.contributions.contains {
                        $0.source == selection
                    } ?? false
                    return (
                        stored,
                        update,
                        previousContributionCount,
                        sourceWasAlreadyIncluded
                    )
                } catch {
                    try? ConversationArchiveService.restorePreparedRecord(
                        from: context,
                        in: session
                    )
                    throw error
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let (
                    stored,
                    update,
                    previousContributionCount,
                    sourceWasAlreadyIncluded
                )):
                    self.finishStoringChat(
                        selection: selection,
                        chatName: chatName,
                        stored: stored,
                        update: update,
                        previousContributionCount: previousContributionCount,
                        sourceWasAlreadyIncluded: sourceWasAlreadyIncluded,
                        reportUpdate: isUpdating
                    )
                case .failure(let error):
                    self.storedChatStates[selection] = .invalid(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func finishStoringChat(
        selection: VersionChatID,
        chatName: String,
        stored: StoredChat,
        update: ConversationArchiveUpdate,
        previousContributionCount: Int,
        sourceWasAlreadyIncluded: Bool,
        reportUpdate: Bool
    ) {
        storedChatStates[selection] = .stored(stored.document.storedAt)
        chatDetails[selection] = .loaded(
            firstMessageDate: stored.document.messages.first?.date
        )
        if let session {
            refreshConversationCatalog(in: session)
        }
        if selectedConversationID == update.conversation.record.id {
            selectedConversation = update.conversation
        }
        guard reportUpdate else { return }

        let count = update.addedMessageCount
        let contributionCount = update.conversation.record.totalContributionCount
        if contributionCount > 1 {
            informationMessage = UnifiedViewPresentation.incorporationCompletionMessage(
                chatName: chatName,
                previousContributionCount: previousContributionCount,
                contributionCount: contributionCount,
                addedMessageCount: count,
                sourceWasAlreadyIncluded: sourceWasAlreadyIncluded
            )
        } else if count == 0 {
            informationMessage = "“\(chatName)” ya estaba al día."
        } else if count == 1 {
            informationMessage = "Se ha añadido 1 mensaje nuevo a “\(chatName)”."
        } else {
            informationMessage = "Se han añadido \(count.formatted()) mensajes nuevos a “\(chatName)”."
        }
    }

    private func resolveSelectionState(_ selection: VersionChatID) {
        guard let session,
              let version = session.version(id: selection.versionID),
              let chat = version.chats.first(where: { $0.id == selection.chatID }) else { return }
        workQueue.async { [weak self] in
            let displayState: StoredChatDisplayState
            if !Self.hasStoredChatDocument(selection, in: version) {
                displayState = ConversationArchiveService.hasArchive(
                    for: chat,
                    in: version,
                    paths: session.paths
                ) ? .updateAvailable(Date()) : .notStored
            } else if let reader = version.reader {
                displayState = StoredChatDisplayState(reader.storageState(for: chat))
            } else if version.storedChatStore.containsChat(chatId: chat.id),
                      let stored = try? version.storedChatStore.openChat(chatId: chat.id) {
                displayState = .stored(stored.document.storedAt)
            } else {
                displayState = .notStored
            }

            DispatchQueue.main.async {
                guard let self, self.session?.version(id: selection.versionID) === version else { return }
                self.storedChatStates[selection] = displayState
            }
        }
    }

    private func finishOpening(_ result: Result<LibrarySession, Error>, operationID: UUID) {
        guard operation?.id == operationID else { return }
        operation = nil
        switch result {
        case .success(let session):
            install(session, preservingSelection: false)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func install(_ newSession: LibrarySession, preservingSelection: Bool) {
        unifiedViewAdditionPreview = nil
        storedCopyDeletionPreview = nil
        let previousSelection = preservingSelection ? selectedChatID : nil
        session = newSession
        selectedChatID = previousSelection.flatMap { newSession.chat(for: $0) == nil ? nil : $0 }
        conversationCatalog = []
        selectedConversationID = nil
        selectedConversation = nil
        highlightedChatIDs = []
        isLoadingConversationCatalog = false
        isOpeningConversation = false
        conversationPanelError = nil
        openConversationRequestID = nil
        chatDetails = [:]
        storedChatStates = Dictionary(uniqueKeysWithValues: newSession.versions.flatMap { version in
            version.chats.map { (VersionChatID(versionID: version.id, chatID: $0.id), .checking) }
        })
        UserDefaults.standard.set(newSession.paths.rootURL.path, forKey: DefaultsKey.lastLibraryPath)
        refreshStoredChatStates()
        refreshConversationCatalog(in: newSession)
        if let selectedChatID {
            selectChat(selectedChatID)
        }
        if Self.shouldPresentBackupImporter(for: newSession) {
            isShowingBackupImporter = true
            inspectBackups()
        }
    }

    private func loadChatDetails(_ selection: VersionChatID) {
        guard chatDetails[selection] == nil,
              let version = session?.version(id: selection.versionID) else { return }

        chatDetails[selection] = .loading
        workQueue.async { [weak self] in
            let result = Result {
                if let backup = version.backup {
                    // This reader intentionally has no storage root. Asking for chat
                    // details must never create Media directories or copy files.
                    let reader = try backup.openReader()
                    return try reader.getChat(chatId: selection.chatID).messages.first?.date
                }
                return try version.storedChatStore
                    .openChat(chatId: selection.chatID)
                    .document.messages.first?.date
            }
            DispatchQueue.main.async {
                guard let self, self.session?.version(id: selection.versionID) === version else { return }
                switch result {
                case .success(let firstMessageDate):
                    self.chatDetails[selection] = .loaded(firstMessageDate: firstMessageDate)
                case .failure(let error):
                    self.chatDetails[selection] = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func loadSourceChats(in metadataSession: LibrarySession) {
        guard metadataSession.versions.contains(where: \.hasSourceBackup) else { return }
        let operationID = beginOperation(
            kind: .loadingChats,
            title: "Leyendo las conversaciones…"
        )
        sourceLoadQueue.async { [weak self] in
            let result = Result {
                try LibraryService.loadSourceChats(in: metadataSession) { progress in
                    self?.publish(
                        progress,
                        operationID: operationID,
                        fallbackTitle: "Leyendo las conversaciones…"
                    )
                }
            }
            DispatchQueue.main.async {
                guard let self,
                      self.operation?.id == operationID,
                      self.session === metadataSession else { return }
                self.operation = nil
                switch result {
                case .success(let loadedSession):
                    self.installLoadedSourceChats(loadedSession)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func installLoadedSourceChats(_ loadedSession: LibrarySession) {
        let previousSelection = selectedChatID
        session = loadedSession
        selectedChatID = previousSelection.flatMap {
            loadedSession.chat(for: $0) == nil ? nil : $0
        }
        chatDetails = [:]
        storedChatStates = Dictionary(uniqueKeysWithValues: loadedSession.versions.flatMap { version in
            version.chats.map {
                (VersionChatID(versionID: version.id, chatID: $0.id), .checking)
            }
        })
        refreshStoredChatStates()
        if let selectedChatID {
            selectChat(selectedChatID)
        }
    }

    private func refreshStoredChatStates() {
        guard let session else { return }
        workQueue.async { [weak self] in
            var states: [VersionChatID: StoredChatDisplayState] = [:]
            let archiveKeys = (try? ConversationArchiveService.archiveKeys(
                paths: session.paths
            )) ?? []
            for version in session.versions {
                let identityResolver = ConversationIdentityResolver(
                    backupURL: version.hasSourceBackup ? version.backupURL : nil
                )
                for chat in version.chats {
                    let key = VersionChatID(versionID: version.id, chatID: chat.id)
                    if !Self.hasStoredChatDocument(key, in: version) {
                        let identity = identityResolver.identity(for: chat)
                        states[key] = !archiveKeys.isDisjoint(with: identity.keys)
                            ? .updateAvailable(Date())
                            : .notStored
                    } else if let reader = version.reader {
                        states[key] = StoredChatDisplayState(reader.storageState(for: chat))
                    } else if let stored = try? version.storedChatStore.openChat(chatId: chat.id) {
                        states[key] = .stored(stored.document.storedAt)
                    } else {
                        states[key] = .notStored
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self, self.session === session else { return }
                self.storedChatStates = states
            }
        }
    }

    private func refreshConversationCatalog(in session: LibrarySession) {
        let requestID = UUID()
        conversationCatalogRequestID = requestID
        isLoadingConversationCatalog = true
        conversationPanelError = nil

        workQueue.async { [weak self] in
            let result = Result { try ConversationArchiveService.catalog(in: session) }

            DispatchQueue.main.async {
                guard let self,
                      self.session === session,
                      self.conversationCatalogRequestID == requestID else { return }
                self.isLoadingConversationCatalog = false
                switch result {
                case .success(let items):
                    self.conversationCatalog = items
                    self.refreshStoredChatStates()
                case .failure(let error):
                    self.conversationPanelError = error.localizedDescription
                }
            }
        }
    }

    private nonisolated static func hasStoredChatDocument(
        _ selection: VersionChatID,
        in version: LibraryVersionSession
    ) -> Bool {
        let documentURL = version.storedChatsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(selection.chatID), isDirectory: true)
            .appendingPathComponent("chat.json")
        return FileManager.default.fileExists(atPath: documentURL.path)
    }

    private func isUpdateAvailable(_ state: StoredChatDisplayState?) -> Bool {
        if case .updateAvailable = state { return true }
        return false
    }

    private func beginOperation(kind: AppOperation.Kind, title: String, detail: String? = nil) -> UUID {
        let id = UUID()
        operation = AppOperation(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            fractionCompleted: nil
        )
        errorMessage = nil
        return id
    }

    private nonisolated func publish(
        _ progress: WABackupProgress,
        operationID: UUID,
        fallbackTitle: String
    ) {
        let update = AppProgressUpdateCoalescer.Update(
            progress: progress,
            operationID: operationID,
            fallbackTitle: fallbackTitle
        )
        guard appProgressUpdateCoalescer.submit(update) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let update = appProgressUpdateCoalescer.takeLatest(),
                  let self,
                  var operation = self.operation,
                  operation.id == update.operationID else {
                return
            }
            operation.title = Self.title(
                for: update.progress.phase,
                fallback: update.fallbackTitle
            )
            operation.detail = update.progress.currentItem ?? operation.detail
            operation.fractionCompleted = update.progress.fractionCompleted
            self.operation = operation
        }
    }

    private static func title(for phase: WABackupProgress.Phase, fallback: String) -> String {
        switch phase {
        case .discoveringIPhoneBackups, .inspectingIPhoneBackup: return "Analizando copias…"
        case .loadingManifest: return "Leyendo la copia del iPhone…"
        case .copyingBackupFiles: return "Extrayendo WhatsApp…"
        case .writingMetadata, .indexingFiles, .indexingPathAliases, .indexingMediaItems,
             .calculatingBackupInfo: return "Preparando la copia…"
        case .loadingChats: return "Leyendo las conversaciones…"
        case .readingChat, .loadingMessages, .processingMessages, .buildingContacts,
             .copyingChatMedia: return fallback
        case .validatingConversationSources, .hashingConversationMedia,
             .canonicalizingConversationMessages, .inferringConversationPerspectives,
             .aligningConversationMessages, .classifyingConversationComposition:
            return "Combinando la conversación…"
        case .materializingConversation, .copyingConversationMedia:
            return "Creando la Vista unificada…"
        case .creatingPortableConversationArchive:
            return "Creando el archivo de conversación…"
        case .inspectingPortableConversationArchive:
            return "Validando el archivo de conversación…"
        case .extractingPortableConversationArchive:
            return "Extrayendo el archivo de conversación…"
        case .completed: return fallback
        }
    }

    private static func portableFilename(for chatName: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = chatName
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Chat exportado" : sanitized
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}
