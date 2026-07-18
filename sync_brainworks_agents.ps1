param(
  [Parameter(Mandatory = $false)]
  [string]$Root = $env:BRAINWORKS_ROOT,

  [Parameter(Mandatory = $false)]
  [string]$UserHome = $HOME,

  [Parameter(Mandatory = $false)]
  [string]$OpenClawWorkspace
)

if (-not $Root) {
  $Root = 'C:\Users\Kudzie\OneDrive\BrainWorks'
}

if (-not $OpenClawWorkspace) {
  $OpenClawWorkspace = $UserHome

  $openclaw = Get-Command openclaw -ErrorAction SilentlyContinue
  if ($openclaw) {
    $configuredWorkspace = (& openclaw config get agents.defaults.workspace 2>$null).Trim()
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($configuredWorkspace)) {
      $OpenClawWorkspace = $configuredWorkspace
    }
  }
}

$cognitiveExtensionNote = @"

Cognitive-extension layers (log when observed, in addition to the mandatory pair):
- knowledge: assess Kudzie's grasp (0-100) and self-confidence (0-100) of a topic; emit a metric.
- gap: a misunderstanding or a topic asked about repeatedly; emit metric with seen/importance/recommendation.
- mistake: a repeated error pattern across projects; emit metric with occurred/likelihood/recommendation.
- bias: a recurring reasoning preference or blind spot.
- belief: a stated opinion that changed; emit metric with prior/current/evidence.
See $Root\agent_write_instruction.md for the exact layer vocabulary, metric shapes, and examples.
"@

$producerProtocol = @"
# BrainWorks Producer Protocol

BrainWorks lives at $Root.

- Read BrainWorks.md before significant planning, implementation, or decision-making work.
- Treat BrainWorks.md as curated memory and observations.jsonl as raw evidence.
- You are a producer, not the curator. Never edit BrainWorks.md directly.
- At the end of each significant chat, editor, or CLI coding session, append one canonical JSONL entry to observations.jsonl.
- Prefer piping JSON through stdin: @'...json...'@ | powershell -File $Root\append_observation.ps1
- Use -Json only when the payload is already stored in a PowerShell variable.
- If direct append is unavailable, output the JSON block for manual paste.
- Record both personality and technical or workflow evidence every session.
- Follow the exact schema and rules in $Root\agent_write_instruction.md.
- OpenClaw is the only curator allowed to promote evidence into BrainWorks.md.
"@ + $cognitiveExtensionNote

$copilotInstruction = @"
---
applyTo: "**"
---

This machine uses BrainWorks at $Root.

- Read BrainWorks.md before significant planning, implementation, or decision-making work.
- Never edit BrainWorks.md directly. OpenClaw is the curator.
- At the end of each significant chat, editor, or CLI coding session, append one canonical JSONL entry to observations.jsonl.
- Prefer piping JSON through stdin: @'...json...'@ | powershell -File $Root\append_observation.ps1.
- Use -Json only when the payload is already stored in a PowerShell variable.
- In VS Code Copilot, do not inspect append_observation.ps1 with file-read tools before appending. Execute it directly through the terminal command above.
- For BrainWorks files outside the current project workspace, prefer terminal reads such as Get-Content over file-reader tools when possible.
- Record both personality and technical or workflow evidence.
- Follow $Root\agent_write_instruction.md for the exact schema and rules.
"@ + $cognitiveExtensionNote

$copilotCliInstruction = @"
# BrainWorks Producer Protocol

BrainWorks lives at $Root.

- Read $Root\BrainWorks.md before significant planning, implementation, or decision-making work.
- Treat $Root\BrainWorks.md as curated memory and $Root\observations.jsonl as raw evidence.
- Never edit BrainWorks.md directly. OpenClaw is the curator.
- At the end of each significant Copilot CLI session, append one canonical JSONL entry to $Root\observations.jsonl.
- Prefer piping JSON through stdin: @'...json...'@ | powershell -File $Root\append_observation.ps1.
- Use -Json only when the payload is already stored in a PowerShell variable.
- If direct append is unavailable, output the JSON block for manual paste.
- Record both personality and technical or workflow evidence every session.
- Follow $Root\agent_write_instruction.md for the exact schema and rules.
"@ + $cognitiveExtensionNote

