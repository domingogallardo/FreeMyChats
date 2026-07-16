import Foundation
@preconcurrency import SwiftWABackupAPI

@MainActor
final class FreeMyChatsStore: ObservableObject {
    static let defaultBackupPath = NSString(
        string: "~/Library/Application Support/MobileSync/Backup/"
    ).expandingTildeInPath

    private enum DefaultsKey {
        static let lastLibraryPath = "lastLibraryPath"
        static let backupSearchPath = "backupSearchPath"
        static let resumeBackupImportAfterPermission = "resumeBackupImportAfterPermission"
    }

    @Published var backupSearchPath: String
    @Published private(set) var backupRows: [BackupInspectionRow] = []
    @Published private(set) var session: LibrarySession?
    @Published var selectedChatID: VersionChatID?
    @Published private(set) var exportedChats: [ExportedChatListItem] = []
    @Published private(set) var selectedExportID: ConversationArchiveID?
    @Published private(set) var selectedExport: ArchivedConversation?
    @Published private(set) var isLoadingExportCatalog = false
    @Published private(set) var isOpeningExport = false
    @Published private(set) var exportPanelError: String?
    @Published private(set) var exportStates: [VersionChatID: ChatExportDisplayState] = [:]
    @Published private(set) var chatDetails: [VersionChatID: ChatDetailsState] = [:]
    @Published var chatFilter: ChatListFilter = .all
    @Published var chatSortOrder: ChatListSortOrder = .recent
    @Published private(set) var operation: AppOperation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var informationMessage: String?
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
    private var exportCatalogRequestID: UUID?
    private var openExportRequestID: UUID?
    private let readingPositionStore = ChatReadingPositionStore()

    init() {
        backupSearchPath = UserDefaults.standard.string(forKey: DefaultsKey.backupSearchPath)
            ?? Self.defaultBackupPath
    }

    var versions: [LibraryVersionSession] {
        session?.versions ?? []
    }

    nonisolated static func shouldPresentBackupImporter(
        for session: LibrarySession,
        resumeAfterPermission: Bool
    ) -> Bool {
        session.versions.isEmpty || resumeAfterPermission
    }

    var selectedVersion: LibraryVersionSession? {
        guard let selectedChatID else { return nil }
        return session?.version(id: selectedChatID.versionID)
    }

    var selectedChat: ChatInfo? {
        guard let selectedChatID else { return nil }
        return session?.chat(for: selectedChatID)
    }

    var exportingChatID: VersionChatID? {
        guard case .exportingChat(let selection) = operation?.kind else { return nil }
        return selection
    }

    var isLoadingSourceChats: Bool {
        guard case .loadingChats = operation?.kind else { return false }
        return true
    }

