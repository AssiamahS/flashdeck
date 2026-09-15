import ImageIO
import SwiftUI
import UIKit

/// Loads a card image by URL. Unlike AsyncImage it plays animated GIFs, sends a
/// real User-Agent (Wikimedia rate-limits the default one), and runs the link
/// through ImageURL.normalize first so pasted page links still show a picture.
struct RemoteImage: View {
    let source: String
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                AnimatedImageView(image: image)
                    .aspectRatio(image.size, contentMode: .fit)
            } else if failed {
                Label("Image didn't load", systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView()
                    .padding()
            }
        }
        .task(id: source) { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        guard let normalized = ImageURL.normalize(source), let url = URL(string: normalized) else {
            failed = true
            return
        }
        do {
            let data = try await ImageLoader.data(for: url)
            guard let decoded = ImageLoader.decode(data) else {
                failed = true
                return
            }
            image = decoded
        } catch {
            failed = true
        }
    }
}

enum ImageLoader {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 300_000_000)
        config.httpAdditionalHeaders = ["User-Agent": "FlashDeck/1.3 (iOS; https://github.com/AssiamahS/flashdeck)"]
        return URLSession(configuration: config)
    }()

    static func data(for url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Animated GIF → UIImage.animatedImage with the file's frame timing; anything else → UIImage(data:).
    static func decode(_ data: Data) -> UIImage? {
        let isGIF = data.starts(with: [0x47, 0x49, 0x46]) // "GIF"
        guard isGIF, let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var total = 0.0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            var delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.1
            if delay < 0.02 { delay = 0.1 }
            frames.append(UIImage(cgImage: cg))
            total += delay
        }
        return UIImage.animatedImage(with: frames, duration: total)
    }
}

/// UIImageView plays animated UIImages; SwiftUI's Image shows only the first frame.
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image { view.image = image }
    }
}
