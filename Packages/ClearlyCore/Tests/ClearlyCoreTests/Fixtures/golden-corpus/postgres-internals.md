---
title: Postgres Internals
tags: [database, performance]
---

# Postgres Internals

The mental model I use when debugging slow queries.

## The query planner

Costs are estimates, not measurements. When EXPLAIN says "Cost: 1234.56", that's a unitless number meaningful only relative to other plans the planner considered. EXPLAIN ANALYZE actually runs the query and gives you wall-clock time, which is what you actually care about.

The planner's main decisions: which index to use (if any), join order, join algorithm (nested loop, hash, merge). It picks based on table statistics — if those are stale (`pg_stat_user_tables.last_analyze` is months old), the plan can be very wrong. `ANALYZE table_name` re-collects them.

## Indexes

B-tree is the default and what you usually want. GIN is for full-text search and array containment. BRIN is for huge append-only tables where the column is correlated with insertion order (timestamps, IDs). Partial indexes (`WHERE deleted_at IS NULL`) are underused and powerful — they keep the index small for the queries that actually hit it.

## The query won't use my index

Common reasons: function call on the indexed column (`WHERE lower(email) = ?` doesn't use a regular index on email — needs a functional index `(lower(email))`), implicit type coercion, very small table where seq scan is faster, OR conditions that need a UNION instead.

## MVCC and bloat

Every UPDATE creates a new row version; the old version sticks around until VACUUM. Heavy update workloads bloat tables and indexes. Autovacuum is on by default but tuned conservatively — high-write tables benefit from per-table autovacuum settings. `pg_stat_user_tables.n_dead_tup` shows the dead-tuple count.
