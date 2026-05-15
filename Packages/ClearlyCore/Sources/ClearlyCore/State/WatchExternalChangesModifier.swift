import SwiftUI

/// Outcome of comparing on-disk content to the in-memory editor text when an
/// external write fires.
public enum ExternalChangeDecision: Equatable {
    /// Disk content matches the editor already — almost certainly the echo
    /// from our own save (DocumentGroup autosave). No-op.
    case ignoreEcho
    /// The user has typed since the last on-disk version we observed.
    /// Dropping the external change preserves their unsaved work.
    case ignoreDirty
    /// Safe to overwrite the editor with the new disk content.
    case apply(String)
}

/// Pure policy function. Echo-detection wins over dirty-detection so that
/// a save round-trip where the editor and disk agree is always a no-op,
/// even if `lastKnownDisk` lags.
public func mergeExternalChange(
    disk: String,
    currentText: String,
    lastKnownDisk: String
) -> ExternalChangeDecision {
    if disk == currentText { return .ignoreEcho }
    if currentText != lastKnownDisk { return .ignoreDirty }
    return .apply(disk)
}

/// State machine that pairs `mergeExternalChange` with a baseline that
/// advances on every observed on-disk content (initial load + each presenter
/// callback). Baseline does NOT advance on user typing — that's the whole
/// point of dirty detection. Extracted so the policy is unit-testable without
/// a SwiftUI host.
public final class ExternalChangeReducer {
    private(set) public var lastKnownDisk: String

    public init(initialText: String) {
        self.lastKnownDisk = initialText
    }

    /// Returns the new editor text iff the change should be applied. Always
    /// advances `lastKnownDisk` to the observed disk content.
    public func observe(disk: String, currentText: String) -> String? {
        let decision = mergeExternalChange(disk: disk, currentText: currentText, lastKnownDisk: lastKnownDisk)
        lastKnownDisk = disk
        if case .apply(let new) = decision { return new }
        return nil
    }
}

public extension View {
    /// Watch the file at `fileURL` for out-of-process modifications and
    /// reflect them into `text` when safe (editor not mid-edit).
    ///
    /// `onApply` fires immediately after the editor binding is updated with
    /// new disk content. The Mac app uses this hook to refresh the underlying
    /// `NSDocument`'s bookkeeping so SwiftUI's autosave doesn't pop a
    /// "file changed by another application" conflict dialog.
    func watchExternalChanges(
        fileURL: URL?,
        text: Binding<String>,
        onApply: ((URL) -> Void)? = nil
    ) -> some View {
        modifier(WatchExternalChangesModifier(fileURL: fileURL, text: text, onApply: onApply))
    }
}

private struct WatchExternalChangesModifier: ViewModifier {
    let fileURL: URL?
    @Binding var text: String
    let onApply: ((URL) -> Void)?

    @State private var watcher: ExternalFileWatcher?
    @State private var reducer: ExternalChangeReducer?
    /// Bumped on every `bind()`. `presentedItemDidChange` callbacks captured
    /// from the OLD watcher can still complete after `removeFilePresenter`
    /// (Apple's API only guarantees deregistration, not synchronous drain).
    /// We snapshot this token into each watcher's closure and drop callbacks
    /// whose token no longer matches the current generation.
    @State private var bindGeneration: Int = 0

    func body(content: Content) -> some View {
        content
            .onAppear { bind(to: fileURL) }
            .onDisappear {
                watcher?.stop()
                watcher = nil
                reducer = nil
                bindGeneration &+= 1
            }
            .onChange(of: fileURL) { _, newURL in
                bind(to: newURL)
            }
    }

    private func bind(to url: URL?) {
        watcher?.stop()
        bindGeneration &+= 1
        guard let url else {
            watcher = nil
            reducer = nil
            return
        }
        // FileDocument's init(configuration:) set `text` from disk just before
        // the view appeared, so `text` is the right baseline at bind time.
        let reducer = ExternalChangeReducer(initialText: text)
        self.reducer = reducer
        let onApply = self.onApply
        let token = bindGeneration
        watcher = ExternalFileWatcher(url: url) { diskText in
            // Watcher invokes on its operation queue; SwiftUI state mutations
            // must run on main.
            DispatchQueue.main.async {
                // Drop callbacks left over from a previous watcher — those
                // carry the wrong file's content and would clobber the editor.
                guard token == bindGeneration else { return }
                if let newText = reducer.observe(disk: diskText, currentText: text) {
                    text = newText
                    onApply?(url)
                }
            }
        }
    }
}
