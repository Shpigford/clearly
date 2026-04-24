import Foundation
import ClearlyCore

/// Tracks Claude Code's prompt cache TTL and opportunistically fires a
/// background no-op call to keep the 100K-token system prompt hot. First call
/// after app launch costs ~30s; subsequent calls within ~5 minutes are fast
/// because Claude Code reuses its cached system prompt. We warm the moment
/// the user opens the Ingest flow so the 30s overlaps with URL typing time,
/// and short-circuit if we know the cache is already warm.
enum AgentWarmer {
    /// Matches Claude's prompt-cache 5-minute ephemeral TTL. We're a little
    /// conservative (4 minutes) to avoid racing the server-side eviction.
    private static let warmTTL: TimeInterval = 240

    private static var lastWarmedAt: Date?
    private static var inFlight: Task<Void, Never>?

    /// True if the last warmup (or real call, if we extend this later) is
    /// still inside the cache TTL.
    static var isWarm: Bool {
        guard let last = lastWarmedAt else { return false }
        return Date().timeIntervalSince(last) < warmTTL
    }

    /// Note that the cache was exercised by a real (non-warmup) call. Called
    /// after a successful run so we don't redundantly warm afterwards.
    static func markExercised() {
        lastWarmedAt = Date()
    }

    /// Fire a background warmup call unless one is already in flight and the
    /// cache is inside TTL. Returns immediately.
    static func warmIfNeeded(runner: AgentRunner) {
        if isWarm { return }
        if inFlight != nil { return }

        inFlight = Task.detached(priority: .utility) {
            do {
                _ = try await runner.run(prompt: "ready", model: nil)
                await MainActor.run {
                    AgentWarmer.lastWarmedAt = Date()
                    AgentWarmer.inFlight = nil
                    DiagnosticLog.log("AgentWarmer: cache warmed")
                }
            } catch {
                await MainActor.run {
                    AgentWarmer.inFlight = nil
                    DiagnosticLog.log("AgentWarmer: warmup failed — \(error)")
                }
            }
        }
    }
}
