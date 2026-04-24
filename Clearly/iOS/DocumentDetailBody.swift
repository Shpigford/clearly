#if os(iOS)
import SwiftUI
import ClearlyCore

/// Shared editor + preview body for the iOS document view. Both the iPhone
/// `RawTextDetailView_iOS` (where state is view-local) and the iPad
/// `IPadDetailView_iOS` (where state lives on an `IPadTab`) render through
/// this view by injecting the session + states + wiki-link handler.
///
/// Lifecycle (open/close/flush) is NOT handled here — the caller owns it.
struct DocumentDetailBody: View {
    @Environment(VaultSession.self) private var vault

    let session: IOSDocumentSession
    let file: VaultFile
    @Binding var viewMode: ViewMode
    @ObservedObject var outlineState: OutlineState
    @ObservedObject var backlinksState: BacklinksState
    let onOpenFile: (VaultFile) -> Void

    @State private var showBacklinks = false
    @State private var showOutline = false
    @State private var showConflictDiff = false
    @StateObject private var findState = FindState()

    var body: some View {
        VStack(spacing: 0) {
            if session.hasConflict { conflictBanner }
            if findState.isVisible {
                FindOverlay_iOS(findState: findState)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
        }
        .animation(Theme.Motion.smooth, value: findState.isVisible)
        .onChange(of: viewMode) { _, newMode in
            findState.activeMode = newMode
            if newMode != .edit, findState.isVisible {
                findState.dismiss()
            }
        }
        .onAppear { findState.activeMode = viewMode }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewMode = (viewMode == .edit) ? .preview : .edit
                } label: {
                    Image(systemName: viewMode == .edit ? "eye" : "square.and.pencil")
                }
                .accessibilityLabel(viewMode == .edit ? "Show preview" : "Show editor")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    findState.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("Find in note")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showOutline = true } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .accessibilityLabel("Outline")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showBacklinks = true } label: {
                    Image(systemName: "link")
                }
                .accessibilityLabel("Backlinks")
            }
        }
        .onAppear {
            // Resync outline + backlinks on every mount. Needed because:
            // (1) .onChange(of: session.text) doesn't fire for the initial
            //     value on a fresh mount, so tab-switch remounts would show
            //     stale outlines when a remote edit updated session.text
            //     while the tab was inactive.
            // (2) refreshBacklinks is wired to indexProgress transitions
            //     elsewhere, but a tab opened during steady-state (no
            //     indexing in flight) would have no initial backlinks.
            outlineState.parseHeadings(from: session.text)
            refreshBacklinks()
        }
        .onChange(of: session.text) { _, newText in
            outlineState.parseHeadings(from: newText)
        }
        .onChange(of: vault.indexProgress) { _, newValue in
            if newValue == nil { refreshBacklinks() }
        }
        .sheet(isPresented: $showBacklinks) {
            BacklinksSheet_iOS(backlinksState: backlinksState, onOpenFile: onOpenFile)
                .environment(vault)
        }
        .sheet(isPresented: $showOutline) {
            OutlineSheet_iOS(outlineState: outlineState, onJump: jumpToHeading)
        }
        .sheet(isPresented: $showConflictDiff) {
            conflictDiffSheet
        }
    }

    @ViewBuilder
    private var conflictDiffSheet: some View {
        if let outcome = session.conflictOutcome {
            DiffView(
                leftTitle: file.name,
                leftText: outcome.currentText,
                rightTitle: "Conflict copy",
                rightText: outcome.siblingText,
                footer: "Conflict saved as \(outcome.siblingURL.lastPathComponent) — edit either file to keep it.",
                onDismiss: {
                    session.dismissConflict()
                    showConflictDiff = false
                }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.isLoading {
            ProgressView(file.isPlaceholder ? "Downloading from iCloud…" : "Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = session.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle.weight(.light))
                    .foregroundStyle(Theme.warningColorSwiftUI)
                Text("Couldn't open this note")
                    .font(.headline)
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Both editor and preview stay mounted; toggling viewMode just
            // flips opacity + hit-testing. Prevents the ~2s WKWebView cold
            // start every time the user hits Preview — first mount still
            // pays that cost, subsequent edit↔preview flips are instant.
            ZStack {
                EditorView_iOS(
                    text: Binding(
                        get: { session.text },
                        set: { session.text = $0 }
                    ),
                    documentURL: file.url,
                    outlineState: outlineState,
                    findState: findState
                )
                .opacity(viewMode == .edit ? 1 : 0)
                .allowsHitTesting(viewMode == .edit)

                PreviewView_iOS(
                    markdown: session.text,
                    fileURL: file.url,
                    isVisible: viewMode == .preview,
                    onWikiLinkClicked: handleWikiLink,
                    onTaskToggle: handleTaskToggle
                )
                .opacity(viewMode == .preview ? 1 : 0)
                .allowsHitTesting(viewMode == .preview)
            }
        }
    }

    private func refreshBacklinks() {
        let indexes = [vault.currentIndex].compactMap { $0 }
        backlinksState.update(for: file.url, using: indexes)
    }

    private func jumpToHeading(_ heading: HeadingItem) {
        viewMode = .edit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            outlineState.scrollToRange?(heading.range)
        }
    }

    private func handleWikiLink(_ target: String) {
        Task {
            do {
                let file = try await vault.openOrCreate(name: target)
                await MainActor.run { onOpenFile(file) }
            } catch {
                DiagnosticLog.log("Wiki-link open/create failed for \(target): \(error)")
            }
        }
    }

    private func handleTaskToggle(_ line: Int, _ checked: Bool) {
        var lines = session.text.components(separatedBy: "\n")
        let idx = line - 1
        guard idx >= 0, idx < lines.count else { return }
        if checked {
            lines[idx] = lines[idx]
                .replacingOccurrences(of: "- [ ]", with: "- [x]")
                .replacingOccurrences(of: "* [ ]", with: "* [x]")
                .replacingOccurrences(of: "+ [ ]", with: "+ [x]")
        } else {
            lines[idx] = lines[idx]
                .replacingOccurrences(of: "- [x]", with: "- [ ]")
                .replacingOccurrences(of: "- [X]", with: "- [ ]")
                .replacingOccurrences(of: "* [x]", with: "* [ ]")
                .replacingOccurrences(of: "* [X]", with: "* [ ]")
                .replacingOccurrences(of: "+ [x]", with: "+ [ ]")
                .replacingOccurrences(of: "+ [X]", with: "+ [ ]")
        }
        session.text = lines.joined(separator: "\n")
    }

    private var conflictBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warningColorSwiftUI)
            Text(bannerText)
                .font(.footnote)
            Spacer()
            if session.conflictOutcome != nil {
                Button("View diff") { showConflictDiff = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.warningColorSwiftUI.opacity(0.12))
    }

    private var bannerText: String {
        if session.wasDeletedRemotely {
            return "This note was deleted on another device."
        }
        return "This note has an offline conflict"
    }
}
#endif
