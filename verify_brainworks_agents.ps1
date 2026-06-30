param(
  [Parameter(Mandatory = $false)]
  [string]$Root = $env:BRAINWORKS_ROOT,

  [Parameter(Mandatory = $false)]
  [string]$UserHome = $HOME
)

if (-not $Root) {
  $Root = 'C:\Users\Kudzie\OneDrive\BrainWorks'
}

$failures = @()
$warnings = @()

function Assert-FileContains {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string[]]$Needles,

    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  if (-not (Test-Path $Path)) {
    $script:failures += "$Label missing: $Path"
    return
  }

  $content = Get-Content -Raw $Path
  foreach ($needle in $Needles) {
    if ($content -notlike "*$needle*") {
      $script:failures += "$Label does not contain required text: $needle"
    }
  }
}

function Assert-TerminalAutoApprove {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SettingsPath,

    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  if (-not (Test-Path $SettingsPath)) {
    $script:warnings += "$Label settings missing: $SettingsPath"
    return
  }

  $settings = Get-Content -Raw $SettingsPath | ConvertFrom-Json
  $autoApprove = $settings.'chat.tools.terminal.autoApprove'
  if (-not $autoApprove) {
    $script:failures += "$Label terminal auto-approval is missing."
    return
  }

  foreach ($needle in @('BrainWorks', 'append_observation', 'validate_observations', 'verify_brainworks_agents')) {
    $matches = @($autoApprove.PSObject.Properties | Where-Object { $_.Name -like "*$needle*" })
    if ($matches.Count -eq 0) {
      $script:failures += "$Label terminal auto-approval does not include $needle."
      continue
    }

    $enabled = @($matches | Where-Object {
      $_.Value.approve -eq $true -and $_.Value.matchCommandLine -eq $true
    })
    if ($enabled.Count -eq 0) {
      $script:failures += "$Label terminal auto-approval entry for $needle is missing approve=true and matchCommandLine=true."
    }
  }
}

function Assert-ClaudePermissions {
  param([Parameter(Mandatory = $true)][string]$SettingsPath)

  if (-not (Test-Path $SettingsPath)) {
    $script:warnings += "Claude permissions settings missing: $SettingsPath"
    return
  }

  $settings = Get-Content -Raw $SettingsPath | ConvertFrom-Json
  $allow = @($settings.permissions.allow)
  foreach ($needle in @('BrainWorks', 'append_observation.ps1', 'validate_observations.ps1', 'verify_brainworks_agents.ps1')) {
    if (-not ($allow | Where-Object { $_ -like "*$needle*" })) {
      $script:failures += "Claude permissions in $SettingsPath do not include $needle."
    }
  }
}

$coreFiles = @(
  (Join-Path $Root 'BrainWorks.md'),
  (Join-Path $Root 'observations.jsonl'),
  (Join-Path $Root 'append_observation.ps1'),
  (Join-Path $Root 'agent_write_instruction.md'),
  (Join-Path $Root 'opencode_claw_instruction.md')
)

foreach ($file in $coreFiles) {
  if (-not (Test-Path $file)) {
    $failures += "Core file missing: $file"
  }
}

$needles = @($Root, 'BrainWorks', 'observations.jsonl', 'append_observation.ps1')

$surfaces = @(
  @{ Label = 'Local repository AGENTS.md'; Path = Join-Path $Root 'AGENTS.md' },
  @{ Label = 'Codex documented AGENTS.md'; Path = Join-Path $UserHome '.codex\AGENTS.md' },
  @{ Label = 'Codex compatibility instructions.md'; Path = Join-Path $UserHome '.codex\instructions.md' },
  @{ Label = 'Claude global CLAUDE.md'; Path = Join-Path $UserHome '.claude\CLAUDE.md' },
  @{ Label = 'GitHub Copilot global instructions'; Path = Join-Path $UserHome '.github\copilot-instructions.md' },
  @{ Label = 'Copilot CLI instructions'; Path = Join-Path $UserHome '.copilot\copilot-instructions.md' },
  @{ Label = 'VS Code Copilot instructions'; Path = Join-Path $UserHome '.copilot\instructions\brainworks.instructions.md' },
  @{ Label = 'Cursor global rule'; Path = Join-Path $UserHome '.cursor\rules\brainworks-observation.mdc' },
  @{ Label = 'Gemini/Antigravity GEMINI.md'; Path = Join-Path $UserHome '.gemini\GEMINI.md' },
  @{ Label = 'Gemini compatibility AGENTS.md'; Path = Join-Path $UserHome '.gemini\config\AGENTS.md' },
  @{ Label = 'Codex/agent skill'; Path = Join-Path $UserHome '.agents\skills\brainworks-observer\SKILL.md' },
  @{ Label = 'Gemini skill'; Path = Join-Path $UserHome '.gemini\skills\brainworks-observer\SKILL.md' }
)

