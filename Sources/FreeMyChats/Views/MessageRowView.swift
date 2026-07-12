import AppKit
import SwiftUI
import SwiftWABackupAPI

struct MessageRowView: View {
    let message: MessageInfo
    let mediaDirectoryURL: URL

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isFromMe { Spacer(minLength: 80) }
            bubble
            if !message.isFromMe { Spacer(minLength: 80) }
        }
        .frame(maxWidth: .infinity)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !message.isFromMe, let author = message.author?.displayName {
                Text(author)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }

            if let replyTo = message.replyTo {
                Label("Respuesta al mensaje \(replyTo)", systemImage: "arrowshape.turn.up.left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
            }

            if let text = message.message, !text.isEmpty {
                Text(text)
                    .textSelection(.enabled)
            }

            if let mediaURL {
                MediaAttachmentView(
                    url: mediaURL,
                    filename: message.mediaFilename ?? mediaURL.lastPathComponent,
                    messageType: message.messageType,
                    seconds: message.seconds
                )
            }

            if let caption = message.caption, !caption.isEmpty, caption != message.message {
                Text(caption)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let latitude = message.latitude, let longitude = message.longitude {
                Button {
                    WorkspaceService.openMap(latitude: latitude, longitude: longitude)
                } label: {
                    Label("Abrir ubicación", systemImage: "map")
                }
                .buttonStyle(.borderless)
            }

            if message.message == nil, mediaURL == nil, message.latitude == nil {
                Label(message.messageType, systemImage: iconForMessageType)
                    .foregroundStyle(.secondary)
            }

            if let error = message.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if let reactions = message.reactions, !reactions.isEmpty {
                    Text(reactions.map(\.emoji).joined(separator: " "))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                }
                Spacer(minLength: 8)
                Text(Self.timeFormatter.string(from: message.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            message.isFromMe ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 11)
        )
    }

    private var mediaURL: URL? {
        guard let filename = message.mediaFilename else { return nil }
        let url = mediaDirectoryURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var iconForMessageType: String {
        switch message.messageType.lowercased() {
        case "image": return "photo"
        case "video": return "video"
        case "audio": return "waveform"
        case "document": return "doc"
        case "location": return "mappin.and.ellipse"
        case "contact": return "person.crop.circle"
        case "sticker", "gif": return "sparkles"
        default: return "bubble.left"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct MediaAttachmentView: View {
    let url: URL
    let filename: String
    let messageType: String
    let seconds: Int?

    var body: some View {
        if isImage, let image = NSImage(contentsOf: url) {
            Button {
                WorkspaceService.open(url)
            } label: {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Abrir \(filename)")
        } else {
            Button {
                WorkspaceService.open(url)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: attachmentIcon)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(attachmentDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundStyle(.secondary)
                }
                .padding(9)
                .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
    }

    private var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "heic", "thumb"]
            .contains(url.pathExtension.lowercased())
    }

    private var attachmentIcon: String {
        switch messageType.lowercased() {
        case "video": return "video.fill"
        case "audio": return "waveform"
        case "document": return "doc.fill"
        default: return "paperclip"
        }
    }

    private var attachmentDetail: String {
        if let seconds {
            return "\(messageType) · \(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))"
        }
        return messageType
    }
}
