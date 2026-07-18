# BrainWorks Producer Protocol

BrainWorks is the shared cross-tool memory system for Kudzie.

Canonical files:

- `C:\Users\Kudzie\OneDrive\BrainWorks\BrainWorks.md`
- `C:\Users\Kudzie\OneDrive\BrainWorks\observations.jsonl`
- `C:\Users\Kudzie\OneDrive\BrainWorks\append_observation.ps1`
- `C:\Users\Kudzie\OneDrive\BrainWorks\trait_rules.json`

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

`rule_of_three_flags` are local one-session notices only. They help a producer point at traits observed in the same entry, but they do not make a trait promotion-ready. Every flag must use a trait that also appears in that entry's `observations`, `times_observed` must be `1`, and `promote` must be `false`.

Trait aliases are maintained by the curator in `trait_rules.json` with explicit canonical categories and rationale. Producers should write the clearest observed snake_case trait for the session and let `promote_brainworks.ps1` normalize aliases, ignore self-telemetry, count distinct dates, and derive promotion readiness.

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
      "layer": "identity",
      "trait": "snake_case_trait_name",
      "detail": "One concrete observation from this session.",
      "confidence": "Tentative"
    },
    {
      "category": "workflow",
      "layer": "habit",
      "trait": "another_trait_name",
      "detail": "One concrete workflow or technical observation from this session.",
      "confidence": "Tentative"
    },
    {
      "category": "technical",
      "layer": "knowledge",
      "trait": "rust_async",
      "detail": "User reasoned about Rust async runtimes correctly; grasped spawn_local vs block_on.",
      "confidence": "Moderate",
      "metric": { "topic": "Rust", "subtopic": "async", "knowledge": 45, "confidence": 60, "basis": "observed reasoning" }
    },
    {
      "category": "technical",
      "layer": "gap",
      "trait": "confuses_jwt_auth_vs_authz",
      "detail": "User described JWT as handling authorization; it is authentication. Misstated in 2 sessions.",
      "confidence": "Strong",
      "metric": { "seen": 2, "importance": "High", "recommendation": "Study OAuth2 / OIDC auth-vs-authz distinction." }
    },
    {
      "category": "workflow",
      "layer": "mistake",
      "trait": "forgets_timezone_handling",
      "detail": "Repeatedly omitted timezone normalization in date logic across 3 projects.",
      "confidence": "Strong",
      "metric": { "occurred": 3, "likelihood": "High", "recommendation": "Run timezone validator before date math." }
    },
    {
      "category": "decision_making",
      "layer": "bias",
      "trait": "anchors_on_first_solution",
      "detail": "User locked onto the first architecture proposed and under-weighted alternatives.",
      "confidence": "Moderate"
    },
    {
      "category": "personality",
      "layer": "belief",
      "trait": "prefers_modular_monolith_over_microservices",
      "detail": "Reversed prior 'microservices always' stance after 3 migrations; now favors modular monolith.",
      "confidence": "Strong",
      "metric": { "prior": "Microservices are always better", "current": "Prefer modular monoliths", "evidence": "3 successful migrations" }
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

### Layer dimension

`layer` is an optional controlled vocabulary that classifies which cognitive model an
observation updates. It is additive: older entries without `layer` still validate. It lets
the curator route observations to the correct BrainWorks.md section and lets the graph
cluster by cognitive model. Valid layer keys (rollout phase 1):

- `identity` — who Kudzie is (goals, values, expertise levels)
- `knowledge` — what Kudzie knows and how confidently (quantitative, recency-overwrite)
- `gap` — knowledge gap or misunderstanding (quantitative severity)
- `mistake` — repeated error pattern (quantitative recurrence)
- `bias` — recurring thinking bias or reasoning preference (qualitative)
- `belief` — a stated opinion that changed (qualitative, before/after)
- `habit` — work habit or rhythm (qualitative)
- `mental_model` — preferred reasoning frame (qualitative)
- `personality` — default when the observation is about temperament/response
- `workflow` — default when the observation is about how work is done
- `technical` — default when the observation is about a tool/skill
- `communication` — default when the observation is about how Kudzie communicates
- `decision_making` — default when the observation is about a decision

Layers `knowledge`, `gap`, `mistake`, `belief` may carry a `metric` object. For
`knowledge` the metric holds `knowledge` (0-100 grasp) and `confidence` (0-100 self-assessed);
these are overwritten by recency, not promoted by date-count. For `gap`/`mistake` the metric
holds recurrence/severity fields used by the curator to prioritize teaching and warnings.

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

COGNITIVE EXTENSION (phase 1 layers — log when observed, in addition to the mandatory pair):

- Knowledge (`layer: knowledge`): assess Kudzie's grasp of a topic and self-confidence about it. Emit a `metric` with `knowledge` (0-100 grasp) and `confidence` (0-100 self-assessed). Example: `rust_async` knowledge 45, confidence 60.
- Knowledge gaps (`layer: gap`): a misunderstanding or a topic asked about repeatedly. Emit `metric` with `seen` (conversation count), `importance` (Low/Medium/High), and `recommendation`. The curator uses this to prioritize teaching.
- Mistake patterns (`layer: mistake`): a repeated error across projects. Emit `metric` with `occurred` (project count), `likelihood` (Low/Medium/High), and `recommendation`. The curator uses this to warn proactively.
- Thinking biases (`layer: bias`): a recurring reasoning preference or blind spot (anchoring, over-abstraction, underestimating migration effort).
- Belief evolution (`layer: belief`): a stated opinion that changed. Emit `metric` with `prior`, `current`, and `evidence`.

These are additive to the mandatory personality + technical/workflow pair. A session that logs only the mandatory pair still validates; the validator warns when no cognitive-extension layer is present so producers build the habit.

## Rules

- Personality and technical or workflow observations are both mandatory.
- `layer` is optional but encouraged. Valid keys: identity, knowledge, gap, mistake, bias, belief, habit, mental_model, personality, workflow, technical, communication, decision_making. Unknown keys are flagged as warnings.
- `metric` is allowed only on layers knowledge, gap, mistake, belief. A `metric` on any other layer is flagged as a warning.
- For `knowledge` metrics, `knowledge` and `confidence` are 0-100 integers; the curator overwrites by recency, not by date-count.
- For `gap`/`mistake` metrics, `seen`/`occurred` are positive integers and `importance`/`likelihood` are Low/Medium/High.
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
- Traits must be snake_case in both `observations` and `rule_of_three_flags`.
- Do not record agent self-telemetry as user evidence. Examples include probe-write traits, metadata-query traits, canonical JSONL appending, autonomous observation logging, and system setup mechanics.
- A trait repeated many times in one session still counts as one local notice. Set `times_observed` to `1`.
- Producers must never set `promote` to `true`. Promotion is derived by `promote_brainworks.ps1` from distinct dates and curator-maintained alias rules.
- Producers do not promote, curate, or rewrite `BrainWorks.md`. OpenClaw does that.
