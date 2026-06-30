---
type: reference
title: "Single-Tenant Threat Model"
address: c-000007
domain: security
created: 2026-06-30
updated: 2026-06-30
tags:
  - reference
  - security
  - threat-model
  - compound-vault
status: evergreen
related:
  - "[[Multi-Writer Safety]]"
  - "[[Contextual Retrieval]]"
  - "[[2026-06-30-v1.7-v1.9.2-release-arc]]"
---

# Single-Tenant Threat Model

Documented in **v1.9.1** (`SECURITY.md`), closing findings H2 + S3 from the v1.9.0 pre-public-promotion audit. The audit's verdict on the design choices was that they are **correct for a single-tenant vault** — the gap was documentation: operators running on a shared host deserve to know what changes for them.

> **Trust boundary:** claude-obsidian assumes **one user, one machine, filesystem permissions as the security perimeter.** Everything below is a deliberate trade-off that buys simplicity and recoverability at single-tenant scale, and becomes a liability only when that assumption breaks.

---

## Three intentional design choices

### 1. Cross-process lock release

`scripts/wiki-lock.sh release` is `rm -f` with no PID match — any process can release any lock. This makes crash recovery trivial (a janitor reaps stale locks; no orphaned locks wedge the vault). **On a shared host** it means any local user can release another's lock and induce a write race. Mitigation for shared hosts: run the vault under a dedicated user, or restrict `.vault-meta/locks/` permissions. See [[Multi-Writer Safety]].

### 2. Auto-commit hook scope

The `PostToolUse` hook runs `git add -- wiki/ .raw/ .vault-meta/` and commits automatically. This is the mechanism that turns ephemeral chat into compounding committed knowledge. **On a shared or CI host** auto-committing may be undesirable (noisy history, committing secrets staged elsewhere is _not_ a risk — scope is limited to those three paths — but unattended commits can surprise). Mitigation: `touch .vault-meta/auto-commit.disabled` (v1.9.1 opt-out gate); default behavior is unchanged for existing users.

### 3. Filesystem-permission trust boundary

There is no in-app access control, encryption-at-rest, or per-page ACL. The vault trusts the OS filesystem permissions entirely. This is correct for a personal vault and out of scope to "fix." **On a shared host**, treat the whole vault as readable/writable by anyone with filesystem access and place it accordingly.

---

## Data-egress posture (v1.7.1)

Orthogonal to the host model but part of the same "no surprises" discipline:

- **Tier-1 contextual-prefix generation** can send page bodies to the Anthropic API. Default-off; requires explicit `--allow-egress`. Without it, `contextual-prefix.py --peek` reports `tier=synthetic` even with `ANTHROPIC_API_KEY` set. (Closed BLOCKER B1.) See [[Contextual Retrieval]].
- **Remote ollama probes** are refused unless `--allow-remote-ollama` is passed; an off-localhost `OLLAMA_URL` will not be probed silently (S4). Mirrors the `tiling-check.py` gate.
- **Telemetry logs integers only** (`cache: wrote=N read=N tok`), never page content.

---

## What the audit explicitly did NOT change

The single-tenant choices above were **affirmed, not patched** — the v1.9.1 work was documentation plus defense-in-depth hardening (symlink canonicalization, stale-lock reaper, off-localhost asserts), not a redesign. Composite audit score moved 91.6 → ~94; public-promotion ship verdict stayed GREEN.

---

## Connections

See [[Multi-Writer Safety]] for the locking design choice #1 describes.
See [[Contextual Retrieval]] for the egress-gated tier-1 path.
See [[2026-06-30-v1.7-v1.9.2-release-arc]] for the release context and audit lineage.
Source: `SECURITY.md` §"Threat model: single-tenant vault".
