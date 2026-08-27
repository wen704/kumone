import SwiftUI

// MARK: - iOS 15 navigation compatibility
//
// iOS 16+ keeps NavigationStack / NavigationLink(value:) / navigationDestination.
// iOS 15 falls back to NavigationView(.stack) with classic
// NavigationLink(destination:) links, which embed their destination directly,
// so `DestinationsModifier` registers nothing there.

/// Stack container: `NavigationStack` bound to the `[Destination]` path on
/// iOS 16+/macOS; `NavigationView` (stack style) on iOS 15.
///
/// On iOS 15 there is no path binding, so popping to the root is done by
/// recreating the view tree: increment `generation` (the 16+ branch ignores it).
struct AppNavigationStack<Content: View>: View {
    @Binding var path: [Destination]
    var generation: Int = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(macOS)
        NavigationStack(path: $path) { content() }
        #else
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) { content() }
        } else {
            NavigationView { content() }
                .navigationViewStyle(.stack)
                .id(generation)
        }
        #endif
    }
}

/// Navigation link driven by a `Destination` value: `NavigationLink(value:)`
/// on iOS 16+/macOS, classic `NavigationLink(destination:)` on iOS 15.
struct AppNavLink<Label: View>: View {
    let value: Destination
    @ViewBuilder var label: () -> Label

    var body: some View {
        #if os(macOS)
        NavigationLink(value: value) { label() }
        #else
        if #available(iOS 16.0, *) {
            NavigationLink(value: value) { label() }
        } else {
            NavigationLink(destination: DestinationContent(destination: value)) { label() }
        }
        #endif
    }
}

/// Programmatic push for iOS 15: `NavigationView` has no path, so a hidden
/// `NavigationLink(isActive:)` drives it. Renders nothing on iOS 16+ (the
/// caller appends to the path instead).
struct LegacyPushLink: View {
    @Binding var isPushed: Bool
    let destination: Destination

    var body: some View {
        if #available(iOS 16.0, *) {
            EmptyView()
        } else {
            NavigationLink(
                isActive: $isPushed,
                destination: { DestinationContent(destination: destination) },
                label: { EmptyView() }
            )
            .hidden()
        }
    }
}

/// Sheet 内的导航根容器:`NavigationStack`(iOS 16+/macOS)或
/// `NavigationView(.stack)`(iOS 15),行为一致。
struct SheetNavigationRoot<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(macOS)
        NavigationStack { content() }
        #else
        if #available(iOS 16.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }
                .navigationViewStyle(.stack)
        }
        #endif
    }
}

// MARK: - Text-entry prompt compatibility

extension View {
    /// 文字输入弹窗。iOS 16+ 用 alert(内嵌 TextField 从 16 才真正渲染),
    /// iOS 15 降级为带输入框的小 sheet;macOS 保持 alert。
    @ViewBuilder
    func playlistCreationPrompt(
        isPresented: Binding<Bool>,
        name: Binding<String>,
        onCreate: @escaping (String) -> Void
    ) -> some View {
        #if os(macOS)
        self.alert("新建歌单", isPresented: isPresented) {
            TextField("歌单名称", text: name)
            Button("创建") { onCreate(name.wrappedValue) }
            Button("取消", role: .cancel) { name.wrappedValue = "" }
        }
        #else
        if #available(iOS 16.0, *) {
            self.alert("新建歌单", isPresented: isPresented) {
                TextField("歌单名称", text: name)
                Button("创建") { onCreate(name.wrappedValue) }
                Button("取消", role: .cancel) { name.wrappedValue = "" }
            }
        } else {
            self.sheet(isPresented: isPresented) {
                PlaylistCreationSheet(name: name, onCreate: onCreate)
            }
        }
        #endif
    }
}

#if os(iOS)
/// iOS 15 回退:alert 内嵌 TextField 不会渲染,改用小 sheet。
private struct PlaylistCreationSheet: View {
    @Binding var name: String
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                TextField("歌单名称", text: $name)
                    .focused($focused)
                    .onSubmit(create)
            }
            .navigationTitle("新建歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        name = ""
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { focused = true }
    }

    private func create() {
        onCreate(name)
        dismiss()
    }
}
#endif
