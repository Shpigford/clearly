import Foundation
import ClearlyCore

/// Spawns the user's locally-installed `claude` CLI to answer a prompt. This
/// is Wiki mode's primary agent path — for Claude Pro / Max / Team users it
/// reuses the subscription they already pay for. The binary keeps its own
/// OAuth token in Keychain; Clearly never touches it.
///
/// Invocation:
///   claude --print --output-format json --tools "" --no-session-persistence [--model <alias>]
///
/// - `--tools ""` disables every built-in tool; we only want plain text
///   generation, not Claude Code's file/bash capabilities.
/// - `--no-session-persistence` keeps the call stateless so repeated ingests
///   don't grow a session history on disk.
/// - Prompt is fed via stdin so we don't blow ARG_MAX on long sources.
struct ClaudeCLIAgentRunner: AgentRunner {
    let binaryURL: URL
    let environment: [String: String]

    init(binaryURL: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.binaryURL = binaryURL
        self.environment = environment
    }

    func run(prompt: String, model: String?) async throws -> AgentResult {
        let arguments = Self.buildArguments(model: model)
        let (stdoutData, stderrText, status) = try await spawn(prompt: prompt, arguments: arguments)

        guard status == 0 else {
            throw AgentError.transport("claude exited with status \(status). stderr: \(stderrText.prefix(512))")
        }
        return try Self.decode(data: stdoutData)
    }

    // MARK: - Argument layout

    static func buildArguments(model: String?) -> [String] {
        var args: [String] = [
            "--print",
            "--output-format", "json",
            "--tools", "",
            "--no-session-persistence",
            // Critical for cache reuse: moves cwd / git / env sections out of
            // the system prompt into the first user message. Without this,
            // every invocation gets a slightly different system prompt (e.g.
            // a file touched by FSEvents changes `git status` output) and
            // the ~95K prompt-cache entry gets invalidated on every call.
            "--exclude-dynamic-system-prompt-sections",
        ]
        if let model, !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }
        return args
    }

    // MARK: - Process plumbing

    private func spawn(prompt: String, arguments: [String]) async throws -> (Data, String, Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = arguments
            // Pin a stable cwd so Claude Code's `cwd` section (moved into the
            // first user message by --exclude-dynamic-system-prompt-sections)
            // is identical across invocations, which is what keeps the
            // prompt cache valid between calls.
            process.currentDirectoryURL = Self.stableWorkingDirectory()
            process.environment = environment

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { _ in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errText = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: (outData, errText, process.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AgentError.transport(String(describing: error)))
                return
            }

            // Feed prompt on a background queue so we don't block while the
            // pipe's buffer drains.
            let writer = stdin.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = prompt.data(using: .utf8) {
                    try? writer.write(contentsOf: data)
                }
                try? writer.close()
            }
        }
    }

    /// A stable per-user working directory the subprocess always runs from.
    /// Using the app's caches directory keeps it inside the sandbox container,
    /// writable if Claude ever needs scratch space, and identical across
    /// invocations so prompt-cache keys line up.
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

    // MARK: - Response decoding

    static func decode(data: Data) throws -> AgentResult {
        struct Envelope: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
            }
            let is_error: Bool?
            let result: String?
            let usage: Usage?
            let subtype: String?
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw AgentError.invalidResponse("claude JSON decode failure: \(error); raw: \(raw.prefix(512))")
        }
        if envelope.is_error == true {
            throw AgentError.invalidResponse("claude reported is_error=true (subtype=\(envelope.subtype ?? "-"))")
        }
        guard let text = envelope.result, !text.isEmpty else {
            throw AgentError.invalidResponse("claude returned empty result")
        }
        return AgentResult(
            text: text,
            inputTokens: envelope.usage?.input_tokens ?? 0,
            outputTokens: envelope.usage?.output_tokens ?? 0,
            model: "claude-cli"
        )
    }
}
