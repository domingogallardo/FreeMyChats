import Foundation
import XCTest
@testable import FreeMyChats

final class VideoPlayerTests: XCTestCase {
    func testGIFBackedByMP4UsesVideoPlayer() {
        XCTAssertTrue(
            MediaAttachmentPresentation.shouldUseVideoPlayer(
                messageType: "GIF",
                url: URL(fileURLWithPath: "/tmp/animation.mp4")
            )
        )
    }

    func testImageGIFDoesNotUseVideoPlayer() {
        XCTAssertFalse(
            MediaAttachmentPresentation.shouldUseVideoPlayer(
                messageType: "GIF",
                url: URL(fileURLWithPath: "/tmp/animation.gif")
            )
        )
    }

    func testOnlyGIFVideosLoop() {
        XCTAssertTrue(
            MediaAttachmentPresentation.shouldLoopVideo(messageType: "GIF")
        )
        XCTAssertFalse(
            MediaAttachmentPresentation.shouldLoopVideo(messageType: "Video")
        )
    }

    @MainActor
    func testPlaybackControllerReportsMissingVideo() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let controller = VideoPlaybackController(url: missingURL)

        XCTAssertFalse(controller.canPlay)
        XCTAssertNil(controller.player)
        XCTAssertEqual(controller.errorMessage, "No se encuentra el archivo de vídeo.")

        controller.play()

        XCTAssertNil(controller.player)
    }

    func testThumbnailCacheReturnsNilForMissingVideo() async {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let thumbnail = await VideoThumbnailCache.shared.thumbnail(for: missingURL)

        XCTAssertNil(thumbnail)
    }
}
