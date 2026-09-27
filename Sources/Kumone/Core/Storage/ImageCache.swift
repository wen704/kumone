import CryptoKit
import Foundation
import SwiftUI

/// Two-tier (memory + disk) image cache with in-flight request coalescing.
actor ImageCache {
    static let shared = ImageCache()

    private nonisolated(unsafe) let memory = NSCache<NSString, PlatformImage>()
    private let fileManager = FileManager.default
    private let diskURL: URL
    private var inflight: [String: Task<PlatformImage?, Never>] = [:]

    private init() {
        memory.countLimit = 300
        memory.totalCostLimit = 64 * 1024 * 1024
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskURL = caches.appendingPathComponent("im.missuo.Kumone/images", isDirectory: true)
    }

    func image(for url: URL) async -> PlatformImage? {
        let key = Self.cacheKey(for: url)
        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let existing = inflight[key] {
            return await existing.value
        }
        let task = Task<PlatformImage?, Never> { [diskURL, fileManager] in
            let fileURL = diskURL.appendingPathComponent(key)
            do {
                try fileManager.createDirectory(at: diskURL, withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: fileURL.path) {
                    let data = try Data(contentsOf: fileURL)
                    if let image = PlatformImage(data: data) {
                        return image
                    }
                    try fileManager.removeItem(at: fileURL)
                }
            } catch {
                print("Image cache disk lookup failed: \(error)")
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                      let image = PlatformImage(data: data) else { return nil }
                do {
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    print("Image cache disk write failed: \(error)")
                }
                return image
            } catch {
                print("Image download failed: \(error)")
                return nil
            }
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let result {
            let width = result.size.width
            let height = result.size.height
            memory.setObject(result, forKey: key as NSString,
                             cost: Int(width * height * 4))
        }
        return result
    }

    /// Synchronous in-memory lookup — safe off the actor (`NSCache` is
    /// thread-safe). Returns nil unless the image is resident in memory; use
    /// `image(for:)` for disk/network loads.
    nonisolated func cachedImage(for url: URL) -> PlatformImage? {
        memory.object(forKey: Self.cacheKey(for: url) as NSString)
    }

    func usage() throws -> CacheUsage {
        try fileManager.createDirectory(at: diskURL, withIntermediateDirectories: true)
        let files = try fileManager.contentsOfDirectory(
            at: diskURL,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let bytes = try files.reduce(into: Int64(0)) { total, fileURL in
            let values = try fileURL.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return CacheUsage(bytes: bytes)
    }

    func clear() throws {
        try fileManager.createDirectory(at: diskURL, withIntermediateDirectories: true)
        let files = try fileManager.contentsOfDirectory(
            at: diskURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for fileURL in files {
            try fileManager.removeItem(at: fileURL)
        }
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
        memory.removeAllObjects()
    }

    private static func cacheKey(for url: URL) -> String {
        let digest = Insecure.MD5.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// AsyncImage replacement backed by `ImageCache`, with a crossfade reveal.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var animated: Bool = true
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: PlatformImage?
    @State private var loadedURL: URL?

    init(url: URL?, animated: Bool = true,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.animated = animated
        self.placeholder = placeholder
        // Seed from the in-memory cache so a re-created view (e.g. the iOS 26
        // tab-bar accessory rebuilt on a tab switch, #46) shows already-decoded
        // artwork immediately instead of flashing the placeholder.
        let seeded = url.flatMap { ImageCache.shared.cachedImage(for: $0) }
        _image = State(initialValue: seeded)
        _loadedURL = State(initialValue: seeded == nil ? nil : url)
    }

    var body: some View {
        ZStack {
            placeholder()
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(animated ? .opacity.animation(.easeIn(duration: 0.22)) : .identity)
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                loadedURL = nil
                return
            }
            guard url != loadedURL else { return }
            // Synchronous memory hit first — no actor hop, no placeholder frame.
            if let memoryHit = ImageCache.shared.cachedImage(for: url) {
                image = memoryHit
                loadedURL = url
                return
            }
            if let cached = await ImageCache.shared.image(for: url) {
                guard !Task.isCancelled else { return }
                image = cached
                loadedURL = url
            }
        }
    }
}

extension CachedAsyncImage where Placeholder == AnyView {
    /// Default placeholder: a quiet neutral fill with a music note.
    init(url: URL?, animated: Bool = true) {
        self.init(url: url, animated: animated) {
            AnyView(
                ZStack {
                    Rectangle().fill(.quaternary.opacity(0.5))
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
            )
        }
    }
}
