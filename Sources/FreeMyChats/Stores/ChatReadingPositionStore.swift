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

    func remove(chat: VersionChatID, in libraryURL: URL) {
        var updatedPositions = positions
        updatedPositions.removeValue(forKey: positionKey(for: chat, in: libraryURL))
        defaults.set(updatedPositions, forKey: Self.defaultsKey)
    }

    func remove(versionID: String, in libraryURL: URL) {
        let prefix = [
            libraryURL.standardizedFileURL.path,
            versionID,
            ""
        ].joined(separator: "\u{1F}")
        let updatedPositions = positions.filter { !$0.key.hasPrefix(prefix) }
        defaults.set(updatedPositions, forKey: Self.defaultsKey)
    }

    func messageID(for conversation: ConversationArchiveID, in libraryURL: URL) -> Int? {
        positions[conversationPositionKey(for: conversation, in: libraryURL)]
    }

    func save(
        messageID: Int,
        for conversation: ConversationArchiveID,
        in libraryURL: URL
    ) {
        var updatedPositions = positions
        updatedPositions[conversationPositionKey(for: conversation, in: libraryURL)] = messageID
        defaults.set(updatedPositions, forKey: Self.defaultsKey)
    }

    func remove(conversation: ConversationArchiveID, in libraryURL: URL) {
        var updatedPositions = positions
        updatedPositions.removeValue(
            forKey: conversationPositionKey(for: conversation, in: libraryURL)
        )
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

    private func conversationPositionKey(
        for conversation: ConversationArchiveID,
        in libraryURL: URL
    ) -> String {
        [
            libraryURL.standardizedFileURL.path,
            "conversation",
            conversation.rawValue
        ].joined(separator: "\u{1F}")
    }
}