    func visibleChats(in version: LibraryVersionSession) -> [ChatInfo] {
        let filteredChats = version.chats.filter { chat in
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
        session = nil
        exportStates = [:]
        chatDetails = [:]
        selectedChatID = nil
        exportedChats = []
        selectedExportID = nil
        selectedExport = nil
        isLoadingExportCatalog = false
        isOpeningExport = false
        exportPanelError = nil
        exportCatalogRequestID = nil
        openExportRequestID = nil
        discoveryIssue = nil
        importedBackupCleanupPrompt = nil
        isShowingBackupImporter = false
        UserDefaults.standard.removeObject(forKey: DefaultsKey.resumeBackupImportAfterPermission)
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
                    UserDefaults.standard.removeObject(
                        forKey: DefaultsKey.resumeBackupImportAfterPermission
                    )
                case .failure(let error):
                    self.backupRows = []
                    let issue = BackupDiscoveryIssue(error: error)
                    self.discoveryIssue = issue
                    if issue == .permissionRequired {
                        UserDefaults.standard.set(
                            true,
                            forKey: DefaultsKey.resumeBackupImportAfterPermission
                        )
                    } else {
                        UserDefaults.standard.removeObject(
                            forKey: DefaultsKey.resumeBackupImportAfterPermission
                        )
                    }
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
            detail: "Las conversaciones ya exportadas se conservarán."
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
        // removed or moved export cannot leave a stale in-memory "exported" state.
        resolveSelectionState(selection)
        loadChatDetails(selection)
    }

    func exportChat(_ selection: VersionChatID) {
        guard exportStates[selection] == .notExported
                || isUpdateAvailable(exportStates[selection]) else { return }
        // A previous read from older app versions may have left a Media-only
        // directory. Explicit export replaces that incomplete directory safely.
        performExport(selection, overwriteExisting: true)
    }

    func replaceExport(_ selection: VersionChatID) {
        performExport(selection, overwriteExisting: true)
    }

    func openExport(_ selection: ConversationArchiveID) {
        guard let session,
              exportedChats.contains(where: { $0.id == selection }) else { return }

        let requestID = UUID()
        openExportRequestID = requestID
        selectedExportID = selection
        selectedExport = nil
        isOpeningExport = true
        exportPanelError = nil

        workQueue.async { [weak self] in
            let result = Result {
                try ConversationArchiveService.open(id: selection, paths: session.paths)
            }
            DispatchQueue.main.async {
                guard let self,
                      self.openExportRequestID == requestID,
                      self.selectedExportID == selection else { return }
                self.isOpeningExport = false
                switch result {
                case .success(let exported):
                    self.selectedExport = exported
                case .failure(let error):
                    self.exportPanelError = error.localizedDescription
                }
            }
        }
    }

    func showExportList() {
        openExportRequestID = nil
        selectedExportID = nil
        selectedExport = nil
        isOpeningExport = false
        exportPanelError = nil
    }

    func revealLibrary() {
        guard let session else { return }
        WorkspaceService.reveal(session.paths.rootURL)
    }

    func revealSelectedChat() {
        guard let selectedExport else { return }
        WorkspaceService.reveal(selectedExport.directoryURL)
    }

    func revealExport(_ selection: VersionChatID) {
        guard let version = session?.version(id: selection.versionID) else { return }
        let exportURL = version.exportsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(selection.chatID), isDirectory: true)
        guard FileManager.default.fileExists(atPath: exportURL.path) else {
            errorMessage = "La carpeta de esta exportación ya no está disponible."
            return
        }
        WorkspaceService.reveal(exportURL)
    }

