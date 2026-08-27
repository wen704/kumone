import SwiftUI

private struct OpenLoginKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openLogin: () -> Void {
        get { self[OpenLoginKey.self] }
        set { self[OpenLoginKey.self] = newValue }
    }
}

struct PlayerChromeModifier: ViewModifier {
    @EnvironmentObject private var player: PlayerService
    let detailWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                PlayerBar()
                    .frame(width: detailWidth)
            }
            .overlay(alignment: .trailing) {
                rightPanel
            }
            .animation(AppAnimation.standard, value: player.activePanel)
    }

    @ViewBuilder
    private var rightPanel: some View {
        if let panel = player.activePanel {
            Group {
                switch panel {
                case .lyrics:
                    LyricsPanel()
                case .queue:
                    QueuePanel()
                }
            }
            .padding(.top, 12)
            .padding(.bottom, Theme.Layout.playerChromeClearance + 10)
            .padding(.trailing, 16)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

enum SidebarItem: Hashable {
    case home
    case explore
    case fm
    case likedSongs
    case daily
    case recents
    case collections
    case cloud
    case playlist(Int)
}

enum Destination: Hashable {
    case playlist(Int)
    case album(Int)
    case artist(Int)
    case daily
    case toplists
    case recents
    case collections
    case cloud
    case search(String)
}

/// Renders the page for a `Destination`. Shared by the iOS 16+
/// `navigationDestination` registration and the iOS 15 classic
/// `NavigationLink(destination:)` links in `AppNavLink`.
struct DestinationContent: View {
    let destination: Destination

    var body: some View {
        Group {
            switch destination {
            case .playlist(let id):
                PlaylistDetailView(playlistID: id)
            case .album(let id):
                AlbumDetailView(albumID: id)
            case .artist(let id):
                ArtistDetailView(artistID: id)
            case .daily:
                DailySongsView()
            case .toplists:
                ToplistsView()
            case .recents:
                RecentsView()
            case .collections:
                CollectionsView()
            case .cloud:
                CloudView()
            case .search(let query):
                SearchView(query: query)
            }
        }
        .playerContentInset()
    }
}

/// Registers the shared navigation destinations on a stack. No-op on iOS 15,
/// where `AppNavLink` embeds its destination directly.
struct DestinationsModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            content.navigationDestination(for: Destination.self) { destination in
                DestinationContent(destination: destination)
            }
        } else {
            content
        }
    }
}

extension View {
    func playerChrome(detailWidth: CGFloat) -> some View {
        modifier(PlayerChromeModifier(detailWidth: detailWidth))
    }

    /// Pages clear the floating player bar with an explicit trailing
    /// `PlayerClearanceSpacer` in their scroll content; safeAreaPadding
    /// proved unreliable inside navigation stacks (#12).
    func playerContentInset() -> some View {
        self
    }

    func appDestinations() -> some View {
        modifier(DestinationsModifier())
    }
}

/// Trailing spacer for scrollable pages so the last row clears the
/// floating player bar.
struct PlayerClearanceSpacer: View {
    var body: some View {
        #if os(iOS)
        Color.clear.frame(height: 80) // mini player bar above the tab bar
        #else
        Color.clear.frame(height: Theme.Layout.playerChromeClearance + 8)
        #endif
    }
}
