---
type: moc
title: "Release Features"
created: 2026-07-10
tags:
  - moc
related:
  - "[[claude-obsidian-moc]]"
  - "[[2026-06-30-v1.7-v1.9.2-release-arc]]"
---

# Release Features — Map of Content

> Links into the cluster on the v1.7–v1.9 feature arc and the infrastructure behind it.

## Why this MOC exists

The compound vault matured across a tight release arc: transport + locking (v1.7), methodology modes (v1.8), and the thinking framework (v1.9). These notes are the durable record of what shipped and why.

## Core notes

- [[Methodology Modes]] — LYT / PARA / Zettelkasten / Generic routing (this vault is on **LYT**)
- [[Multi-Writer Safety]] — per-file advisory locks for safe concurrent ingest
- [[10-Principle Thinking Framework]] — the OBSERVE→GROW loop as an invocable skill
- [[DragonScale Memory]] — the memory mechanisms shipped opt-in
- [[single-tenant-threat-model]] — the security model documented in v1.9.1

## Adjacent MOCs

- [[wiki-pattern-moc]]
- [[retrieval-moc]]

## Open questions / frontier

- v2.0 (derive) + v2.5 (GUI) are the remaining two audit axes to lead — scope them.
- Which release features deserve their own atomic notes vs. staying in the spine note?
