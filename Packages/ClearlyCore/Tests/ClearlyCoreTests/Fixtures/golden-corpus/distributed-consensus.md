---
title: Distributed Consensus
tags: [systems]
---

# Distributed Consensus

Quick tour of the algorithms I keep needing to remember the difference between.

## Paxos

The classical algorithm. Two phases: prepare/promise, then accept/accepted. Tolerates up to (n-1)/2 node failures in a cluster of n. Famously hard to explain, hard to implement correctly. Most real-world systems use a derivative (Multi-Paxos, Fast Paxos) rather than vanilla Paxos.

## Raft

Designed to be understandable. Leader-based: one node is elected leader and all writes flow through it. Replication via append-entries RPC. Same fault-tolerance bound as Paxos but the protocol is much easier to reason about and implement. etcd, Consul, CockroachDB all use Raft.

## CRDTs

A different paradigm — instead of agreeing on an order of operations, design the data structure so any order of operations converges. Counters, sets, registers, sequences all have CRDT variants. Trades stronger consistency for availability — particularly under network partitions. The local-first software movement leans heavily on CRDTs because they let devices edit offline and merge later.

## When to pick what

Strong consistency, single-region, occasional leader changes acceptable: Raft. Same but with rare network partitions where you need partition tolerance: think hard about CAP, then probably still Raft. Multi-leader, eventually consistent, offline-first: CRDTs. Trying to write your own: don't, use a library.
