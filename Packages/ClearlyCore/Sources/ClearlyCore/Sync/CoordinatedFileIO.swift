import Foundation

public enum CoordinatedFileIO {
    public static func read(at url: URL) throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [], error: &coordinatorError
        ) { resolved in
            result = Result { try Data(contentsOf: resolved) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    public static func write(_ data: Data, to url: URL) throws {
        try write(data, to: url, presenter: nil)
    }

    /// Writes `data` atomically to `url`, passing `presenter` to the
    /// `NSFileCoordinator`. When a presenter is supplied, the coordinator
    /// suppresses callbacks back to that presenter for this operation — so
    /// the caller doesn't see its own write echo back through
    /// `presentedItemDidChange`.
    public static func write(_ data: Data, to url: URL, presenter: NSFilePresenter?) throws {
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinatorError
        ) { resolved in
            do { try data.write(to: resolved, options: .atomic) }
            catch { writeError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    public static func move(from src: URL, to dst: URL) throws {
        var coordinatorError: NSError?
        var moveError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: src, options: .forMoving,
            writingItemAt: dst, options: .forReplacing,
            error: &coordinatorError
        ) { resolvedSrc, resolvedDst in
            do { try FileManager.default.moveItem(at: resolvedSrc, to: resolvedDst) }
            catch { moveError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let moveError { throw moveError }
    }

    public static func delete(at url: URL) throws {
        var coordinatorError: NSError?
        var deleteError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinatorError
        ) { resolved in
            do { try FileManager.default.removeItem(at: resolved) }
            catch { deleteError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let deleteError { throw deleteError }
    }
}
