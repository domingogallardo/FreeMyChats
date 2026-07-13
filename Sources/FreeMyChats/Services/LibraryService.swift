import Foundation
import SwiftWABackupAPI

enum LibraryServiceError: Error, LocalizedError {
    case destinationNotEmpty(URL)
    case invalidLibrary(URL)
    case unsupportedSchema(Int)
    case duplicateBackup
    case sourceAlreadyDeleted
    case exportedChatNotFound
    case originalIPhoneBackupNotFound(URL)
    case layoutMigrationConflict(URL)

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
        case .exportedChatNotFound:
            return "El chat exportado ya no está disponible."
        case .originalIPhoneBackupNotFound(let url):
            return "La copia original del iPhone ya no está en \(url.path)."
        case .layoutMigrationConflict(let url):
            return "No se ha podido reorganizar la biblioteca porque ya existe un archivo distinto en \(url.path)."
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
        try fileManager.createDirectory(at: paths.exportsURL, withIntermediateDirectories: true)
        try write(LibraryManifest(), to: paths.manifestURL)
        return try open(paths: paths)
    }

    static func open(
        selectedURL: URL,
        progress: WABackupProgressHandler? = nil
    ) throws -> LibrarySession {
        let paths = LibraryPaths.resolvingSelection(selectedURL)
        try migrateLegacyLibraryIfNeeded(at: paths)
        return try open(paths: paths, progress: progress)
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
            let exportDirectoryName = makeExportDirectoryName(
                for: info.source.iPhoneBackupCreationDate,
                excluding: Set(manifest.versions.map(\.resolvedExportDirectoryName))
            )
            manifest.versions.append(
                LibraryVersionRecord(
                    id: id,
                    sourceBackupIdentifier: info.source.iPhoneBackupIdentifier,
                    sourceBackupCreationDate: info.source.iPhoneBackupCreationDate,
                    importedAt: Date(),
                    exportDirectoryName: exportDirectoryName
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

    static func deleteExportedChat(
        _ selection: VersionChatID,
        from session: LibrarySession
    ) throws -> LibrarySession {
        guard let version = session.version(id: selection.versionID) else {
            throw LibraryServiceError.exportedChatNotFound
        }

        let fileManager = FileManager.default
        let chatsURL = version.exportsURL.appendingPathComponent("Chats", isDirectory: true)
        let chatURL = chatsURL.appendingPathComponent(
            String(selection.chatID),
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: chatURL.path) else {
            throw LibraryServiceError.exportedChatNotFound
        }

        let stagingURL = session.paths.rootURL.appendingPathComponent(
            ".deleting-export-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        let stagedChatURL = stagingURL.appendingPathComponent("Chat", isDirectory: true)
        try fileManager.moveItem(at: chatURL, to: stagedChatURL)

        let removeVersion = !version.hasSourceBackup
            && exportedChatIDs(at: version.exportsURL).isEmpty

        if removeVersion {
            var manifestWasUpdated = false
            do {
                let sourceURL = version.backupURL.deletingLastPathComponent()
                let legacyExportsURL = version.exportsURL.deletingLastPathComponent()
                    .appendingPathComponent(version.id, isDirectory: true)
                let stagedSourceURL = stagingURL.appendingPathComponent("Source", isDirectory: true)
                let stagedExportsURL = stagingURL.appendingPathComponent("Exports", isDirectory: true)
                let stagedLegacyExportsURL = stagingURL.appendingPathComponent(
                    "LegacyExports",
                    isDirectory: true
                )

                if fileManager.fileExists(atPath: sourceURL.path) {
                    try fileManager.moveItem(at: sourceURL, to: stagedSourceURL)
                }
                if fileManager.fileExists(atPath: version.exportsURL.path) {
                    try fileManager.moveItem(at: version.exportsURL, to: stagedExportsURL)
                }
                if legacyExportsURL.standardizedFileURL != version.exportsURL.standardizedFileURL,
                   fileManager.fileExists(atPath: legacyExportsURL.path) {
                    try fileManager.moveItem(at: legacyExportsURL, to: stagedLegacyExportsURL)
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
                try removeDirectoryIfEffectivelyEmpty(version.exportsURL)
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

    static func exportCatalog(in session: LibrarySession) -> [ExportedChatListItem] {
        var items: [ExportedChatListItem] = []
        let fileManager = FileManager.default

        for version in session.versions {
            for chatID in exportedChatIDs(at: version.exportsURL) {
                guard let exported = try? version.exportStore.openChat(chatId: chatID) else {
                    continue
                }

                let chat = exported.document.chat
                let photoURL = chat.photoFilename.map {
                    exported.mediaDirectoryURL.appendingPathComponent($0)
                }.flatMap {
                    fileManager.fileExists(atPath: $0.path) ? $0 : nil
                }
                items.append(
                    ExportedChatListItem(
                        id: VersionChatID(versionID: version.id, chatID: chatID),
                        chat: chat,
                        exportedAt: exported.document.exportedAt,
                        versionTitle: version.record.title,
                        directoryURL: exported.directoryURL,
                        photoURL: photoURL
                    )
                )
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.exportedAt != rhs.exportedAt {
                return lhs.exportedAt > rhs.exportedAt
            }
            return lhs.chat.name.localizedStandardCompare(rhs.chat.name) == .orderedAscending
        }
    }

    private static func open(
        paths: LibraryPaths,
        progress: WABackupProgressHandler? = nil
    ) throws -> LibrarySession {
        guard FileManager.default.fileExists(atPath: paths.manifestURL.path) else {
            throw LibraryServiceError.invalidLibrary(paths.rootURL)
        }

        var manifest = try readManifest(at: paths.manifestURL)
        guard manifest.schemaVersion == LibraryManifest.currentSchemaVersion else {
            throw LibraryServiceError.unsupportedSchema(manifest.schemaVersion)
        }

        try FileManager.default.createDirectory(at: paths.sourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.exportsURL, withIntermediateDirectories: true)
        manifest = try migrateUserFacingLayout(paths: paths, manifest: manifest)

        let versions = try manifest.versions.map { record in
            try openVersion(record, paths: paths, progress: progress)
        }
        return LibrarySession(paths: paths, manifest: manifest, versions: versions)
    }

    private static func openVersion(
        _ record: LibraryVersionRecord,
        paths: LibraryPaths,
        progress: WABackupProgressHandler?
    ) throws -> LibraryVersionSession {
        let backupURL = paths.backupURL(for: record.id)
        let exportsURL = paths.exportURL(for: record)
        let profilePhotosURL = paths.profilePhotosURL(for: record.id)
        let exportedChatIDs = exportedChatIDs(at: exportsURL)

        let metadataURL = backupURL
            .appendingPathComponent(".wa-backup", isDirectory: true)
            .appendingPathComponent("backup-info.json")

        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let backup = ExtractedWhatsAppBackup(url: backupURL)
            _ = try backup.getBackupInfo()
            let reader = try backup.openReader(exportRootDirectory: exportsURL)
            try FileManager.default.createDirectory(
                at: profilePhotosURL,
                withIntermediateDirectories: true
            )
            let chats = try reader.getChats(
                directoryToSavePhotos: profilePhotosURL,
                progress: progress
            )
            return LibraryVersionSession(
                record: record,
                backupURL: backupURL,
                exportsURL: exportsURL,
                backup: backup,
                reader: reader,
                chats: chats,
                backupByteCount: try allocatedSize(of: backupURL)
            )
        }

        let exportStore = ChatExportStore(rootDirectory: exportsURL)
        let chats = exportedChatIDs.compactMap {
            try? exportStore.openChat(chatId: $0).document.chat
        }
        return LibraryVersionSession(
            record: record,
            backupURL: backupURL,
            exportsURL: exportsURL,
            backup: nil,
            reader: nil,
            chats: chats,
            backupByteCount: 0
        )
    }

    private static func exportedChatIDs(at exportsURL: URL) -> [Int] {
        let chatsURL = exportsURL.appendingPathComponent("Chats", isDirectory: true)
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: chatsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        return entries.compactMap { entry in
            guard let chatID = Int(entry.lastPathComponent),
                  entry.lastPathComponent == String(chatID) else { return nil }
            var visibleEntry = entry
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = false
            try? visibleEntry.setResourceValues(resourceValues)
            return chatID
        }.sorted()
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

        let stagedExportsURL = stagingURL.appendingPathComponent("Exports", isDirectory: true)
        if fileManager.fileExists(atPath: stagedExportsURL.path) {
            try? fileManager.moveItem(at: stagedExportsURL, to: version.exportsURL)
        }

        let stagedLegacyExportsURL = stagingURL.appendingPathComponent(
            "LegacyExports",
            isDirectory: true
        )
        let legacyExportsURL = version.exportsURL.deletingLastPathComponent()
            .appendingPathComponent(version.id, isDirectory: true)
        if fileManager.fileExists(atPath: stagedLegacyExportsURL.path) {
            try? fileManager.moveItem(at: stagedLegacyExportsURL, to: legacyExportsURL)
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

    private static func migrateLegacyLibraryIfNeeded(at paths: LibraryPaths) throws {
        guard !FileManager.default.fileExists(atPath: paths.manifestURL.path) else { return }

        let legacyBackupURL = paths.rootURL.appendingPathComponent("Backup", isDirectory: true)
        let metadataURL = legacyBackupURL
            .appendingPathComponent(".wa-backup", isDirectory: true)
            .appendingPathComponent("backup-info.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw LibraryServiceError.invalidLibrary(paths.rootURL)
        }

        let info = try ExtractedWhatsAppBackup(url: legacyBackupURL).getBackupInfo()
        let id = UUID().uuidString.lowercased()
        let legacyExportsURL = paths.rootURL.appendingPathComponent("Exports", isDirectory: true)
        let temporaryExportsURL = paths.rootURL.appendingPathComponent(
            ".legacy-exports-\(UUID().uuidString)",
            isDirectory: true
        )
        let record = LibraryVersionRecord(
            id: id,
            sourceBackupIdentifier: info.source.iPhoneBackupIdentifier,
            sourceBackupCreationDate: info.source.iPhoneBackupCreationDate,
            importedAt: Date(),
            exportDirectoryName: makeExportDirectoryName(
                for: info.source.iPhoneBackupCreationDate,
                excluding: []
            )
        )
        let newBackupURL = paths.backupURL(for: id)
        let newExportsURL = paths.exportURL(for: record)
        let fileManager = FileManager.default
        let hadLegacyExports = fileManager.fileExists(atPath: legacyExportsURL.path)

        do {
            if hadLegacyExports {
                try fileManager.moveItem(at: legacyExportsURL, to: temporaryExportsURL)
            }
            try fileManager.createDirectory(
                at: newBackupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(at: paths.exportsURL, withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacyBackupURL, to: newBackupURL)
            if hadLegacyExports {
                try fileManager.moveItem(at: temporaryExportsURL, to: newExportsURL)
            }

            try write(LibraryManifest(versions: [record]), to: paths.manifestURL)
        } catch {
            try? fileManager.removeItem(at: paths.manifestURL)
            if fileManager.fileExists(atPath: newBackupURL.path) {
                try? fileManager.moveItem(at: newBackupURL, to: legacyBackupURL)
            }
            if hadLegacyExports, fileManager.fileExists(atPath: newExportsURL.path) {
                try? fileManager.moveItem(at: newExportsURL, to: temporaryExportsURL)
            }
            if hadLegacyExports, fileManager.fileExists(atPath: temporaryExportsURL.path) {
                try? fileManager.removeItem(at: legacyExportsURL)
                try? fileManager.moveItem(at: temporaryExportsURL, to: legacyExportsURL)
            }
            throw error
        }
    }

    private static func migrateUserFacingLayout(
        paths: LibraryPaths,
        manifest: LibraryManifest
    ) throws -> LibraryManifest {
        var usedNames = Set(
            manifest.versions.compactMap(\.exportDirectoryName)
        )
        var changedManifest = false
        var migratedVersions: [LibraryVersionRecord] = []
        migratedVersions.reserveCapacity(manifest.versions.count)

        for record in manifest.versions {
            let migratedRecord: LibraryVersionRecord
            if record.exportDirectoryName == nil {
                let name = makeExportDirectoryName(
                    for: record.sourceBackupCreationDate,
                    excluding: usedNames
                )
                usedNames.insert(name)
                migratedRecord = record.withExportDirectoryName(name)
                changedManifest = true
            } else {
                migratedRecord = record
            }

            let legacyExportsURL = paths.legacyExportURL(for: record.id)
            let readableExportsURL = paths.exportURL(for: migratedRecord)
            if legacyExportsURL.standardizedFileURL != readableExportsURL.standardizedFileURL,
               FileManager.default.fileExists(atPath: legacyExportsURL.path) {
                try mergeDirectory(at: legacyExportsURL, into: readableExportsURL)
            }

            try moveProfilePhotoCatalog(
                from: readableExportsURL,
                to: paths.profilePhotosURL(for: record.id)
            )
            try removeDirectoryIfEffectivelyEmpty(readableExportsURL)
            migratedVersions.append(migratedRecord)
        }

        guard changedManifest else { return manifest }
        var migratedManifest = manifest
        migratedManifest.versions = migratedVersions
        try write(migratedManifest, to: paths.manifestURL)
        return migratedManifest
    }

    private static func moveProfilePhotoCatalog(
        from exportsURL: URL,
        to catalogURL: URL
    ) throws {
        let oldCatalogURL = exportsURL.appendingPathComponent(
            "ChatProfilePhotos",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: oldCatalogURL.path) else { return }
        try mergeDirectory(at: oldCatalogURL, into: catalogURL)
    }

    private static func mergeDirectory(at sourceURL: URL, into destinationURL: URL) throws {
        let fileManager = FileManager.default
        var sourceIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &sourceIsDirectory) else {
            return
        }
        guard sourceIsDirectory.boolValue else {
            throw LibraryServiceError.layoutMigrationConflict(sourceURL)
        }

        var destinationIsDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: destinationURL.path, isDirectory: &destinationIsDirectory) {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return
        }
        guard destinationIsDirectory.boolValue else {
            throw LibraryServiceError.layoutMigrationConflict(destinationURL)
        }

        for sourceItemURL in try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let destinationItemURL = destinationURL.appendingPathComponent(
                sourceItemURL.lastPathComponent,
                isDirectory: false
            )
            var itemIsDirectory: ObjCBool = false
            _ = fileManager.fileExists(atPath: sourceItemURL.path, isDirectory: &itemIsDirectory)
            if itemIsDirectory.boolValue {
                try mergeDirectory(at: sourceItemURL, into: destinationItemURL)
            } else if fileManager.fileExists(atPath: destinationItemURL.path) {
                let sourceData = try Data(contentsOf: sourceItemURL)
                let destinationData = try Data(contentsOf: destinationItemURL)
                guard sourceData == destinationData else {
                    throw LibraryServiceError.layoutMigrationConflict(destinationItemURL)
                }
                try fileManager.removeItem(at: sourceItemURL)
            } else {
                try fileManager.moveItem(at: sourceItemURL, to: destinationItemURL)
            }
        }
        try removeDirectoryIfEffectivelyEmpty(sourceURL)
    }

    private static func removeDirectoryIfEffectivelyEmpty(_ directoryURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        let contents = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        let meaningfulContents = contents.filter { $0 != ".DS_Store" }
        guard meaningfulContents.isEmpty else { return }
        try fileManager.removeItem(at: directoryURL)
    }

    private static func makeExportDirectoryName(
        for date: Date,
        excluding existingNames: Set<String>
    ) -> String {
        let baseName = "Copia \(exportDirectoryDateFormatter.string(from: date))"
        guard existingNames.contains(baseName) else { return baseName }

        var suffix = 2
        while existingNames.contains("\(baseName) (\(suffix))") {
            suffix += 1
        }
        return "\(baseName) (\(suffix))"
    }

    private static let exportDirectoryDateFormatter: DateFormatter = {
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

    private static func write(_ manifest: LibraryManifest, to url: URL) throws {
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
