import Foundation
import os
import ClearlyCore

/// Spawns the user's locally-installed `claude` CLI to answer a prompt. This
/// is Wiki mode's primary agent path — for Claude Pro / Max / Team users it
/// reuses the subscription they already pay for. The binary keeps its own
/// OAuth token in Keychain; Clearly never touches it.
///
/// Invocation:
///   claude --print --output-format json
///       --tools "<built-in subset>"
///       --no-session-persistence
///       [--exclude-dynamic-system-prompt-sections]   // only if claude >= 2.1.98 (issue #289)
///       [--model <alias>]
///
/// `--tools` REPLACES the built-in tool set (`""` disables all built-ins; `"Read,Grep,Glob"`
/// limits to those three; the agent CANNOT call Bash, Edit, Write, etc.). Verified empirically.
///
/// We deliberately do NOT pass `--mcp-config`. Chat handles retrieval
/// in-process via `VaultChatRetriever` (RAG); Capture/Review use just the
/// built-in Read/Grep/Glob tools.
///
/// Prompt is fed via stdin so we don't blow ARG_MAX on long sources.
struct ClaudeCLIAgentRunner: AgentRunner {
    let binaryURL: URL
    let environment: [String: String]
    /// Built-in tool list passed to `--tools`. `""` disables every built-in (Chat RAG path —
    /// the agent only completes over the inlined context); `"Read,Grep,Glob"` is what
    /// Capture/Review use to explore the vault.
    let enabledTools: String
    /// Overrides the default stable caches-dir cwd. Capture/Review pin cwd
    /// to the vault so Read/Grep/Glob operate on notes; Chat does not need
    /// a vault cwd because RAG inlines the retrieved context.
    let workingDirectoryOverride: URL?

    init(
        binaryURL: URL,
        enabledTools: String = "",
        workingDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.binaryURL = binaryURL
        self.enabledTools = enabledTools
        self.workingDirectoryOverride = workingDirectory
        self.environment = environment
    }

    func run(prompt: String, model: String?) async throws -> AgentResult {
        let supportsExcludeDynamic = await Self.supportsExcludeDynamicFlag(binaryURL: binaryURL)
        let arguments = Self.buildArguments(
            model: model,
            tools: enabledTools,
            includeExcludeDynamicFlag: supportsExcludeDynamic
        )
        let (stdoutData, stderrText, status) = try await spawn(prompt: prompt, arguments: arguments)

        DiagnosticLog.log("claude RUN: status=\(status) promptLen=\(prompt.count) stdoutLen=\(stdoutData.count) stderrLen=\(stderrText.count)")
        guard status == 0 else {
            throw AgentError.transport("claude exited with status \(status). stderr: \(stderrText.prefix(512))")
        }
        guard !stdoutData.isEmpty else {
            throw AgentError.invalidResponse("claude exited successfully but produced no stdout")
        }
        return try Self.decode(data: stdoutData)
    }

    // MARK: - Argument layout

    static func buildArguments(
        model: String?,
        tools: String,
        includeExcludeDynamicFlag: Bool
    ) -> [String] {
        var args: [String] = [
            "--print",
            "--output-format", "json",
            "--tools", tools,
            "--no-session-persistence",
        ]
        if includeExcludeDynamicFlag {
            // Critical for cache reuse: moves cwd / git / env sections out of
            // the system prompt into the first user message. Without this,
            // every invocation gets a slightly different system prompt (e.g.
            // a file touched by FSEvents changes `git status` output) and
            // the ~95K prompt-cache entry gets invalidated on every call.
            // Added in @anthropic-ai/claude-code 2.1.98 — gated by
            // `supportsExcludeDynamicFlag(binaryURL:)` so older CLIs don't
            // bail with "unknown option" (issue #289).
            args.append("--exclude-dynamic-system-prompt-sections")
        }
        if let model, !model.isEmpty {
            args.append(contentsOf: ["--model", model])
        }
        return args
    }

    // MARK: - Version probing

    /// `OSAllocatedUnfairLock` (rather than `NSLock`) so the lock is safe to
    /// acquire from async contexts — `NSLock.lock()` is flagged unavailable
    /// from async functions (warning today, error in Swift 6 language mode).
    private static let versionCache = OSAllocatedUnfairLock<[String: Bool]>(initialState: [:])

