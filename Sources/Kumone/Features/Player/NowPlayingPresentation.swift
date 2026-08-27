import SwiftUI

#if os(iOS)
/// Shared geometry and interaction constants for the iPhone Now Playing
/// presentation. Keeping these values together makes the relationship between
/// the drag indicator and the track header explicit and regression-testable.
enum NowPlayingPresentationMetrics {
    /// The compact layout starts at the safe-area edge, which already sits
    /// about 12pt below the Dynamic Island. One additional point produces the
    /// same visible 13pt gap used below the indicator.
    static let dynamicIslandSafeAreaClearance: CGFloat = 12
    static let indicatorTopSpacing: CGFloat = 1
    static let indicatorToHeaderSpacing: CGFloat = 13
    static let indicatorWidth: CGFloat = 44
    static let indicatorHeight: CGFloat = 5
    static let indicatorHitWidth: CGFloat = 180
    static let indicatorHitHeight: CGFloat = 82
    static let controlsRevealHitHeight: CGFloat = 132
    static let controlsTransitionOffset: CGFloat = 30
    static let controlsTransitionScale: CGFloat = 0.97

    /// A strong ease-out lets the lyrics reclaim space immediately, then
    /// settles gently instead of moving at a constant speed.
    static let controlsLayoutAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.38
    )
    /// Motion and opacity deliberately use separate tracks. The spring gives
    /// the controls a restrained pop while the alpha curve fades them in
    /// quickly and eases through the final few percent.
    static let controlsRevealMotionAnimation = Animation.spring(
        response: 0.44,
        dampingFraction: 0.82,
        blendDuration: 0.08
    )
    static let controlsDismissMotionAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.28
    )
    static let controlsFadeInAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.24
    )
    static let controlsFadeOutAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.18
    )

    static let dismissDistance: CGFloat = 110
    static let dismissPrediction: CGFloat = 190
    static let miniPlayerExpandDistance: CGFloat = 28
    static let miniPlayerExpandPrediction: CGFloat = 72
    static let presentationAnimation = Animation.spring(
        response: 0.52,
        dampingFraction: 0.9,
        blendDuration: 0.1
    )

    static var immersiveHeaderTopInset: CGFloat {
        indicatorTopSpacing + indicatorHeight + indicatorToHeaderSpacing
    }

    static var dynamicIslandToIndicatorSpacing: CGFloat {
        dynamicIslandSafeAreaClearance + indicatorTopSpacing
    }

    static func shouldDismiss(
        translation: CGFloat,
        predictedTranslation: CGFloat
    ) -> Bool {
        translation > dismissDistance || predictedTranslation > dismissPrediction
    }

    static func shouldExpandFromMiniPlayer(
        translation: CGFloat,
        predictedTranslation: CGFloat
    ) -> Bool {
        translation < -miniPlayerExpandDistance
            || predictedTranslation < -miniPlayerExpandPrediction
    }

    /// The system can briefly report no accessory placement while it reparents
    /// the view between the expanded and inline tab-bar containers. Prefer the
    /// compact layout during that undefined interval so a full-width player
    /// cannot be laid out inside the inline container for a transient frame.
    static func shouldUseInlineMiniPlayerLayout(
        placementIsInline: Bool?
    ) -> Bool {
        placementIsInline ?? true
    }
}

private struct DismissNowPlayingActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

struct NowPlayingDismissDragAction {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void
}

private struct DismissNowPlayingDragActionKey: EnvironmentKey {
    static let defaultValue: NowPlayingDismissDragAction? = nil
}

extension EnvironmentValues {
    var dismissNowPlayingAction: (() -> Void)? {
        get { self[DismissNowPlayingActionKey.self] }
        set { self[DismissNowPlayingActionKey.self] = newValue }
    }

    var dismissNowPlayingDragAction: NowPlayingDismissDragAction? {
        get { self[DismissNowPlayingDragActionKey.self] }
        set { self[DismissNowPlayingDragActionKey.self] = newValue }
    }
}

