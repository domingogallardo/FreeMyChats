import Foundation
import SwiftWABackupAPI

enum LibraryServiceError: Error, LocalizedError {
    case destinationNotEmpty(URL)
    case invalidLibrary(URL)
    case unsupportedSchema(Int)
    case duplicateBackup
    case sourceAlreadyDeleted

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
        let exportURL = session.paths.exportURL(for: id)
        let fileManager = FileManager.default
        var manifestWasUpdated = false

        do {
            try fileManager.createDirectory(at: exportURL, withIntermediateDirectories: true)
            let extracted = try iPhoneBackup.extractWhatsAppBackup(to: backupURL, progress: progress)
            let info = try extracted.getBackupInfo()
            var manifest = session.manifest
            manifest.versions.append(
                LibraryVersionRecord(
                    id: id,
                    sourceBackupIdentifier: info.source.iPhoneBackupIdentifier,
                    sourceBackupCreationDate: info.source.iPhoneBackupCreationDate,
                    importedAt: Date()
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
            try? fileManager.removeItem(at: exportURL)
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

    private static func open(
        paths: LibraryPaths,
        progress: WABackupProgressHandler? = nil
    ) throws -> LibrarySession {
        guard FileManager.default.fileExists(atPath: paths.manifestURL.path) else {
            throw LibraryServiceError.invalidLibrary(paths.rootURL)
        }

        let manifest = try readManifest(at: paths.manifestURL)
        guard manifest.schemaVersion == LibraryManifest.currentSchemaVersion else {
            throw LibraryServiceError.unsupportedSchema(manifest.schemaVersion)
        }

        try FileManager.default.createDirectory(at: paths.sourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.exportsURL, withIntermediateDirectories: true)

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
        let exportsURL = paths.exportURL(for: record.id)
        try FileManager.default.createDirectory(at: exportsURL, withIntermediateDirectories: true)

        let metadataURL = backupURL
            .appendingPathComponent(".wa-backup", isDirectory: true)
            .appendingPathComponent("backup-info.json")

        if FileManager.default.fileExists(atPath: metadataURL.path) {
            let backup = ExtractedWhatsAppBackup(url: backupURL)
            _ = try backup.getBackupInfo()
            let reader = try backup.openReader(exportRootDirectory: exportsURL)
            let chats = try reader.getChats(progress: progress)
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
        let chats = try exportStore.listExportedChats().map {
            try exportStore.openChat(chatId: $0.chatId).document.chat
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
        let newBackupURL = paths.backupURL(for: id)
        let newExportsURL = paths.exportURL(for: id)
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
            } else {
                try fileManager.createDirectory(at: newExportsURL, withIntermediateDirectories: true)
            }

            let record = LibraryVersionRecord(
                id: id,
                sourceBackupIdentifier: info.source.iPhoneBackupIdentifier,
                sourceBackupCreationDate: info.source.iPhoneBackupCreationDate,
                importedAt: Date()
            )
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
