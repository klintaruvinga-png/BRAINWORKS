# BrainWorks Update Plan

## Objective

Turn BrainWorks into the single cross-tool cognitive system for Kudzie. All agents read the same curated model, all producers append evidence to one log, and only OpenClaw curates `BrainWorks.md`.

## Current Problems

1. Ownership was previously blurred. Too many agents could influence the model directly.
2. Legacy memory concepts such as `SOUL.md`, `identity.md`, and `memory.md` were mixed with the new system.
3. Some instruction surfaces are real and documented, while others are weak, unofficial, or tool-specific hacks.
4. Raw observations and curated knowledge were not cleanly separated.
5. There was no strict validation and promotion path from session evidence to model updates.
6. The system risks filling with generic observations unless producers are forced to log concrete personality and workflow evidence.

## Target Operating Model

- `BrainWorks.md` is the canonical curated model.
- `observations.jsonl` is the append-only evidence log.
- Producers read `BrainWorks.md` before significant work and append one JSON object at session end.
- OpenClaw is the sole curator. It validates evidence, resolves conflicts, and promotes repeated patterns into `BrainWorks.md`.
- Legacy memory files are either mapped into this structure or retired.

## Phase 1: Stabilize the Canonical Files

Owner: OpenClaw

Actions:

- Keep `BrainWorks.md` as the only curated cross-tool source of truth.
- Keep `observations.jsonl` as raw evidence only.
- Lock the producer-curator split in `agent_write_instruction.md` and `opencode_claw_instruction.md`.
- Remove stale references to `SOUL.md` as a live dependency unless a deliberate migration is being done.

Acceptance criteria:

- No producer instruction tells an agent to edit `BrainWorks.md`.
- No active protocol treats `SOUL.md`, `identity.md`, or `memory.md` as primary memory files.

## Phase 2: Wire All Agent Surfaces to the Same Brain

Owner: OpenClaw

Actions:

- Sync producer instructions into Codex, Claude, Copilot, Cursor, Gemini, and any other active surface.
- Prefer official instruction surfaces first.
- Use compatibility layers only where a tool has no clean documented global path.
- Keep one source instruction in this repo and generate downstream copies from it.

Acceptance criteria:

- Every active tool points to `C:\Users\Kudzie\OneDrive\BrainWorks\BrainWorks.md`.
- Every active tool points to `C:\Users\Kudzie\OneDrive\BrainWorks\observations.jsonl`.
- Every active tool uses the same producer rules and schema.

## Phase 3: Enforce Logging Discipline

Owner: Producers for writing, OpenClaw for enforcement

Actions:

- Require one append per session through `append_observation.ps1`.
- Keep the schema strict: one JSON object per line, no arrays, no transcript dumps.
- Require both personality and technical or workflow observations in every entry.
- Reject generic traits such as "smart", "good", or "likes quality" unless backed by session-specific detail.

Acceptance criteria:

- `validate_observations.ps1` passes on the full log.
- New entries contain at least one personality observation and one technical or workflow observation.
- Sensitive data never appears in the log.

## Phase 4: Establish the Curator Workflow

Owner: OpenClaw

Actions:

- Run `validate_observations.ps1` before any curation pass.
- Run `promote_brainworks.ps1` to generate promotion candidates.
- Promote only patterns seen across at least three distinct session dates unless the fact is directly stated by Kudzie.
- Surface conflicts instead of silently overwriting model statements.
- Record every curator change in the `Changelog` section of `BrainWorks.md`.

Acceptance criteria:

- Every promoted statement has traceable evidence in `observations.jsonl`.
- Conflicting statements are resolved explicitly.
- `BrainWorks.md` changes only through curator action.

## Phase 5: Populate the Model With Real Evidence

Owner: All producers, curated by OpenClaw

Actions:

- Run the system for at least 30 days of normal work.
- Focus on repeated behaviours, not flattering summaries.
- Capture where Kudzie corrects framing, pushes for speed, rejects fluff, accepts directness, or changes direction under pressure.
- Capture technical patterns such as preferred output shapes, tolerance for uncertainty, and recurring execution failures.

Acceptance criteria:

- Core sections in `BrainWorks.md` have promoted content, not placeholders.
- Promotions are based on repeated evidence, not one-session impressions.

## Phase 6: Simplify and Retire Noise

Owner: OpenClaw

Actions:

- Audit duplicate files, undocumented hacks, and stale prompts.
- Keep only files that serve one of three roles: canonical model, raw evidence, or tool instruction surface.
- Retire compatibility files when a tool gains a documented native surface.

Acceptance criteria:

- The system stays understandable without a diagram.
- New agents can be onboarded by reading `BrainWorks.md`, `agent_write_instruction.md`, and `opencode_claw_instruction.md`.

## Immediate Next Steps

1. Verify every active tool still reads the synced instructions correctly.
2. Fix any remaining validation warnings in `observations.jsonl`.
3. Start a 30-day evidence collection window with no further architecture expansion unless a real failure appears.
4. Schedule OpenClaw curator passes weekly or after major work clusters.
5. Revisit legacy file migration only after enough evidence exists to justify it.
