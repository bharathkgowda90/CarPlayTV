import UIKit

/// Small in-memory cache for channel logos shown on the car screen.
actor ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let data = try? await URLSession.shared.data(from: url).0, let image = UIImage(data: data) else { return nil }
        let thumbnail = image.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? image
        cache.setObject(thumbnail, forKey: url as NSURL)
        return thumbnail
    }
}
