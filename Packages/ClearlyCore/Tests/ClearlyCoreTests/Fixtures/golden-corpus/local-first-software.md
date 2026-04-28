---
title: Local-First Software
tags: [research, software]
---

# Local-First Software

Notes from reading Ink & Switch's essay and related material.

## Core Principles

Seven ideals: no spinners (data is on your device, reads are instant), your data your device (not held hostage in someone else's cloud), network optional (works offline, syncs when connected), collaboration without coordination (CRDTs resolve conflicts automatically), long-term preservation (files outlive the app and the company), security and privacy by default, and you retain ultimate ownership and control.

## Why It Matters

The pendulum is swinging back from cloud-everything. Privacy regulation, on-device AI processing, and users tired of apps breaking when WiFi drops are all pushing in the same direction. "Cloud apps trade ownership for convenience. Local-first apps give you both." — Martin Kleppmann.

## Key Technologies

CRDTs (Conflict-free Replicated Data Types) are the foundation — Yjs and Automerge are the two major implementations. They let multiple devices edit the same document without a central coordinator and merge changes deterministically. SQLite is having a renaissance for local storage; the combination of file-based databases and CRDTs is unusually powerful.

## Open Questions

How do you handle schema migrations across devices that haven't synced in months? What's the right UX for showing sync state without anxiety? How do permissions work when there's no server to enforce them?
