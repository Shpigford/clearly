import Foundation
import ClearlyCore

/// Owns the currently-staged `WikiOperation` and drives the diff-review sheet.
/// A recipe run (Capture / Chat / Review) or the `propose_operation` MCP tool
/// calls `stage(_:vaultRoot:)`, which shows the sheet; `accept()` commits on disk via
/// `WikiOperationApplier`; `dismiss()` rejects and clears state.
///
/// Per-file rejection is tracked in `rejectedPaths` — the user can drop
/// individual files from the batch without cancelling the whole operation.
@Observable
@MainActor
final class WikiOperationController {
    var stagedOperation: WikiOperation?
    var stagedVaultRoot: URL?
    var selectedPath: String?
    var rejectedPaths: Set<String> = []
    var isApplying: Bool = false
    var applyError: String?

    /// Auto-Review parks its proposal here instead of staging immediately, so
    /// the diff sheet doesn't pop in the user's face on vault open. The
    /// LogSidebar header surfaces a ready badge while a pending op
    /// exists; clicking the badge calls `presentPending()` to move it onto
    /// the staged slot and open the sheet.
    var pendingOperation: WikiOperation?
    var pendingVaultRoot: URL?
    var hasPendingOperation: Bool { pendingOperation != nil }
    var pendingOperationLabel: String {
        switch pendingOperation?.kind {
        case .capture: return "Capture"
        case .chat: return "Chat"
        case .review: return "Review"
        case .integrate: return "Integrate"
        case .other, .none: return "Operation"
        }
    }

    /// Set while an *interactive* recipe (Capture) is running — drives the
    /// progress overlay so a long cache warmup doesn't look like silent
    /// failure. Auto-Review uses `isAutoReviewing` instead so it stays out
    /// of the user's face.
    var isRunningRecipe: Bool = false
    var recipeStatus: String?

    /// Set while auto-Review runs silently in the background. Used only for
    /// double-fire prevention; never drives a UI overlay.
    var isAutoReviewing: Bool = false

    var isPresenting: Bool { stagedOperation != nil }

    func startRecipe(_ status: String) {
        isRunningRecipe = true
        recipeStatus = status
    }

    func updateRecipeStatus(_ status: String) {
        recipeStatus = status
    }

    func finishRecipe() {
        isRunningRecipe = false
        recipeStatus = nil
    }

    /// Changes the user has kept for apply — staged minus rejected.
    var effectiveChanges: [FileChange] {
        guard let op = stagedOperation else { return [] }
        return op.changes.filter { !rejectedPaths.contains($0.path) }
    }

    // MARK: - Staging

    func stage(_ operation: WikiOperation, vaultRoot: URL?) {
        stagedOperation = operation
        stagedVaultRoot = vaultRoot
        selectedPath = operation.changes.first?.path
        rejectedPaths = []
        applyError = nil
        isApplying = false
    }

    func dismiss() {
        recordHandledReviewIfNeeded()
        stagedOperation = nil
        stagedVaultRoot = nil
        selectedPath = nil
        rejectedPaths = []
        applyError = nil
        isApplying = false
    }

    // MARK: - Pending review
    //
    // `pendingOperation` has its own lifecycle independent of `stagedOperation`.
    // It's set by `holdForReview` (auto-Review) and consumed by `presentPending`
    // (badge click). Dismissing or accepting an unrelated staged op (Capture /
    // Chat) must NOT touch the pending slot — losing a held Review because
    // the user closed a Capture sheet would be a real bug.

    func holdForReview(_ operation: WikiOperation, vaultRoot: URL) {
        pendingOperation = operation
        pendingVaultRoot = vaultRoot
    }

    func presentPending() {
        guard let op = pendingOperation, let root = pendingVaultRoot else { return }
        pendingOperation = nil
        pendingVaultRoot = nil
        stage(op, vaultRoot: root)
    }

    func clearPendingReviewIfVaultChanged(to activeVaultRoot: URL?) {
        guard pendingOperation != nil || pendingVaultRoot != nil else { return }
        guard
            let pendingVaultRoot,
            let activeVaultRoot,
            Self.sameFileURL(pendingVaultRoot, activeVaultRoot)
        else {
            pendingOperation = nil
            pendingVaultRoot = nil
            return
        }
    }

    // MARK: - Per-file reject

    func toggleReject(path: String) {
        if rejectedPaths.contains(path) {
            rejectedPaths.remove(path)
        } else {
            rejectedPaths.insert(path)
        }
    }

    func isRejected(_ path: String) -> Bool {
        rejectedPaths.contains(path)
    }

    private func recordHandledReviewIfNeeded() {
        guard stagedOperation?.kind == .review, let stagedVaultRoot else { return }
        WikiVaultState.recordReviewRun(at: stagedVaultRoot)
    }

    // MARK: - Apply

    /// Applies the effective (non-rejected) changes under the staged vault. On
    /// success, clears state and calls `onApplied` with the applied operation
    /// so callers can append to `log.md`, refresh the tree, etc.
    func accept(
        onApplied: ((WikiOperation, URL) -> Void)? = nil
    ) {
        guard let staged = stagedOperation else { return }
        guard let vaultRoot = stagedVaultRoot else {
            applyError = "No vault selected for this operation."
            return
        }
        let changes = effectiveChanges
        if changes.isEmpty {
            // All files rejected — treat as dismiss.
            dismiss()
            return
        }
        let applied = WikiOperation(
            id: staged.id,
            kind: staged.kind,
            title: staged.title,
            rationale: staged.rationale,
            changes: changes,
            createdAt: staged.createdAt
        )

        isApplying = true
        applyError = nil

        Task.detached(priority: .userInitiated) {
            do {
                try WikiOperationApplier.apply(applied, at: vaultRoot)
                await MainActor.run {
                    self.dismiss()
                    onApplied?(applied, vaultRoot)
                }
            } catch {
                await MainActor.run {
                    self.applyError = Self.describe(error)
                    self.isApplying = false
                }
            }
        }
    }

    // MARK: - Error formatting

    private static func describe(_ error: Error) -> String {
        if let apply = error as? WikiOperationApplier.ApplyError {
            switch apply {
            case .pathAlreadyExists(let p):
                return "Can't create \(p): a file is already there."
            case .pathNotFound(let p):
                return "Can't modify or delete \(p): the file doesn't exist."
            case .modifyBaseMismatch(let p):
                return "\(p) was edited since the agent proposed this change. Re-run the operation."
            case .deleteContentMismatch(let p):
                return "\(p) contents changed since the agent proposed deleting it."
            case .nonUTF8Contents(let p):
                return "\(p) isn't valid UTF-8."
            case .ioFailure(let p, let message):
                return "IO failure on \(p): \(message)"
            case .rollbackFailed(let original, let applied):
                return "Apply failed (\(original)) and rollback also failed on: \(applied.joined(separator: ", ")). Check the vault manually."
            }
        }
        if let validation = error as? WikiOperationError {
            switch validation {
            case .noChanges: return "Operation has no changes."
            case .duplicatePath(let p): return "Duplicate path in operation: \(p)."
            case .pathIsAbsolute(let p): return "Path must be vault-relative: \(p)."
            case .pathEscapesVault(let p): return "Path escapes the vault: \(p)."
            case .pathIsEmpty: return "Operation has an empty path."
            case .noOpModify(let p): return "Modify for \(p) has identical before/after."
            }
        }
        return String(describing: error)
    }

    private static func sameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path ==
            rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
