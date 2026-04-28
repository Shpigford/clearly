---
title: Swift Performance
tags: [swift, performance]
---

# Swift Performance

Things I learned the hard way profiling a hot path.

## Reference counting cost

ARC isn't free. Every retain/release is an atomic operation. Hot loops that pass class instances around are silently doing thousands of atomic ops. The fix is usually to use a struct, or borrow the instance with `withExtendedLifetime` so retain/release happens once at the boundary.

## Existential containers

`any Protocol` boxing has a per-call overhead — the runtime has to look up the witness table. For hot paths, prefer `some Protocol` (opaque types) which the compiler can specialize. You'll see this matter in benchmarks of generic code with type-erased collections.

## Array.append in tight loops

`reserveCapacity(N)` before a loop that appends N times saves repeated reallocations. Not always measurable, but cheap to add when you know the size upfront.

## String operations

`String` is heap-allocated for anything past a small inline buffer. Concatenation in a loop creates many intermediate copies. `var output = ""; output.reserveCapacity(...); for ... { output.append(...) }` is dramatically faster than `+=` chains.

## Profile, don't guess

Instruments → Time Profiler is the source of truth. Most of my "I bet that line is slow" intuitions turn out to be wrong, and the actual hot spot is somewhere I didn't suspect. Allocation traces are also revealing — sometimes the slow part isn't CPU but pressure on the allocator.
