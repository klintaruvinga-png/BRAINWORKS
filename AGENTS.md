<!-- BEGIN BRAINWORKS MANAGED BLOCK -->
# BrainWorks Producer Protocol

BrainWorks lives at C:\Users\Kudzie\OneDrive\BrainWorks.

- Read BrainWorks.md before significant planning, implementation, or decision-making work.
- Treat BrainWorks.md as curated memory and observations.jsonl as raw evidence.
- You are a producer, not the curator. Never edit BrainWorks.md directly.
- At the end of each significant chat, editor, or CLI coding session, append one canonical JSONL entry to observations.jsonl.
- Prefer piping JSON through stdin: @'...json...'@ | powershell -File C:\Users\Kudzie\OneDrive\BrainWorks\append_observation.ps1
- Use -Json only when the payload is already stored in a PowerShell variable.
- If direct append is unavailable, output the JSON block for manual paste.
- Record both personality and technical or workflow evidence every session.
- Follow the exact schema and rules in C:\Users\Kudzie\OneDrive\BrainWorks\agent_write_instruction.md.
- OpenClaw is the only curator allowed to promote evidence into BrainWorks.md.
<!-- END BRAINWORKS MANAGED BLOCK -->

# Repository Guidelines

## Project Structure & Module Organization

This repository is a small, flat workspace for the BrainWorks cognitive model. Keep files at the repository root unless a new subdirectory has a clear purpose.

- `BrainWorks.md`: canonical model and long-term reference.
- `observations.jsonl`: append-only session observation log.
- `append_observation.ps1`: validates and appends one JSON object line.
- `agent_write_instruction.md`, `opencode_claw_instruction.md`: operating rules for contributing agents.

If you add supporting material, prefer descriptive names that match the current pattern, for example `new_protocol.md` or `sync_observations.ps1`.

## Build, Test, and Development Commands

There is no build pipeline in this repository. Work is mostly Markdown editing and JSONL maintenance.

- `Get-Content -Raw .\BrainWorks.md`
  Reads the canonical model before planning or editing.
- `powershell -File .\append_observation.ps1 -Json '{"date":"2026-06-29","agent":"codex","session_type":"general","observations":[],"session_summary":"...","rule_of_three_flags":[]}'`
  Validates JSON and appends it to `observations.jsonl`.
- `Get-Content .\observations.jsonl | Select-Object -Last 1 | ConvertFrom-Json | Out-Null`
  Smoke-checks that the newest log entry is valid JSON.

## Coding Style & Naming Conventions

Keep prose direct and operational. Use short paragraphs, explicit file references, and concrete wording.

- Markdown: use `#` headings, short sections, and stable terminology.
- JSONL: one compact JSON object per line, no wrapping array, no trailing commas.
- PowerShell: preserve readable formatting, use standard cmdlets, and keep validation explicit.
- Filenames: prefer descriptive names; use `.md` for instructions and `.ps1` for automation.

## Testing Guidelines

There is no formal test suite. Validation is file-specific.

- For `observations.jsonl`, verify new entries parse as JSON.
- For Markdown updates, check heading structure and confirm referenced paths exist.
- Do not rewrite or reorder historical log entries unless the task explicitly requires migration.

## Commit & Pull Request Guidelines

This repository is Git-backed. Use short imperative commit subjects such as `Add observation append example` or `Clarify promotion protocol`.

Pull requests should explain the changed file, the reason for the change, and any schema or workflow impact. Include before/after snippets when modifying `BrainWorks.md` structure or the JSONL schema.

## Security & Data Handling

Never store passwords, credentials, raw chat logs, or temporary emotions in this repository. `observations.jsonl` should contain distilled observations only, not transcript dumps.