$cursorRule = @"
---
description: BrainWorks producer protocol for Cursor sessions
alwaysApply: true
---

- BrainWorks lives at $Root.
- Read BrainWorks.md before significant planning, implementation, or decision-making work.
- Never edit BrainWorks.md directly. OpenClaw is the curator.
- Append one canonical JSONL entry to observations.jsonl at the end of each significant chat, editor, or CLI session.
- Prefer piping JSON through stdin: @'...json...'@ | powershell -File $Root\append_observation.ps1.
- Use -Json only when the payload is already stored in a PowerShell variable.
- Record both personality and technical or workflow evidence.
- Follow $Root\agent_write_instruction.md for the exact schema and rules.
"@ + $cognitiveExtensionNote

$antigravityAgents = @"
# Global Antigravity Agent Rules

## BrainWorks Producer Protocol

BrainWorks lives at $Root.

- Read BrainWorks.md before significant planning, implementation, or decision-making work.
- Never edit BrainWorks.md directly. OpenClaw is the curator.
- At the end of each significant Antigravity, AGY, Gemini chat, or CLI session, append one canonical JSONL entry to observations.jsonl.
- Prefer piping JSON through stdin: @'...json...'@ | powershell -File $Root\append_observation.ps1.
- Use -Json only when the payload is already stored in a PowerShell variable.
- If direct append is unavailable, output the JSON block for manual paste.
- Record both personality and technical or workflow evidence every session.
- Follow the exact schema and rules in $Root\agent_write_instruction.md.
"@ + $cognitiveExtensionNote

$openClawProtocol = @"
# BrainWorks Curator Protocol

BrainWorks lives at $Root.

- Read $Root\BrainWorks.md before significant planning, implementation, decision-making, or curation work.
- Use $Root\BrainWorks.md as the curated model of Kudzie.
- Treat $Root\observations.jsonl as raw evidence, not the primary model.
- OpenClaw is the curator. Validate evidence, resolve conflicts, and promote repeated patterns into BrainWorks.md.
- Other agents are producers. They append evidence to observations.jsonl and must not edit BrainWorks.md.
- Follow $Root\opencode_claw_instruction.md for curation passes.
- If OpenClaw participates in a normal chat or CLI coding session, append one canonical JSONL entry at session end.
"@

$skillContent = @"
---
name: brainworks-observer
description: Use when working with Kudzie on this machine. Load BrainWorks, record both personality and technical or workflow evidence, append a canonical JSONL entry, and never curate BrainWorks directly unless you are OpenClaw.
---

# BrainWorks Observer

1. Read $Root\BrainWorks.md before significant work.
2. Follow $Root\agent_write_instruction.md for the exact JSONL schema and observation rules.
3. Append one JSON object line to $Root\observations.jsonl at session end with $Root\append_observation.ps1.
4. Do not edit $Root\BrainWorks.md directly unless you are the OpenClaw curator.
"@

$cursorPersonalContext = "BrainWorks lives at $Root. Read BrainWorks.md before significant planning, implementation, or decision-making work. Treat BrainWorks.md as curated memory and observations.jsonl as raw evidence. Never edit BrainWorks.md directly; OpenClaw is the only curator. At the end of each significant chat, editor, or CLI session, append one canonical JSONL entry to observations.jsonl. Prefer piping JSON through stdin with @'...json...'@ | powershell -File $Root\append_observation.ps1; use -Json only when the payload is already stored in a PowerShell variable. Record both personality and technical or workflow evidence, and follow $Root\agent_write_instruction.md for the exact schema and rules."

