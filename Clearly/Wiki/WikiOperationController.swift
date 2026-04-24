import Foundation
import ClearlyCore

/// Owns the currently-staged `WikiOperation` and drives the diff-review sheet.
/// A recipe run (Ingest / Query / Lint) or the `propose_operation` MCP tool
/// calls `stage(_:)`, which shows the sheet; `accept(at:)` commits on disk via
/// `WikiOperationApplier`; `dismiss()` rejects and clears state.
///
/// Per-file rejection is tracked in `rejectedPaths` — the user can drop
/// individual files from the batch without cancelling the whole operation.
@Observable
@MainActor
final class WikiOperationController {
    var stagedOperation: WikiOperation?
    var selectedPath: String?
    var rejectedPaths: Set<String> = []
    var isApplying: Bool = false
    var applyError: String?

    var isPresenting: Bool { stagedOperation != nil }

    /// Changes the user has kept for apply — staged minus rejected.
    var effectiveChanges: [FileChange] {
        guard let op = stagedOperation else { return [] }
        return op.changes.filter { !rejectedPaths.contains($0.path) }
    }

    // MARK: - Staging

    func stage(_ operation: WikiOperation) {
        stagedOperation = operation
        selectedPath = operation.changes.first?.path
        rejectedPaths = []
        applyError = nil
        isApplying = false
    }

    func dismiss() {
        stagedOperation = nil
        selectedPath = nil
        rejectedPaths = []
        applyError = nil
        isApplying = false
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

    // MARK: - Apply

    /// Applies the effective (non-rejected) changes under `vaultRoot`. On
    /// success, clears state and calls `onApplied` with the applied operation
    /// so callers can append to `log.md`, refresh the tree, etc.
    func accept(
        at vaultRoot: URL,
        onApplied: ((WikiOperation) -> Void)? = nil
    ) {
        guard let staged = stagedOperation else { return }
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
                    onApplied?(applied)
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
}
