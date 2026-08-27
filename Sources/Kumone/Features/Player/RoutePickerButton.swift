import AVKit
import SwiftUI

/// System AirPlay / output-route picker (`AVRoutePickerView`), styled to sit
/// among the transport controls. Because playback is audio-only (AVPlayer with
/// no video track), selecting a route sends audio to the device — it does not
/// mirror the screen.
struct RoutePickerButton: View {
    var diameter: CGFloat = 40
    var glyphSize: CGFloat = 15
    var request = 0
    /// White-on-glass (now-playing) vs. accent-aware (player bar).
    var tint: Color = .white.opacity(0.8)
    var background: Color = .white.opacity(0.1)

    var body: some View {
        RoutePickerRepresentable(
            tint: PlatformColor(tint), glyphSize: glyphSize, request: request
        )
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
            .help("AirPlay")
    }
}

#if os(iOS)
private struct RoutePickerRepresentable: UIViewRepresentable {
    let tint: UIColor
    let glyphSize: CGFloat
    let request: Int

    final class Coordinator {
        var request: Int
        init(request: Int) { self.request = request }
    }

    func makeCoordinator() -> Coordinator { Coordinator(request: request) }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.backgroundColor = .clear
        view.tintColor = tint
        view.activeTintColor = UIColor(Theme.accent)
        view.prioritizesVideoDevices = false // audio routing, not screen mirroring
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        guard request != context.coordinator.request else { return }
        context.coordinator.request = request
        DispatchQueue.main.async {
            view.subviews.compactMap { $0 as? UIButton }.first?
                .sendActions(for: .touchUpInside)
        }
    }
}
#elseif os(macOS)
private struct RoutePickerRepresentable: NSViewRepresentable {
    let tint: NSColor
    let glyphSize: CGFloat
    let request: Int

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(tint, for: .normal)
        view.setRoutePickerButtonColor(NSColor(Theme.accent), for: .active)
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.setRoutePickerButtonColor(tint, for: .normal)
    }
}
#endif