function Set-ManagedBrainWorksBlock {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Content
  )

  $start = '<!-- BEGIN BRAINWORKS MANAGED BLOCK -->'
  $end = '<!-- END BRAINWORKS MANAGED BLOCK -->'
  $block = "$start`r`n$Content`r`n$end"

  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  if (Test-Path $Path) {
    $existing = Get-Content -Raw $Path
    $pattern = "(?s)$([regex]::Escape($start)).*?$([regex]::Escape($end))"
    if ($existing -match $pattern) {
      $updated = [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
    }
    else {
      $updated = "$block`r`n`r`n$existing"
    }
  }
  else {
    $updated = $block
  }

  Set-Content -Path $Path -Value $updated -NoNewline
}

$targets = @(
  @{ Path = Join-Path $UserHome '.codex\AGENTS.md'; Content = $producerProtocol },
  @{ Path = Join-Path $UserHome '.codex\instructions.md'; Content = $producerProtocol },
  @{ Path = Join-Path $UserHome '.claude\CLAUDE.md'; Content = $producerProtocol },
  @{ Path = Join-Path $UserHome '.github\copilot-instructions.md'; Content = $producerProtocol },
  @{ Path = Join-Path $UserHome '.cursor\rules\brainworks-observation.mdc'; Content = $cursorRule },
  @{ Path = Join-Path $UserHome '.gemini\GEMINI.md'; Content = $antigravityAgents },
  @{ Path = Join-Path $UserHome '.gemini\config\AGENTS.md'; Content = $antigravityAgents },
  @{ Path = Join-Path $UserHome '.copilot\copilot-instructions.md'; Content = $copilotCliInstruction },
  @{ Path = Join-Path $UserHome '.copilot\instructions\brainworks.instructions.md'; Content = $copilotInstruction },
  @{ Path = Join-Path $UserHome '.agents\skills\brainworks-observer\SKILL.md'; Content = $skillContent },
  @{ Path = Join-Path $UserHome '.gemini\skills\brainworks-observer\SKILL.md'; Content = $skillContent }
)

$sharedInstructionTargets = @(
  (Join-Path $UserHome '.codex\AGENTS.md'),
  (Join-Path $UserHome '.claude\CLAUDE.md'),
  (Join-Path $UserHome '.github\copilot-instructions.md')
)

foreach ($target in $targets) {
  $dir = Split-Path -Parent $target.Path
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  if ($sharedInstructionTargets -contains $target.Path) {
    Set-ManagedBrainWorksBlock -Path $target.Path -Content $target.Content
  }
  else {
    Set-Content -Path $target.Path -Value $target.Content -NoNewline
  }
}

Set-ManagedBrainWorksBlock -Path (Join-Path $OpenClawWorkspace 'AGENTS.md') -Content $openClawProtocol
Set-ManagedBrainWorksBlock -Path (Join-Path $Root 'AGENTS.md') -Content $producerProtocol

function Set-JsonProperty {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Object,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [object]$Value
  )

  if ($Object.PSObject.Properties.Name -contains $Name) {
    $Object.$Name = $Value
  }
  else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (Test-Path $Path) {
    return Get-Content -Raw $Path | ConvertFrom-Json
  }

  return [pscustomobject]@{}
}

function Save-JsonFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [object]$Object
  )

  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  $Object | ConvertTo-Json -Depth 100 | Set-Content -Path $Path -NoNewline
}

