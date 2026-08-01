import Foundation
import SwiftWABackupAPI

enum ProfilePhotoResolver {
    static func photoURL(
        for chat: ChatInfo,
        in version: LibraryVersionSession,
        paths: LibraryPaths
    ) -> URL? {
        guard let filename = chat.photoFilename else { return nil }
        let catalogURL = paths
            .profilePhotosURL(for: version.id)
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            return catalogURL
        }

        let storedChatURL = version.storedChatsURL
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(String(chat.id), isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: storedChatURL.path) ? storedChatURL : nil
    }

    static func photoURL(
        for item: ConversationCatalogItem,
        in session: LibrarySession
    ) -> URL? {
        var sources = item.contributionSources
        if let preferredSource = item.preferredPhotoSource,
           let index = sources.firstIndex(of: preferredSource) {
            sources.remove(at: index)
            sources.insert(preferredSource, at: 0)
        }

        for source in sources {
            guard let version = session.version(id: source.versionID),
                  let chat = version.chats.first(where: { $0.id == source.chatID }),
                  let photoURL = photoURL(for: chat, in: version, paths: session.paths) else {
                continue
            }
            return photoURL
        }
        return item.photoURL
    }
}
