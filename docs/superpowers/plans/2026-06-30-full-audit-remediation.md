# Full Audit Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every confirmed full-sweep finding and the related supply-chain risk with hermetic regression coverage.

**Architecture:** Repair the existing shell/Python workflows in focused slices. Keep public interfaces stable, use Python JSON encoding for structured output, and make cleanup and overwrite behavior explicit and safe.

**Tech Stack:** Bash 3.2, Python standard library, JSON, Markdown Agent Skills, Make.

---

### Task 1: Retrieval integrity

**Files:**
- Modify: `scripts/contextual-prefix.py`
- Modify: `scripts/rerank.py`
- Modify: `scripts/retrieve.py`
- Modify: `tests/test_contextual_prefix.py`
- Modify: `tests/test_retrieve.py`

- [ ] Add a regression test that creates three chunks, shrinks the page to one
  chunk, and asserts the two surplus files are removed.
- [ ] Run `python3 tests/test_contextual_prefix.py` and confirm that regression
  fails because stale files remain.
- [ ] Add tests for empty-page cleanup and `--all` garbage collection of a chunk
  directory whose `page_path` no longer exists; assert `--peek` removes nothing.
- [ ] Implement successful-postwrite reconciliation:

```python
expected = {f"chunk-{idx:03d}.json" for idx in range(len(chunks))}
for stale in chunk_dir.glob("chunk-*.json"):
    if stale.name not in expected:
        stale.unlink()
```

- [ ] Add a failing test proving no-op reranking preserves `bm25_score`, not a
  missing `score` key.
- [ ] Add a failing integration test with duplicate top chunks from one page and
  assert `--top 2` returns two distinct pages.
- [ ] Make fallback score lookup use `bm25_score` with legacy `score` fallback,
  rerank the full candidate pool, deduplicate by page, then truncate.
- [ ] Run both targeted tests and confirm all retrieval regressions pass.

### Task 2: Cross-process lock lifecycle and commit completion

**Files:**
- Modify: `scripts/wiki-lock.sh`
- Modify: `tests/test_wiki_lock.sh`
- Modify: `hooks/hooks.json`
- Modify: `skills/save/SKILL.md`
- Modify: `skills/wiki-fold/SKILL.md`
- Modify: `skills/wiki-ingest/SKILL.md`
- Modify: `skills/autoresearch/SKILL.md`

- [ ] Add a shell regression test: acquire a lock, run
  `clear-stale --max-age 3600` from another process, and assert the fresh lock
  remains.
- [ ] Run `bash tests/test_wiki_lock.sh` and confirm the regression fails.
- [ ] Remove PID-liveness cleanup from the administrative reaper; remove locks
  only when their validated age exceeds `max_age`. Treat malformed timestamps
  conservatively and document the lease model.
- [ ] Add a test proving an old lock is still reaped.
- [ ] Extract the hook staging/commit command into a reusable checked-in script
  or document and invoke an equivalent explicit post-release action from every
  lock-protected mutating skill. Ensure the action runs only after all locks are
  released.
- [ ] Validate `hooks/hooks.json` with `python3 -m json.tool`.
- [ ] Run lock and concurrency suites.

### Task 3: Installer correctness and supply-chain safety

**Files:**
- Modify: `bin/setup-dragonscale.sh`
- Modify: `bin/setup-vault.sh`
- Create or modify: installer regression tests under `tests/`
- Modify: `Makefile`
- Modify: relevant installation documentation

- [ ] Add a temporary-vault regression test containing `address: c-000041`
  without a counter; assert setup initializes the next value as `42`.
- [ ] Confirm it fails with the current hardcoded `1`.
- [ ] Replace direct counter initialization with allocator `--rebuild`.
- [ ] Add tests proving existing `graph.json`, `app.json`, and
  `appearance.json` survive normal setup byte-for-byte, while explicit
  `--force` replaces them and creates timestamp-safe backups.
- [ ] Implement non-destructive default writes and documented `--force`.
- [ ] Pin the Excalidraw release URL and expected SHA-256 in the script. Download
  with `curl --fail --location` to a temporary file, verify with portable
  `shasum -a 256`/`sha256sum`, then atomically rename.
- [ ] Test download failure, checksum mismatch, and successful atomic install
  using a local fixture or stubbed `curl`; no network access.
- [ ] Add installer tests to `make test` and run them.

### Task 4: Transport and remote-consent correctness

**Files:**
- Modify: `scripts/detect-transport.sh`
- Modify: `bin/setup-retrieve.sh`
- Create or modify: transport/setup tests under `tests/`
- Modify: `Makefile`

- [ ] Add a fake incompatible `obsidian-cli` to `PATH` and assert detection
  chooses filesystem.
- [ ] Add a fake compatible CLI exposing every command used by
  `skills/wiki-cli/SKILL.md` and assert detection chooses CLI.
- [ ] Replace name-only detection with an explicit capability probe.
- [ ] Add a regression test from a vault path containing a double quote and
  assert emitted transport JSON parses and preserves exact strings.
- [ ] Generate the complete snapshot through Python `json.dumps`; do not
  interpolate unescaped strings into a heredoc.
- [ ] Add a setup-retrieve regression proving `--allow-remote-ollama --check`
  parses successfully and retains consent after argument parsing.
- [ ] Store the flag in a boolean and use that boolean in the remote guard.
- [ ] Run all new shell tests with Bash 3.2 and validate JSON output.

### Task 5: Route confinement and skill portability

**Files:**
- Modify: `scripts/wiki-mode.py`
- Modify: `tests/test_wiki_mode.py`
- Modify: `skills/save/SKILL.md`
- Modify: `skills/autoresearch/SKILL.md`
- Modify: `skills/wiki-query/SKILL.md`
- Modify: `skills/wiki-ingest/SKILL.md`

- [ ] Add failing route tests for absolute and traversal-containing folder
  overrides in generic, LYT, PARA, and Zettelkasten configurations.
- [ ] Normalize every route as a relative POSIX path under `wiki/`; reject
  configured roots that are absolute or escape that boundary with exit code 4.
- [ ] Keep filename sanitization and valid custom subfolders working.
- [ ] Add `Bash` to every legacy `allowed-tools` declaration whose documented
  workflow executes shell commands.
- [ ] Replace non-portable hashing instructions with a feature-detected helper:

```bash
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$file" | awk '{print $1}'
else
  sha256sum "$file" | awk '{print $1}'
fi
```

- [ ] Run mode tests and a scripted frontmatter/tool-contract validation.

### Task 6: Full validation and completeness review

**Files:**
- Review all branch changes.

- [ ] Run every targeted regression suite with
  `PATH="/opt/homebrew/bin:$PATH"` on macOS.
- [ ] Run `PATH="/opt/homebrew/bin:$PATH" make test`.
- [ ] Run `shellcheck bin/*.sh scripts/*.sh tests/*.sh`; resolve new errors and
  ensure pre-existing informational findings are not expanded.
- [ ] Run `ruff check scripts tests`; do not expand scope solely to clean
  unrelated pre-existing style findings.
- [ ] Run `python3 -m compileall -q scripts tests`, JSON validation, and
  `git diff --check`.
- [ ] Map the final diff and tests back to all twelve confirmed findings plus
  the Excalidraw hardening item. Any uncovered item keeps the verdict at HOLD.
- [ ] Commit cohesive slices with no generated artifacts or user workspace
  state.

