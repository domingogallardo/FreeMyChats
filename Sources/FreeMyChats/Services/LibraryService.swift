import Foundation
import Darwin
import SwiftWABackupAPI

enum LibraryServiceError: Error, LocalizedError {
    case destinationNotEmpty(URL)
    case invalidLibrary(URL)
    case unsupportedSchema(Int)
    case duplicateBackup
    case sourceAlreadyDeleted
    case storedChatNotFound
    case originalIPhoneBackupNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .destinationNotEmpty(let url):
            return "La carpeta \(url.lastPathComponent) no está vacía. Elige una carpeta nueva."
        case .invalidLibrary(let url):
            return "No se ha encontrado una biblioteca de Free My Chats válida en \(url.path)."
        case .unsupportedSchema(let version):
            return "La versión \(version) del formato de biblioteca no es compatible."
        case .duplicateBackup:
            return "Esta copia de iPhone ya forma parte de la biblioteca."
        case .sourceAlreadyDeleted:
            return "La copia fuente ya había sido eliminada."
        case .storedChatNotFound:
            return "El chat guardado ya no está disponible."
        case .originalIPhoneBackupNotFound(let url):
            return "La copia original del iPhone ya no está en \(url.path)."
        }
    }
}

enum LibraryService {
    static func create(at rootURL: URL) throws -> LibrarySession {
        let paths = LibraryPaths(rootURL: rootURL)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: paths.rootURL.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: paths.rootURL.path)
            guard contents.isEmpty else {
                throw LibraryServiceError.destinationNotEmpty(paths.rootURL)
            }
        }

        try fileManager.createDirectory(at: paths.sourcesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.storedChatsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: paths.importedChatsURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: paths.mergedChatsURL, withIntermediateDirectories: true)
        try write(LibraryManifest(), to: paths.manifestURL)
        return try open(paths: paths)
    }

    static func open(
        selectedURL: URL,
        progress: WABackupProgressHandler? = nil
    ) throws -> LibrarySession {
        let paths = LibraryPaths.resolvingSelection(selectedURL)
        return try open(paths: paths, progress: progress)
    }

    static func openMetadata(selectedURL: URL) throws -> LibrarySession {
        let paths = LibraryPaths.resolvingSelection(selectedURL)
        return try open(paths: paths, loadSourceChats: false)
    }

    static func loadSourceChats(
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> LibrarySession {
        let versions = try session.versions.map { version in
            guard version.hasSourceBackup else { return version }
            return try openVersion(
                version.record,
                paths: session.paths,
                progress: progress,
                loadSourceChats: true
            )
        }
        return LibrarySession(
            paths: session.paths,
            manifest: session.manifest,
            versions: versions
        )
    }

    static func addBackup(
        _ iPhoneBackup: IPhoneBackup,
        to session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> LibrarySession {
        guard !session.manifest.versions.contains(where: {
            $0.sourceBackupIdentifier == iPhoneBackup.identifier
                && $0.sourceBackupCreationDate == iPhoneBackup.creationDate
        }) else {
            throw LibraryServiceError.duplicateBackup
        }

        let id = UUID().uuidString.lowercased()
        let backupURL = session.paths.backupURL(for: id)
        let fileManager = FileManager.default
        var manifestWasUpdated = false

        do {
            let extracted = try iPhoneBackup.extractWhatsAppBackup(to: backupURL, progress: progress)
            let info = try extracted.getBackupInfo()
            var manifest = session.manifest
            let storageDirectoryName = makeStorageDirectoryName(
                for: info.source.iPhoneBackupCreationDate,
                excluding: Set(manifest.versions.map(\.storageDirectoryName))
            )
            manifest.versions.append(
                LibraryVersionRecord(
                    id: id,
                    sourceBackupIdentifier: info.source.iPhoneBackupIdentifier,
                    sourceBackupCreationDate: info.source.iPhoneBackupCreationDate,
                    importedAt: Date(),
                    storageDirectoryName: storageDirectoryName
                )
            )
            manifest.versions.sort { $0.sourceBackupCreationDate > $1.sourceBackupCreationDate }
            try write(manifest, to: session.paths.manifestURL)
            manifestWasUpdated = true
            return try open(paths: session.paths, progress: progress)
        } catch {
            if manifestWasUpdated {
                try? write(session.manifest, to: session.paths.manifestURL)
            }
            try? fileManager.removeItem(at: backupURL.deletingLastPathComponent())
            throw error
        }
    }

    static func deleteSourceBackup(
        versionID: String,
        from session: LibrarySession
    ) throws -> LibrarySession {
        guard let version = session.version(id: versionID), version.hasSourceBackup else {
            throw LibraryServiceError.sourceAlreadyDeleted
        }

        let versionSourceURL = version.backupURL.deletingLastPathComponent()
        let stagingURL = session.paths.sourcesURL.appendingPathComponent(
            ".deleting-\(versionID)-\(UUID().uuidString)",
            isDirectory: true
        )
        let fileManager = FileManager.default

        try fileManager.moveItem(at: versionSourceURL, to: stagingURL)
        do {
            try fileManager.removeItem(at: stagingURL)
        } catch {
            try? fileManager.moveItem(at: stagingURL, to: versionSourceURL)
            throw error
        }

        return try open(paths: session.paths)
    }

    static func moveOriginalIPhoneBackupToTrash(at sourceURL: URL) throws {
        do {
            try FileManager.default.trashItem(at: sourceURL, resultingItemURL: nil)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == CocoaError.Code.fileNoSuchFile.rawValue {
                throw LibraryServiceError.originalIPhoneBackupNotFound(sourceURL)
            }
            throw error
        }
    }

    static func deleteStoredChat(
        _ selection: VersionChatID,
        from session: LibrarySession
    ) throws -> LibrarySession {
        guard let version = session.version(id: selection.versionID) else {
            throw LibraryServiceError.storedChatNotFound
        }

        let fileManager = FileManager.default
        let chatsURL = version.storedChatsURL.appendingPathComponent("Chats", isDirectory: true)
        let chatURL = chatsURL.appendingPathComponent(
            String(selection.chatID),
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: chatURL.path) else {
            throw LibraryServiceError.storedChatNotFound
        }

        let stagingURL = session.paths.rootURL.appendingPathComponent(
            ".deleting-stored-chat-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        let stagedChatURL = stagingURL.appendingPathComponent("Chat", isDirectory: true)
        try fileManager.moveItem(at: chatURL, to: stagedChatURL)

        let removeVersion = !version.hasSourceBackup
            && storedChatIDs(at: version.storedChatsURL).isEmpty

        if removeVersion {
            var manifestWasUpdated = false
            do {
                let sourceURL = version.backupURL.deletingLastPathComponent()
                let stagedSourceURL = stagingURL.appendingPathComponent("Source", isDirectory: true)
                let stagedStoredChatsURL = stagingURL.appendingPathComponent("StoredChats", isDirectory: true)

                if fileManager.fileExists(atPath: sourceURL.path) {
                    try fileManager.moveItem(at: sourceURL, to: stagedSourceURL)
                }
                if fileManager.fileExists(atPath: version.storedChatsURL.path) {
                    try fileManager.moveItem(at: version.storedChatsURL, to: stagedStoredChatsURL)
                }

                var manifest = session.manifest
                manifest.versions.removeAll { $0.id == selection.versionID }
                try write(manifest, to: session.paths.manifestURL)
                manifestWasUpdated = true
                try fileManager.removeItem(at: stagingURL)
            } catch {
                if manifestWasUpdated {
                    try? write(session.manifest, to: session.paths.manifestURL)
                }
                restoreDeletedVersion(
                    version,
                    chatURL: chatURL,
                    stagingURL: stagingURL,
                    using: fileManager
                )
                throw error
            }
        } else {
            do {
                try removeDirectoryIfEffectivelyEmpty(chatsURL)
                try removeDirectoryIfEffectivelyEmpty(version.storedChatsURL)
                try fileManager.removeItem(at: stagingURL)
            } catch {
                if fileManager.fileExists(atPath: stagedChatURL.path) {
                    try? fileManager.createDirectory(
                        at: chatURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? fileManager.moveItem(at: stagedChatURL, to: chatURL)
                }
                try? fileManager.removeItem(at: stagingURL)
                throw error
            }
        }

        return try open(paths: session.paths)
    }

    private static func open(
        paths: LibraryPaths,
        progress: WABackupProgressHandler? = nil,
        loadSourceChats: Bool = true
    ) throws -> LibrarySession {
        guard FileManager.default.fileExists(atPath: paths.manifestURL.path) else {
            throw LibraryServiceError.invalidLibrary(paths.rootURL)
        }

        let manifest = try readManifest(at: paths.manifestURL)
        guard manifest.isSupported else {
            throw LibraryServiceError.unsupportedSchema(manifest.schemaVersion)
        }

        try FileManager.default.createDirectory(at: paths.sourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.storedChatsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: paths.importedChatsURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: paths.mergedChatsURL,
            withIntermediateDirectories: true
        )
        let versions = try manifest.versions.map { record in
            try openVersion(
                record,
                paths: paths,
                progress: progress,
                loadSourceChats: loadSourceChats
            )
        }
        return LibrarySession(paths: paths, manifest: manifest, versions: versions)
    }

    private static func openVersion(
        _ record: LibraryVersionRecord,
        paths: LibraryPaths,
        progress: WABackupProgressHandler?,
        loadSourceChats: Bool
    ) throws -> LibraryVersionSession {
        let backupURL = paths.backupURL(for: record.id)
        let storedChatsURL = paths.storedChatURL(for: record)
        let profilePhotosURL = paths.profilePhotosURL(for: record.id)
        let storedChatIDs = storedChatIDs(at: storedChatsURL)

        let metadataURL = backupURL
            .appendingPathComponent(".wa-backup", isDirectory: true)
            .appendingPathComponent("backup-info.json")

        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let backup = ExtractedWhatsAppBackup(url: backupURL)
            _ = try backup.getBackupInfo()
            let reader = try backup.openReader(storageRootDirectory: storedChatsURL)
            try FileManager.default.createDirectory(
                at: profilePhotosURL,
                withIntermediateDirectories: true
            )
            let chats = loadSourceChats
                ? try reader.getChats(
                    directoryToSavePhotos: profilePhotosURL,
                    progress: progress
                )
                : []
            return LibraryVersionSession(
                record: record,
                backupURL: backupURL,
                storedChatsURL: storedChatsURL,
                backup: backup,
                reader: reader,
                chats: chats,
                backupByteCount: try allocatedSize(of: backupURL)
            )
        }

        let storedChatStore = StoredChatStore(rootDirectory: storedChatsURL)
        let chats = storedChatIDs.compactMap {
            try? storedChatStore.openChat(chatId: $0).document.chat
        }
        return LibraryVersionSession(
            record: record,
            backupURL: backupURL,
            storedChatsURL: storedChatsURL,
            backup: nil,
            reader: nil,
            chats: chats,
            backupByteCount: 0
        )
    }

    private static func storedChatIDs(at storedChatsURL: URL) -> [Int] {
        let chatsURL = storedChatsURL.appendingPathComponent("Chats", isDirectory: true)
        guard let directory = opendir(chatsURL.path) else { return [] }
        defer { closedir(directory) }

        var ids: [Int] = []
        while let entryPointer = readdir(directory) {
            var entry = entryPointer.pointee
            let name = withUnsafePointer(to: &entry.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            guard let chatID = Int(name), name == String(chatID) else { continue }
            var visibleEntry = chatsURL.appendingPathComponent(name, isDirectory: true)
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = false
            try? visibleEntry.setResourceValues(resourceValues)
            ids.append(chatID)
        }
        return ids.sorted()
    }

    private static func restoreDeletedVersion(
        _ version: LibraryVersionSession,
        chatURL: URL,
        stagingURL: URL,
        using fileManager: FileManager
    ) {
        let stagedSourceURL = stagingURL.appendingPathComponent("Source", isDirectory: true)
        let sourceURL = version.backupURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: stagedSourceURL.path) {
            try? fileManager.moveItem(at: stagedSourceURL, to: sourceURL)
        }

        let stagedStoredChatsURL = stagingURL.appendingPathComponent("StoredChats", isDirectory: true)
        if fileManager.fileExists(atPath: stagedStoredChatsURL.path) {
            try? fileManager.moveItem(at: stagedStoredChatsURL, to: version.storedChatsURL)
        }

        let stagedChatURL = stagingURL.appendingPathComponent("Chat", isDirectory: true)
        if fileManager.fileExists(atPath: stagedChatURL.path) {
            try? fileManager.createDirectory(
                at: chatURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.moveItem(at: stagedChatURL, to: chatURL)
        }
        try? fileManager.removeItem(at: stagingURL)
    }

    private static func removeDirectoryIfEffectivelyEmpty(_ directoryURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        let contents = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        let meaningfulContents = contents.filter { $0 != ".DS_Store" }
        guard meaningfulContents.isEmpty else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    private static func makeStorageDirectoryName(
        for date: Date,
        excluding existingNames: Set<String>
    ) -> String {
        let baseName = "Copia \(storageDirectoryDateFormatter.string(from: date))"
        guard existingNames.contains(baseName) else { return baseName }

        var suffix = 2
        while existingNames.contains("\(baseName) (\(suffix))") {
            suffix += 1
        }
        return "\(baseName) (\(suffix))"
    }

    private static let storageDirectoryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()

    private static func readManifest(at url: URL) throws -> LibraryManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryManifest.self, from: Data(contentsOf: url))
    }

    static func write(_ manifest: LibraryManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url, options: .atomic)
    }

    private static func allocatedSize(of directoryURL: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
