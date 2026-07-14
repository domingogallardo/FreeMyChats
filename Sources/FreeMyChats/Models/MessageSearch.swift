import Foundation
import SwiftWABackupAPI

enum MessageSearch {
    static func filter(_ messages: [MessageInfo], query: String) -> [MessageInfo] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return messages }

        return messages.filter { message in
            [
                message.message,
                message.caption,
                message.replyToPreview,
                message.author?.displayName,
                message.mediaFilename
            ]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
        }
    }
}
