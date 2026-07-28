@preconcurrency import AppKit
@preconcurrency import AVFoundation

final class VideoThumbnailCache: @unchecked Sendable {
    static let shared = VideoThumbnailCache()

    private struct LoadedThumbnail: @unchecked Sendable {
        let image: NSImage?
        let cost: Int
    }

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 128
        cache.totalCostLimit = 96 * 1_024 * 1_024
    }

    func thumbnail(for url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let loaded = await Task.detached(priority: .utility) {
            Self.loadThumbnail(from: url)
        }.value

        if let image = loaded.image {
            cache.setObject(image, forKey: key, cost: loaded.cost)
        }
        return loaded.image
    }

    private static func loadThumbnail(from url: URL) -> LoadedThumbnail {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LoadedThumbnail(image: nil, cost: 0)
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 840, height: 600)

        let requestedTime = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(
            at: requestedTime,
            actualTime: nil
        ) else {
            return LoadedThumbnail(image: nil, cost: 0)
        }

        return LoadedThumbnail(
            image: NSImage(cgImage: cgImage, size: .zero),
            cost: cgImage.width * cgImage.height * 4
        )
    }
}
