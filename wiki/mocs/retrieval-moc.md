---
type: moc
title: "Retrieval"
created: 2026-07-10
tags:
  - moc
related:
  - "[[claude-obsidian-moc]]"
---

# Retrieval — Map of Content

> Links into the cluster on how the vault surfaces the right knowledge at the right time.

## Why this MOC exists

A compound vault is only as good as its retrieval. These notes cover the retrieval strategy — contextual + BM25 + cosine rerank — and the argument for why a curated wiki outperforms naive chunk-and-embed RAG.

## Core notes

- [[Contextual Retrieval]] — the v1.7 opt-in hybrid retrieval approach
- [[Query-Time Retrieval]] — resolving the right pages when a question lands
- [[Wiki vs RAG]] — why synthesized pages beat raw-chunk retrieval

## Adjacent MOCs

- [[wiki-pattern-moc]]

## Open questions / frontier

- When is contextual retrieval worth its indexing cost vs. reading `index.md` directly?
- How should retrieval behave across methodology modes ([[Methodology Modes]])?
