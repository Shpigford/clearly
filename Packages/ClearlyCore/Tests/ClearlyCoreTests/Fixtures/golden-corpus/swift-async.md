---
title: Swift Async/Await Quirks
tags: [swift, concurrency]
---

# Swift Async/Await Quirks

Things I keep tripping over.

## Actor reentrancy

`actor` doesn't serialize the way you'd expect when you `await` inside an actor method. Other tasks can interleave at the suspension point. If you have invariants that need to hold across an await, you need to re-check them after the await returns. This bites people coming from Erlang or Akka.

## Task cancellation isn't automatic

`Task.isCancelled` is a check, not a guarantee. Long-running synchronous loops won't notice cancellation unless you explicitly check. URLSession's async APIs respect cancellation; ad-hoc work doesn't.

## @MainActor inheritance

A method declared on a `@MainActor` type doesn't automatically run on the main actor when called from a nonisolated context — the call site decides. The compiler will tell you to `await` or `Task { @MainActor in ... }` to bridge.

## Sendable is contagious

Once you have one Sendable requirement, it tends to spread through the codebase. Closures capturing non-Sendable values become problematic. The fix is usually to refactor data flow so values are explicitly passed at boundaries, not captured.

## Performance gotchas

`Task { }` is more expensive than people assume — there's a heap allocation and dispatch queue hop. For fire-and-forget hot paths, prefer structured concurrency. For high-throughput work, an `AsyncStream` with a single consumer is often cheaper than spinning up many short Tasks.
