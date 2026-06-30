# BrainWorks Producer Protocol

BrainWorks is the shared cross-tool memory system for Kudzie.

Canonical files:

- `C:\Users\Kudzie\OneDrive\BrainWorks\BrainWorks.md`
- `C:\Users\Kudzie\OneDrive\BrainWorks\observations.jsonl`
- `C:\Users\Kudzie\OneDrive\BrainWorks\append_observation.ps1`

Role split:

- Most agents are **producers**. They read `BrainWorks.md` and append evidence to `observations.jsonl`.
- **OpenClaw is the curator.** It is the only agent allowed to promote evidence into `BrainWorks.md`.
- Producers must **never edit `BrainWorks.md` directly**.

## On Session Start

Before significant planning, implementation, or decision-making work:

1. Read `BrainWorks.md` in full.
2. Use it to calibrate tone, assumptions, depth, and collaboration style.
3. Treat it as the current curated model. Treat `observations.jsonl` as raw evidence, not as the source to reason from directly.

## On Session End

Append exactly one JSON object line to:

`C:\Users\Kudzie\OneDrive\BrainWorks\observations.jsonl`

Use:

`powershell -File C:\Users\Kudzie\OneDrive\BrainWorks\append_observation.ps1 -Json '{...}'`

Preferred CLI-safe form on Windows:

```powershell
@'
{"date":"YYYY-MM-DD","agent":"codex","session_type":"coding","observations":[{"category":"personality","trait":"snake_case_trait_name","detail":"One concrete observation from this session.","confidence":"Tentative"},{"category":"workflow","trait":"another_trait_name","detail":"One concrete workflow or technical observation from this session.","confidence":"Tentative"}],"session_summary":"Two sentences max.","rule_of_three_flags":[{"trait":"snake_case_trait_name","times_observed":1,"promote":false}]}
'@ | powershell -File C:\Users\Kudzie\OneDrive\BrainWorks\append_observation.ps1
```

Use `-Json` only when the JSON payload is already stored in a PowerShell variable. For nested CLI calls, pipe the JSON through stdin to avoid quote stripping.

If direct append is unavailable, output the JSON block for manual paste.

One object per line. Never overwrite. Always append.

Recommended `agent` values:

- `codex`
- `claude`
- `claude-code`
- `cursor`
- `vscode-copilot`
- `antigravity`
- `agy`
- `openclaw`
- `other`

Schema:

```json
{
  "date": "YYYY-MM-DD",
  "agent": "codex",
  "session_type": "coding",
  "observations": [
    {
      "category": "personality",
      "trait": "snake_case_trait_name",
      "detail": "One concrete observation from this session.",
      "confidence": "Tentative"
    },
    {
      "category": "workflow",
      "trait": "another_trait_name",
      "detail": "One concrete workflow or technical observation from this session.",
      "confidence": "Tentative"
    }
  ],
  "session_summary": "Two sentences max.",
  "rule_of_three_flags": [
    {
      "trait": "snake_case_trait_name",
      "times_observed": 1,
      "promote": false
    }
  ]
}
```

## What To Observe

Both blocks are required every session.

PERSONALITY:

- Impatience signals: rushing, terse corrections, pushing for earlier output
- Response to challenge: accepts reasoning, asks for evidence, resists, redirects
- Behaviour under pressure or when blocked
- What gets approved without comment
- Tone shifts across the session
- How Kudzie responds when wrong versus when right

TECHNICAL AND WORKFLOW:

- Where Kudzie identified the real problem before the agent did
- Where the agent had to correct Kudzie
- What output format was accepted, revised, or rejected
- How the problem framing changed during the session
- Patterns in what Kudzie consistently gets right
- Patterns in what consistently trips Kudzie up

## Rules

- Personality and technical or workflow observations are both mandatory.
- `Tentative` = observed in this session only.
- `Moderate` = observed across two distinct session dates.
- `Strong` = observed across three or more distinct session dates.
- `Confirmed` = directly stated by Kudzie or consistently observed across many sessions.
- `Hypothesis` belongs in curated `BrainWorks.md` reasoning only; producer JSONL entries should use `Tentative`, `Moderate`, `Strong`, or `Confirmed`.
- Do not mark anything `Moderate`, `Strong`, or `Confirmed` from one session alone unless it is a direct user-stated fact.
- Never attribute your own actions, preferences, or choices to Kudzie.
- Record only observations grounded in Kudzie's behaviour, statements, or direct evidence.
- One JSON object per line. No wrapping arrays. No trailing commas.
- Never store passwords, credentials, raw chat logs, or temporary emotions.
- A trait repeated many times in one session still counts as one session date in `rule_of_three_flags`.
- Producers do not promote, curate, or rewrite `BrainWorks.md`. OpenClaw does that.
