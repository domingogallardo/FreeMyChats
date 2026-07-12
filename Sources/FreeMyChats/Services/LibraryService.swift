import Foundation
import SwiftWABackupAPI

enum LibraryServiceError: Error, LocalizedError {
    case destinationNotEmpty(URL)
    case invalidLibrary(URL)

    var errorDescription: String? {
        switch self {
        case .destinationNotEmpty(let url):
            return "La carpeta \(url.lastPathComponent) no está vacía. Elige una carpeta nueva para crear la biblioteca."
        case .invalidLibrary(let url):
            return "No se ha encontrado una biblioteca de Free My Chats válida en \(url.path)."
        }
    }
}

enum LibraryService {
    static func create(
        from iPhoneBackup: IPhoneBackup,
        at rootURL: URL,
        progress: WABackupProgressHandler? = nil
    ) throws -> LibrarySession {
        let paths = LibraryPaths(rootURL: rootURL)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: paths.rootURL.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: paths.rootURL.path)
            guard contents.isEmpty else {
                throw LibraryServiceError.destinationNotEmpty(paths.rootURL)
            }
        }

        try fileManager.createDirectory(at: paths.rootURL, withIntermediateDirectories: true)
        do {
            try fileManager.createDirectory(at: paths.exportsURL, withIntermediateDirectories: true)
            _ = try iPhoneBackup.extractWhatsAppBackup(to: paths.backupURL, progress: progress)
            return try open(paths: paths, progress: progress)
        } catch {
            try? fileManager.removeItem(at: paths.rootURL)
            throw error
        }
    }

    static func open(
        selectedURL: URL,
        progress: WABackupProgressHandler? = nil
    ) throws -> LibrarySession {
        try open(paths: LibraryPaths.resolvingSelection(selectedURL), progress: progress)
    }

    static func reloadChats(
        in session: LibrarySession,
        progress: WABackupProgressHandler? = nil
    ) throws -> [ChatInfo] {
        try session.reader.getChats(progress: progress)
    }

    private static func open(
        paths: LibraryPaths,
        progress: WABackupProgressHandler?
    ) throws -> LibrarySession {
        let metadataURL = paths.backupURL
            .appendingPathComponent(".wa-backup", isDirectory: true)
            .appendingPathComponent("backup-info.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw LibraryServiceError.invalidLibrary(paths.rootURL)
        }

        try FileManager.default.createDirectory(at: paths.exportsURL, withIntermediateDirectories: true)
        let backup = ExtractedWhatsAppBackup(url: paths.backupURL)
        let info = try backup.getBackupInfo()
        let reader = try backup.openReader(exportRootDirectory: paths.exportsURL)
        let chats = try reader.getChats(progress: progress)
        return LibrarySession(paths: paths, backup: backup, reader: reader, info: info, chats: chats)
    }
}
