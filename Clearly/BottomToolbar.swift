import SwiftUI
import AppKit
import ClearlyCore

/// Floating-pill bottom toolbar shown over the document content. Holds the
/// Edit/Preview segmented control, live word/character count, Copy menu, and
/// Outline toggle. Replaces the previous top SwiftUI `.toolbar` mode picker
/// and the inline `StatusBar` view.
struct BottomToolbar: View {
    @Binding var viewMode: ViewMode
    @ObservedObject var statusBarState: StatusBarState
    @ObservedObject var outlineState: OutlineState
    let fileURL: URL?
    let documentText: () -> String

    /// Reserved height for the bottom controls. `ContentView` passes this to
    /// `EditorView.extraBottomInset` and the preview CSS floor so content
    /// scrolls clear of the overlay.
    static let pillHeight: CGFloat = 40

    var body: some View {
        if #available(macOS 26.0, *) {
            glassBody
        } else {
            legacyBody
        }
    }

    @available(macOS 26.0, *)
    private var glassBody: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ModePill(viewMode: $viewMode)

                Spacer(minLength: 12)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)

                countText
                    .accessibilityLabel("\(statusBarState.counts.totalWords) words, \(statusBarState.counts.totalChars) characters")
                    .accessibilityAddTraits(.isStaticText)

                Spacer(minLength: 12)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)

                HStack(spacing: 8) {
                    glassCopyMenu
                    glassOutlineToggle
                }
            }
            .frame(height: Self.pillHeight)
        }
    }

    private var legacyBody: some View {
        HStack(spacing: 0) {
            ModePill(viewMode: $viewMode)

            Spacer(minLength: 12)
                .contentShape(Rectangle())
                .allowsHitTesting(false)

            countText
                .accessibilityLabel("\(statusBarState.counts.totalWords) words, \(statusBarState.counts.totalChars) characters")
                .accessibilityAddTraits(.isStaticText)

            Spacer(minLength: 12)
                .contentShape(Rectangle())
                .allowsHitTesting(false)

            HStack(spacing: 2) {
                copyMenu
                outlineToggle
            }
        }
        .frame(height: Self.pillHeight)
    }

    private var countText: some View {
        let counts = statusBarState.counts
        let words = counts.hasSelection ? counts.selectionWords : counts.totalWords
        let chars = counts.hasSelection ? counts.selectionChars : counts.totalChars
        return Text("\(words.formatted()) words \u{00B7} \(chars.formatted()) characters")
            .font(.system(size: 11))
            .tracking(0.3)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var copyMenu: some View {
        Menu {
            copyMenuContent
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(BottomToolbarIconStyle(isActive: false))
        .frame(width: 28, height: 28)
        .help("Copy document")
        .accessibilityLabel("Copy document")
    }

    private var outlineToggle: some View {
        Button {
            outlineState.isVisible.toggle()
        } label: {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(BottomToolbarIconStyle(isActive: outlineState.isVisible))
        .frame(width: 28, height: 28)
        .help("Toggle outline")
        .accessibilityLabel("Toggle outline")
        .accessibilityAddTraits(outlineState.isVisible ? .isSelected : [])
    }

    @available(macOS 26.0, *)
    private var glassCopyMenu: some View {
        Menu {
            copyMenuContent
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Copy document")
        .accessibilityLabel("Copy document")
    }

    @available(macOS 26.0, *)
    private var glassOutlineToggle: some View {
        Button {
            outlineState.isVisible.toggle()
        } label: {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            outlineState.isVisible
                ? .regular.tint(Color.accentColor.opacity(0.35)).interactive()
                : .regular.interactive(),
            in: .circle
        )
        .help("Toggle outline")
        .accessibilityLabel("Toggle outline")
        .accessibilityAddTraits(outlineState.isVisible ? .isSelected : [])
    }

    @ViewBuilder
    private var copyMenuContent: some View {
        Button("Copy Markdown")  { CopyActions.copyMarkdown(documentText()) }
        Button("Copy HTML")      { CopyActions.copyHTML(documentText()) }
        Button("Copy Rich Text") { CopyActions.copyRichText(documentText()) }
        Button("Copy Plain Text") { CopyActions.copyPlainText(documentText()) }
        Divider()
        Button("Copy File Path") {
            if let url = fileURL { CopyActions.copyFilePath(url) }
        }
        .disabled(fileURL == nil)
        Button("Copy File Name") {
            if let url = fileURL { CopyActions.copyFileName(url) }
        }
        .disabled(fileURL == nil)
    }
}

// MARK: - Edit / Preview segmented pill

private struct ModePill: View {
    @Binding var viewMode: ViewMode

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(macOS 26.0, *) {
            HStack(spacing: 2) {
                segment(.edit, title: "Edit", systemImage: "pencil")
                segment(.preview, title: "Preview", systemImage: "eye")
            }
            .padding(2)
            .glassEffect(.regular, in: .capsule)
        } else {
            HStack(spacing: 2) {
                segment(.edit, title: "Edit", systemImage: "pencil")
                segment(.preview, title: "Preview", systemImage: "eye")
            }
            .padding(2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(NSColor.unemphasizedSelectedContentBackgroundColor))
            )
        }
    }

    @ViewBuilder
    private func segment(_ mode: ViewMode, title: String, systemImage: String) -> some View {
        let isSelected = viewMode == mode

        Button {
            if reduceMotion {
                viewMode = mode
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    viewMode = mode
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: 22)
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 0.5)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) mode")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Mouse tracker (hover detection without blocking clicks)

/// NSView with an NSTrackingArea that fires `onHover` callbacks but returns
/// nil from `hitTest` so clicks pass through to whatever is underneath.
struct BottomHoverTracker: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrackingView)?.onHover = onHover
    }

    private final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

// MARK: - Right-side icon button style

private struct BottomToolbarIconStyle: ButtonStyle {
    let isActive: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .background {
                let opacity: Double = {
                    if configuration.isPressed { return 0.16 }
                    if isActive { return 0.14 }
                    if isHovering { return 0.08 }
                    return 0
                }()
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(opacity) : Color.primary.opacity(opacity))
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}
