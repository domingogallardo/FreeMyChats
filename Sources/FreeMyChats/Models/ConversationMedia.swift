import Foundation
import SwiftWABackupAPI

enum VisualMediaKind: String, CaseIterable {
    case image
    case video
}

enum MediaAttachmentPresentation {
    private static let videoExtensions: Set<String> = [
        "3gp", "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm"
    ]
    private static let imageExtensions: Set<String> = [
        "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "thumb", "tif", "tiff", "webp"
    ]
    private static let imageMessageTypes: Set<String> = [
        "gif", "image", "photo", "sticker"
    ]

    static func visualMediaKind(messageType: String, url: URL) -> VisualMediaKind? {
        let normalizedType = messageType.lowercased()
        let fileExtension = url.pathExtension.lowercased()

        if normalizedType == "video" || videoExtensions.contains(fileExtension) {
            return .video
        }
        if imageMessageTypes.contains(normalizedType)
            || imageExtensions.contains(fileExtension) {
            return .image
        }
        return nil
    }

    static func shouldUseVideoPlayer(messageType: String, url: URL) -> Bool {
        visualMediaKind(messageType: messageType, url: url) == .video
    }

    static func shouldUseImagePreview(messageType: String, url: URL) -> Bool {
        visualMediaKind(messageType: messageType, url: url) == .image
    }

    static func shouldLoopVideo(messageType: String) -> Bool {
        messageType.caseInsensitiveCompare("gif") == .orderedSame
    }
}

struct ConversationMediaItem: Identifiable, Equatable {
    let id: Int
    let kind: VisualMediaKind
    let url: URL
    let filename: String
    let date: Date
    let caption: String?
    let authorName: String?
    let isFromMe: Bool
    let messageType: String
    let expectedDuration: Int?

    static func items(in conversation: ArchivedConversation) -> [ConversationMediaItem] {
        items(
            messages: conversation.document.messages,
            mediaDirectoryURL: conversation.mediaDirectoryURL
        )
    }

    static func items(
        messages: [MessageInfo],
        mediaDirectoryURL: URL
    ) -> [ConversationMediaItem] {
        messages
            .reversed()
            .compactMap { message in
                guard let filename = message.mediaFilename else { return nil }
                let url = mediaDirectoryURL.appendingPathComponent(filename)
                guard let kind = MediaAttachmentPresentation.visualMediaKind(
                    messageType: message.messageType,
                    url: url
                ) else {
                    return nil
                }

                return ConversationMediaItem(
                    id: message.id,
                    kind: kind,
                    url: url,
                    filename: filename,
                    date: message.date,
                    caption: normalizedCaption(for: message),
                    authorName: message.author?.displayName,
                    isFromMe: message.isFromMe,
                    messageType: message.messageType,
                    expectedDuration: message.seconds
                )
            }
    }

    private static func normalizedCaption(for message: MessageInfo) -> String? {
        [message.caption, message.message]
            .compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { !$0.isEmpty }
    }
}
