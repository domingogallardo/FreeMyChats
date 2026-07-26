import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class AppProgressUpdateCoalescerTests: XCTestCase {
    func testBurstKeepsOnlyLatestUpdateAndSchedulesOneDelivery() throws {
        let coalescer = AppProgressUpdateCoalescer()
        let operationID = UUID()
        var scheduledDeliveries = 0

        for index in 0..<100_000 {
            let shouldSchedule = coalescer.submit(
                AppProgressUpdateCoalescer.Update(
                    progress: WABackupProgress(
                        phase: .canonicalizingConversationMessages,
                        completedUnitCount: index,
                        totalUnitCount: 100_000,
                        unit: .messages
                    ),
                    operationID: operationID,
                    fallbackTitle: "Exportando"
                )
            )
            if shouldSchedule {
                scheduledDeliveries += 1
            }
        }

        XCTAssertEqual(scheduledDeliveries, 1)
        let latest = try XCTUnwrap(coalescer.takeLatest())
        XCTAssertEqual(latest.progress.completedUnitCount, 99_999)
        XCTAssertEqual(latest.operationID, operationID)
        XCTAssertTrue(
            coalescer.submit(
                AppProgressUpdateCoalescer.Update(
                    progress: WABackupProgress(
                        phase: .completed,
                        completedUnitCount: 1,
                        totalUnitCount: 1,
                        unit: .phases
                    ),
                    operationID: operationID,
                    fallbackTitle: "Exportando"
                )
            )
        )
    }
}
