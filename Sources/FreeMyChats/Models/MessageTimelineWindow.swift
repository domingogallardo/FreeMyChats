import Foundation
import SwiftWABackupAPI

struct MessageTimelineRow: Identifiable {
    let message: MessageInfo
    let beginsNewDay: Bool

    var id: Int { message.id }
}

/// Keeps the SwiftUI timeline bounded while retaining the full decoded export
/// as its backing store.
struct MessageTimelineWindow {
    private let allMessages: [MessageInfo]
    private let pageSize: Int
    private let maximumVisibleCount: Int
    private(set) var range: Range<Int>
    private(set) var rows: [MessageTimelineRow]

    init(
        messages: [MessageInfo],
        centeredOn messageID: Int?,
        pageSize: Int = 300,
        maximumVisibleCount: Int = 900
    ) {
        let safeMaximum = max(1, maximumVisibleCount)
        self.allMessages = messages
        self.pageSize = min(max(1, pageSize), safeMaximum)
        self.maximumVisibleCount = safeMaximum

        guard !messages.isEmpty else {
            self.range = 0..<0
            self.rows = []
            return
        }

        let initialRange: Range<Int>
        if let messageID,
           let targetIndex = messages.firstIndex(where: { $0.id == messageID }) {
            var lowerBound = max(0, targetIndex - safeMaximum / 2)
            let upperBound = min(messages.count, lowerBound + safeMaximum)
            lowerBound = max(0, upperBound - safeMaximum)
            initialRange = lowerBound..<upperBound
        } else {
            let lowerBound = max(0, messages.count - safeMaximum)
            initialRange = lowerBound..<messages.count
        }
        self.range = initialRange
        self.rows = Self.makeRows(messages: messages, range: initialRange)
    }

    var isEmpty: Bool { range.isEmpty }
    var hasEarlierMessages: Bool { range.lowerBound > allMessages.startIndex }
    var hasLaterMessages: Bool { range.upperBound < allMessages.endIndex }
    var firstMessageID: Int? { rows.first?.id }
    var lastMessageID: Int? { rows.last?.id }

    func contains(messageID: Int) -> Bool {
        rows.contains(where: { $0.id == messageID })
    }

    /// Shifts the fixed-size window earlier and returns an ID that remains in
    /// both windows so the view can preserve its visual anchor.
    mutating func loadEarlier() -> Int? {
        guard hasEarlierMessages, let anchor = firstMessageID else { return nil }

        let lowerBound = max(allMessages.startIndex, range.lowerBound - pageSize)
        let upperBound = min(allMessages.endIndex, lowerBound + maximumVisibleCount)
        range = lowerBound..<upperBound
        rows = Self.makeRows(messages: allMessages, range: range)
        return anchor
    }

    /// Shifts the fixed-size window later and returns an ID that remains in
    /// both windows so the view can preserve its visual anchor.
    mutating func loadLater() -> Int? {
        guard hasLaterMessages, let anchor = lastMessageID else { return nil }

        let upperBound = min(allMessages.endIndex, range.upperBound + pageSize)
        let lowerBound = max(allMessages.startIndex, upperBound - maximumVisibleCount)
        range = lowerBound..<upperBound
        rows = Self.makeRows(messages: allMessages, range: range)
        return anchor
    }

    mutating func moveToBeginning() -> Int? {
        guard let firstMessage = allMessages.first else { return nil }

        let upperBound = min(allMessages.endIndex, allMessages.startIndex + maximumVisibleCount)
        range = allMessages.startIndex..<upperBound
        rows = Self.makeRows(messages: allMessages, range: range)
        return firstMessage.id
    }

    mutating func moveToEnd() -> Int? {
        guard let lastMessage = allMessages.last else { return nil }

        let lowerBound = max(allMessages.startIndex, allMessages.endIndex - maximumVisibleCount)
        range = lowerBound..<allMessages.endIndex
        rows = Self.makeRows(messages: allMessages, range: range)
        return lastMessage.id
    }

    mutating func move(to messageID: Int) -> Int? {
        guard let targetIndex = allMessages.firstIndex(where: { $0.id == messageID }) else {
            return nil
        }

        guard !range.contains(targetIndex) else { return messageID }

        var lowerBound = max(allMessages.startIndex, targetIndex - maximumVisibleCount / 2)
        let upperBound = min(allMessages.endIndex, lowerBound + maximumVisibleCount)
        lowerBound = max(allMessages.startIndex, upperBound - maximumVisibleCount)
        range = lowerBound..<upperBound
        rows = Self.makeRows(messages: allMessages, range: range)
        return messageID
    }

    private static func makeRows(
        messages: [MessageInfo],
        range: Range<Int>
    ) -> [MessageTimelineRow] {
        let calendar = Calendar.autoupdatingCurrent
        return range.map { index in
            let message = messages[index]
            let beginsNewDay = index == range.lowerBound
                || !calendar.isDate(message.date, inSameDayAs: messages[index - 1].date)
            return MessageTimelineRow(message: message, beginsNewDay: beginsNewDay)
        }
    }
}
