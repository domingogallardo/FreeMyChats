@preconcurrency import AppKit
import Foundation
@preconcurrency import ImageIO
import UniformTypeIdentifiers

final class ImageThumbnailCache: @unchecked Sendable {
    static let shared = ImageThumbnailCache()

    private struct LoadedThumbnail: @unchecked Sendable {
        let image: NSImage?
        let cost: Int
    }

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 128 * 1_024 * 1_024
    }

    func thumbnail(for url: URL) async -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let loaded = await Task.detached(priority: .userInitiated) {
            Self.loadThumbnail(from: url)
        }.value

        if let image = loaded.image {
            cache.setObject(image, forKey: key, cost: loaded.cost)
        }
        return loaded.image
    }

    private static func loadThumbnail(from url: URL) -> LoadedThumbnail {
        guard let source = imageSource(for: url) else {
            return LoadedThumbnail(image: nil, cost: 0)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 840
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return LoadedThumbnail(image: nil, cost: 0)
        }

        return LoadedThumbnail(
            image: NSImage(cgImage: cgImage, size: .zero),
            cost: cgImage.width * cgImage.height * 4
        )
    }

    private static func imageSource(for url: URL) -> CGImageSource? {
        guard url.pathExtension.caseInsensitiveCompare("thumb") == .orderedSame else {
            return CGImageSourceCreateWithURL(url as CFURL, nil)
        }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceTypeIdentifierHint: UTType.jpeg.identifier
        ]
        return CGImageSourceCreateWithData(data as CFData, options as CFDictionary)
    }
}
