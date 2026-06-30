# OpenClaw BrainWorks Curator Protocol

All BrainWorks files live at:

`C:\Users\Kudzie\OneDrive\BrainWorks\`

OpenClaw is the curator.

Producers across Claude, Codex, Cursor, Copilot, Antigravity, and CLI tools append evidence to `observations.jsonl`. OpenClaw validates that evidence, resolves conflicts, and is the only agent allowed to update `BrainWorks.md`.

Canonical files:

- `BrainWorks.md` - curated cognitive model
- `observations.jsonl` - append-only raw evidence
- `validate_observations.ps1` - log integrity and schema validation
- `promote_brainworks.ps1` - promotion proposal generator

## On Session Start

1. Read `BrainWorks.md` in full before planning, implementation, or curation work.
2. Use it to calibrate tone, assumptions, and change discipline.
3. Treat empty, stale, or contradictory sections as curator work items.

## Curator Pass

Run this whenever curation is requested or on a scheduled BrainWorks maintenance pass:

1. Read `observations.jsonl` in full.
2. Run `validate_observations.ps1` before reasoning about promotions.
3. If validation fails, fix the log first. Do not curate from malformed evidence.
4. Count distinct session dates per trait. Multiple mentions on one date still count once.
5. Ignore producer evidence that only describes the logging mechanism or agent self-telemetry.
6. Treat 3 or more distinct session dates as promotion-eligible unless the evidence conflicts or is too weak.
7. Generate a promotion proposal with `promote_brainworks.ps1`.
8. Update `BrainWorks.md` only after the evidence threshold is met and the proposed text is coherent.
9. Append a `Changelog` entry for every curator update.
10. If OpenClaw participated in the session directly, also append its own producer JSONL entry to `observations.jsonl`.

## Promotion Report Format

Use this exact structure when summarizing the curator pass:

---
BRAINWORKS PROMOTION PROPOSAL - [DATE]

READY TO PROMOTE (3+ distinct sessions):
 Trait: [trait_name]
 Category: [category]
 Observed: [date1], [date2], [date3]
 Proposed text: [exact text to write into BrainWorks.md]
 Target section: [section name]
 Confidence: Strong

STILL BUILDING (1-2 sessions):
 Trait: [trait_name] - [N] sessions so far

CONFLICTS:
 Trait: [trait_name]
 Existing text: [current BrainWorks entry]
 New evidence: [what conflicts]
 Resolution: [retain existing / supersede existing]

OWNER SECTIONS:
 [list any proposed changes to Identity, Core Principles,
 Long-Term Goals, or Lifetime Mission]
---

## Conflict Rule

If new evidence contradicts an existing curated statement:

- Do not silently overwrite the old statement.
- Surface the conflict in the promotion proposal.
- Keep the retained statement in place until the curator resolves the conflict.
- Move the superseded statement into `Decision History` with the change date and reason.

## Guardrails

- Producers never edit `BrainWorks.md`.
- OpenClaw never curates from a malformed log.
- `observations.jsonl` is evidence, not narrative memory.
- `BrainWorks.md` is the only curated cross-tool source of truth.
