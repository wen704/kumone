import SwiftUI

/// Design tokens: color, radius, spacing, layout metrics.
enum Theme {
    /// NetEase red, tuned slightly warmer for macOS.
    static let accent = Color(red: 0.925, green: 0.286, blue: 0.286) // #EC4949
    static let accentDeep = Color(red: 0.788, green: 0.161, blue: 0.161) // #C92929

    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.973, green: 0.357, blue: 0.357), accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    enum Radius {
        static let badge: CGFloat = 4
        static let small: CGFloat = 6
        static let standard: CGFloat = 8
        static let large: CGFloat = 12
        static let panel: CGFloat = 20
    }

    enum Layout {
        static let contentInset: CGFloat = 24
        static let cardSize: CGFloat = 160
        /// Row height for a shelf of cover cards: artwork, then up to two lines
        /// of title and one of subtitle.
        static let coverShelfHeight: CGFloat = 226
        /// Row height for a shelf of artist cards: circular artwork, one name.
        static let artistShelfHeight: CGFloat = 196
        static let sidebarWidth: CGFloat = 220
        static let playerBarHeight: CGFloat = 56
        /// Gap between the floating player bar and the window's bottom edge.
        /// Must match the bar's own `.padding(.bottom,)` in PlayerBar.
        static let playerBarBottomMargin: CGFloat = 10
        /// Bottom inset pages need so scrolled content clears the floating bar.
        static var playerChromeClearance: CGFloat { playerBarHeight + playerBarBottomMargin }
        /// Extra breathing margin for scrollable content clearing chrome.
        static let scrollBreathingMargin: CGFloat = 8

        #if os(iOS)
        enum FloatingChrome {
            /// Total height of GlassTabBar: 56pt content + 2 * 4pt inset.
            static let tabBarHeight: CGFloat = 64
            /// Total height of legacy mini player bar: 44pt button + 2 * 4pt vertical padding.
            static let miniPlayerHeight: CGFloat = 52
            /// Spacing between mini player and tab bar in customTabInterface.
            static let barSpacing: CGFloat = 8
            /// Bottom padding under the tab bar.
            static let bottomMargin: CGFloat = 6
            /// Breathing margin ensuring content clears above the floating bars.
            static let extraPadding: CGFloat = 12

            /// Clearance needed when only the tab bar is visible.
            static var tabBarClearance: CGFloat {
                tabBarHeight + bottomMargin + extraPadding
            }

            /// Clearance needed when both mini player and tab bar are visible.
            static var fullChromeClearance: CGFloat {
                miniPlayerHeight + barSpacing + tabBarHeight + bottomMargin + extraPadding
            }
        }
        #endif
        static let minWindowWidth: CGFloat = 1020
        /// Width the split view's divider occupies between the two columns.
        static let splitDividerWidth: CGFloat = 8
        /// Window minimum while the sidebar is collapsed. The window-wide
        /// minimum is a *content* constraint, so with the sidebar hidden it
        /// lands entirely on the detail column; restoring the sidebar would
        /// then add its width on top and `.contentMinSize` would widen the
        /// window every time the now-playing page is dismissed (#19).
        /// Subtracting the sidebar here keeps the restored total at
        /// `minWindowWidth`.
        static var minWindowWidthSidebarCollapsed: CGFloat {
            minWindowWidth - sidebarWidth - splitDividerWidth
        }
        static let minWindowHeight: CGFloat = 640
        static let defaultWindowWidth: CGFloat = 1200
        static let defaultWindowHeight: CGFloat = 780
    }
}

/// Motion tokens (mirrors kaset's `AppAnimation`).
enum AppAnimation {
    static let quick = Animation.easeOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.25)
    static let smooth = Animation.easeInOut(duration: 0.35)
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)

    static let staggerDelay = 0.04
    static let maxStaggerDelay = 0.4

    static func stagger(for index: Int) -> Double {
        min(Double(index) * staggerDelay, maxStaggerDelay)
    }
}

extension View {
    /// `scrollClipDisabled` is iOS 17 / macOS 14; older systems clip normally.
    @ViewBuilder
    func compatScrollClipDisabled() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) { scrollClipDisabled() } else { self }
    }

    /// `contentTransition(.opacity)` is iOS 16+; iOS 15 swaps content
    /// without a transition.
    @ViewBuilder
    func compatContentTransitionOpacity() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            contentTransition(.opacity)
        } else {
            self
        }
    }

    /// `scrollContentBackground(.hidden)` is iOS 16+/macOS 13+; iOS 15
    /// keeps the default list background.
    @ViewBuilder
    func compatHiddenScrollBackground() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// `formStyle(.grouped)` is iOS 16+/macOS 13+; grouped is already the
    /// default on older systems, so it degrades to a no-op.
    @ViewBuilder
    func compatGroupedFormStyle() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            formStyle(.grouped)
        } else {
            self
        }
    }

    /// `onGeometryChange` is iOS 16.4+; this preference-based tracker works
    /// on every supported OS.
    func compatWidthTracking(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: WidthTrackingKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(WidthTrackingKey.self, perform: onChange)
    }

    /// Hides the toolbar background; `toolbarBackgroundVisibility` is
    /// macOS 15+/iOS 18+, iOS 16–17 falls back to `toolbarBackground`,
    /// and iOS 15 keeps the system default background.
    @ViewBuilder
    func compatHiddenToolbarBackground() -> some View {
        #if os(macOS)
        toolbarBackgroundVisibility(.hidden, for: .automatic)
        #else
        if #available(iOS 18.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .automatic)
        } else if #available(iOS 16.0, *) {
            toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
        #endif
    }

    /// `presentationDetents([.height(360)])` is iOS 16+; iOS 15 presents the
    /// sheet at full height.
    @ViewBuilder
    func compatPresentationDetentsHeight360() -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            presentationDetents([.height(360)])
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Glass background with a graceful material fallback on macOS 15.
    /// `glassEffect` 需要 Xcode 26 SDK(iOS 26 符号),`#if compiler(>=6.2)`
    /// 让旧工具链(如 Xcode 16.2/iOS 18 SDK)编译时直接走材质降级分支。
    @ViewBuilder
    func compatGlass(interactive: Bool = false, in shape: some Shape) -> some View {
        #if compiler(>=6.2) && os(macOS)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #elseif compiler(>=6.2) && os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

/// `LabeledContent` is iOS 16+; this renders the same trailing-secondary
/// layout on iOS 15 and above.
struct CompatLabeledContent: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WidthTrackingKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
