---
type: concept
title: "10-Principle Thinking Framework"
address: c-000006
complexity: intermediate
domain: knowledge-management
aliases:
  - "Thinking Loop"
  - "/think"
  - "OBSERVE LISTEN THINK"
created: 2026-06-30
updated: 2026-06-30
tags:
  - concept
  - thinking
  - methodology
  - framework
  - compound-vault
status: shipped
related:
  - "[[think]]"
  - "[[Methodology Modes]]"
  - "[[LLM Wiki Pattern]]"
  - "[[concepts/_index]]"
sources:
  - "[[2026-06-30-v1.7-v1.9.2-release-arc]]"
---

# 10-Principle Thinking Framework

Shipped in **v1.9.0** (2026-05-18) as the plugin's 15th skill and a methodology spine that runs through every other skill. The loop is **OBSERVE–OBSERVE–LISTEN–THINK–CONNECT–CONNECT–FEEL–ACCEPT–CREATE–GROW**.

> **Status: shipped v1.9.0.** Integrated at three levels: the new `/think` skill (canonical source), a per-skill "How to think" appendix on all 14 pre-existing SKILL.md files, and as the phase structure of the v1.8.0 pre-push audit that preceded it. It is invocable standalone (`/think <problem>`) and does not require a vault.

---

## The ten principles

| #   | Principle              | One-line definition                                                                                    |
| --- | ---------------------- | ------------------------------------------------------------------------------------------------------ |
| 1   | **OBSERVE** (external) | Look at the actual artifact/source before extracting anything. No shortcuts.                           |
| 2   | **OBSERVE** (internal) | Metacognition — the often-skipped one. Audit your own biases and default assumptions.                  |
| 3   | **LISTEN**             | Active listening — what does the user actually want, and why this, now?                                |
| 4   | **THINK**              | First-principles analysis. The `/best-practices` six-cut engineering kernel lives _inside_ this stage. |
| 5   | **CONNECT** (lateral)  | Cross-reference against what else is known; contradictions are the highest-signal finding.             |
| 6   | **CONNECT** (systemic) | Orchestrate the system — which downstream consumers depend on this choice?                             |
| 7   | **FEEL**               | Intuition and empathy — will this empower the reader/user, or shame/confuse them?                      |
| 8   | **ACCEPT**             | Intellectual humility; anti-sycophancy enforcement. Admit what isn't true or isn't known.              |
| 9   | **CREATE**             | Generative output — produce the artifact, atomically and completely.                                   |
| 10  | **GROW**               | Iterate. Capture the feedback loop; file what's worth not re-deriving.                                 |

The two doubled stages are deliberate: OBSERVE splits external/internal because metacognition is the most-skipped step, and CONNECT splits lateral/systemic because relating-to-peers and relating-to-the-whole-system are different cognitive moves.

---

## Why it ships as code

Per the v1.8.0 pre-push audit's GROW notes, the framework first proved its value _as the audit's own mental spine_ — OBSERVE-internal forced explicit bias documentation; GROW forced a feedback-loop section. Shipping it as a first-class skill (plus appendices on every other skill) makes that discipline available to every future invocation, not just one-off audits. The release is itself the GROW step of the audit, embodied in code.

Each per-skill appendix is skill-specific, not a template stub. Examples:

- **wiki-mode's** OBSERVE-internal: "audit the assumption that `mode=generic` is the default."
- **autoresearch's** OBSERVE-internal: "am I steering the search toward what I already expect to find? confirmation bias kills research."
- **wiki-lint's** FEEL: "a lint report should empower, not shame."

---

## Composition

- `/think` + `/save` — the canonical compounding loop: apply the principles, then save the insights worth not re-deriving.
- `/think` + `/best-practices` — engineering discipline at the THINK stage; the six-cut kernel _is_ the inside of stage 4.
- `/think` + `agents/verifier.md` — a fresh-context reviewer as an OBSERVE-internal substitute for solo work, catching biases the chair missed.

---

## Honest limitations

- **It is a discipline, not a guarantee.** The loop structures attention; it does not make a wrong analysis right. A rushed pass through ten stages is still a rushed pass.
- **Read-only by design.** `/think` loads structure and discipline (tools: `Read, Grep, Glob, Bash`); it never mutates. The mutation happens in whatever skill the thinking feeds.
- **Appendix drift risk.** Fifteen skills each carry a 10-row mapping; keeping those accurate as skills evolve is ongoing maintenance, not a solved problem.

---

## Connections

See [[think]] for the canonical skill and stage-by-stage prompts.
See [[Methodology Modes]] — both are v1.8/v1.9 methodology-axis investments.
See [[LLM Wiki Pattern]] for the pattern this disciplines.
See [[2026-06-30-v1.7-v1.9.2-release-arc]] for the release context.
