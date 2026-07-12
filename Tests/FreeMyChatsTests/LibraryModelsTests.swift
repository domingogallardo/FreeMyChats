import Foundation
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class LibraryModelsTests: XCTestCase {
    func testLibraryPathsUseBackupAndExportsSiblings() {
        let root = URL(fileURLWithPath: "/tmp/My Library", isDirectory: true)
        let paths = LibraryPaths(rootURL: root)

        XCTAssertEqual(paths.rootURL.path, "/tmp/My Library")
        XCTAssertEqual(paths.backupURL.path, "/tmp/My Library/Backup")
        XCTAssertEqual(paths.exportsURL.path, "/tmp/My Library/Exports")
    }

    func testResolvingBackupSelectionReturnsLibraryRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backup = root.appendingPathComponent("Backup", isDirectory: true)
        let metadataDirectory = backup.appendingPathComponent(".wa-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: metadataDirectory.appendingPathComponent("backup-info.json"))
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LibraryPaths.resolvingSelection(backup)

        XCTAssertEqual(paths.rootURL, root.standardizedFileURL)
        XCTAssertEqual(paths.backupURL, backup.standardizedFileURL)
    }

    func testExportDisplayStatePreservesUnavailableAndInvalidStates() {
        XCTAssertEqual(ChatExportDisplayState(.notExported), .notExported)
        XCTAssertEqual(ChatExportDisplayState(.invalid(reason: "broken")), .invalid("broken"))
        XCTAssertFalse(ChatExportDisplayState.notExported.isPhysicallyExported)
        XCTAssertTrue(ChatExportDisplayState.invalid("broken").isPhysicallyExported)
    }
}
