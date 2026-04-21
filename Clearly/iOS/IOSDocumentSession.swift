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
    public private(set) var hasConflict: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var isLoading: Bool = false

    public var isDirty: Bool { text != lastSavedText }

    @ObservationIgnored private var presenter: DocumentPresenter?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var isOwnWriteInFlight = false

    public static let autosaveDebounceSeconds: Double = 2.0

    public init() {}

    // MARK: - Lifecycle

    public func open(_ file: VaultFile, via vault: VaultSession) async {
        await close()

        self.file = file
        isLoading = true
        errorMessage = nil
        text = ""
        lastSavedText = ""
        hasConflict = false

        do {
            if file.isPlaceholder {
                try await vault.ensureDownloaded(file.url)
            }
            let loaded = try await vault.readRawText(at: file.url)
            lastSavedText = loaded
            text = loaded
            isLoading = false
            attachPresenter(for: file.url)
            checkForConflict()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    public func close() async {
        await flush()
        detachPresenter()
        autosaveTask?.cancel()
        autosaveTask = nil
        file = nil
        text = ""
        lastSavedText = ""
        hasConflict = false
        errorMessage = nil
        isLoading = false
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
                checkForConflict()
            } catch {
                // Transient read failures are recoverable on the next change or reopen.
            }
        }
    }

    fileprivate func handleRemoteMove(to newURL: URL) {
        guard let f = file else { return }
        file = VaultFile(url: newURL, name: f.name, modified: f.modified, isPlaceholder: f.isPlaceholder)
    }

    fileprivate func handleRemoteDeletion() {
        detachPresenter()
        if isDirty {
            hasConflict = true
            return
        }
        file = nil
        text = ""
        lastSavedText = ""
        hasConflict = false
    }

    private func checkForConflict() {
        guard let url = file?.url else { hasConflict = false; return }
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        hasConflict = !versions.isEmpty
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
