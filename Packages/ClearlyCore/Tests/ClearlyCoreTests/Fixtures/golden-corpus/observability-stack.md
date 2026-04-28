---
title: Observability Stack
tags: [systems, software]
---

# Observability Stack

The three pillars and what each one is actually for.

## Logs

Discrete events with timestamps. Best for "what happened on this specific request." Awful for aggregate questions ("p99 latency last hour"). Use structured logging — `log.info("user_signed_up", user_id: ..., source: ...)` — so the log shipper can index fields.

## Metrics

Pre-aggregated time-series numbers. Counters, gauges, histograms. Cheap to scrape and store, fast to query. The right tool for "is something wrong right now" dashboards and alerting. Wrong tool for "why" — metrics tell you the symptom, not the cause.

## Traces

Distributed traces capture the path of a single request across services. The killer feature is correlating "this slow request" to "this database query" to "this network call." OpenTelemetry is the de-facto standard.

## What I'd build today

Metrics in Prometheus, traces in Tempo, logs in Loki. Grafana on top. All three speak OpenTelemetry. Sentry on top of that for error aggregation specifically — generic logs aren't great at "this error happened 47 times in the last hour, here's the stack trace and breadcrumbs."

The integration that earns its keep: trace IDs propagated to logs, so when you spot a slow trace you can pivot to the exact log lines from that request.