    /// True if the `claude` CLI at `binaryURL` recognises
    /// `--exclude-dynamic-system-prompt-sections`. The flag landed in
    /// `@anthropic-ai/claude-code@2.1.98`; older builds reject the unknown
    /// option and exit status 1, breaking Wiki Chat + Capture (issue #289).
    /// Result is cached per absolute path for the lifetime of the process —
    /// the probe runs at most once per binary path per app launch.
    ///
    /// Async because the underlying `Process.waitUntilExit()` would otherwise
    /// block the MainActor (the chat / capture entry points run in
    /// `Task { @MainActor in ... }` contexts) for ~50–150ms on first call.
    /// The dispatch hop suspends the cooperative thread instead.
    static func supportsExcludeDynamicFlag(binaryURL: URL) async -> Bool {
        let key = binaryURL.path
        if let cached = versionCache.withLock({ $0[key] }) {
            return cached
        }
        let supported: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: probeSupportsExcludeDynamicFlag(at: binaryURL))
            }
        }
        versionCache.withLock { $0[key] = supported }
        return supported
    }

    /// Spawns `claude --version` synchronously and parses the output.
    /// Mirrors the lightweight pattern in `AgentDiscovery.lookupOnPath`.
    /// On any error / non-zero exit / unparseable output, returns `false`
    /// — safer to drop the optimisation than to risk re-introducing the
    /// "unknown option" error from a malformed version string.
    private static func probeSupportsExcludeDynamicFlag(at binaryURL: URL) -> Bool {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--version"]
        process.environment = environmentForSubprocess(
            base: ProcessInfo.processInfo.environment,
            currentDirectory: nil,
            binaryURL: binaryURL
        )
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0 else { return false }
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              let version = parseClaudeVersion(text)
        else { return false }
        return isAtLeast(version: version, major: 2, minor: 1, patch: 98)
    }

    /// Parses the leading semver from `claude --version` output, e.g.
    /// `"2.1.122 (Claude Code)\n"` → `(2, 1, 122)`. Tolerates trailing
    /// non-digit suffixes on the patch component (`"2.1.98-beta"` → 98).
    /// Returns nil on any parse failure; caller treats nil as "unsupported".
    static func parseClaudeVersion(_ stdout: String) -> (Int, Int, Int)? {
        let firstToken = stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? ""
        let parts = firstToken.split(separator: ".")
        guard parts.count >= 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1])
        else { return nil }
        let patchDigits = String(parts[2]).prefix { $0.isASCII && $0.isNumber }
        guard !patchDigits.isEmpty, let patch = Int(patchDigits) else { return nil }
        return (major, minor, patch)
    }

    /// Numeric tuple comparison. Don't string-compare semvers — `"2.1.100"`
    /// sorts *before* `"2.1.98"` lexicographically, which would silently
    /// misclassify the latest CLIs as too old.
    private static func isAtLeast(
        version v: (Int, Int, Int),
        major: Int,
        minor: Int,
        patch: Int
    ) -> Bool {
        if v.0 != major { return v.0 > major }
        if v.1 != minor { return v.1 > minor }
        return v.2 >= patch
    }

    // MARK: - Process plumbing

    private func spawn(prompt: String, arguments: [String]) async throws -> (Data, String, Int32) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = binaryURL
            process.arguments = arguments
            // Capture/Review override cwd to the vault so Read/Grep/Glob see
            // notes. Chat uses the stable caches dir because RAG inlines all
            // context and needs no filesystem tools.
            process.currentDirectoryURL = workingDirectoryOverride ?? Self.stableWorkingDirectory()
            // Sandboxed parents inherit a HOME pointing at the app container
            // (`~/Library/Containers/<bundle-id>/Data`). Claude reads its OAuth
            // credentials from `$HOME/.claude/.credentials.json` — pointing it
            // at the container makes it think the user isn't logged in. Always
            // hand it the real user home so subscription auth works.
            let resolvedEnv = Self.environmentForSubprocess(
                base: environment,
                currentDirectory: process.currentDirectoryURL,
                binaryURL: binaryURL
            )
            process.environment = resolvedEnv

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

    /// Replaces auth-sensitive inherited values with the real user values.
    /// Without this, sandboxed/App-launched children can look for CLI auth
    /// state inside Clearly's container or inherit Claude's own SDK mode flags.
    static func environmentForSubprocess(
        base: [String: String],
        currentDirectory: URL? = nil,
        binaryURL: URL? = nil
    ) -> [String: String] {
        var env = base
        for key in [
            "APP_SANDBOX_CONTAINER_ID",
            "CFFIXED_USER_HOME",
            "CLAUDECODE",
            "CLAUDE_AGENT_SDK_VERSION",
            "CLAUDE_CODE_ENABLE_TASKS",
            "CLAUDE_CODE_ENTRYPOINT",
            "CLAUDE_CODE_EXECPATH",
            "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS",
        ] {
            env.removeValue(forKey: key)
        }
        let user = NSUserName()
        let resolvedHome = realUserHome() ?? "/Users/\(user)"
        env["HOME"] = resolvedHome
        env["USER"] = user
        env["LOGNAME"] = user
        if let currentDirectory {
            env["PWD"] = currentDirectory.path
        }
        // npm-installed CLIs (Codex, Claude pre-Bun) ship as `#!/usr/bin/env node`
        // scripts. Apps launched from the Dock inherit a minimal PATH
        // (`/usr/bin:/bin:/usr/sbin:/sbin`) which doesn't include the node
        // alongside the CLI in the same bin dir — so `env` fails to find
        // `node`. Prepend the binary's parent dir so the shebang resolves.
        if let binaryURL {
            let binDir = binaryURL.deletingLastPathComponent().path
            let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            if !existing.split(separator: ":").contains(Substring(binDir)) {
                env["PATH"] = "\(binDir):\(existing)"
            }
        }
        return env
    }

    /// Resolve the user's REAL home directory, bypassing the sandbox redirect.
    /// `NSHomeDirectory()` and `NSHomeDirectoryForUser(_:)` both honour the
    /// container substitution; `getpwuid(geteuid())->pw_dir` reads straight
    /// from OpenDirectory and returns `/Users/<name>`.
    private static func realUserHome() -> String? {
        guard let pw = getpwuid(geteuid()), let dir = pw.pointee.pw_dir else { return nil }
        return String(cString: dir)
    }

    /// A stable per-user working directory the subprocess always runs from.
    /// It is writable if Claude needs scratch space and identical across
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
