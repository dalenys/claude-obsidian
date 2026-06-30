---
type: concept
title: "Contextual Retrieval"
address: c-000004
complexity: advanced
domain: knowledge-management
aliases:
  - "Hybrid Retrieval"
  - "wiki-retrieve"
  - "Contextual Prefix"
created: 2026-06-30
updated: 2026-06-30
tags:
  - concept
  - knowledge-management
  - retrieval
  - bm25
  - embeddings
  - compound-vault
status: shipped
related:
  - "[[wiki-retrieve]]"
  - "[[Query-Time Retrieval]]"
  - "[[Hot Cache]]"
  - "[[DragonScale Memory]]"
  - "[[Wiki vs RAG]]"
  - "[[concepts/_index]]"
sources:
  - "[[2026-06-30-v1.7-v1.9.2-release-arc]]"
---

# Contextual Retrieval

Shipped opt-in in **v1.7** as the `wiki-retrieve` primitive; hardened in **v1.9.2**. It replaces the v1.6 static read order (`hot → index → drill`) with a hybrid retriever modeled on Anthropic's September 2024 _Contextual Retrieval_ research.

> **Status: shipped v1.7 (opt-in), hardened v1.9.2.** Enable with `bash bin/setup-retrieve.sh`. Feature-detected by [[wiki-query]] and [[autoresearch]]; when absent, those skills fall back to the v1.6 read order. Retrieval is the free-tier axis where claude-obsidian sits at #1 — no paid vector DB, no managed embedding service required.

---

## The problem it solves

The v1.6 retrieval path was a fixed traversal: read `hot.md`, then `index.md`, then drill into pages. That works at small scale but degrades as the vault grows — the index becomes a bottleneck and relevant passages buried in long pages never surface. Standard RAG chunking has the opposite failure: a chunk ripped from its page loses the context that made it findable ("it" / "the algorithm" / "this release" lose their referents).

## The three legs

`wiki-retrieve` combines three signals, mirroring Anthropic's contextual-retrieval recipe:

1. **Contextual prefix** — before indexing, each chunk is prepended with a short LLM-generated sentence situating it in its page (`scripts/contextual-prefix.py`). This is the "contextual" in contextual retrieval: the chunk carries its own context into the index.
2. **BM25** — lexical/keyword scoring (`scripts/bm25-index.py`) catches exact terms, identifiers, and rare tokens that embeddings smear.
3. **Cosine rerank** — embedding similarity (`scripts/rerank.py`) reranks the BM25 candidates semantically.

Anthropic's published result for this combination: **~35% reduction** in retrieval failures from contextual embeddings alone, **~49%** adding contextual BM25, and **~67%** with a reranking step on top. The plugin's value is shipping that recipe against a local-first stack (BM25 in stdlib, embeddings via local `nomic-embed-text` on ollama).

---

## v1.9.2 prompt-cache hardening

v1.9.2 ported Anthropic prompt-caching best practice into the **one** place the plugin calls the Anthropic API directly — tier-1 contextual-prefix generation:

- **Cache only above the Haiku floor.** A page-body `cache_control` marker is attached only when the body clears the Haiku 4.5 minimum cacheable size (`HAIKU_CACHE_MIN_CHARS = 16384`, ~4096 tokens). Below the floor the API silently ignores the marker, so the prior unconditional marker was a misleading no-op. Extracted as the unit-tested pure function `cache_control_for()`.
- **Cache telemetry.** The tier-1 path logs `cache: wrote=<N> read=<N> tok` from the response `usage` fields — integers only, never page content (preserving the data-egress posture).
- **Sequential invariant documented.** Cache reads depend on chunk 0's response landing before chunk 1 is sent (the Anthropic prompt-caching concurrency rule). A note guards against a future parallelization silently zeroing every cache read.

See the [Anthropic prompt-caching docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) for the underlying mechanics (byte-identical prefix requirement, breakpoint placement, TTL).

---

## Data-egress consent (v1.7.1 posture)

The tier-1 contextual-prefix path can send page bodies off-machine to the Anthropic API. That is **default-off**: it requires an explicit `--allow-egress` flag, and `bin/setup-retrieve.sh` prompts for consent. Without the flag, `contextual-prefix.py --peek` reports `tier=synthetic` (a local, no-egress fallback) even when `ANTHROPIC_API_KEY` is set. The same default-deny pattern gates remote ollama probes behind `--allow-remote-ollama`. This consent gap was BLOCKER B1 in the v1.7 audit; the flag closed it.

---

## Honest limitations

- **Opt-in, and for good reason.** It needs a local embedding model (ollama) and an indexing pass. Small vaults are better served by the v1.6 read order — the hybrid retriever earns its keep above a few hundred pages.
- **Embedding cost is local hardware time**, not free — and remote-ollama or live tier-1 egress crosses a privacy boundary the consent flags deliberately gate.
- **The Anthropic failure-reduction percentages are theirs, on their corpus.** They justify the architecture; they are not a measured claim about this vault. The repo's own `wiki/meta/retrieval-benchmark-v1.7.md` holds the in-vault numbers.

---

## Connections

See [[wiki-retrieve]] for the skill and setup.
See [[Query-Time Retrieval]] for the higher-level query synthesis this feeds.
See [[Hot Cache]] for the always-on level-0 context this complements (not replaces).
See [[Wiki vs RAG]] for why a wiki still beats pure RAG at human scale even with hybrid retrieval.
See [[2026-06-30-v1.7-v1.9.2-release-arc]] for the release context.