foreach ($surface in $surfaces) {
  Assert-FileContains -Path $surface.Path -Needles $needles -Label $surface.Label
}

$openclawWorkspace = $UserHome
$openclaw = Get-Command openclaw -ErrorAction SilentlyContinue
if ($openclaw) {
  $configuredWorkspace = (& openclaw config get agents.defaults.workspace 2>$null).Trim()
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($configuredWorkspace)) {
    $openclawWorkspace = $configuredWorkspace
  }
}
Assert-FileContains -Path (Join-Path $openclawWorkspace 'AGENTS.md') -Needles @($Root, 'OpenClaw is the curator', 'observations.jsonl') -Label 'OpenClaw active workspace AGENTS.md'

$codeSettings = Join-Path $env:APPDATA 'Code\User\settings.json'
if (Test-Path $codeSettings) {
  $settings = Get-Content -Raw $codeSettings | ConvertFrom-Json
  if ($settings.'chat.useClaudeMdFile' -ne $true) { $failures += 'VS Code chat.useClaudeMdFile is not true.' }
  if ($settings.'chat.useAgentsMdFile' -ne $true) { $failures += 'VS Code chat.useAgentsMdFile is not true.' }
  if ($settings.'github.copilot.chat.codeGeneration.useInstructionFiles' -ne $true) { $failures += 'VS Code Copilot instruction files are not enabled.' }
  $instructionLocations = $settings.'chat.instructionsFilesLocations'
  if (-not $instructionLocations) {
    $failures += 'VS Code chat.instructionsFilesLocations is missing.'
  }
  else {
    $expectedInstructionDir = (Join-Path $UserHome '.copilot\instructions').TrimEnd('\', '/')
    $enabledInstructionLocation = @($instructionLocations.PSObject.Properties | Where-Object {
      $_.Name.TrimEnd('\', '/') -eq $expectedInstructionDir -and $_.Value -eq $true
    })
    if ($enabledInstructionLocation.Count -eq 0) {
      $failures += "VS Code chat.instructionsFilesLocations does not enable $expectedInstructionDir."
    }
  }

  $globalAutoApprove = $settings.'chat.tools.global.autoApprove'
  if ($globalAutoApprove -ne $true -and $globalAutoApprove.read_file -ne $true) {
    $failures += 'VS Code read_file tool is not auto-approved for BrainWorks external-file reads.'
  }

  $eligible = $settings.'chat.tools.eligibleForAutoApproval'
  if ($eligible -and $eligible.read_file -eq $false) {
    $failures += 'VS Code read_file tool is explicitly ineligible for auto-approval.'
  }
}
else {
  $warnings += "VS Code settings missing: $codeSettings"
}

$cursorSettings = Join-Path $env:APPDATA 'Cursor\User\settings.json'
Assert-TerminalAutoApprove -SettingsPath $codeSettings -Label 'VS Code'
Assert-TerminalAutoApprove -SettingsPath $cursorSettings -Label 'Cursor'
Assert-ClaudePermissions -SettingsPath (Join-Path $UserHome '.claude\settings.json')
Assert-ClaudePermissions -SettingsPath (Join-Path $UserHome '.claude\settings.local.json')

$antiSettings = Join-Path $UserHome '.gemini\antigravity-cli\settings.json'
if (Test-Path $antiSettings) {
  $anti = Get-Content -Raw $antiSettings | ConvertFrom-Json
  if ($anti.allowNonWorkspaceAccess -ne $true) {
    $failures += 'Antigravity allowNonWorkspaceAccess is not true.'
  }
  $trusted = @($anti.trustedWorkspaces)
  foreach ($workspace in @($UserHome, $Root)) {
    if ($trusted -notcontains $workspace) {
      $failures += "Antigravity trustedWorkspaces does not include $workspace."
    }
  }
}
else {
  $warnings += "Antigravity settings missing: $antiSettings"
}

foreach ($name in @('codex', 'claude', 'cursor', 'agy', 'gemini', 'openclaw', 'copilot')) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    $warnings += "Executable not found on PATH: $name"
  }
}

$copilot = Get-Command copilot -ErrorAction SilentlyContinue
if ($copilot) {
  $copilotVersion = (& copilot --version 2>$null)
  if ($LASTEXITCODE -ne 0 -or -not ($copilotVersion -like '*GitHub Copilot CLI*')) {
    $failures += 'GitHub Copilot CLI is on PATH but did not return a usable version.'
  }
}

if ([Environment]::GetEnvironmentVariable('BRAINWORKS_ROOT', 'User') -ne $Root) {
  $failures += 'User environment BRAINWORKS_ROOT does not match BrainWorks root.'
}

if ([Environment]::GetEnvironmentVariable('BRAINWORKS_APPEND_SCRIPT', 'User') -ne (Join-Path $Root 'append_observation.ps1')) {
  $failures += 'User environment BRAINWORKS_APPEND_SCRIPT does not match append script.'
}

