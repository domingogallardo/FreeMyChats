import AVFoundation
import SwiftUI

struct AudioPlayerView: View {
    let filename: String

    @StateObject private var playback: AudioPlaybackController

    init(url: URL, filename: String, expectedDuration: Int?) {
        self.filename = filename
        _playback = StateObject(
            wrappedValue: AudioPlaybackController(
                url: url,
                expectedDuration: expectedDuration.map(TimeInterval.init)
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button(action: playback.togglePlayback) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!playback.canPlay)
                .help(playback.isPlaying ? "Pausar audio" : "Reproducir audio")
                .accessibilityLabel(playback.isPlaying ? "Pausar audio" : "Reproducir audio")

                VStack(alignment: .leading, spacing: 4) {
                    Text(filename)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 7) {
                        Text(AudioTimeFormatter.string(from: playback.currentTime))
                            .monospacedDigit()
                            .frame(minWidth: 32, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { playback.currentTime },
                                set: playback.seek(to:)
                            ),
                            in: 0...playback.sliderUpperBound,
                            onEditingChanged: playback.setSeeking
                        )
                        .disabled(!playback.canPlay)
                        .accessibilityLabel("Posición del audio")

                        Text(AudioTimeFormatter.string(from: playback.duration))
                            .monospacedDigit()
                            .frame(minWidth: 32, alignment: .leading)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Button {
                    WorkspaceService.reveal(playback.url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Mostrar \(filename) en Finder")
                .accessibilityLabel("Mostrar audio en Finder")
            }

            if let errorMessage = playback.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(9)
        .frame(minWidth: 300)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
        .onReceive(Self.progressTimer) { _ in
            playback.refreshProgress()
        }
    }

    private static let progressTimer = Timer.publish(
        every: 0.25,
        on: .main,
        in: .common
    ).autoconnect()
}

@MainActor
final class AudioPlaybackController: ObservableObject {
    let url: URL

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval
    @Published private(set) var errorMessage: String?
    @Published private(set) var canPlay: Bool

    private var player: AVPlayer?
    private var isSeeking = false
    private var resumeAfterSeeking = false
    private var seekRequestID: UUID?
    private var endObserver: NSObjectProtocol?
    private static weak var activeController: AudioPlaybackController?

    var sliderUpperBound: TimeInterval { max(duration, 1) }

    init(url: URL, expectedDuration: TimeInterval?) {
        self.url = url
        self.duration = max(expectedDuration ?? 0, 0)
        self.canPlay = FileManager.default.fileExists(atPath: url.path)
        if !canPlay {
            errorMessage = "No se encuentra el archivo de audio."
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func togglePlayback() {
        guard preparePlayerIfNeeded(), let player else { return }

        if isPlaying || player.rate != 0 {
            pause()
            return
        }

        if duration > 0, currentTime >= duration - 0.05 {
            currentTime = 0
        }

        if let activeController = Self.activeController,
           activeController !== self {
            activeController.pause()
        }

        performSeek(to: currentTime, autoplay: true)
    }

    func pause() {
        player?.pause()
        if let player {
            updateCurrentTime(from: player)
        }
        seekRequestID = nil
        isSeeking = false
        resumeAfterSeeking = false
        isPlaying = false
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    func seek(to time: TimeInterval) {
        guard preparePlayerIfNeeded() else { return }
        let target = min(max(time, 0), duration)
        currentTime = target
    }

    func setSeeking(_ seeking: Bool) {
        guard seeking != isSeeking else { return }

        if seeking {
            resumeAfterSeeking = isPlaying
            player?.pause()
            isPlaying = false
            seekRequestID = nil
        }
        isSeeking = seeking
        if !seeking {
            let shouldResume = resumeAfterSeeking
            resumeAfterSeeking = false
            performSeek(to: currentTime, autoplay: shouldResume)
        }
    }

    func refreshProgress() {
        guard let player, !isSeeking else { return }
        if let error = player.error ?? player.currentItem?.error {
            playbackDidFail(error)
            return
        }
        guard isPlaying else { return }
        updateCurrentTime(from: player)
    }

    @discardableResult
    private func preparePlayerIfNeeded() -> Bool {
        if player != nil { return true }
        guard canPlay else { return false }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.player = player
        let playbackRelay = AudioPlaybackRelay(self)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                playbackRelay.controller?.playbackDidFinish()
            }
        }

        Task { @MainActor [weak self, weak item] in
            guard let self, let item else { return }
            if let assetDuration = try? await item.asset.load(.duration),
               assetDuration.seconds.isFinite,
               assetDuration.seconds > 0 {
                duration = assetDuration.seconds
            }
        }
        return true
    }

    private func performSeek(to seconds: TimeInterval, autoplay: Bool) {
        guard let player else { return }
        let target = min(max(seconds, 0), duration)
        let requestID = UUID()
        seekRequestID = requestID
        isSeeking = true
        player.pause()

        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self, weak player] finished in
            Task { @MainActor in
                guard let self, self.seekRequestID == requestID else { return }
                self.seekRequestID = nil
                self.isSeeking = false
                guard finished, let player else {
                    self.errorMessage = "No se ha podido cambiar la posición del audio."
                    return
                }

                self.currentTime = target
                guard autoplay else { return }
                player.play()
                Self.activeController = self
                self.isPlaying = true
                self.errorMessage = nil
            }
        }
    }

    private func updateCurrentTime(from player: AVPlayer) {
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            currentTime = min(max(seconds, 0), duration)
        }
    }

    private func playbackDidFinish() {
        currentTime = duration
        isPlaying = false
        if Self.activeController === self {
            Self.activeController = nil
        }
    }

    private func playbackDidFail(_ error: Error) {
        player?.pause()
        isPlaying = false
        canPlay = false
        errorMessage = "No se ha podido reproducir este audio."
        if Self.activeController === self {
            Self.activeController = nil
        }
    }
}

private final class AudioPlaybackRelay: @unchecked Sendable {
    weak var controller: AudioPlaybackController?

    init(_ controller: AudioPlaybackController) {
        self.controller = controller
    }
}

enum AudioTimeFormatter {
    static func string(from interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "0:00" }
        let totalSeconds = Int(interval.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
