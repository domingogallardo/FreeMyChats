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
    @Published private(set) var chats: [ChatInfo] = []
    @Published var selectedChatID: Int?
    @Published private(set) var selectedExport: ExportedChat?
    @Published private(set) var exportStates: [Int: ChatExportDisplayState] = [:]
    @Published var chatSearchText = ""
    @Published var chatFilter: ChatListFilter = .all
    @Published private(set) var operation: AppOperation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var discoveryIssue: String?

    private let workQueue = DispatchQueue(label: "com.domingogallardo.FreeMyChats.library", qos: .userInitiated)
    private var hasStarted = false

    init() {
        backupSearchPath = UserDefaults.standard.string(forKey: DefaultsKey.backupSearchPath)
            ?? Self.defaultBackupPath
    }

    var visibleChats: [ChatInfo] {
        chats.filter { chat in
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

    var selectedChat: ChatInfo? {
        guard let selectedChatID else { return nil }
        return chats.first { $0.id == selectedChatID }
    }

    var selectedExportState: ChatExportDisplayState {
        guard let selectedChatID else { return .notExported }
        return exportStates[selectedChatID] ?? .checking
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        if let savedPath = UserDefaults.standard.string(forKey: DefaultsKey.lastLibraryPath) {
            openLibrary(at: URL(fileURLWithPath: savedPath), fallbackToDiscovery: true)
        } else {
            inspectBackups()
        }
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

    func createLibrary(from row: BackupInspectionRow, at rootURL: URL) {
        guard let backup = row.iPhoneBackup else {
            errorMessage = "Esta copia no está disponible para crear una biblioteca."
            return
        }

        let operationID = beginOperation(
            kind: .creatingLibrary,
            title: "Creando la biblioteca…",
            detail: row.creationDate.map { "Copia del \(Self.dateFormatter.string(from: $0))" }
        )

        workQueue.async { [weak self] in
            let result = Result {
                try LibraryService.create(from: backup, at: rootURL) { progress in
                    self?.publish(progress, operationID: operationID, fallbackTitle: "Creando la biblioteca…")
                }
            }
            DispatchQueue.main.async {
                self?.finishOpening(result, operationID: operationID)
            }
        }
    }

    func openLibrary(at selectedURL: URL, fallbackToDiscovery: Bool = false) {
        let operationID = beginOperation(kind: .openingLibrary, title: "Abriendo la biblioteca…")
        workQueue.async { [weak self] in
            let result = Result {
                try LibraryService.open(selectedURL: selectedURL) { progress in
                    self?.publish(progress, operationID: operationID, fallbackTitle: "Abriendo la biblioteca…")
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if fallbackToDiscovery, case .failure = result {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.lastLibraryPath)
                    self.operation = nil
                    self.inspectBackups()
                    return
                }
                self.finishOpening(result, operationID: operationID)
            }
        }
    }

    func closeLibrary() {
        session = nil
        chats = []
        exportStates = [:]
        selectedChatID = nil
        selectedExport = nil
        chatSearchText = ""
        discoveryIssue = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.lastLibraryPath)
        inspectBackups()
    }

    func reloadChats() {
        guard let session else { return }
        let operationID = beginOperation(kind: .loadingChats, title: "Actualizando la biblioteca…")
        workQueue.async { [weak self] in
            let result = Result {
                try LibraryService.reloadChats(in: session) { progress in
                    self?.publish(progress, operationID: operationID, fallbackTitle: "Actualizando la biblioteca…")
                }
            }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let chats):
                    session.chats = chats
                    self.chats = chats
                    if let selected = self.selectedChatID, !chats.contains(where: { $0.id == selected }) {
                        self.selectedChatID = nil
                        self.selectedExport = nil
                    }
                    self.refreshExportStates()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func selectChat(_ chatID: Int?) {
        guard let chatID, session != nil, chats.contains(where: { $0.id == chatID }) else {
            selectedExport = nil
            return
        }

        selectedExport = nil
        switch exportStates[chatID] ?? .checking {
        case .notExported:
            exportChat(chatID: chatID, overwriteExisting: false)
        case .exported:
            openExport(chatID: chatID)
        case .stale:
            openExport(chatID: chatID)
        case .invalid:
            break
        case .checking:
            resolveSelectionState(chatID: chatID)
        }
    }

    func updateSelectedExport() {
        guard let selectedChatID else { return }
        exportChat(chatID: selectedChatID, overwriteExisting: true)
    }

    func revealLibrary() {
        guard let session else { return }
        WorkspaceService.reveal(session.paths.rootURL)
    }

    func revealSelectedChat() {
        guard let selectedExport else { return }
        WorkspaceService.reveal(selectedExport.directoryURL)
    }

    func profilePhotoURL(for chat: ChatInfo) -> URL? {
        guard let filename = chat.photoFilename, let session else { return nil }
        let url = session.paths.exportsURL
            .appendingPathComponent("ChatProfilePhotos", isDirectory: true)
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func dismissError() {
        errorMessage = nil
    }

    private func exportChat(chatID: Int, overwriteExisting: Bool) {
        guard let session else { return }
        let chatName = chats.first { $0.id == chatID }?.name ?? "chat"
        let operationID = beginOperation(
            kind: .exportingChat(chatID),
            title: "Exportando “\(chatName)”…",
            detail: "Creando una carpeta independiente con sus mensajes y archivos."
        )

        workQueue.async { [weak self] in
            let result = Result {
                try session.reader.exportChat(
                    chatId: chatID,
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
                    let date = exported.document.exportedAt
                    self.exportStates[chatID] = .exported(date)
                    if self.selectedChatID == chatID {
                        self.selectedExport = exported
                    }
                case .failure(let error):
                    self.exportStates[chatID] = .invalid(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func openExport(chatID: Int) {
        guard let session else { return }
        let operationID = beginOperation(kind: .openingChat(chatID), title: "Abriendo el chat exportado…")
        workQueue.async { [weak self] in
            let result = Result { try session.reader.openExportedChat(chatId: chatID) }
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                switch result {
                case .success(let exported):
                    if self.selectedChatID == chatID {
                        self.selectedExport = exported
                    }
                case .failure(let error):
                    self.exportStates[chatID] = .invalid(error.localizedDescription)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func resolveSelectionState(chatID: Int) {
        guard let session, let chat = chats.first(where: { $0.id == chatID }) else { return }
        let operationID = beginOperation(kind: .openingChat(chatID), title: "Comprobando la exportación…")
        workQueue.async { [weak self] in
            let displayState = ChatExportDisplayState(session.reader.exportState(for: chat))
            DispatchQueue.main.async {
                guard let self, self.operation?.id == operationID else { return }
                self.operation = nil
                self.exportStates[chatID] = displayState
                guard self.selectedChatID == chatID else { return }
                switch displayState {
                case .notExported:
                    self.exportChat(chatID: chatID, overwriteExisting: false)
                case .exported, .stale:
                    self.openExport(chatID: chatID)
                case .invalid, .checking:
                    break
                }
            }
        }
    }

    private func finishOpening(_ result: Result<LibrarySession, Error>, operationID: UUID) {
        guard operation?.id == operationID else { return }
        operation = nil
        switch result {
        case .success(let session):
            self.session = session
            chats = session.chats
            selectedChatID = nil
            selectedExport = nil
            chatSearchText = ""
            exportStates = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, .checking) })
            UserDefaults.standard.set(session.paths.rootURL.path, forKey: DefaultsKey.lastLibraryPath)
            refreshExportStates()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func refreshExportStates() {
        guard let session else { return }
        let sourceChats = chats
        workQueue.async { [weak self] in
            let states = Dictionary(uniqueKeysWithValues: sourceChats.map { chat in
                (chat.id, ChatExportDisplayState(session.reader.exportState(for: chat)))
            })
            DispatchQueue.main.async {
                guard let self, self.session === session else { return }
                self.exportStates = states
            }
        }
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
             .calculatingBackupInfo: return "Preparando la biblioteca…"
        case .loadingChats: return "Leyendo la biblioteca…"
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
