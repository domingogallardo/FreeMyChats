import AVKit
import SwiftUI

struct VideoPlayerView: View {
    let filename: String
    let expectedDuration: Int?

    @StateObject private var playback: VideoPlaybackController
    @State private var thumbnail: NSImage?
    @State private var didFinishLoadingThumbnail = false

    init(
        url: URL,
        filename: String,
        expectedDuration: Int?,
        isLooping: Bool
    ) {
        self.filename = filename
        self.expectedDuration = expectedDuration
        _playback = StateObject(
            wrappedValue: VideoPlaybackController(
                url: url,
                isLooping: isLooping
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            playerSurface

            HStack(spacing: 7) {
                Text(filename)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let expectedDuration {
                    Text("·")
                    Text(AudioTimeFormatter.string(from: TimeInterval(expectedDuration)))
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                Button {
                    WorkspaceService.open(playback.url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Abrir \(filename) en otra aplicación")
                .accessibilityLabel("Abrir vídeo en otra aplicación")
            }
            .foregroundStyle(.secondary)

            if let errorMessage = playback.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(9)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
        .task(id: playback.url) {
            let loadedThumbnail = await VideoThumbnailCache.shared.thumbnail(for: playback.url)
            guard !Task.isCancelled else { return }
            thumbnail = loadedThumbnail
            didFinishLoadingThumbnail = true
        }
        .onDisappear {
            playback.stop()
        }
    }

    @ViewBuilder
    private var playerSurface: some View {
        if let player = playback.player {
            EmbeddedVideoPlayerView(player: player)
                .frame(width: 420, height: 236)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            Button(action: playback.play) {
                ZStack {
                    Color.black

                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                    } else if didFinishLoadingThumbnail {
                        Image(systemName: "video.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }

                    if playback.canPlay {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 52))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                            .shadow(radius: 4)
                    }
                }
                .frame(width: 420, height: 236)
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!playback.canPlay)
            .help("Reproducir \(filename)")
            .accessibilityLabel("Reproducir vídeo \(filename)")
        }
    }
}

private struct EmbeddedVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        playerView.player = player
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: ()) {
        playerView.player = nil
    }
}

@MainActor
final class VideoPlaybackController: ObservableObject {
    let url: URL
    let isLooping: Bool

    @Published private(set) var player: AVPlayer?
    @Published private(set) var errorMessage: String?
    @Published private(set) var canPlay: Bool

    private var looper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private static weak var activeController: VideoPlaybackController?

    init(url: URL, isLooping: Bool = false) {
        self.url = url
        self.isLooping = isLooping
        self.canPlay = FileManager.default.fileExists(atPath: url.path)
        if !canPlay {
            errorMessage = "No se encuentra el archivo de vídeo."
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
    }

    func play() {
        guard canPlay else { return }

        if let activeController = Self.activeController,
           activeController !== self {
            activeController.stop()
        }

        if player == nil {
            preparePlayer()
        }

        player?.play()
        Self.activeController = self
        errorMessage = nil
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        if let queuePlayer = player as? AVQueuePlayer {
            queuePlayer.removeAllItems()
        } else {
            player?.replaceCurrentItem(with: nil)
        }
        player = nil
        removeObservers()
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    private func preparePlayer() {
        let item = AVPlayerItem(url: url)
        let player: AVPlayer
        if isLooping {
            let queuePlayer = AVQueuePlayer()
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            player = queuePlayer
        } else {
            let singlePlayer = AVPlayer(playerItem: item)
            singlePlayer.actionAtItemEnd = .pause
            player = singlePlayer
        }
        self.player = player

        let relay = VideoPlaybackRelay(self)
        if !isLooping {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    relay.controller?.playbackDidFinish()
                }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: isLooping ? player.currentItem : item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                relay.controller?.playbackDidFail()
            }
        }
    }

    private func playbackDidFinish() {
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    private func playbackDidFail() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        canPlay = false
        errorMessage = "No se ha podido reproducir este vídeo."
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    private func removeObservers() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
    }
}

private final class VideoPlaybackRelay: @unchecked Sendable {
    weak var controller: VideoPlaybackController?

    init(_ controller: VideoPlaybackController) {
        self.controller = controller
    }
}