if ([Environment]::GetEnvironmentVariable('COPILOT_CUSTOM_INSTRUCTIONS_DIRS', 'User') -ne (Join-Path $UserHome '.copilot\instructions')) {
  $failures += 'User environment COPILOT_CUSTOM_INSTRUCTIONS_DIRS does not match Copilot instruction directory.'
}

$cursorDb = Join-Path $env:APPDATA 'Cursor\User\globalStorage\state.vscdb'
$python = Get-Command python -ErrorAction SilentlyContinue
if ((Test-Path $cursorDb) -and $python) {
  $env:BW_CURSOR_DB = $cursorDb
  $env:BW_ROOT = $Root
  $cursorStatus = @'
import os
import sqlite3

conn = sqlite3.connect(os.environ["BW_CURSOR_DB"])
try:
    row = conn.execute(
        "select value from ItemTable where key=?",
        ("aicontext.personalContext",),
    ).fetchone()
finally:
    conn.close()

value = row[0] if row and row[0] is not None else ""
print("ok" if os.environ["BW_ROOT"] in value and "append_observation.ps1" in value else "missing")
'@ | & $python.Source -

  Remove-Item Env:\BW_CURSOR_DB -ErrorAction SilentlyContinue
  Remove-Item Env:\BW_ROOT -ErrorAction SilentlyContinue

  if ($cursorStatus.Trim() -ne 'ok') {
    $failures += 'Cursor personal context does not contain BrainWorks instructions.'
  }
}
else {
  $warnings += 'Cursor personal context could not be verified because Cursor DB or python is unavailable.'
}

$validator = Join-Path $Root 'validate_observations.ps1'
if (Test-Path $validator) {
  & $validator -Path $Root
  if ($LASTEXITCODE -ne 0) {
    $failures += 'Observation log validation failed.'
  }
}

$appendScript = Join-Path $Root 'append_observation.ps1'
if (Test-Path $appendScript) {
  $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brainworks-append-verify-" + [guid]::NewGuid().ToString("N"))
  try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $prettyPayload = @'
{
  "date": "2026-06-29",
  "agent": "codex",
  "session_type": "verification",
  "observations": [
    {
      "category": "personality",
      "trait": "append_script_compaction_probe",
      "detail": "Temporary verifier payload confirms pretty JSON is compacted before append.",
      "confidence": "Tentative"
    },
    {
      "category": "workflow",
      "trait": "jsonl_single_line_enforcement",
      "detail": "Temporary verifier payload confirms the appender preserves one JSON object per line.",
      "confidence": "Tentative"
    }
  ],
  "session_summary": "Temporary verifier payload only.",
  "rule_of_three_flags": [
    {
      "trait": "append_script_compaction_probe",
      "times_observed": 1,
      "promote": false
    }
  ]
}
'@
    $prettyPayload | powershell -NoProfile -ExecutionPolicy Bypass -File $appendScript -Path $tempRoot | Out-Null
    $tempLog = Join-Path $tempRoot 'observations.jsonl'
    $tempLines = @(Get-Content $tempLog)
    if ($tempLines.Count -ne 1) {
      $failures += 'append_observation.ps1 did not compact pretty JSON to one JSONL line.'
    }
    else {
      $null = $tempLines[0] | ConvertFrom-Json -ErrorAction Stop
    }

    $invalidPayload = @'
{
  "date": "2026-06-29",
  "agent": "codex",
  "session_type": "verification",
  "observations": [
    {
      "category": "workflow",
      "trait": "invalid_append_probe",
      "detail": "Temporary verifier payload intentionally omits personality evidence.",
      "confidence": "Tentative"
    }
  ],
  "session_summary": "Temporary invalid verifier payload only.",
  "rule_of_three_flags": []
}
'@
    $invalidPayload | powershell -NoProfile -ExecutionPolicy Bypass -File $appendScript -Path $tempRoot *> $null
    if ($LASTEXITCODE -eq 0) {
      $failures += 'append_observation.ps1 accepted an invalid payload without personality evidence.'
    }

    $tempLinesAfterInvalid = @(Get-Content $tempLog)
    if ($tempLinesAfterInvalid.Count -ne 1) {
      $failures += 'append_observation.ps1 modified the log after an invalid payload.'
    }
  }
  catch {
    $failures += "append_observation.ps1 compaction check failed: $($_.Exception.Message)"
  }
  finally {
    if (Test-Path $tempRoot) {
      Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
  }
}

if ($warnings.Count -gt 0) {
  Write-Output 'WARNINGS:'
  $warnings | ForEach-Object { Write-Output " - $_" }
}

if ($failures.Count -gt 0) {
  Write-Output 'FAILURES:'
  $failures | ForEach-Object { Write-Output " - $_" }
  exit 1
}

Write-Output 'BrainWorks static integration verification passed.'
Write-Output "OpenClaw workspace verified: $openclawWorkspace"