/// Owns only presentation mechanics for Now Playing: the drag indicator and
/// interactive dismissal offset. Playback layout and safe areas remain in
/// `NowPlayingView` and SwiftUI's presentation container.
struct IOSNowPlayingPresentation<Content: View>: View {
    private let mode: NowPlayingMode
    private let usesSystemInteractiveDismissal: Bool
    private let dismissAnimation: Animation?
    private let content: Content

    @Binding private var isPresented: Bool
    @State private var dragOffset: CGFloat = 0

    init(
        isPresented: Binding<Bool>,
        mode: NowPlayingMode,
        usesSystemInteractiveDismissal: Bool = false,
        dismissAnimation: Animation? = NowPlayingPresentationMetrics.presentationAnimation,
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.mode = mode
        self.usesSystemInteractiveDismissal = usesSystemInteractiveDismissal
        self.dismissAnimation = dismissAnimation
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let isInteractive = proxy.size.width < 720 && mode != .classic
            let usesCustomDrag = isInteractive && !usesSystemInteractiveDismissal

            ZStack(alignment: .top) {
                content
                    .environment(\.dismissNowPlayingAction, dismiss)
                    .environment(
                        \.dismissNowPlayingDragAction,
                        dismissDragAction(usesCustomDrag: usesCustomDrag)
                    )

                if isInteractive {
                    dragIndicator
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: usesCustomDrag ? dragOffset : 0)
        }
    }

    @ViewBuilder
    private var dragIndicator: some View {
        if usesSystemInteractiveDismissal {
            dragIndicatorSurface
                .accessibilityLabel("下拉关闭播放页")
                .accessibilityAction(named: Text("关闭播放页"), dismiss)
        } else {
            dragIndicatorSurface
                .contentShape(Rectangle())
                .gesture(dismissGesture)
                .accessibilityLabel("下拉关闭播放页")
                .accessibilityAction(named: Text("关闭播放页"), dismiss)
        }
    }

    private var dragIndicatorSurface: some View {
        ZStack(alignment: .top) {
            Color.clear

            Capsule()
                .fill(.white.opacity(0.38))
                .frame(
                    width: NowPlayingPresentationMetrics.indicatorWidth,
                    height: NowPlayingPresentationMetrics.indicatorHeight
                )
                .padding(.top, NowPlayingPresentationMetrics.indicatorTopSpacing)
        }
        .frame(
            width: NowPlayingPresentationMetrics.indicatorHitWidth,
            height: NowPlayingPresentationMetrics.indicatorHitHeight
        )
        .accessibilityIdentifier("nowPlayingDismissIndicator")
    }

    private var dismissGesture: some Gesture {
        // The surface itself moves during the drag. Measuring in global
        // coordinates keeps the gesture origin fixed and prevents feedback
        // oscillation between the finger and the moving hit target.
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                updateDismissDrag(value.translation.height)
            }
            .onEnded { value in
                finishDismissDrag(
                    value.translation.height,
                    value.predictedEndTranslation.height
                )
            }
    }

    private func dismissDragAction(usesCustomDrag: Bool) -> NowPlayingDismissDragAction {
        NowPlayingDismissDragAction(
            onChanged: { translation in
                guard usesCustomDrag else { return }
                updateDismissDrag(translation)
            },
            onEnded: finishDismissDrag
        )
    }

    private func updateDismissDrag(_ translation: CGFloat) {
        dragOffset = max(translation, 0)
    }

    private func finishDismissDrag(_ translation: CGFloat, _ predictedTranslation: CGFloat) {
        if NowPlayingPresentationMetrics.shouldDismiss(
            translation: translation,
            predictedTranslation: predictedTranslation
        ) {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                dragOffset = 0
            }
        }
    }

    private func dismiss() {
        if let dismissAnimation {
            withAnimation(dismissAnimation) {
                isPresented = false
            }
        } else {
            isPresented = false
        }
    }
}
#endif
