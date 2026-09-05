import SwiftUI

struct MainWindow: View {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var toasts: ToastCenter

    @State private var selection: SidebarItem = .home
    @State private var path: [Destination] = []
    @State private var showLogin = false
    @State private var detailWidth: CGFloat = 0
    /// iOS 15:NavigationView 没有可编程路径,切换侧栏选择时递增以重建
    /// 详情列视图树,实现回到根页面(16+ 分支忽略)。
    @State private var detailGeneration = 0
    /// iOS 15:程序化搜索跳转的查询词,激活隐藏的 NavigationLink
    /// (16+ 直接 append 到 path)。
    @State private var pushedSearchQuery: String?

    var body: some View {
        navigationContainer
            #if os(macOS)
            // Immersive now-playing page: hide the whole window toolbar
            // (sidebar toggle, navigation title, search field).
            .toolbar(player.showNowPlaying ? .hidden : .automatic, for: .windowToolbar)
            // Keep the single main window alive on Cmd+W / red button so the Dock
            // icon can always bring it back (#60/#63/#66/#70).
            .background(MainWindowConfigurator())
            #endif
            .playerChrome(detailWidth: detailWidth)
            .environment(\.openLogin, { showLogin = true })
            .task {
#if os(macOS)
            // Keep this action in the app delegate: when the user closes the
            // last WindowGroup window, there is no view left to receive a
            // Dock reopen event directly.
            AppDelegate.shared?.openMainWindow = { openWindow(id: "main") }
#endif
            DesktopLyricsController.shared.sync(with: settings.showDesktopLyrics)
            await account.bootstrap()
            }
            .onChange(of: settings.showDesktopLyrics) { _ in
                DesktopLyricsController.shared.sync(with: settings.showDesktopLyrics)
            }
            .sheet(isPresented: $showLogin) {
                LoginSheet()
            }
            .overlay {
                if player.showNowPlaying {
                    NowPlayingView()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let toast = toasts.current {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 12)
                }
            }
            .animation(AppAnimation.smooth, value: player.showNowPlaying)
            .animation(.spring(response: 0.3, dampingFraction: 1), value: toasts.current)
    }

    @ViewBuilder
    private var navigationContainer: some View {
        #if os(macOS)
        MainWindowSplitContainer(
            selection: $selection,
            showLogin: $showLogin,
            submitSearch: submitSearch
        ) {
            detailStack
        }
        #else
        if #available(iOS 16.0, *) {
            MainWindowSplitContainer(
                selection: $selection,
                showLogin: $showLogin,
                submitSearch: submitSearch
            ) {
                detailStack
            }
        } else {
            MainWindowSidebarLayout(
                selection: $selection,
                showLogin: $showLogin,
                submitSearch: submitSearch
            ) {
                detailStack
            }
        }
        #endif
    }

    private var detailStack: some View {
        AppNavigationStack(path: $path, generation: detailGeneration) {
            rootView
                .playerContentInset()
                .background(
                    // iOS 15:程序化搜索跳转的隐藏链接(见 LegacyPushLink)。
                    LegacyPushLink(
                        isPushed: Binding(
                            get: { pushedSearchQuery != nil },
                            set: { if !$0 { pushedSearchQuery = nil } }
                        ),
                        destination: .search(pushedSearchQuery ?? "")
                    )
                )
                .appDestinations()
        }
        .compatWidthTracking { width in
            detailWidth = width
        }
        .onChange(of: selection) { _ in
            path = []
            pushedSearchQuery = nil
            detailGeneration += 1
        }
    }

    private func submitSearch(_ query: String) {
        if #available(iOS 16.0, *) {
            path.append(Destination.search(query))
        } else {
            pushedSearchQuery = query
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch selection {
        case .home:
            HomeView()
        case .explore:
            ExploreView()
        case .fm:
            FMView()
        case .search:
            // iPad search entry: SearchView's `.searchable` bar surfaces in the
            // detail nav bar (the desktop toolbar search field doesn't render on
            // iPad). (#59)
            SearchView(query: "")
        case .likedSongs:
            if let playlist = account.likedSongsPlaylist {
                PlaylistDetailView(playlistID: playlist.id, isLikedList: true)
                    .id(playlist.id)
            } else {
                loginPrompt
            }
        case .daily:
            DailySongsView()
        case .recents:
            RecentsView()
        case .collections:
            CollectionsView()
        case .cloud:
            CloudView()
        case .playlist(let id):
            PlaylistDetailView(playlistID: id)
                .id(id)
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("登录后查看你喜欢的音乐")
                .font(.headline)
            Button("登录") { showLogin = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Split / sidebar containers

/// iOS 16+/macOS 分栏容器;沉浸式播放页打开时收起侧栏(修复分割线
/// 拖拽光标在覆盖层下仍可触发的问题,#6)。
@available(iOS 16.0, macOS 13.0, *)
private struct MainWindowSplitContainer<Detail: View>: View {
    @Binding var selection: SidebarItem
    @Binding var showLogin: Bool
    let submitSearch: (String) -> Void
    @ViewBuilder var detail: () -> Detail

    @EnvironmentObject private var player: PlayerService
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var visibilityBeforeNowPlaying: NavigationSplitViewVisibility?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection, showLogin: $showLogin)
                .navigationSplitViewColumnWidth(min: 200, ideal: Theme.Layout.sidebarWidth, max: 280)
        } detail: {
            detail()
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            // `sharedBackgroundVisibility` 是 iOS/macOS 26 SDK 符号,
            // 旧工具链(Xcode 16.2)编译时退回普通 ToolbarItem。
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    SearchFieldView { submitSearch($0) }
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    SearchFieldView { submitSearch($0) }
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                SearchFieldView { submitSearch($0) }
            }
            #endif
        }
        .onChange(of: player.showNowPlaying) { _ in
            if player.showNowPlaying {
                visibilityBeforeNowPlaying = columnVisibility
                columnVisibility = .detailOnly
            } else {
                columnVisibility = visibilityBeforeNowPlaying ?? .all
                visibilityBeforeNowPlaying = nil
            }
        }
    }
}

