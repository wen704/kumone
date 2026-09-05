#if canImport(CarPlay) && os(iOS)
import Testing
import CarPlay
import UIKit
@testable import KumoneCore

/// Covers the playback-queue template that backs CarPlay's Up Next button.
///
/// The rest of the CarPlay stack (CarPlayConnector) drives CPInterfaceController and
/// CPNowPlayingTemplate.shared, neither of which can be instantiated outside a live CarPlay
/// scene, so it is exercised on-device rather than here. `queueTemplate` is deliberately a
/// pure function of player state so this part stays unit-testable.
@Suite("CarPlay queue template")
struct CarPlayQueueTemplateTests {

    private func makeTrack(id: Int, name: String, artist: String, album: String) throws -> Track {
        let json = """
        {
            "id": \(id),
            "name": "\(name)",
            "artists": [{"id": 1, "name": "\(artist)"}],
            "album": {"id": 10, "name": "\(album)", "picUrl": "https://example.com/pic.jpg"},
            "duration": 226000
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(Track.self, from: json)
    }

    @Test("Pins the current track in its own section and lists what's next")
    @MainActor
    func buildsCurrentAndUpcomingSections() throws {
        let current = try makeTrack(id: 1, name: "夜曲", artist: "周杰伦", album: "十一月的萧邦")
        let next = try makeTrack(id: 2, name: "晴天", artist: "周杰伦", album: "叶惠美")

        let template = CarPlayTemplateFactory.queueTemplate(
            current: current,
            upcoming: [next],
            onCurrentTap: {},
            onTrackTap: { _ in }
        )

        #expect(template.sections.count == 2)

        let currentSection = template.sections[0]
        #expect(currentSection.header == "正在播放")
        #expect(currentSection.items.count == 1)

        let currentItem = try #require(currentSection.items.first as? CPListItem)
        #expect(currentItem.text == "夜曲")
        #expect(currentItem.detailText == "周杰伦")
        // The pinned row is the only one flagged as playing, so the driver can tell at a
        // glance which entry is live.
        #expect(currentItem.isPlaying == true)

        let upcomingSection = template.sections[1]
        #expect(upcomingSection.header == "即将播放 · 1 首")
        let nextItem = try #require(upcomingSection.items.first as? CPListItem)
        #expect(nextItem.text == "晴天")
        #expect(nextItem.isPlaying == false)
    }

    @Test("Tapping an upcoming row reports the track that was picked")
    @MainActor
    func upcomingRowForwardsItsTrack() throws {
        let first = try makeTrack(id: 2, name: "晴天", artist: "周杰伦", album: "叶惠美")
        let second = try makeTrack(id: 3, name: "稻香", artist: "周杰伦", album: "魔杰座")
        var picked: Track?

        let template = CarPlayTemplateFactory.queueTemplate(
            current: nil,
            upcoming: [first, second],
            onCurrentTap: {},
            onTrackTap: { picked = $0 }
        )

        // No current track → only the upcoming section is built.
        #expect(template.sections.count == 1)

        let item = try #require(template.sections[0].items[1] as? CPListItem)
        item.handler?(item, {})
        #expect(picked?.id == second.id)
    }

    @Test("Caps very long queues at CarPlay's limit but still reports the true count")
    @MainActor
    func capsQueueLength() throws {
        let total = CPListTemplate.maximumItemCount + 120
        let tracks = try (0..<total).map { try makeTrack(id: $0, name: "曲目\($0)", artist: "歌手", album: "专辑") }

        let template = CarPlayTemplateFactory.queueTemplate(
            current: nil,
            upcoming: tracks,
            onCurrentTap: {},
            onTrackTap: { _ in }
        )

        // Anything past the framework limit is dropped by CarPlay itself, so the template must
        // not rely on a hand-picked cap.
        #expect(template.sections[0].items.count == CPListTemplate.maximumItemCount)
        // ...but the header still tells the driver how long the queue really is.
        #expect(template.sections[0].header == "即将播放 · \(total) 首")
    }

    @Test("Shows an empty-state message when nothing is queued")
    @MainActor
    func emptyQueue() {
        let template = CarPlayTemplateFactory.queueTemplate(
            current: nil,
            upcoming: [],
            onCurrentTap: {},
            onTrackTap: { _ in }
        )

        #expect(template.sections.isEmpty)
        #expect(template.emptyViewTitleVariants == ["当前没有播放队列"])
    }
}
#endif
