import Foundation
import SwiftWABackupAPI

enum MessageDateNavigation {
    struct Target: Equatable {
        let messageID: Int
        let date: Date
        let isExactDate: Bool
    }

    static func dateRange(
        in messages: [MessageInfo],
        calendar: Calendar = .autoupdatingCurrent
    ) -> ClosedRange<Date>? {
        guard let firstDate = messages.first?.date,
              let lastDate = messages.last?.date else {
            return nil
        }

        return calendar.startOfDay(for: firstDate)...calendar.startOfDay(for: lastDate)
    }

    static func target(
        closestTo date: Date,
        in messages: [MessageInfo],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Target? {
        guard !messages.isEmpty else { return nil }

        let selectedDay = calendar.startOfDay(for: date)
        let nextMessageIndex = lowerBoundIndex(
            onOrAfter: selectedDay,
            in: messages
        )

        if messages.indices.contains(nextMessageIndex),
           calendar.isDate(messages[nextMessageIndex].date, inSameDayAs: selectedDay) {
            return Target(
                messageID: messages[nextMessageIndex].id,
                date: selectedDay,
                isExactDate: true
            )
        }

        let futureTarget = messages.indices.contains(nextMessageIndex)
            ? Target(
                messageID: messages[nextMessageIndex].id,
                date: calendar.startOfDay(for: messages[nextMessageIndex].date),
                isExactDate: false
            )
            : nil

        let pastTarget: Target?
        if nextMessageIndex > messages.startIndex {
            let previousMessage = messages[nextMessageIndex - 1]
            let previousDay = calendar.startOfDay(for: previousMessage.date)
            let firstPreviousMessageIndex = lowerBoundIndex(
                onOrAfter: previousDay,
                in: messages
            )
            pastTarget = Target(
                messageID: messages[firstPreviousMessageIndex].id,
                date: previousDay,
                isExactDate: false
            )
        } else {
            pastTarget = nil
        }

        switch (pastTarget, futureTarget) {
        case let (past?, future?):
            let pastDistance = calendar.dateComponents(
                [.day],
                from: past.date,
                to: selectedDay
            ).day ?? .max
            let futureDistance = calendar.dateComponents(
                [.day],
                from: selectedDay,
                to: future.date
            ).day ?? .max
            return pastDistance <= futureDistance ? past : future
        case let (past?, nil):
            return past
        case let (nil, future?):
            return future
        case (nil, nil):
            return nil
        }
    }

    static func date(
        bySelectingYear year: Int,
        month: Int,
        preservingDayFrom selectedDate: Date,
        within dateRange: ClosedRange<Date>,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let days = calendar.range(
            of: .day,
            in: .month,
            for: calendar.date(
                from: DateComponents(year: year, month: month, day: 1)
            ) ?? selectedDate
        ) else {
            return nil
        }

        let preservedDay = calendar.component(.day, from: selectedDate)
        let components = DateComponents(
            year: year,
            month: month,
            day: min(preservedDay, days.count)
        )
        guard let candidate = calendar.date(from: components) else {
            return nil
        }

        return min(max(calendar.startOfDay(for: candidate), dateRange.lowerBound), dateRange.upperBound)
    }

    private static func lowerBoundIndex(
        onOrAfter date: Date,
        in messages: [MessageInfo]
    ) -> Int {
        var lowerBound = messages.startIndex
        var upperBound = messages.endIndex

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if messages[middle].date < date {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return lowerBound
    }
}
