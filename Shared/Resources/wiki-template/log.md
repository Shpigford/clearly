# Log

Chronological record of every accepted Capture, Chat, and Review operation.
Append-only — the agent never edits prior entries.

Each entry follows this shape:

```
## [YYYY-MM-DD] <operation> | <title>

- Files touched: N (M created, P modified)
- Model: <provider/model>
- Tokens: <in> / <out> · ~$<cost>
- Rationale: <one-sentence summary>
```

So `grep "^## \[" log.md | tail -5` gives you the five most recent operations.

---

<!-- Operations land here as they're accepted. -->