    func deleteExportedContribution(_ selection: VersionChatID) {
        guard let session,
              exportStates[selection]?.isPhysicallyExported == true else { return }
        let chatName = session.chat(for: selection)?.name ?? "chat"
        let operationID = beginOperation(
            kind: .deletingExportedContribution(selection),
            title: "Borrando la exportación de “\(chatName)”…",
            detail: "Reconstruyendo la conversación con las demás copias."
        )

        workQueue.async { [weak self] in
            let result = Result {
                try ConversationArchiveService.removeContribution(
                    source: selection,
                    from: session
                )
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let removal):
                    let previousExportID = self.selectedExportID
                    let previousExport = self.selectedExport
                    self.install(removal.session, preservingSelection: true)

                    if previousExportID == removal.conversationID {
                        if let conversation = removal.conversation {
                            self.selectedExportID = conversation.record.id
                            self.selectedExport = conversation
                        } else {
                            self.readingPositionStore.remove(
                                conversation: removal.conversationID,
                                in: session.paths.rootURL
                            )
                        }
                    } else if let previousExportID, let previousExport {
                        self.selectedExportID = previousExportID
                        self.selectedExport = previousExport
                    }

                    if let conversation = removal.conversation {
                        let count = conversation.record.contributions.count
                        let copies = count == 1 ? "1 copia" : "\(count) copias"
                        self.informationMessage = "Se ha borrado la exportación de “\(chatName)”. La conversación conserva \(copies)."
                    } else {
                        self.informationMessage = "Se ha borrado la última exportación de “\(chatName)” y la conversación ha salido del catálogo."
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

        let exportedChatURL = version.exportsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(chat.id), isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: exportedChatURL.path) ? exportedChatURL : nil
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

    private func performExport(_ selection: VersionChatID, overwriteExisting: Bool) {
        guard let session,
              let version = session.version(id: selection.versionID),
              let reader = version.reader else {
            errorMessage = "La copia fuente fue eliminada; este chat no se puede volver a exportar."
            return
        }
        let chat = version.chats.first { $0.id == selection.chatID }
        let chatName = chat?.name ?? "chat"
        let isUpdating = chat.map {
            ConversationArchiveService.hasArchive(
                for: $0,
                in: version,
                paths: session.paths
            )
        } ?? false
        let operationID = beginOperation(
            kind: .exportingChat(selection),
            title: isUpdating ? "Actualizando “\(chatName)”…" : "Exportando “\(chatName)”…",
            detail: isUpdating
                ? "Añadiendo los mensajes nuevos a la conversación guardada."
                : "Creando una conversación independiente con sus mensajes y archivos."
        )

        workQueue.async { [weak self] in
            let result = Result {
                let exported = try reader.exportChat(
                    chatId: selection.chatID,
                    overwriteExisting: overwriteExisting
                ) { progress in
                    self?.publish(
                        progress,
                        operationID: operationID,
                        fallbackTitle: isUpdating
                            ? "Actualizando “\(chatName)”…"
                            : "Exportando “\(chatName)”…"
                    )
                }
                let update = try ConversationArchiveService.incorporate(
                    exported,
                    source: selection,
                    in: session
                )
                return (exported, update)
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let (exported, update)):
                    self.exportStates[selection] = .exported(exported.document.exportedAt)
                    self.chatDetails[selection] = .loaded(
                        firstMessageDate: exported.document.messages.first?.date
                    )
                    if let session = self.session {
                        self.refreshExportCatalog(in: session)
                    }
                    if self.selectedExportID == update.conversation.record.id {
                        self.selectedExport = update.conversation
                    }
                    if isUpdating {
                        let count = update.addedMessageCount
                        if count == 0 {
                            self.informationMessage = "“\(chatName)” ya estaba al día."
                        } else if count == 1 {
                            self.informationMessage = "Se ha añadido 1 mensaje nuevo a “\(chatName)”."
                        } else {
                            self.informationMessage = "Se han añadido \(count.formatted()) mensajes nuevos a “\(chatName)”."
                        }
                    }
                case .failure(let error):
                    self.exportStates[selection] = .invalid(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func resolveSelectionState(_ selection: VersionChatID) {
        guard let session,
              let version = session.version(id: selection.versionID),
              let chat = version.chats.first(where: { $0.id == selection.chatID }) else { return }
        workQueue.async { [weak self] in
            let displayState: ChatExportDisplayState
            if !Self.hasExportDocument(selection, in: version) {
                displayState = ConversationArchiveService.hasArchive(
                    for: chat,
                    in: version,
                    paths: session.paths
                ) ? .updateAvailable(Date()) : .notExported
            } else if let reader = version.reader {
                displayState = ChatExportDisplayState(reader.exportState(for: chat))
            } else if version.exportStore.containsChat(chatId: chat.id),
                      let exported = try? version.exportStore.openChat(chatId: chat.id) {
                displayState = .exported(exported.document.exportedAt)
            } else {
                displayState = .notExported
            }

            DispatchQueue.main.async {
                guard let self, self.session?.version(id: selection.versionID) === version else { return }
                self.exportStates[selection] = displayState
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
        let previousSelection = preservingSelection ? selectedChatID : nil
        session = newSession
        selectedChatID = previousSelection.flatMap { newSession.chat(for: $0) == nil ? nil : $0 }
        exportedChats = []
        selectedExportID = nil
        selectedExport = nil
        isLoadingExportCatalog = false
        isOpeningExport = false
        exportPanelError = nil
        openExportRequestID = nil
        chatDetails = [:]
        exportStates = Dictionary(uniqueKeysWithValues: newSession.versions.flatMap { version in
            version.chats.map { (VersionChatID(versionID: version.id, chatID: $0.id), .checking) }
        })
        UserDefaults.standard.set(newSession.paths.rootURL.path, forKey: DefaultsKey.lastLibraryPath)
        refreshExportStates()
        refreshExportCatalog(in: newSession)
        if let selectedChatID {
            selectChat(selectedChatID)
        }
        let resumeAfterPermission = UserDefaults.standard.bool(
            forKey: DefaultsKey.resumeBackupImportAfterPermission
        )
        if Self.shouldPresentBackupImporter(
            for: newSession,
            resumeAfterPermission: resumeAfterPermission
        ) {
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
                    // This reader intentionally has no export root. Asking for chat
                    // details must never create Media directories or copy files.
                    let reader = try backup.openReader()
                    return try reader.getChat(chatId: selection.chatID).messages.first?.date
                }
                return try version.exportStore
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
        exportStates = Dictionary(uniqueKeysWithValues: loadedSession.versions.flatMap { version in
            version.chats.map {
                (VersionChatID(versionID: version.id, chatID: $0.id), .checking)
            }
        })
        refreshExportStates()
        if let selectedChatID {
            selectChat(selectedChatID)
        }
    }

    private func refreshExportStates() {
        guard let session else { return }
        workQueue.async { [weak self] in
            var states: [VersionChatID: ChatExportDisplayState] = [:]
            let archiveKeys = (try? ConversationArchiveService.archiveKeys(
                paths: session.paths
            )) ?? []
            for version in session.versions {
                let identityResolver = ConversationIdentityResolver(
                    backupURL: version.hasSourceBackup ? version.backupURL : nil
                )
                for chat in version.chats {
                    let key = VersionChatID(versionID: version.id, chatID: chat.id)
                    if !Self.hasExportDocument(key, in: version) {
                        let identity = identityResolver.identity(for: chat)
                        states[key] = !archiveKeys.isDisjoint(with: identity.keys)
                            ? .updateAvailable(Date())
                            : .notExported
                    } else if let reader = version.reader {
                        states[key] = ChatExportDisplayState(reader.exportState(for: chat))
                    } else if let exported = try? version.exportStore.openChat(chatId: chat.id) {
                        states[key] = .exported(exported.document.exportedAt)
                    } else {
                        states[key] = .notExported
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self, self.session === session else { return }
                self.exportStates = states
            }
        }
    }

    private func refreshExportCatalog(in session: LibrarySession) {
        let requestID = UUID()
        exportCatalogRequestID = requestID
        isLoadingExportCatalog = true
        exportPanelError = nil

        workQueue.async { [weak self] in
            let result = Result { try ConversationArchiveService.synchronize(in: session) }

            DispatchQueue.main.async {
                guard let self,
                      self.session === session,
                      self.exportCatalogRequestID == requestID else { return }
                self.isLoadingExportCatalog = false
                switch result {
                case .success(let items):
                    self.exportedChats = items
                    self.refreshExportStates()
                case .failure(let error):
                    self.exportPanelError = error.localizedDescription
                }
            }
        }
    }

    private nonisolated static func hasExportDocument(
        _ selection: VersionChatID,
        in version: LibraryVersionSession
    ) -> Bool {
        let documentURL = version.exportsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(selection.chatID), isDirectory: true)
            .appendingPathComponent("chat.json")
        return FileManager.default.fileExists(atPath: documentURL.path)
    }
    private func isUpdateAvailable(_ state: ChatExportDisplayState?) -> Bool {
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
        DispatchQueue.main.async { [weak self] in
            guard let self, var operation = self.operation, operation.id == operationID else { return }
            operation.title = Self.title(for: progress.phase, fallback: fallbackTitle)
            operation.detail = progress.currentItem ?? operation.detail
            operation.fractionCompleted = progress.fractionCompleted
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
        case .exportingChat, .loadingMessages, .processingMessages, .buildingContacts,
             .exportingMedia: return fallback
        case .completed: return fallback
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}