function Set-BrainWorksTerminalAutoApprove {
  param([Parameter(Mandatory = $true)][string]$SettingsPath)

  $settings = Read-JsonFile -Path $SettingsPath

  $autoApprove = $settings.'chat.tools.terminal.autoApprove'
  if (-not $autoApprove) {
    $autoApprove = [pscustomobject]@{}
  }

  $escapedRoot = [regex]::Escape($Root)
  $readPattern = '/.*(Get-Content|Select-String|rg).*{0}\\(BrainWorks\.md|agent_write_instruction\.md|opencode_claw_instruction\.md|BRAINWORKS_UPDATE_PLAN\.md|BRAINWORKS_VERIFICATION\.md|observations\.jsonl).*/' -f $escapedRoot
  $appendPattern = '/.*powershell(\.exe)?(\s+-NoProfile)?(\s+-ExecutionPolicy\s+Bypass)?\s+-File\s+[''"]?{0}\\append_observation\.ps1[''"]?.*/' -f $escapedRoot
  $validatePattern = '/.*powershell(\.exe)?(\s+-NoProfile)?(\s+-ExecutionPolicy\s+Bypass)?\s+-File\s+[''"]?{0}\\(validate_observations|verify_brainworks_agents)\.ps1[''"]?.*/' -f $escapedRoot

  foreach ($pattern in @($readPattern, $appendPattern, $validatePattern)) {
    Set-JsonProperty -Object $autoApprove -Name $pattern -Value ([pscustomobject]@{
      approve = $true
      matchCommandLine = $true
    })
  }

  Set-JsonProperty -Object $settings -Name 'chat.tools.terminal.autoApprove' -Value $autoApprove

  Save-JsonFile -Path $SettingsPath -Object $settings
}

function Set-VSCodeBrainWorksInstructions {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SettingsPath,

    [Parameter(Mandatory = $true)]
    [string]$InstructionDir
  )

  $settings = Read-JsonFile -Path $SettingsPath

  Set-JsonProperty -Object $settings -Name 'chat.useClaudeMdFile' -Value $true
  Set-JsonProperty -Object $settings -Name 'chat.useAgentsMdFile' -Value $true
  Set-JsonProperty -Object $settings -Name 'github.copilot.chat.codeGeneration.useInstructionFiles' -Value $true

  $globalAutoApprove = $settings.'chat.tools.global.autoApprove'
  if ($globalAutoApprove -ne $true) {
    if ($globalAutoApprove -is [bool] -or -not $globalAutoApprove) {
      $globalAutoApprove = [pscustomobject]@{}
    }

    Set-JsonProperty -Object $globalAutoApprove -Name 'read_file' -Value $true
    Set-JsonProperty -Object $settings -Name 'chat.tools.global.autoApprove' -Value $globalAutoApprove
  }

  $eligible = $settings.'chat.tools.eligibleForAutoApproval'
  if (-not $eligible) {
    $eligible = [pscustomobject]@{}
  }

  Set-JsonProperty -Object $eligible -Name 'read_file' -Value $true
  Set-JsonProperty -Object $settings -Name 'chat.tools.eligibleForAutoApproval' -Value $eligible

  $locations = $settings.'chat.instructionsFilesLocations'
  if (-not $locations) {
    $locations = [pscustomobject]@{}
  }

  Set-JsonProperty -Object $locations -Name $InstructionDir -Value $true
  Set-JsonProperty -Object $settings -Name 'chat.instructionsFilesLocations' -Value $locations

  Save-JsonFile -Path $SettingsPath -Object $settings
}

function Add-ClaudePermissions {
  param([Parameter(Mandatory = $true)][string]$SettingsPath)

  $settings = Read-JsonFile -Path $SettingsPath

  if (-not $settings.permissions) {
    Set-JsonProperty -Object $settings -Name 'permissions' -Value ([pscustomobject]@{})
  }

  $allow = @()
  if ($settings.permissions.allow) {
    $allow = @($settings.permissions.allow)
  }

  $brainworksPermissions = @(
    "PowerShell(Get-Content *$Root*)",
    "PowerShell(*$Root\append_observation.ps1*)",
    "PowerShell(*$Root\validate_observations.ps1*)",
    "PowerShell(*$Root\verify_brainworks_agents.ps1*)",
    "Bash(*$Root\append_observation.ps1*)",
    "Bash(*$Root\validate_observations.ps1*)"
  )

  foreach ($permission in $brainworksPermissions) {
    if ($allow -notcontains $permission) {
      $allow += $permission
    }
  }

  Set-JsonProperty -Object $settings.permissions -Name 'allow' -Value $allow
  Save-JsonFile -Path $SettingsPath -Object $settings
}

