import AppKit
import SwiftUI
import SwiftWABackupAPI

struct MessageRowView: View {
    let message: MessageInfo
    let mediaDirectoryURL: URL
    let isHighlighted: Bool
    let navigateToReply: (Int) -> Void

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
                Button {
                    navigateToReply(replyTo)
                } label: {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.left")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Respuesta al mensaje \(replyTo)")
                            if let preview = message.replyToPreview, !preview.isEmpty {
                                Text(preview)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Ir al mensaje original")
                .accessibilityLabel(replyAccessibilityLabel(replyTo: replyTo))
                .accessibilityHint("Mueve la conversación al mensaje original")
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
                    Task { @MainActor in
                        WorkspaceService.openMap(latitude: latitude, longitude: longitude)
                    }
                } label: {
                    Label("Abrir ubicación", systemImage: "map")
                }
                .buttonStyle(.borderless)
                .help("Abrir esta ubicación en Mapas")
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
                if !reactionGroups.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(reactionGroups) { group in
                            MessageReactionButton(group: group)
                        }
                    }
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
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(
                    Color.accentColor.opacity(isHighlighted ? 0.95 : 0),
                    lineWidth: isHighlighted ? 3 : 0
                )
        }
        .shadow(
            color: Color.accentColor.opacity(isHighlighted ? 0.45 : 0),
            radius: isHighlighted ? 10 : 0
        )
        .scaleEffect(isHighlighted ? 1.015 : 1)
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }

    private var mediaURL: URL? {
        message.mediaFilename.map { mediaDirectoryURL.appendingPathComponent($0) }
    }

    private var reactionGroups: [MessageReactionGroup] {
        MessageReactionGroup.grouped(message.reactions ?? [])
    }

    private func replyAccessibilityLabel(replyTo: Int) -> String {
        guard let preview = message.replyToPreview, !preview.isEmpty else {
            return "Respuesta al mensaje \(replyTo)"
        }
        return "Respuesta al mensaje \(replyTo): \(preview)"
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

private struct MessageReactionButton: View {
    let group: MessageReactionGroup

    @State private var isShowingAuthors = false

    var body: some View {
        Button {
            isShowingAuthors.toggle()
        } label: {
            HStack(spacing: 3) {
                Text(group.emoji)
                if group.authors.count > 1 {
                    Text(group.authors.count.formatted())
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Capsule())
            .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Mostrar quién reaccionó con \(group.emoji)")
        .accessibilityLabel("\(group.emoji), \(reactionCountLabel)")
        .accessibilityHint("Muestra las personas que reaccionaron")
        .popover(isPresented: $isShowingAuthors) {
            reactionAuthorsPopover
        }
    }

    private var reactionAuthorsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(group.emoji) \(reactionCountLabel)")
                .font(.headline)

            Divider()

            ForEach(group.authors) { author in
                Label(
                    author.displayName,
                    systemImage: author.isCurrentUser
                        ? "person.crop.circle.fill"
                        : "person.crop.circle"
                )
            }
        }
        .textSelection(.enabled)
        .padding(12)
        .frame(minWidth: 220, alignment: .leading)
    }

    private var reactionCountLabel: String {
        group.authors.count == 1
            ? "1 reacción"
            : "\(group.authors.count.formatted()) reacciones"
    }
}

private struct MediaAttachmentView: View {
    let url: URL
    let filename: String
    let messageType: String
    let seconds: Int?

    var body: some View {
        if isAudio {
            AudioPlayerView(
                url: url,
                filename: filename,
                expectedDuration: seconds
            )
        } else if isImage {
            Button {
                WorkspaceService.open(url)
            } label: {
                MediaThumbnailView(url: url)
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
            .help("Abrir \(filename)")
        }
    }

    private var isImage: Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "heic", "thumb"]
            .contains(url.pathExtension.lowercased())
    }

    private var isAudio: Bool {
        messageType.caseInsensitiveCompare("audio") == .orderedSame
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

private struct MediaThumbnailView: View {
    let url: URL

    @State private var image: NSImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if didFail {
                Label("No se pudo mostrar la imagen", systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 280, height: 120)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 280, height: 120)
            }
        }
        .frame(maxWidth: 420, maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .task(id: url) {
            let loadedImage = await ImageThumbnailCache.shared.thumbnail(for: url)
            guard !Task.isCancelled else { return }
            image = loadedImage
            didFail = loadedImage == nil
        }
    }
}
