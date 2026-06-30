---
type: concept
title: "Methodology Modes"
address: c-000003
complexity: intermediate
domain: knowledge-management
aliases:
  - "Vault Modes"
  - "Organizational Modes"
  - "wiki-mode"
created: 2026-06-30
updated: 2026-06-30
tags:
  - concept
  - knowledge-management
  - methodology
  - wiki-mode
  - compound-vault
status: shipped
related:
  - "[[methodology-modes]]"
  - "[[wiki-mode]]"
  - "[[methodology-modes-guide]]"
  - "[[LLM Wiki Pattern]]"
  - "[[claude-obsidian-ecosystem]]"
  - "[[concepts/_index]]"
sources:
  - "[[2026-06-30-v1.7-v1.9.2-release-arc]]"
---

# Methodology Modes

Shipped in **v1.8.0** (2026-05-17). A methodology mode lets the vault declare an _organizational style_ that page-filing skills consult before they create a page. It is the first-class answer to "where does a new note go?" — and it closed **priority gap 5** (methodology support) from the May 2026 compass artifact, taking claude-obsidian to #1 on 5 of 7 competitive axes.

> **Status: shipped v1.8.0, deepened v1.9.0.** Four modes; `generic` is the default and reproduces v1.6/v1.7 behavior byte-for-byte. No other Claude+Obsidian plugin ships methodology modes as a first-class skill — this is a category-defining axis, not a cosmetic one.

---

## The four modes

| Mode                            | Folder shape                             | Navigation           | Best for                                           |
| ------------------------------- | ---------------------------------------- | -------------------- | -------------------------------------------------- |
| **Generic**                     | `sources/ entities/ concepts/ sessions/` | folder browse        | the default — beginners, mixed use; no opinion     |
| **LYT** (Linking Your Thinking) | `mocs/ notes/`                           | link-follow via MOCs | knowledge clusters; atomic notes + Maps of Content |
| **PARA**                        | `projects/ areas/ resources/ archives/`  | folder browse        | GTD-style knowledge workers; actionability         |
| **Zettelkasten**                | flat, timestamped IDs                    | ID reference + graph | researchers; dense linking, high discipline        |

The full decision tree lives in the [[methodology-modes]] reference; the narrative rationale and migration guidance in [[methodology-modes-guide]].

---

## How routing works

The mode is written to `.vault-meta/mode.json` (gitignored by default; `git add -f` to commit if the choice should follow the repo). Three consumer skills — [[wiki-ingest]], [[save]], and [[autoresearch]] — call the router **before** filing any new page:

```bash
python3 scripts/wiki-mode.py route <type> "<name>"
# generic:      wiki/sources/Karpathy-2025-essay.md
# lyt:          wiki/notes/Karpathy-2025-essay.md   (+ update the relevant MOC)
# para:         wiki/resources/incoming/Karpathy-2025-essay.md  (await user triage)
# zettelkasten: wiki/20260517123456-Karpathy-2025-essay.md
```

If `mode.json` is absent the router returns `generic` paths, so no consumer skill needs special-casing. This is the key design property: **mode awareness is a single router call, not a branch in every skill.** The router (`scripts/wiki-mode.py`, pure stdlib) also mints Zettel timestamp IDs and lists per-mode templates.

Mode-specific follow-up the ingest skills perform automatically:

- **LYT** — after filing an atomic note, update (or create) the topic MOC at `wiki/mocs/<topic>-moc.md`.
- **PARA** — new ingests land in `wiki/resources/incoming/` and are _not_ auto-categorized; the user triages.
- **Zettelkasten** — the filename already carries the timestamp ID; the `id:` frontmatter is populated to match.

---

## Setup

```bash
bash bin/setup-mode.sh            # interactive
bash bin/setup-mode.sh --mode para  # non-interactive; idempotent, safe to re-run to switch
```

Setup optionally seeds the template folders for the chosen mode (6 templates ship under `skills/wiki-mode/templates/`: LYT moc/atomic, PARA project/area/resource, Zettel atomic).

---

## Why it matters

The compass artifact identified methodology support as the one axis where every competing Claude+Obsidian project tied — none had it. Shipping it as a router that consumers query (rather than as hardcoded paths) means the discipline is _additive_: a `generic` vault behaves exactly as before, and switching modes is one command. v1.9.0 deepened the axis further by adding the [[10-Principle Thinking Framework]]'s per-skill mapping, so even the mode-routing skill documents _why_ it audits the assumption that `mode=generic` is the default.

---

## Honest limitations

- **PARA leaves categorization to the human.** The router refuses to guess a resource's area/project — incoming/ is a deliberate holding pen, not a failure.
- **LYT MOC upkeep is semi-automatic.** New notes get linked into a MOC, but MOC curation (splitting, merging) is still human work.
- **mode.json is host-local by default.** A teammate cloning the repo gets `generic` unless the mode was force-committed. Intentional (host-specific runtime config), but a surprise if unexpected.

---

## Connections

See [[methodology-modes]] for the quick decision tree.
See [[methodology-modes-guide]] for the full narrative guide and per-mode migration notes.
See [[wiki-mode]] for the skill that reads and writes the mode.
See [[LLM Wiki Pattern]] for the pattern this organizes.
See [[2026-06-30-v1.7-v1.9.2-release-arc]] for the release context.
