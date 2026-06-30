# BrainWorks Verification

Last checked: 2026-06-30

## Static Wiring

Passed with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Kudzie\OneDrive\BrainWorks\verify_brainworks_agents.ps1
```

Verified surfaces:

- Local BrainWorks repository: `C:\Users\Kudzie\OneDrive\BrainWorks\AGENTS.md`
- Codex: `C:\Users\Kudzie\.codex\AGENTS.md`
- Codex compatibility: `C:\Users\Kudzie\.codex\instructions.md`
- Claude Code: `C:\Users\Kudzie\.claude\CLAUDE.md`
- GitHub Copilot global instructions: `C:\Users\Kudzie\.github\copilot-instructions.md`
- VS Code Copilot: `C:\Users\Kudzie\.copilot\instructions\brainworks.instructions.md`
- Copilot CLI: `C:\Users\Kudzie\.copilot\copilot-instructions.md`
- Cursor rule: `C:\Users\Kudzie\.cursor\rules\brainworks-observation.mdc`
- Cursor personal context: `aicontext.personalContext` in Cursor state database
- Gemini / Antigravity: `C:\Users\Kudzie\.gemini\GEMINI.md`
- Gemini compatibility: `C:\Users\Kudzie\.gemini\config\AGENTS.md`
- BrainWorks skills: `C:\Users\Kudzie\.agents\skills\brainworks-observer\SKILL.md` and `C:\Users\Kudzie\.gemini\skills\brainworks-observer\SKILL.md`
- OpenClaw active workspace: `C:\Users\Kudzie\AGENTS.md`
- User environment: `BRAINWORKS_ROOT`, `BRAINWORKS_APPEND_SCRIPT`, `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`
- VS Code permissions: `read_file` is auto-approved, BrainWorks terminal reads are auto-approved, and writes are scoped to `append_observation.ps1`, `validate_observations.ps1`, and `verify_brainworks_agents.ps1`
- Cursor permissions: BrainWorks terminal reads and script writes are auto-approved in Cursor settings
- Claude permissions: BrainWorks read, append, validate, and verify commands are present in `.claude\settings.json` and `.claude\settings.local.json`
- Antigravity permissions: `allowNonWorkspaceAccess` is enabled and trusted workspaces include `C:\Users\Kudzie` and `C:\Users\Kudzie\OneDrive\BrainWorks`
- GitHub Copilot CLI executable: `copilot --version` returns `GitHub Copilot CLI 1.0.65`
- CLI startup checks on 2026-06-30: `codex --version`, `claude --version`, `cursor --version`, `agy --version`, `gemini --version`, `openclaw --version`, `copilot --version`, and `gh --version` all returned successfully.

The validator currently passes with historical warnings for lines 1, 3, and 18 missing personality observations. Strict mode intentionally fails only those legacy evidence-block violations. New appends are schema-checked by `append_observation.ps1`, including required personality and technical/workflow evidence, `rule_of_three_flags` shape, and JSONL compaction.

## Runtime Probes

Passed:

- Codex CLI: clean-folder probe from `C:\Users\Kudzie\Documents\BrainWorksProbe` read `BrainWorks.md`, read `agent_write_instruction.md`, returned the correct canonical paths, and appended to `observations.jsonl`.
- Antigravity / AGY: clean-folder transcript shows it read `BrainWorks.md`, loaded `brainworks-observer`, read `agent_write_instruction.md`, appended to `observations.jsonl` through stdin, and verified the appended JSON.
- Claude Code read path: clean-folder stream output shows it read `BrainWorks.md` and `agent_write_instruction.md`, then returned the correct canonical paths.
- Claude Code write path: clean-folder probe from `C:\Users\Kudzie\Documents\BrainWorksProbe` appended a `claude-code` observation through `append_observation.ps1`. The first successful append exposed that pretty-printed JSON could split across multiple physical lines; `append_observation.ps1` now parses and re-serializes every payload with `ConvertTo-Json -Compress` before appending, preserving JSONL shape.
- OpenClaw read path: session-keyed local agent probe read `BrainWorks.md` and returned the correct canonical path, custodian, last updated date, and log path.
- OpenClaw write path: session-keyed local agent probe read `BrainWorks.md` and `agent_write_instruction.md`, appended a valid `openclaw` JSONL entry through stdin, returned `OPENCLAW_WRITE_PROBE_DONE`, and `validate_observations.ps1` passed afterward.
- VS Code Copilot write path: first interactive probe launched and asked for external-file read permission. The sync script was updated to auto-approve the read-only `read_file` tool, preserve scoped terminal write approval for BrainWorks scripts, and instruct Copilot not to inspect `append_observation.ps1` before executing it. A later clean-folder probe from `C:\Users\Kudzie\Documents\BrainWorksProbe` appended a valid `vscode-copilot` JSONL entry without an additional shell-observed permission block.
- GitHub Copilot CLI install path: the broken npm CLI install was repaired with `npm install -g @github/copilot@latest`. `copilot --version` now succeeds and the Windows platform binary is present.
- Codex subagent fan-out: independent validation and agent-coverage audits were successfully run earlier. A later retry on 2026-06-30 failed before work began because the Codex subagent usage limit was reached until 2026-06-30 03:30.

Not fully proven yet:

- Cursor runtime write path: global rule, personal context, and terminal permissions are configured. `cursor agent ...` launched Cursor processes but did not append a `cursor` observation from the shell-observed probe. Kudzie stated Cursor is out of credits, so it is configured but intentionally not expected to respond until credits return.
- GitHub Copilot CLI runtime write path: the CLI now starts, but the non-interactive BrainWorks write probe returned `You have exceeded your monthly quota`. Runtime write remains unproven until Copilot quota is available.
- Gemini CLI runtime: blocked by Google `UNSUPPORTED_CLIENT` / ineligible tier error. Antigravity is the working replacement path on this machine.

## Current Status

BrainWorks is globally wired at the file, settings, environment, and permission level. Codex, Claude Code, Antigravity, OpenClaw, and VS Code Copilot have proven clean-folder read/write behavior. Cursor and GitHub Copilot CLI are configured but runtime write is blocked by current credit/quota state. Gemini CLI is blocked by account/client eligibility, with Antigravity serving as the working Gemini-family path.
