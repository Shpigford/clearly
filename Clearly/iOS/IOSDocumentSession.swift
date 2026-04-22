#if os(iOS)
import Foundation
import Observation
import ClearlyCore

/// Per-open-document state on iOS. Mirrors the Mac's `OpenDocument` model:
/// authoritative `text`, `lastSavedText` snapshot for dirty computation, and
/// routed writes through `CoordinatedFileIO`. Owns one `DocumentPresenter` so
/// remote edits (Mac → iCloud → iPhone) refresh the open note in place.
///
/// Lifecycle: caller invokes `open(_:via:)` when a file is selected and
/// `close()` when navigating away. `.task(id:)` in the detail view and
/// `.onDisappear` / `.onChange(scenePhase)` hooks drive these calls.
@Observable
@MainActor
public final class IOSDocumentSession {

    public private(set) var file: VaultFile?
    public var text: String = "" {
        didSet {
            if oldValue != text, file != nil, text != lastSavedText {
                scheduleAutosave()
            }
        }
    }
    public private(set) var lastSavedText: String = ""
    public private(set) var conflictOutcome: ConflictResolver.Outcome?
    public private(set) var wasDeletedRemotely: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var isLoading: Bool = false

    public var isDirty: Bool { text != lastSavedText }
    public var hasConflict: Bool { conflictOutcome != nil || wasDeletedRemotely }

    @ObservationIgnored private var presenter: DocumentPresenter?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var isOwnWriteInFlight = false
    @ObservationIgnored private weak var vault: VaultSession?

    public static let autosaveDebounceSeconds: Double = 2.0

    public init() {}

    // MARK: - Lifecycle

    public func open(_ file: VaultFile, via vault: VaultSession) async {
        await close()

        self.vault = vault
        self.file = file
        isLoading = true
        errorMessage = nil
        text = ""
        lastSavedText = ""
        conflictOutcome = nil
        wasDeletedRemotely = false

        do {
            if file.isPlaceholder {
                try await vault.ensureDownloaded(file.url)
            }
            let loaded = try await vault.readRawText(at: file.url)
            lastSavedText = loaded
            text = loaded
            isLoading = false
            attachPresenter(for: file.url)
            resolveConflictIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    public func close(discardUnsavedChanges: Bool = false) async {
        if discardUnsavedChanges {
            autosaveTask?.cancel()
            autosaveTask = nil
        } else {
            await flush()
        }
        detachPresenter()
        autosaveTask?.cancel()
        autosaveTask = nil
        file = nil
        text = ""
        lastSavedText = ""
        conflictOutcome = nil
        wasDeletedRemotely = false
        errorMessage = nil
        isLoading = false
    }

    /// Called by the UI after the user has viewed the diff sheet and tapped "Done".
    public func dismissConflict() {
        conflictOutcome = nil
        wasDeletedRemotely = false
    }

    // MARK: - Save path

    public func flush() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard let file, isDirty else { return }
        await performSave(text: text, url: file.url)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let debounce = UInt64(Self.autosaveDebounceSeconds * 1_000_000_000)
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled, let self else { return }
            guard let file = self.file, self.isDirty else { return }
            await self.performSave(text: self.text, url: file.url)
        }
    }

    private func performSave(text: String, url: URL) async {
        isOwnWriteInFlight = true
        defer { isOwnWriteInFlight = false }
        let data = Data(text.utf8)
        let capturedPresenter = presenter
        do {
            try await Task.detached(priority: .utility) {
                try CoordinatedFileIO.write(data, to: url, presenter: capturedPresenter)
            }.value
            lastSavedText = text
            await autoRenameIfApplicable(text: text)
        } catch {
            // Don't clobber `errorMessage` here — that slot drives the
            // load-failure full-screen view, and a save failure must not
            // unmount the editor from under the user's in-progress edit.
            // Leaving `lastSavedText` unchanged keeps `isDirty` true, so
            // the nav-title bullet stays lit and the next autosave (or
            // the scene-phase flush) will retry the write.
            DiagnosticLog.log("IOSDocumentSession save failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Notes.app pattern: when an `Untitled.md` file gets meaningful content,
    /// rename it to derive its name from the first heading / line. The vault's
    /// renameFile fires `presentedItemDidMove`, which calls `handleRemoteMove`
    /// to update `self.file` — no need to set it manually here.
    private func autoRenameIfApplicable(text: String) async {
        guard let vault, let currentFile = self.file else { return }
        _ = await vault.autoRenameUntitledIfApplicable(currentFile, basedOn: text)
    }

    // MARK: - File presenter

    private func attachPresenter(for url: URL) {
        detachPresenter()
        let p = DocumentPresenter()
        p.url = url
        p.session = self
        NSFileCoordinator.addFilePresenter(p)
        presenter = p
    }

    private func detachPresenter() {
        guard let p = presenter else { return }
        NSFileCoordinator.removeFilePresenter(p)
        presenter = nil
    }

    // MARK: - Remote change handling

    fileprivate func handleRemoteChange() {
        guard !isOwnWriteInFlight, let file else { return }
        Task {
            do {
                let url = file.url
                let data = try await Task.detached(priority: .userInitiated) {
                    try CoordinatedFileIO.read(at: url)
                }.value
                let remote = String(decoding: data, as: UTF8.self)
                if !isDirty {
                    lastSavedText = remote
                    text = remote
                }
                resolveConflictIfNeeded()
            } catch {
                // Transient read failures are recoverable on the next change or reopen.
            }
        }
    }

    fileprivate func handleRemoteMove(to newURL: URL) {
        guard let f = file else { return }
        file = VaultFile(url: newURL, name: newURL.lastPathComponent, modified: f.modified, isPlaceholder: f.isPlaceholder)
    }

    fileprivate func handleRemoteDeletion() {
        detachPresenter()
        if isDirty {
            wasDeletedRemotely = true
            return
        }
        file = nil
        text = ""
        lastSavedText = ""
        conflictOutcome = nil
        wasDeletedRemotely = false
    }

    private func resolveConflictIfNeeded() {
        guard let url = file?.url else {
            conflictOutcome = nil
            return
        }
        let capturedPresenter = presenter
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ConflictResolver.Outcome?, Error> in
                do {
                    return .success(try ConflictResolver.resolveIfNeeded(at: url, presenter: capturedPresenter))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self, self.file?.url == url else { return }
            switch result {
            case .success(let outcome):
                if let outcome { self.conflictOutcome = outcome }
            case .failure(let error):
                DiagnosticLog.log("ConflictResolver failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}

/// Thin `NSFilePresenter` that hops every callback onto the main actor and
/// delegates to its owning session. `NSFileCoordinator` does not retain
/// presenters, so the session MUST call `removeFilePresenter` before the
/// presenter deallocates (handled in `IOSDocumentSession.close`).
private final class DocumentPresenter: NSObject, NSFilePresenter, @unchecked Sendable {

    var url: URL?
    weak var session: IOSDocumentSession?

    let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "com.sabotage.clearly.DocumentPresenter"
        return q
    }()

    var presentedItemURL: URL? { url }
    var presentedItemOperationQueue: OperationQueue { queue }

    func presentedItemDidChange() {
        Task { @MainActor [weak session] in
            session?.handleRemoteChange()
        }
    }

    func presentedItemDidMove(to newURL: URL) {
        url = newURL
        Task { @MainActor [weak session] in
            session?.handleRemoteMove(to: newURL)
        }
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor [weak session] in
            session?.handleRemoteDeletion()
        }
        completionHandler(nil)
    }
}
#endif
