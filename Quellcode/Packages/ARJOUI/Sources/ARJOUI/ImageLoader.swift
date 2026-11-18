import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Lädt Logos und Poster, verkleinert sie auf die gebrauchte Grösse und hält sie im Speicher und auf der Platte.
/// Vorgabe von `AsyncImage` wäre ein winziger URL-Cache und volle Bildgrösse im Speicher.
actor ImageLoader {
    static let shared = ImageLoader()

    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let session: URLSession
    /// `NSCache` ist threadsicher; der Zugriff ohne Actor-Sprung lässt bekannte Bilder sofort erscheinen.
    private nonisolated(unsafe) let cache = NSCache<NSString, Box>()
    private var inflight: [String: Task<CGImage?, Never>] = [:]

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.urlCache = URLCache(memoryCapacity: 20 * 1_024 * 1_024, diskCapacity: 300 * 1_024 * 1_024, directory: nil)
            // Logos und Poster ändern sich selten: erst im Cache nachsehen.
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: configuration)
        }
        cache.totalCostLimit = 80 * 1_024 * 1_024
    }

    /// Bild aus dem Speicher-Cache, falls schon geladen (ohne Wartezeit).
    nonisolated func cachedImage(for url: URL, maxPixel: Int) -> CGImage? {
        cache.object(forKey: "\(url.absoluteString)@\(maxPixel)" as NSString)?.image
    }

    func image(for url: URL, maxPixel: Int) async -> CGImage? {
        let key = "\(url.absoluteString)@\(maxPixel)"
        if let cached = cache.object(forKey: key as NSString) { return cached.image }
        if let running = inflight[key] { return await running.value }

        let session = session
        let task = Task<CGImage?, Never> {
            do {
                let (data, response) = try await session.data(from: url)
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
                return Self.downsample(data, maxPixel: maxPixel)
            } catch {
                return nil
            }
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image { cache.setObject(Box(image), forKey: key as NSString, cost: image.bytesPerRow * image.height) }
        return image
    }

    func clear() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Dekodiert nur in der Zielgrösse, ohne das Originalbild komplett im Speicher zu halten.
    nonisolated static func downsample(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Bild aus dem `ImageLoader`; zeigt `placeholder`, bis es geladen ist oder wenn es fehlt.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var maxPixel = 600
    /// Ein winziges Bild, hochgezogen mit `.high`, wirkt wie ein Weichzeichner und kostet keine Rechenzeit.
    var interpolation: Image.Interpolation = .medium
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: CGImage?

    init(url: URL?, contentMode: ContentMode = .fit, maxPixel: Int = 600, interpolation: Image.Interpolation = .medium, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.interpolation = interpolation
        self.contentMode = contentMode
        self.maxPixel = maxPixel
        self.placeholder = placeholder
        // Schon geladene Bilder sind im ersten Bild da: kein Aufblitzen beim Wechseln von Ansichten.
        _image = State(initialValue: url.flatMap { ImageLoader.shared.cachedImage(for: $0, maxPixel: maxPixel) })
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).interpolation(interpolation).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if image != nil, ImageLoader.shared.cachedImage(for: url, maxPixel: maxPixel) != nil { return }
            image = await ImageLoader.shared.image(for: url, maxPixel: maxPixel)
        }
    }
}