function Add-AntigravityTrustedWorkspace {
  param([Parameter(Mandatory = $true)][string]$SettingsPath)

  $settings = Read-JsonFile -Path $SettingsPath
  Set-JsonProperty -Object $settings -Name 'allowNonWorkspaceAccess' -Value $true

  $trusted = @()
  if ($settings.trustedWorkspaces) {
    $trusted = @($settings.trustedWorkspaces)
  }

  foreach ($path in @($UserHome, $Root)) {
    if ($trusted -notcontains $path) {
      $trusted += $path
    }
  }

  Set-JsonProperty -Object $settings -Name 'trustedWorkspaces' -Value $trusted
  Save-JsonFile -Path $SettingsPath -Object $settings
}

$codeSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
$cursorSettings = Join-Path $env:APPDATA 'Cursor\User\settings.json'
$appendScript = Join-Path $Root 'append_observation.ps1'
$copilotInstructionDir = Join-Path $UserHome '.copilot\instructions'

Set-BrainWorksTerminalAutoApprove -SettingsPath $codeSettings
Set-BrainWorksTerminalAutoApprove -SettingsPath $cursorSettings
Set-VSCodeBrainWorksInstructions -SettingsPath $codeSettings -InstructionDir $copilotInstructionDir

Add-ClaudePermissions -SettingsPath (Join-Path $UserHome '.claude\settings.json')
Add-ClaudePermissions -SettingsPath (Join-Path $UserHome '.claude\settings.local.json')
Add-AntigravityTrustedWorkspace -SettingsPath (Join-Path $UserHome '.gemini\antigravity-cli\settings.json')

[Environment]::SetEnvironmentVariable('BRAINWORKS_ROOT', $Root, 'User')
[Environment]::SetEnvironmentVariable('BRAINWORKS_APPEND_SCRIPT', $appendScript, 'User')
[Environment]::SetEnvironmentVariable('COPILOT_CUSTOM_INSTRUCTIONS_DIRS', $copilotInstructionDir, 'User')

$cursorDb = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
$python = Get-Command python -ErrorAction SilentlyContinue
$cursorContextInjected = $false

if (-not (Test-Path $cursorDb)) {
  Write-Warning "Cursor personal context injection skipped because the database was not found: $cursorDb"
}
elseif (-not $python) {
  Write-Warning 'Cursor personal context injection skipped because python was not found on PATH.'
}
else {
  $env:BW_CURSOR_DB = $cursorDb
  $env:BW_CURSOR_CONTEXT = $cursorPersonalContext

@'
import os
import sqlite3

db = os.environ["BW_CURSOR_DB"]
context = os.environ["BW_CURSOR_CONTEXT"]

conn = sqlite3.connect(db)
try:
    conn.execute(
        "insert or replace into ItemTable(key, value) values(?, ?)",
        ("aicontext.personalContext", context),
    )
    conn.commit()
finally:
    conn.close()
'@ | & $python.Source -

  $cursorExitCode = $LASTEXITCODE
  Remove-Item Env:\BW_CURSOR_DB -ErrorAction SilentlyContinue
  Remove-Item Env:\BW_CURSOR_CONTEXT -ErrorAction SilentlyContinue

  if ($cursorExitCode -ne 0) {
    throw "Cursor personal context injection failed with exit code $cursorExitCode."
  }

  $cursorContextInjected = $true
}

Write-Output 'BrainWorks agent surfaces synced.'
if ($cursorContextInjected) {
  Write-Output 'Cursor personal context synced.'
}
else {
  Write-Warning 'Cursor personal context was not synced.'
}
Write-Output "OpenClaw workspace targeted: $OpenClawWorkspace"
