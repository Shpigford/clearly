---
title: CQRS and Event Sourcing
tags: [architecture]
---

# CQRS and Event Sourcing

Two ideas that often get bundled together but solve different problems.

## CQRS

Command-Query Responsibility Segregation: separate the model that handles writes from the model that handles reads. Writes flow through commands; reads flow through query-optimized projections. Useful when the read patterns are dramatically different from the write patterns and trying to share one model causes more pain than two would.

The downside is operational — now you have two models to keep in sync and a rebuild story for projections.

## Event sourcing

Persist a stream of events as the source of truth. Current state is derived by replaying events from the start (or from a snapshot). Auditability is free; "how did we get to this state" is answerable. The downside: schema migrations are now *event* migrations, which is a different muscle than table migrations. Get this wrong and you're stuck with old event shapes forever.

## When to use each

CQRS without event sourcing: common, sensible, low-cost. Event sourcing without CQRS: works fine but rarer in practice. Both together: powerful for domains that genuinely benefit (financial, audit-heavy, multi-tenant systems where users expect "show me the history"). Both together by default for everything: a recipe for over-engineering. Most CRUD apps don't need either.
