import Foundation
import ClearlyCore

/// Spawns the user's locally-installed `codex` CLI to answer a prompt. This
/// is the OpenAI-side counterpart to `ClaudeCLIAgentRunner`; Codex Pro
/// subscribers get the same flat-rate benefit. The binary keeps its own
/// auth token at `~/.codex/auth.json`; Clearly never touches it.
///
/// Invocation:
///   codex exec --json --skip-git-repo-check --sandbox read-only --ephemeral \
///              --output-last-message <tmpfile> [--model <m>] -
///
/// - `--json` emits a JSONL event stream on stdout (`turn.started`,
///   `item.*`, `turn.completed`). We only read `turn.completed` for usage.
/// - `--skip-git-repo-check` lets it run outside a git repo (most vaults).
/// - `--sandbox read-only` allows shell commands but blocks writes — fine
///   for wiki recipes because writes are funneled through `WikiOperationApplier`.
/// - `--ephemeral` keeps the call stateless (no on-disk session history).
/// - `--output-last-message <file>` writes the final assistant text cleanly
///   to a file, sparing us from parsing it out of the JSONL stream.
/// - Trailing `-` makes Codex read the prompt from stdin (matches the
///   `ClaudeCLIAgentRunner` stdin convention; avoids ARG_MAX issues).
///
/// MCP wiring deliberately omitted — see the matching note in `ClaudeCLIAgentRunner`.
struct CodexCLIAgentRunner: AgentRunner {
    let binaryURL: URL
    let environment: [String: String]
    /// Overrides the default stable caches-dir cwd. Used so `codex exec`
    /// treats the vault as its workspace and its sandboxed read tools see
    /// the user's notes.
    let workingDirectoryOverride: URL?

    init(
        binaryURL: URL,
        workingDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.binaryURL = binaryURL
        self.workingDirectoryOverride = workingDirectory
        self.environment = environment
    }

    func run(prompt: String, model: String?) async throws -> AgentResult {
        let outputURL = Self.makeOutputFileURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let arguments = Self.buildArguments(model: model, outputFile: outputURL.path)
        let (stdoutData, stderrText, status) = try await spawn(prompt: prompt, arguments: arguments)

        guard status == 0 else {
            throw AgentError.transport("codex exited with status \(status). stderr: \(stderrText.prefix(512))")
        }

        let usage = Self.extractUsage(from: stdoutData)
        if let cached = usage.cached {
            DiagnosticLog.log("codex usage in=\(usage.input) cached=\(cached) out=\(usage.output)")
        } else {
            DiagnosticLog.log("codex usage in=\(usage.input) out=\(usage.output)")
        }

        let text = try Self.readLastMessage(at: outputURL)
        return AgentResult(
            text: text,
            inputTokens: usage.input,
            outputTokens: usage.output,
            model: "codex-cli"
        )
    }

    // MARK: - Argument layout

    static func buildArguments(model: String?, outputFile: String) -> [String] {
        var args: [String] = [
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--ephemeral",
            "--output-last-message", outputFile,
        ]
        if let model, !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }
        // Positional prompt argument; "-" means read stdin.
        args.append("-")
        return args
    }

    // MARK: - Process plumbing

    private func spawn(prompt: String, arguments: [String]) async throws -> (Data, String, Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectoryOverride ?? Self.stableWorkingDirectory()
            // See ClaudeCLIAgentRunner.environmentForSubprocess — app-launched
            // env can point CLI auth lookups at the wrong home.
            process.environment = ClaudeCLIAgentRunner.environmentForSubprocess(
                base: environment,
                currentDirectory: process.currentDirectoryURL,
                binaryURL: binaryURL
            )

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            let capture = ProcessCaptureState()
            process.terminationHandler = { _ in
                capture.finish(status: process.terminationStatus, continuation: continuation)
            }

            do {
                try process.run()
            } catch {
                capture.fail(AgentError.transport(String(describing: error)), continuation: continuation)
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                capture.finishStdout(data, continuation: continuation)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                capture.finishStderr(data, continuation: continuation)
            }

            let writer = stdin.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = prompt.data(using: .utf8) {
                    try? writer.write(contentsOf: data)
                }
                try? writer.close()
            }
        }
    }

    /// Same caches-dir cwd as Claude. Stable across invocations so that
    /// (when codex grows prompt-cache awareness) our key doesn't churn.
    private static func stableWorkingDirectory() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("wiki-agent", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func makeOutputFileURL() -> URL {
        let base = stableWorkingDirectory() ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("codex-out-\(UUID().uuidString).txt", isDirectory: false)
    }

    // MARK: - Response decoding

    struct Usage: Equatable {
        let input: Int
        let cached: Int?
        let output: Int
    }

    static func extractUsage(from data: Data) -> Usage {
        struct UsageBlock: Decodable {
            let input_tokens: Int?
            let cached_input_tokens: Int?
            let output_tokens: Int?
        }
        // Codex's `--json` output is JSONL. Different versions have wrapped
        // the event payload differently — sometimes flat at the top level,
        // sometimes nested under `msg`. We try both and accept the first
        // match. The event-name has also shifted shape (`turn.completed` vs
        // `turn_completed`); accept either by matching loosely.
        struct FlatEvent: Decodable {
            let type: String?
            let usage: UsageBlock?
        }
        struct NestedEvent: Decodable {
            struct Inner: Decodable {
                let type: String?
                let usage: UsageBlock?
            }
            let msg: Inner?
        }
        func isCompletion(_ name: String?) -> Bool {
            guard let name else { return false }
            return name.contains("turn") && name.contains("complet")
        }
        var latest: Usage = Usage(input: 0, cached: nil, output: 0)
        guard let text = String(data: data, encoding: .utf8) else { return latest }
        let decoder = JSONDecoder()
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let bytes = trimmed.data(using: .utf8) else { continue }
            if let flat = try? decoder.decode(FlatEvent.self, from: bytes),
               isCompletion(flat.type), let usage = flat.usage {
                latest = Usage(
                    input: usage.input_tokens ?? 0,
                    cached: usage.cached_input_tokens,
                    output: usage.output_tokens ?? 0
                )
                continue
            }
            if let nested = try? decoder.decode(NestedEvent.self, from: bytes),
               let inner = nested.msg, isCompletion(inner.type), let usage = inner.usage {
                latest = Usage(
                    input: usage.input_tokens ?? 0,
                    cached: usage.cached_input_tokens,
                    output: usage.output_tokens ?? 0
                )
            }
        }
        return latest
    }

    static func readLastMessage(at url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentError.invalidResponse("codex produced no last message file")
        }
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.invalidResponse("codex returned empty last message")
        }
        return trimmed
    }
}
