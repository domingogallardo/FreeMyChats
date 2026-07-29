import Foundation
import SwiftWABackupAPI
import XCTest
@testable import FreeMyChats

final class ConversationMediaTests: XCTestCase {
    func testBuildsNewestFirstGalleryAndExcludesNonVisualMessages() throws {
        let messages = try [
            decodeMessage(
                id: 1,
                date: "2026-07-20T10:00:00Z",
                messageType: "image",
                mediaFilename: "photo.jpg",
                caption: "  Un día estupendo  "
            ),
            decodeMessage(
                id: 2,
                date: "2026-07-21T10:00:00Z",
                messageType: "video",
                mediaFilename: "clip.mp4",
                seconds: 42
            ),
            decodeMessage(
                id: 3,
                date: "2026-07-22T10:00:00Z",
                messageType: "audio",
                mediaFilename: "note.opus"
            )
        ]
        let mediaDirectory = URL(fileURLWithPath: "/tmp/Media", isDirectory: true)

        let items = ConversationMediaItem.items(
            messages: messages,
            mediaDirectoryURL: mediaDirectory
        )

        XCTAssertEqual(items.map(\.id), [2, 1])
        XCTAssertEqual(items.map(\.kind), [.video, .image])
        XCTAssertEqual(items.first?.expectedDuration, 42)
        XCTAssertEqual(items.last?.caption, "Un día estupendo")
        XCTAssertEqual(items.last?.url, mediaDirectory.appendingPathComponent("photo.jpg"))
    }

    func testRecognizesImagesByTypeAndCommonExtensions() {
        XCTAssertEqual(
            MediaAttachmentPresentation.visualMediaKind(
                messageType: "image",
                url: URL(fileURLWithPath: "/tmp/media-without-extension")
            ),
            .image
        )
        XCTAssertEqual(
            MediaAttachmentPresentation.visualMediaKind(
                messageType: "unknown",
                url: URL(fileURLWithPath: "/tmp/photo.HEIF")
            ),
            .image
        )
        XCTAssertEqual(
            MediaAttachmentPresentation.visualMediaKind(
                messageType: "GIF",
                url: URL(fileURLWithPath: "/tmp/animation.gif")
            ),
            .image
        )
    }

    func testRecognizesVideosByTypeAndCommonExtensions() {
        XCTAssertEqual(
            MediaAttachmentPresentation.visualMediaKind(
                messageType: "video",
                url: URL(fileURLWithPath: "/tmp/media-without-extension")
            ),
            .video
        )
        XCTAssertEqual(
            MediaAttachmentPresentation.visualMediaKind(
                messageType: "unknown",
                url: URL(fileURLWithPath: "/tmp/clip.WEBM")
            ),
            .video
        )
        XCTAssertEqual(
            MediaAttachmentPresentation.visualMediaKind(
                messageType: "GIF",
                url: URL(fileURLWithPath: "/tmp/animation.mp4")
            ),
            .video
        )
    }

    func testExcludesNonVisualAttachments() {
        XCTAssertNil(
            MediaAttachmentPresentation.visualMediaKind(
                messageType: "audio",
                url: URL(fileURLWithPath: "/tmp/note.opus")
            )
        )
        XCTAssertNil(
            MediaAttachmentPresentation.visualMediaKind(
                messageType: "document",
                url: URL(fileURLWithPath: "/tmp/report.pdf")
            )
        )
    }

    private func decodeMessage(
        id: Int,
        date: String,
        messageType: String,
        mediaFilename: String,
        caption: String? = nil,
        seconds: Int? = nil
    ) throws -> MessageInfo {
        var object: [String: Any] = [
            "id": id,
            "chatId": 44,
            "date": date,
            "isFromMe": false,
            "messageType": messageType,
            "mediaFilename": mediaFilename
        ]
        object["caption"] = caption
        object["seconds"] = seconds

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MessageInfo.self, from: data)
    }
}
