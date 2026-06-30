param(
  [Parameter(Mandatory = $false)]
  [string]$Path = $env:BRAINWORKS_ROOT,

  [Parameter(Mandatory = $false)]
  [switch]$StrictEvidenceBlocks
)

if (-not $Path) {
  $Path = 'C:\Users\Kudzie\OneDrive\BrainWorks'
}

$logPath = Join-Path $Path 'observations.jsonl'

if (-not (Test-Path $logPath)) {
  throw "Log file not found: $logPath"
}

$requiredTopLevel = @('date', 'agent', 'session_type', 'observations', 'session_summary', 'rule_of_three_flags')
$requiredObservation = @('category', 'trait', 'detail', 'confidence')
$requiredRuleFlag = @('trait', 'times_observed', 'promote')
$allowedCategories = @('personality', 'workflow', 'technical', 'communication', 'decision_making')
$allowedConfidence = @('Tentative', 'Moderate', 'Strong', 'Confirmed')

$lineNumber = 0
$issues = @()
$warnings = @()
$validCount = 0

Get-Content $logPath | ForEach-Object {
  $lineNumber++
  $line = $_
  $lineIssues = @()
  $lineWarnings = @()

  if ([string]::IsNullOrWhiteSpace($line)) {
    $lineIssues += "Line ${lineNumber}: blank line."
    $issues += $lineIssues
    return
  }

  try {
    $entry = $line | ConvertFrom-Json -ErrorAction Stop
  }
  catch {
    $hint = if ($line -match '}\s*{') { ' Possible concatenated JSON objects.' } else { '' }
    $lineIssues += "Line ${lineNumber}: invalid JSON.$hint"
    $issues += $lineIssues
    return
  }

  if ($entry -is [System.Array]) {
    $lineIssues += "Line ${lineNumber}: top-level JSON must be one object, not an array."
  }

  foreach ($field in $requiredTopLevel) {
    if (-not $entry.PSObject.Properties.Name.Contains($field)) {
      $lineIssues += "Line ${lineNumber}: missing top-level field '$field'."
    }
  }

  if ($entry.date -and $entry.date -notmatch '^\d{4}-\d{2}-\d{2}$') {
    $lineIssues += "Line ${lineNumber}: date must use YYYY-MM-DD format."
  }

  foreach ($field in @('agent', 'session_type', 'session_summary')) {
    if ($entry.PSObject.Properties.Name.Contains($field) -and [string]::IsNullOrWhiteSpace([string]$entry.$field)) {
      $lineIssues += "Line ${lineNumber}: '$field' must not be empty."
    }
  }

  if ($entry.observations -isnot [System.Array] -or $entry.observations.Count -lt 1) {
    $lineIssues += "Line ${lineNumber}: 'observations' must be a non-empty array."
  }
  else {
    foreach ($obs in $entry.observations) {
      foreach ($field in $requiredObservation) {
        if (-not $obs.PSObject.Properties.Name.Contains($field)) {
          $lineIssues += "Line ${lineNumber}: observation missing field '$field'."
        }
        elseif ([string]::IsNullOrWhiteSpace([string]$obs.$field)) {
          $lineIssues += "Line ${lineNumber}: observation field '$field' must not be empty."
        }
      }

      if ($obs.category -and $allowedCategories -notcontains $obs.category) {
        $lineIssues += "Line ${lineNumber}: invalid category '$($obs.category)'."
      }

      if ($obs.confidence -and $allowedConfidence -notcontains $obs.confidence) {
        $lineIssues += "Line ${lineNumber}: invalid confidence '$($obs.confidence)'."
      }
    }
  }

  if ($entry.rule_of_three_flags -isnot [System.Array]) {
    $lineIssues += "Line ${lineNumber}: 'rule_of_three_flags' must be an array."
  }
  else {
    foreach ($flag in $entry.rule_of_three_flags) {
      foreach ($field in $requiredRuleFlag) {
        if (-not $flag.PSObject.Properties.Name.Contains($field)) {
          $lineIssues += "Line ${lineNumber}: rule_of_three_flags entry missing field '$field'."
        }
      }

      if ($flag.PSObject.Properties.Name.Contains('trait') -and [string]::IsNullOrWhiteSpace([string]$flag.trait)) {
        $lineIssues += "Line ${lineNumber}: rule_of_three_flags trait must not be empty."
      }

      if ($flag.PSObject.Properties.Name.Contains('times_observed') -and ($flag.times_observed -isnot [int] -or $flag.times_observed -lt 1)) {
        $lineIssues += "Line ${lineNumber}: rule_of_three_flags times_observed must be a positive integer."
      }

      if ($flag.PSObject.Properties.Name.Contains('promote') -and $flag.promote -isnot [bool]) {
        $lineIssues += "Line ${lineNumber}: rule_of_three_flags promote must be boolean."
      }
    }
  }

  $hasPersonality = $false
  $hasTechnicalOrWorkflow = $false

  foreach ($obs in $entry.observations) {
    if ($obs.category -eq 'personality') {
      $hasPersonality = $true
    }

    if ($obs.category -in @('workflow', 'technical', 'communication', 'decision_making')) {
      $hasTechnicalOrWorkflow = $true
    }
  }

  if (-not $hasPersonality) {
    $lineWarnings += "Line ${lineNumber}: missing personality observation."
  }

  if (-not $hasTechnicalOrWorkflow) {
    $lineWarnings += "Line ${lineNumber}: missing technical or workflow observation."
  }

  if ($StrictEvidenceBlocks) {
    $lineIssues += $lineWarnings
  }
  else {
    $warnings += $lineWarnings
  }

  $issues += $lineIssues

  if ($lineIssues.Count -eq 0) {
    $validCount++
  }
}

if ($issues.Count -gt 0) {
  $issues | ForEach-Object { Write-Output $_ }
  Write-Output "Validation failed. Valid lines: $validCount"
  exit 1
}

if ($warnings.Count -gt 0) {
  $warnings | ForEach-Object { Write-Output "Warning: $_" }
}

Write-Output "Validation passed. Lines checked: $validCount"
