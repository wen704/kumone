import AppKit
import Testing
@testable import KumoneCore

@Suite("Now Playing Artwork Store Tests")
@MainActor
struct NowPlayingArtworkStoreTests {
    @Test func latestArtworkRequestWins() async {
        let firstArtwork = artwork(color: .systemRed)
        let secondArtwork = artwork(color: .systemBlue)
        let store = NowPlayingArtworkStore(player: nil) { url in
            if url.absoluteString.contains("first-artwork") {
                try? await Task.sleep(nanoseconds: 20_000_000)
                return firstArtwork
            }
            return secondArtwork
        }
        store.setArtworkNeeded(true)

        store.update(
            trackID: 1,
            artworkURL: "https://example.com/first-artwork.jpg"
        )
        store.update(
            trackID: 2,
            artworkURL: "https://example.com/second-artwork.jpg"
        )
        try? await Task.sleep(nanoseconds: 40_000_000)

        #expect(store.trackID == 2)
        #expect(store.artwork === secondArtwork)
    }

    @Test func missingArtworkImmediatelyUsesFallback() {
        let store = NowPlayingArtworkStore(player: nil) { _ in artwork(color: .systemRed) }

        store.update(trackID: 1, artworkURL: nil)

        #expect(store.trackID == 1)
        #expect(store.artwork == nil)
        #expect(store.colors == .fallback)
    }

    @Test func failedArtworkLoadUsesFallback() async {
        let loaderCalls = ImageLoaderCallSignal()
        let store = NowPlayingArtworkStore(player: nil) { _ in
            await loaderCalls.record()
            return nil
        }
        store.setArtworkNeeded(true)

        store.update(
            trackID: 1,
            artworkURL: "https://example.com/missing-artwork.jpg"
        )
        await loaderCalls.waitForCall()

        #expect(store.trackID == 1)
        #expect(store.artwork == nil)
        #expect(store.colors == .fallback)
    }

    @Test func waitsForAConsumerBeforeLoadingArtwork() async {
        let loaderCalls = ImageLoaderCallSignal()
        let store = NowPlayingArtworkStore(player: nil) { _ in
            await loaderCalls.record()
            return nil
        }

        store.update(
            trackID: 1,
            artworkURL: "https://example.com/artwork.jpg"
        )

        #expect(await loaderCalls.callCount() == 0)

        store.setArtworkNeeded(true)
        await loaderCalls.waitForCall()

        #expect(await loaderCalls.callCount() == 1)
    }

    private func artwork(color: NSColor) -> PlatformImage {
        let image = PlatformImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        return image
    }
}

private actor ImageLoaderCallSignal {
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record() {
        count += 1
        let waiters = waiters
        self.waiters = []
        waiters.forEach { $0.resume() }
    }

    func waitForCall() async {
        guard count == 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func callCount() -> Int { count }
}
