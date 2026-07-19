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

    static func nearestMatchIndex(
        in matches: [MessageInfo],
        among messages: [MessageInfo],
        to anchorMessageID: Int?
    ) -> Int? {
        guard !matches.isEmpty else { return nil }
        guard let anchorMessageID,
              let anchorIndex = messages.firstIndex(where: { $0.id == anchorMessageID }) else {
            return matches.startIndex
        }

        var closestMatchIndex = matches.startIndex
        var closestDistance = Int.max
        var matchIndex = matches.startIndex

        for (messageIndex, message) in messages.enumerated() {
            guard matchIndex < matches.endIndex else { break }
            guard message.id == matches[matchIndex].id else { continue }

            let distance = abs(messageIndex - anchorIndex)
            if distance < closestDistance {
                closestMatchIndex = matchIndex
                closestDistance = distance
            }
            matchIndex = matches.index(after: matchIndex)
        }

        return closestMatchIndex
    }
}

enum MessageSearchDirection: Equatable {
    case previous
    case next
}

struct MessageSearchNavigator {
    private let messageIDs: [Int]
    private(set) var selectedIndex: Int?

    init(messageIDs: [Int], selectedIndex: Int? = nil) {
        self.messageIDs = messageIDs
        guard !messageIDs.isEmpty else {
            self.selectedIndex = nil
            return
        }

        if let selectedIndex, messageIDs.indices.contains(selectedIndex) {
            self.selectedIndex = selectedIndex
        } else {
            self.selectedIndex = messageIDs.startIndex
        }
    }

    var resultCount: Int { messageIDs.count }
    var selectedResultNumber: Int? { selectedIndex.map { $0 + 1 } }

    var selectedMessageID: Int? {
        selectedIndex.map { messageIDs[$0] }
    }

    var canMoveToPrevious: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > messageIDs.startIndex
    }

    var canMoveToNext: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex < messageIDs.index(before: messageIDs.endIndex)
    }

    mutating func move(_ direction: MessageSearchDirection) -> Int? {
        guard let selectedIndex else { return nil }

        let targetIndex: Int
        switch direction {
        case .previous:
            guard canMoveToPrevious else { return nil }
            targetIndex = messageIDs.index(before: selectedIndex)
        case .next:
            guard canMoveToNext else { return nil }
            targetIndex = messageIDs.index(after: selectedIndex)
        }

        self.selectedIndex = targetIndex
        return messageIDs[targetIndex]
    }
}
