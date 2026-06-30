---
type: concept
title: "Multi-Writer Safety"
address: c-000005
complexity: advanced
domain: knowledge-management
aliases:
  - "Advisory Locking"
  - "wiki-lock"
  - "Concurrency Safety"
created: 2026-06-30
updated: 2026-06-30
tags:
  - concept
  - knowledge-management
  - concurrency
  - locking
  - compound-vault
status: shipped
related:
  - "[[wiki-ingest]]"
  - "[[DragonScale Memory]]"
  - "[[single-tenant-threat-model]]"
  - "[[concepts/_index]]"
sources:
  - "[[2026-06-30-v1.7-v1.9.2-release-arc]]"
---

# Multi-Writer Safety

Shipped in **v1.7**. Per-file advisory locking (`scripts/wiki-lock.sh`) makes parallel ingest safe and closes the latent corruption hole that existed in v1.6, where two parallel sub-agents writing to the same page could silently trample each other.

> **Status: shipped v1.7, hardened v1.9.1.** Unconditional in v1.7+ — no feature gate, no fallback. A skill that doesn't acquire a lock is racing against any other writer. The lock script is core, not opt-in.

---

## The v1.6 hole

v1.6's [[DragonScale Memory]] address allocator was `flock`-guarded, but **page writes themselves were not**. Two sub-agents dispatched to ingest different sources could both decide to update `wiki/entities/Foo.md`, read it, and write back — last-writer-wins, silently losing one agent's edit. The address counter was safe; the actual content was not. v1.7 closes this by guarding the writes, not just the counter.

---

## How the lock works

```bash
bash scripts/wiki-lock.sh acquire wiki/concepts/Foo.md   # blocks; rc=75 (EX_TEMPFAIL) if held
# ... write via the transport-selected method ...
bash scripts/wiki-lock.sh release wiki/concepts/Foo.md
```

Properties:

- **Per-file granularity.** Locks key on `sha1(<vault-relative-path>)`, so concurrent writes to _different_ pages run fully in parallel.
- **Age-based staleness.** Default `STALE_AFTER_SEC=60`; a crashed holder unblocks in ≤60s with no manual intervention.
- **Cross-process release.** Release is `rm -f` — no PID match required. Skill authors are trusted to release what they acquire; cross-skill release is _allowed by design_ (a janitor running `wiki-lock clear-stale --max-age 0` is the canonical recovery path). This is a deliberate single-tenant trade-off — see [[single-tenant-threat-model]].
- **Retry-then-skip protocol.** On `rc=75`, retry once after 2s; if still held, log to `wiki/log.md` and **skip** the page rather than overwrite it.

The v1.6 sub-agent rule is preserved — _sub-agents MUST NOT call `allocate-address.sh`_ (the orchestrator backfills addresses to keep the counter monotonic) — but the new rule is additive: _sub-agents MAY now write pages, provided they acquire locks first._

---

## Interaction with auto-commit

The `PostToolUse` hook auto-commits wiki changes after each Write/Edit. To avoid a torn commit landing mid-ingest, **the hook defers `git add` whenever any lock is currently held** (`wiki-lock list` non-empty → exit early). The commit fires once the batch releases its locks. If `wiki-lock list` itself fails, the hook logs to `.vault-meta/hook.log` and defers rather than committing blind.

---

## v1.9.1 hardening

- **Symlink canonicalization (Data M3).** `validate_path()` previously rejected literal `..` segments but did not canonicalize symlinks — a symlink inside `wiki/` resolving outside `VAULT_ROOT` could escape. It now resolves via `os.path.realpath` and rejects any path whose canonical form falls outside `commonpath(VAULT_ROOT, target)`. Cross-platform (GNU + macOS BSD), no `realpath` flag dependency.
- **Stale-lock reaper on SessionStart (H4).** A `SessionStart` hook runs `wiki-lock.sh clear-stale --max-age 3600` on every resume/startup, so locks orphaned by a crashed batch get reaped automatically — not only on operator demand.
- **`.vault-meta/locks/.gitkeep` (Data M4).** `locks/*` is gitignored but `.gitkeep` is whitelisted, so the directory ships on a fresh clone instead of being created as a first-acquire side effect.

---

## Honest limitations

- **Advisory, not mandatory.** The lock only protects writers that _check_ it. A process that ignores `wiki-lock` and writes directly will still trample. The guarantee is a convention enforced by every shipped skill, not by the filesystem.
- **Cross-platform via fallback, not `flock`.** The meta-lock that serializes lock operations originally required `flock` (absent on macOS), as did the sibling `allocate-address.sh`. Both now fall back to an atomic-`mkdir` spinlock when `flock` is missing — the `flock` path is unchanged on Linux — so multi-writer safety holds on macOS and Linux alike (full `make test` green on both).
- **Single-tenant trust boundary.** Cross-process `rm -f` release assumes a cooperating single user. On a shared host this is an availability footgun — documented in [[single-tenant-threat-model]].

---

## Connections

See [[wiki-ingest]] §Concurrency for the acquire/release protocol in context.
See [[DragonScale Memory]] for the address allocator whose `flock` guard predates (and motivated) this.
See [[single-tenant-threat-model]] for why cross-process release is intentional.
See [[2026-06-30-v1.7-v1.9.2-release-arc]] for the release context.
