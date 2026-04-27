import Foundation

/// Coordinates the three async readers (stdout, stderr, termination) of a
/// `Process` subprocess and resumes a single continuation exactly once when
/// all three have completed. Used by both `ClaudeCLIAgentRunner` and
/// `CodexCLIAgentRunner` — the streaming/teardown shape is identical, only
/// the post-process parsing differs.
final class ProcessCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData: Data?
    private var stderrData: Data?
    private var status: Int32?
    private var didResume = false

    func finishStdout(
        _ data: Data,
        continuation: CheckedContinuation<(Data, String, Int32), Error>
    ) {
        complete(continuation: continuation) {
            stdoutData = data
        }
    }

    func finishStderr(
        _ data: Data,
        continuation: CheckedContinuation<(Data, String, Int32), Error>
    ) {
        complete(continuation: continuation) {
            stderrData = data
        }
    }

    func finish(
        status: Int32,
        continuation: CheckedContinuation<(Data, String, Int32), Error>
    ) {
        complete(continuation: continuation) {
            self.status = status
        }
    }

    func fail(
        _ error: Error,
        continuation: CheckedContinuation<(Data, String, Int32), Error>
    ) {
        var shouldResume = false
        lock.lock()
        if !didResume {
            didResume = true
            shouldResume = true
        }
        lock.unlock()
        if shouldResume {
            continuation.resume(throwing: error)
        }
    }

    private func complete(
        continuation: CheckedContinuation<(Data, String, Int32), Error>,
        update: () -> Void
    ) {
        var result: (Data, String, Int32)?
        lock.lock()
        update()
        if !didResume,
           let stdoutData,
           let stderrData,
           let status {
            didResume = true
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            result = (stdoutData, stderrText, status)
        }
        lock.unlock()
        if let result {
            continuation.resume(returning: result)
        }
    }
}
