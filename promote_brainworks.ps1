param(
  [Parameter(Mandatory = $false)]
  [string]$Path = $env:BRAINWORKS_ROOT
)

if (-not $Path) {
  $Path = 'C:\Users\Kudzie\OneDrive\BrainWorks'
}

$logPath = Join-Path $Path 'observations.jsonl'
$validatePath = Join-Path $Path 'validate_observations.ps1'

if (-not (Test-Path $logPath)) {
  throw "Log file not found: $logPath"
}

if (Test-Path $validatePath) {
  & $validatePath -Path $Path | Out-Null
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    throw 'Validation failed. Fix observations.jsonl before promotion.'
  }
}

$ignoredTraits = @(
  'system_architecture',
  'canonical_jsonl_appending',
  'autonomous_observation_logging'
)

$sectionMap = @{
  personality = 'Personality Model'
  workflow = 'Preferred Workflows'
  technical = 'Standards'
  communication = 'Communication Style'
  decision_making = 'Decision Making'
}

$traits = @{}

Get-Content $logPath | ForEach-Object {
  $entry = $_ | ConvertFrom-Json

  foreach ($obs in $entry.observations) {
    if ($ignoredTraits -contains $obs.trait) {
      continue
    }

    if (-not $traits.ContainsKey($obs.trait)) {
      $traits[$obs.trait] = [ordered]@{
        category = $obs.category
        dates = New-Object System.Collections.Generic.HashSet[string]
        details = New-Object System.Collections.Generic.List[string]
      }
    }

    [void]$traits[$obs.trait].dates.Add($entry.date)
    if ($obs.detail -and -not $traits[$obs.trait].details.Contains($obs.detail)) {
      [void]$traits[$obs.trait].details.Add($obs.detail)
    }
  }
}

$ready = @()
$building = @()

foreach ($traitName in ($traits.Keys | Sort-Object)) {
  $trait = $traits[$traitName]
  $dateList = $trait.dates.ToArray() | Sort-Object
  $count = $dateList.Count
  $target = if ($sectionMap.ContainsKey($trait.category)) { $sectionMap[$trait.category] } else { 'Behavioural Observations' }
  $proposedText = if ($trait.details.Count -gt 0) { $trait.details[$trait.details.Count - 1] } else { $traitName }

  if ($count -ge 3) {
    $ready += [ordered]@{
      trait = $traitName
      category = $trait.category
      dates = $dateList
      target = $target
      proposed = $proposedText
      confidence = 'Strong'
    }
  }
  else {
    $building += [ordered]@{
      trait = $traitName
      count = $count
    }
  }
}

Write-Output '---'
Write-Output ("BRAINWORKS PROMOTION PROPOSAL - {0}" -f (Get-Date -Format 'yyyy-MM-dd'))
Write-Output ''
Write-Output 'READY TO PROMOTE (3+ distinct sessions):'

if ($ready.Count -eq 0) {
  Write-Output ' None'
}
else {
  foreach ($item in $ready) {
    Write-Output (" Trait: {0}" -f $item.trait)
    Write-Output (" Category: {0}" -f $item.category)
    Write-Output (" Observed: {0}" -f ($item.dates -join ', '))
    Write-Output (" Proposed text: {0}" -f $item.proposed)
    Write-Output (" Target section: {0}" -f $item.target)
    Write-Output (" Confidence: {0}" -f $item.confidence)
    Write-Output ''
  }
}

Write-Output 'STILL BUILDING (1-2 sessions):'

if ($building.Count -eq 0) {
  Write-Output ' None'
}
else {
  foreach ($item in $building) {
    Write-Output (" Trait: {0} - {1} sessions so far" -f $item.trait, $item.count)
  }
}

Write-Output ''
Write-Output 'CONFLICTS:'
Write-Output ' None detected automatically. Curator review required.'
Write-Output ''
Write-Output 'OWNER SECTIONS:'
Write-Output ' None proposed automatically. Curator review required.'
Write-Output '---'
