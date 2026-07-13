import Foundation

struct ChatReadingPositionStore {
    private static let defaultsKey = "chatReadingPositions.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func messageID(for chat: VersionChatID, in libraryURL: URL) -> Int? {
        positions[positionKey(for: chat, in: libraryURL)]
    }

    func save(messageID: Int, for chat: VersionChatID, in libraryURL: URL) {
        var updatedPositions = positions
        updatedPositions[positionKey(for: chat, in: libraryURL)] = messageID
        defaults.set(updatedPositions, forKey: Self.defaultsKey)
    }

    private var positions: [String: Int] {
        defaults.dictionary(forKey: Self.defaultsKey)?.compactMapValues { value in
            (value as? NSNumber)?.intValue
        } ?? [:]
    }

    private func positionKey(for chat: VersionChatID, in libraryURL: URL) -> String {
        [
            libraryURL.standardizedFileURL.path,
            chat.versionID,
            String(chat.chatID)
        ].joined(separator: "\u{1F}")
    }
}
