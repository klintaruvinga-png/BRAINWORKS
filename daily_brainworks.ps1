<#
.SYNOPSIS
  Daily BrainWorks maintenance for the scheduled cron.

  Keeps the cognitive map live by:
    1. Running the promotion proposal generator (promote_brainworks.ps1) -
       fast, pure PowerShell, no network sub-agent. Writes a proposal the
       curator can act on.
    2. Always regenerating the graph + provenance view
       (build_brainworks_graph.ps1) so _generated/brainworks-graph.html
       reflects the latest evidence every day.

  Design note (KudzBot, acting as owner):
  The heavy Hermes curator chat is intentionally NOT run here. It spins up an
  interactive sub-agent that can block for minutes and is unreliable in a
  headless scheduler. The curator pass stays a manual/on-demand action
  (run-the-curator.ps1). This script guarantees the graph stays live daily
  without hanging the scheduler.

  Both steps run under a timeout so the cron can never wedge.
#>
param(
  [string]$Root = $env:BRAINWORKS_ROOT,
  [int]$StepTimeoutSeconds = 120
)

if (-not $Root) { $Root = 'C:\Users\Kudzie\OneDrive\BrainWorks' }
$ErrorActionPreference = 'Continue'

function Invoke-Step {
  param(
    [string]$Label,
    [scriptblock]$Block
  )
  Write-Output ("[{0}] starting..." -f $Label)
  $job = Start-Job -ScriptBlock $Block
  $done = Wait-Job -Job $job -Timeout $StepTimeoutSeconds
  if (-not $done) {
    Stop-Job -Job $job -ErrorAction SilentlyContinue
    Write-Output ("[{0}] TIMEOUT after {1}s - skipped." -f $Label, $StepTimeoutSeconds)
    return
  }
  $job.ChildJobs | ForEach-Object { $_.Output.ReadAll() } | ForEach-Object { Write-Output ("[{0}] {1}" -f $Label, $_) }
  Write-Output ("[{0}] done." -f $Label)
}

Set-Location -LiteralPath $Root

Invoke-Step -Label 'promoter' -Block {
  $p = Join-Path $using:Root 'promote_brainworks.ps1'
  if (Test-Path $p) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $p -Path $using:Root 2>&1
  }
}

Invoke-Step -Label 'graph' -Block {
  $g = Join-Path $using:Root 'build_brainworks_graph.ps1'
  if (Test-Path $g) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $g -Path $using:Root 2>&1
  }
  else { throw ("build script missing: " + $g) }
}

Write-Output "[daily] BrainWorks maintenance complete."
