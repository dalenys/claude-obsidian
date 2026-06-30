---
type: meta
title: "Hot Cache"
updated: 2026-06-30
tags:
  - meta
  - hot-cache
status: evergreen
related:
  - "[[index]]"
  - "[[log]]"
  - "[[2026-06-30-v1.7-v1.9.2-release-arc]]"
  - "[[Methodology Modes]]"
  - "[[Contextual Retrieval]]"
---

# Recent Context

Navigation: [[index]] | [[log]] | [[overview]]

## Last Updated

2026-06-30: Filed the **v1.7 to v1.9.2 release arc** into the wiki, which had drifted ~2 months behind the code. Created four concept pages ([[Methodology Modes]], [[Contextual Retrieval]], [[Multi-Writer Safety]], [[10-Principle Thinking Framework]]), one reference ([[single-tenant-threat-model]]), and the spine note [[2026-06-30-v1.7-v1.9.2-release-arc]]. Also overrode this machine's transport to `filesystem` (the installed `obsidian-cli` is yakitrak v0.2.3, not the official CLI the recipes assume).

## Plugin State

- **Version**: 1.9.2 (public canonical; promoted in commit `00213b7`)
- **Repo**: https://github.com/AgriciDaniel/claude-obsidian (branch `main`); working copy at `~/src/github.com/AgriciDaniel/claude-obsidian`
- **Skills**: 15 (added `wiki-cli` + `wiki-retrieve` in v1.7, `wiki-mode` in v1.8, `think` in v1.9)
- **Transport**: filesystem (manual override on this Mac; see [[transport-fallback]])

## Key Recent Facts (the v1.7 to v1.9.2 arc)

- **v1.7 Compound Vault**: transport layer, multi-writer locking ([[Multi-Writer Safety]]), opt-in hybrid retrieval ([[Contextual Retrieval]]), Obsidian CLI; data-egress consent flag + `verifier` agent (v1.7.1).
- **v1.8 Methodology modes**: LYT / PARA / Zettelkasten / Generic ([[Methodology Modes]]); closed compass priority gap 5.
- **v1.9 Thinking framework**: `/think` skill #15 + per-skill appendices ([[10-Principle Thinking Framework]]); v1.9.1 documented the [[single-tenant-threat-model]]; v1.9.2 hardened prompt caching.
- Every minor release was gated by a pre-push audit; the audit findings drove same-day patch releases (v1.8.2, v1.9.1).

## Active Threads

- **Fixed this session**: the `flock` portability bug — both `allocate-address.sh` and `wiki-lock.sh`'s meta-lock failed on macOS (no `flock`) — is fixed via an atomic-`mkdir` spinlock fallback; full `make test` is now green on macOS. This session's pages were hand-allocated `c-000003`..`c-000007` before the fix.
- **Resolved 2026-06-30**: em-dash style — vault now **allows em dashes** vault-wide (matches DragonScale, references, CHANGELOG). The old ban is dropped; no rewriting needed.
- **Resolved 2026-06-30**: git drift — committed the `.obsidian/` config + 3 plugin folders (dataview, obsidian-git, templater) so the environment is reproducible.
- **DragonScale**: all four mechanisms shipped (opt-in), counter at 8 after this session.

## Style Preferences

- Short, direct responses. No trailing summaries. Parallel tool calls when independent.
- Em-dash usage in wiki pages is currently inconsistent across the vault (see Active Threads). This file stays em-dash-free pending a decision.
