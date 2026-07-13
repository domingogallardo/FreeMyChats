import Foundation
@preconcurrency import SwiftWABackupAPI

@MainActor
@available(macOS 14.0, *)
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
    @Published private(set) var exportedChats: [ExportedChatListItem] = []
    @Published private(set) var selectedExportID: VersionChatID?
    @Published private(set) var selectedExport: ExportedChat?
    @Published private(set) var isLoadingExportCatalog = false
    @Published private(set) var isOpeningExport = false
    @Published private(set) var exportPanelError: String?
    @Published private(set) var exportStates: [VersionChatID: ChatExportDisplayState] = [:]
    @Published private(set) var chatDetails: [VersionChatID: ChatDetailsState] = [:]
    @Published var chatSearchText = ""
    @Published var chatFilter: ChatListFilter = .all
    @Published private(set) var operation: AppOperation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var discoveryIssue: String?
    @Published var isShowingBackupImporter = false

    private let workQueue = DispatchQueue(
        label: "com.domingogallardo.FreeMyChats.library",
        qos: .userInitiated
    )
    private var hasStarted = false
    private var exportCatalogRequestID: UUID?
    private var openExportRequestID: UUID?

    init() {
        backupSearchPath = UserDefaults.standard.string(forKey: DefaultsKey.backupSearchPath)
            ?? Self.defaultBackupPath
    }

    var versions: [LibraryVersionSession] {
        session?.versions ?? []
    }

    var selectedVersion: LibraryVersionSession? {
        guard let selectedChatID else { return nil }
        return session?.version(id: selectedChatID.versionID)
    }

    var selectedChat: ChatInfo? {
        guard let selectedChatID else { return nil }
        return session?.chat(for: selectedChatID)
    }

    var openedExportState: ChatExportDisplayState {
        guard let selectedExportID else { return .notExported }
        return exportStates[selectedExportID] ?? .checking
    }

    func visibleChats(in version: LibraryVersionSession) -> [ChatInfo] {
        version.chats.filter { chat in
            let matchesSearch = chatSearchText.isEmpty
                || chat.name.localizedCaseInsensitiveContains(chatSearchText)
                || chat.contactJid.localizedCaseInsensitiveContains(chatSearchText)
            guard matchesSearch else { return false }

            switch chatFilter {
            case .all: return true
            case .groups: return chat.chatType == .group
            case .people: return chat.chatType == .individual
            case .archived: return chat.isArchived
            }
        }
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
            let result = Result {
                try LibraryService.open(selectedURL: selectedURL) { progress in
                    self?.publish(progress, operationID: operationID, fallbackTitle: "Abriendo la biblioteca…")
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if fallbackToWelcome, case .failure = result {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.lastLibraryPath)
                    self.operation = nil
                    return
                }
                self.finishOpening(result, operationID: operationID)
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
        chatSearchText = ""
        discoveryIssue = nil
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
                case .failure:
                    self.backupRows = []
                    self.discoveryIssue = "No se ha podido leer la carpeta de copias seleccionada."
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
        guard exportStates[selection] == .notExported else { return }
        // A previous read from older app versions may have left a Media-only
        // directory. Explicit export replaces that incomplete directory safely.
        performExport(selection, overwriteExisting: true)
    }

    func replaceExport(_ selection: VersionChatID) {
        performExport(selection, overwriteExisting: true)
    }

    func openExport(_ selection: VersionChatID) {
        guard let version = session?.version(id: selection.versionID),
              exportedChats.contains(where: { $0.id == selection }) else { return }

        let requestID = UUID()
        openExportRequestID = requestID
        selectedExportID = selection
        selectedExport = nil
        isOpeningExport = true
        exportPanelError = nil

        workQueue.async { [weak self] in
            let result = Result { try version.exportStore.openChat(chatId: selection.chatID) }
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

    private func performExport(_ selection: VersionChatID, overwriteExisting: Bool) {
        guard let version = session?.version(id: selection.versionID),
              let reader = version.reader else {
            errorMessage = "La copia fuente fue eliminada; este chat no se puede volver a exportar."
            return
        }
        let chatName = version.chats.first { $0.id == selection.chatID }?.name ?? "chat"
        let operationID = beginOperation(
            kind: .exportingChat(selection),
            title: "Exportando “\(chatName)”…",
            detail: "Creando una carpeta independiente con sus mensajes y archivos."
        )

        workQueue.async { [weak self] in
            let result = Result {
                try reader.exportChat(
                    chatId: selection.chatID,
                    overwriteExisting: overwriteExisting
                ) { progress in
                    self?.publish(progress, operationID: operationID, fallbackTitle: "Exportando “\(chatName)”…")
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let exported):
                    self.exportStates[selection] = .exported(exported.document.exportedAt)
                    self.chatDetails[selection] = .loaded(
                        firstMessageDate: exported.document.messages.first?.date
                    )
                    self.upsertExportedChat(
                        exported,
                        selection: selection,
                        versionTitle: version.record.title
                    )
                    if let session = self.session {
                        self.refreshExportCatalog(in: session)
                    }
                    if self.selectedExportID == selection {
                        self.selectedExport = exported
                    }
                case .failure(let error):
                    self.exportStates[selection] = .invalid(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func resolveSelectionState(_ selection: VersionChatID) {
        guard let version = session?.version(id: selection.versionID),
              let chat = version.chats.first(where: { $0.id == selection.chatID }) else { return }
        workQueue.async { [weak self] in
            let displayState: ChatExportDisplayState
            if !Self.hasExportDocument(selection, in: version) {
                displayState = .notExported
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
        chatSearchText = ""
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

    private func refreshExportStates() {
        guard let session else { return }
        workQueue.async { [weak self] in
            var states: [VersionChatID: ChatExportDisplayState] = [:]
            for version in session.versions {
                for chat in version.chats {
                    let key = VersionChatID(versionID: version.id, chatID: chat.id)
                    if !Self.hasExportDocument(key, in: version) {
                        states[key] = .notExported
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
            let items = LibraryService.exportCatalog(in: session)

            DispatchQueue.main.async {
                guard let self,
                      self.session === session,
                      self.exportCatalogRequestID == requestID else { return }
                self.isLoadingExportCatalog = false
                self.exportedChats = items
            }
        }
    }

    private func upsertExportedChat(
        _ exported: ExportedChat,
        selection: VersionChatID,
        versionTitle: String
    ) {
        let item = ExportedChatListItem(
            id: selection,
            chat: exported.document.chat,
            exportedAt: exported.document.exportedAt,
            versionTitle: versionTitle,
            directoryURL: exported.directoryURL,
            photoURL: Self.exportListPhotoURL(
                for: exported.document.chat,
                selection: selection,
                directoryURL: exported.directoryURL,
                session: session
            )
        )
        exportedChats.removeAll { $0.id == selection }
        exportedChats.append(item)
        exportedChats.sort { lhs, rhs in
            if lhs.exportedAt != rhs.exportedAt {
                return lhs.exportedAt > rhs.exportedAt
            }
            return lhs.chat.name.localizedStandardCompare(rhs.chat.name) == .orderedAscending
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

    private nonisolated static func exportListPhotoURL(
        for chat: ChatInfo,
        selection: VersionChatID,
        directoryURL: URL,
        session: LibrarySession?
    ) -> URL? {
        guard let filename = chat.photoFilename else { return nil }
        if let session {
            let catalogURL = session.paths
                .profilePhotosURL(for: selection.versionID)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: catalogURL.path) {
                return catalogURL
            }
        }

        let exportedURL = directoryURL
            .appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: exportedURL.path) ? exportedURL : nil
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