/// iOS 15:NavigationSplitView 不可用,退化为固定宽度侧栏 + 详情栈。
/// 侧栏由 selection 驱动(不含导航链接),详情列自带 NavigationView。
private struct MainWindowSidebarLayout<Detail: View>: View {
    @Binding var selection: SidebarItem
    @Binding var showLogin: Bool
    let submitSearch: (String) -> Void
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection, showLogin: $showLogin)
                .frame(width: Theme.Layout.sidebarWidth)
            Divider()
            detail()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        SearchFieldView { submitSearch($0) }
                    }
                }
        }
    }
}

#if os(macOS)
// MARK: - Main window configurator

/// Grabs the single main `NSWindow` once it exists and installs a close
/// interceptor: Cmd+W / the red button *hide* the window (`orderOut`) instead
/// of destroying the single-instance `Window` scene. Destroying the scene left
/// the app running with no way to reopen it (#60/#66/#70); hiding keeps the
/// SwiftUI scene fully alive so `AppDelegate.applicationShouldHandleReopen`
/// can front it again on a Dock click. Every other window-delegate callback is
/// forwarded untouched to SwiftUI's own delegate.
struct MainWindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private(set) weak var window: NSWindow?
        private weak var forwardee: NSWindowDelegate?

        func attach(to window: NSWindow?) {
            guard let window, self.window == nil else { return }
            self.window = window
            window.isReleasedWhenClosed = false
            // Insert ourselves as the delegate, forwarding to whatever
            // delegate SwiftUI installed.
            if window.delegate !== self {
                forwardee = window.delegate
                window.delegate = self
            }
            AppDelegate.shared?.mainWindow = window
        }

        // Hide instead of close; keep the scene alive.
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }

        // Transparently forward every other delegate callback to SwiftUI.
        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || (forwardee?.responds(to: aSelector) ?? false)
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if forwardee?.responds(to: aSelector) == true { return forwardee }
            return super.forwardingTarget(for: aSelector)
        }
    }
}
#endif

// MARK: - Search field

struct SearchFieldView: View {
    let onSubmit: (String) -> Void

    @State private var text = ""
    @State private var placeholder = "搜索音乐、歌手、专辑"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
                .frame(width: 168)
                .onSubmit {
                    let query = text.trimmingCharacters(in: .whitespaces)
                    let effective = query.isEmpty ? placeholderQuery : query
                    guard !effective.isEmpty else { return }
                    onSubmit(effective)
                    focused = false
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(focused ? 0.18 : 0.08), lineWidth: 1))
        .animation(AppAnimation.quick, value: focused)
        .task {
            if let keyword = try? await NeteaseAPI.searchDefaultKeyword(), !keyword.isEmpty {
                placeholder = keyword
                placeholderQuery = keyword
            }
        }
    }

    @State private var placeholderQuery = ""
}

// MARK: - Toast

struct ToastView: View {
    let toast: Toast

    var body: some View {
        Text(toast.message)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .compatGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}
