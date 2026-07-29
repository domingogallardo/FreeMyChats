import Foundation
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class MessageDateNavigationTests: XCTestCase {
    func testFindsFirstMessageOnSelectedDay() throws {
        let messages = try [
            decodeMessage(id: 1, date: "2026-07-20T22:00:00Z"),
            decodeMessage(id: 2, date: "2026-07-21T08:00:00Z"),
            decodeMessage(id: 3, date: "2026-07-21T18:00:00Z"),
            decodeMessage(id: 4, date: "2026-07-23T09:00:00Z")
        ]

        let target = try XCTUnwrap(
            MessageDateNavigation.target(
                closestTo: try date("2026-07-21T12:00:00Z"),
                in: messages,
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(target.messageID, 2)
        XCTAssertEqual(target.date, try date("2026-07-21T00:00:00Z"))
        XCTAssertTrue(target.isExactDate)
    }

    func testChoosesNearestPastDayWhenItIsCloser() throws {
        let messages = try [
            decodeMessage(id: 1, date: "2026-07-20T22:00:00Z"),
            decodeMessage(id: 2, date: "2026-07-23T09:00:00Z")
        ]

        let target = try XCTUnwrap(
            MessageDateNavigation.target(
                closestTo: try date("2026-07-21T12:00:00Z"),
                in: messages,
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(target.messageID, 1)
        XCTAssertEqual(target.date, try date("2026-07-20T00:00:00Z"))
        XCTAssertFalse(target.isExactDate)
    }

    func testChoosesNearestFutureDayWhenItIsCloser() throws {
        let messages = try [
            decodeMessage(id: 1, date: "2026-07-20T22:00:00Z"),
            decodeMessage(id: 2, date: "2026-07-23T09:00:00Z")
        ]

        let target = try XCTUnwrap(
            MessageDateNavigation.target(
                closestTo: try date("2026-07-22T12:00:00Z"),
                in: messages,
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(target.messageID, 2)
        XCTAssertEqual(target.date, try date("2026-07-23T00:00:00Z"))
        XCTAssertFalse(target.isExactDate)
    }

    func testPrefersPastDayWhenDistancesAreEqual() throws {
        let messages = try [
            decodeMessage(id: 1, date: "2026-07-20T08:00:00Z"),
            decodeMessage(id: 2, date: "2026-07-20T22:00:00Z"),
            decodeMessage(id: 3, date: "2026-07-24T09:00:00Z")
        ]

        let target = try XCTUnwrap(
            MessageDateNavigation.target(
                closestTo: try date("2026-07-22T12:00:00Z"),
                in: messages,
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(target.messageID, 1)
        XCTAssertEqual(target.date, try date("2026-07-20T00:00:00Z"))
        XCTAssertFalse(target.isExactDate)
    }

    func testUsesOnlyAvailableSideOutsideTheMessageRange() throws {
        let messages = try [
            decodeMessage(id: 1, date: "2026-07-20T08:00:00Z"),
            decodeMessage(id: 2, date: "2026-07-23T09:00:00Z"),
            decodeMessage(id: 3, date: "2026-07-23T18:00:00Z")
        ]

        let beforeTarget = try XCTUnwrap(
            MessageDateNavigation.target(
                closestTo: try date("2026-07-18T12:00:00Z"),
                in: messages,
                calendar: utcCalendar
            )
        )
        let afterTarget = try XCTUnwrap(
            MessageDateNavigation.target(
                closestTo: try date("2026-07-25T12:00:00Z"),
                in: messages,
                calendar: utcCalendar
            )
        )

        XCTAssertEqual(beforeTarget.messageID, 1)
        XCTAssertEqual(afterTarget.messageID, 2)
    }

    func testDateRangeUsesTheFirstAndLastConversationDays() throws {
        let messages = try [
            decodeMessage(id: 1, date: "2026-07-20T22:00:00Z"),
            decodeMessage(id: 2, date: "2026-07-23T09:00:00Z")
        ]

        let range = try XCTUnwrap(
            MessageDateNavigation.dateRange(in: messages, calendar: utcCalendar)
        )

        XCTAssertEqual(range.lowerBound, try date("2026-07-20T00:00:00Z"))
        XCTAssertEqual(range.upperBound, try date("2026-07-23T00:00:00Z"))
    }

    func testChangingMonthAndYearPreservesAValidDay() throws {
        let range = try date("2012-12-20T00:00:00Z")...date("2026-07-26T00:00:00Z")

        let selectedDate = MessageDateNavigation.date(
            bySelectingYear: 2018,
            month: 3,
            preservingDayFrom: try date("2026-07-26T00:00:00Z"),
            within: range,
            calendar: utcCalendar
        )

        XCTAssertEqual(selectedDate, try date("2018-03-26T00:00:00Z"))
    }

    func testChangingToShorterMonthAdjustsTheDay() throws {
        let range = try date("2012-01-01T00:00:00Z")...date("2026-12-31T00:00:00Z")

        let selectedDate = MessageDateNavigation.date(
            bySelectingYear: 2025,
            month: 2,
            preservingDayFrom: try date("2026-01-31T00:00:00Z"),
            within: range,
            calendar: utcCalendar
        )

        XCTAssertEqual(selectedDate, try date("2025-02-28T00:00:00Z"))
    }

    func testChangingYearClampsSelectionToConversationRange() throws {
        let range = try date("2012-12-20T00:00:00Z")...date("2026-07-26T00:00:00Z")

        let selectedDate = MessageDateNavigation.date(
            bySelectingYear: 2012,
            month: 7,
            preservingDayFrom: try date("2026-07-26T00:00:00Z"),
            within: range,
            calendar: utcCalendar
        )

        XCTAssertEqual(selectedDate, range.lowerBound)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }

    private func decodeMessage(id: Int, date: String) throws -> MessageInfo {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "id": id,
                "chatId": 44,
                "date": date,
                "isFromMe": false,
                "messageType": "text",
                "message": "Mensaje \(id)"
            ]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MessageInfo.self, from: data)
    }
}
