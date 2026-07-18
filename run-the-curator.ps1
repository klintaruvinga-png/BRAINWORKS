param(
  [string]$Prompt = "Run a BrainWorks curator status check. Read BrainWorks.md and opencode_claw_instruction.md, validate observations.jsonl, run the promotion proposal generator, and report the real stdout. Do not edit BrainWorks.md unless a promotion is clearly ready and coherent."
)

$ErrorActionPreference = 'Stop'
$BrainWorks = 'C:\Users\Kudzie\OneDrive\BrainWorks'
Set-Location -LiteralPath $BrainWorks

# Run the Hermes curator chat under a hard timeout so a stalled sub-agent can
# never wedge a scheduled cron. 10 minutes is generous for a curator pass.
$CuratorTimeoutSec = 600
$cJob = Start-Job -ScriptBlock { param($p) & hermes -p curator chat -q $p 2>&1 } -ArgumentList $Prompt
$cWait = Wait-Job -Job $cJob -Timeout $CuratorTimeoutSec
if (-not $cWait) {
  Stop-Job -Job $cJob -ErrorAction SilentlyContinue
  Write-Output ("[curator] TIMEOUT after {0}s - chat did not finish. Continuing to graph rebuild." -f $CuratorTimeoutSec)
}
else {
  $cJob.ChildJobs | ForEach-Object { $_.Output.ReadAll() } | ForEach-Object { Write-Output $_ }
  Write-Output "[curator] chat completed."
}

# Regenerate the Obsidian-style graph + provenance view after the curator pass
# so the visual always reflects current evidence. Read-only against the model/log.
$buildScript = Join-Path $BrainWorks 'build_brainworks_graph.ps1'
if (Test-Path $buildScript) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript -Path $BrainWorks 2>&1 | ForEach-Object { Write-Output $_ }
}
