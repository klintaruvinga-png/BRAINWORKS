# BrainWorks

BrainWorks is Kudzie's shared AI memory system.

Agents read the curated model before meaningful work. Producers append evidence after meaningful work. OpenClaw curates repeated evidence into the model.

## Core Files

| File | Role |
| --- | --- |
| `BrainWorks.md` | Curated cognitive model. Producers read it. Only OpenClaw curates it. |
| `observations.jsonl` | Append-only evidence log. One JSON object per line. |
| `agent_write_instruction.md` | Producer rules, schema, confidence rules, and observation guidance. |
| `opencode_claw_instruction.md` | OpenClaw curator workflow. |
| `append_observation.ps1` | Validates and appends one observation entry. |
| `validate_observations.ps1` | Checks JSONL structure and BrainWorks schema. |
| `promote_brainworks.ps1` | Generates promotion candidates from repeated traits. |
| `sync_brainworks_agents.ps1` | Writes BrainWorks instructions into supported agent surfaces. |
| `verify_brainworks_agents.ps1` | Verifies static wiring, permissions, CLI presence, and append behavior. |
| `BRAINWORKS_VERIFICATION.md` | Current verification record and known runtime blockers. |
| `BRAINWORKS_UPDATE_PLAN.md` | Operating plan for the BrainWorks rollout. |

## Operating Model

`BrainWorks.md` is curated memory. Treat it as the current model.

`observations.jsonl` is raw evidence. Treat it as append-only. Do not rewrite historical entries unless a migration explicitly requires it.

Most agents are producers. They read `BrainWorks.md`, do the work, then append one validated observation entry.

OpenClaw is the curator. It validates evidence, resolves conflicts, and promotes repeated patterns into `BrainWorks.md`.

## Producer Workflow

Read the model first:

```powershell
Get-Content -Raw .\BrainWorks.md
```

Append one observation at session end:

```powershell
@'
{"date":"YYYY-MM-DD","agent":"codex","session_type":"coding","observations":[{"category":"personality","trait":"snake_case_trait","detail":"Concrete observation from this session.","confidence":"Tentative"},{"category":"workflow","trait":"snake_case_workflow_trait","detail":"Concrete workflow or technical observation from this session.","confidence":"Tentative"}],"session_summary":"Two sentences max.","rule_of_three_flags":[{"trait":"snake_case_trait","times_observed":1,"promote":false}]}
'@ | powershell -NoProfile -ExecutionPolicy Bypass -File .\append_observation.ps1
```

Validate after appending:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\validate_observations.ps1 -Path .
```

The validator currently reports legacy warnings for early entries that predate the personality-observation rule. New entries must pass the stricter appender checks.

## Curator Workflow

Run validation before any curation pass:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\validate_observations.ps1 -Path .
```

Generate promotion candidates:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\promote_brainworks.ps1 -Path .
```

Promote only evidence-backed patterns. Count distinct session dates, not repeated mentions in one session.

## Agent Sync

Sync BrainWorks instructions into supported local agent surfaces:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\sync_brainworks_agents.ps1 -Root "C:\Users\Kudzie\OneDrive\BrainWorks"
```

Verify wiring:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\verify_brainworks_agents.ps1 -Root "C:\Users\Kudzie\OneDrive\BrainWorks"
```

The verifier checks the local repo instructions, global agent files, VS Code and Cursor permission settings, Claude permissions, Antigravity trusted workspaces, required environment variables, Cursor personal context, appender behavior, and log validation.

Runtime proof lives in `BRAINWORKS_VERIFICATION.md`. Some tools can be configured correctly and still fail runtime probes because of credits, quota, or account eligibility.

## Git Policy

Track the BrainWorks source:

- `BrainWorks.md`
- `observations.jsonl`
- `AGENTS.md`
- instruction files
- PowerShell scripts
- verification and rollout docs

Do not track local generated tool state:

- `.agents/`
- `.codex/`
- env files
- logs
- temp files
- editor folders

`observations.jsonl` is tracked by design. It should contain distilled evidence only. Do not store credentials, raw transcripts, or private temporary emotion in it.

## Current Review

The active review branch is:

```text
codex/brainworks-environment-verification
```

The open pull request is:

```text
https://github.com/klintaruvinga-png/BRAINWORKS/pull/1
```
