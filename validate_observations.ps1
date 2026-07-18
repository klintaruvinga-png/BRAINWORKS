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
$traitRulesPath = Join-Path $Path 'trait_rules.json'

if (-not (Test-Path $logPath)) {
  throw "Log file not found: $logPath"
}

function ConvertTo-StringArray {
  param([object]$Value)

  $result = New-Object System.Collections.Generic.List[string]
  if ($null -eq $Value) {
    return $result.ToArray()
  }

  if ($Value -is [System.Array]) {
    foreach ($item in $Value) {
      if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
        [void]$result.Add([string]$item)
      }
    }
  }
  elseif (-not [string]::IsNullOrWhiteSpace([string]$Value)) {
    [void]$result.Add([string]$Value)
  }

  return $result.ToArray()
}

function Get-TraitRules {
  param([string]$RulesPath)

  $rules = [ordered]@{
    ignoredExact = New-Object System.Collections.Generic.HashSet[string]
    ignoredPatterns = New-Object System.Collections.Generic.List[string]
  }

  if (-not (Test-Path $RulesPath)) {
    throw "Trait rules file not found: $RulesPath"
  }

  $parsed = Get-Content -Raw $RulesPath | ConvertFrom-Json

  foreach ($trait in (ConvertTo-StringArray $parsed.ignored_exact_traits)) {
    [void]$rules.ignoredExact.Add($trait)
  }

  foreach ($pattern in (ConvertTo-StringArray $parsed.ignored_patterns)) {
    [void]$rules.ignoredPatterns.Add($pattern)
  }

  return $rules
}

function Test-IgnoredTrait {
  param(
    [string]$Trait,
    [object]$Rules
  )

  if ([string]::IsNullOrWhiteSpace($Trait)) {
    return $false
  }

  if ($Rules.ignoredExact.Contains($Trait)) {
    return $true
  }

  foreach ($pattern in $Rules.ignoredPatterns) {
    if ($Trait -match $pattern) {
      return $true
    }
  }

  return $false
}

function Test-SnakeCaseTrait {
  param([string]$Trait)

  return ($Trait -cmatch '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$')
}

$traitRules = Get-TraitRules -RulesPath $traitRulesPath

$requiredTopLevel = @('date', 'agent', 'session_type', 'observations', 'session_summary', 'rule_of_three_flags')
$requiredObservation = @('category', 'trait', 'detail', 'confidence')
$requiredRuleFlag = @('trait', 'times_observed', 'promote')
$allowedCategories = @('personality', 'workflow', 'technical', 'communication', 'decision_making')
$allowedConfidence = @('Tentative', 'Moderate', 'Strong', 'Confirmed')
$allowedLayers = @('identity', 'knowledge', 'gap', 'mistake', 'bias', 'belief', 'habit', 'mental_model', 'personality', 'workflow', 'technical', 'communication', 'decision_making')
$metricAllowedLayers = @('knowledge', 'gap', 'mistake', 'belief')
$allowedSeverity = @('Low', 'Medium', 'High')
$severityObservationLayers = @('gap', 'mistake')

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

  $observationTraits = New-Object System.Collections.Generic.HashSet[string]

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

      if ($obs.PSObject.Properties.Name.Contains('trait') -and -not [string]::IsNullOrWhiteSpace([string]$obs.trait)) {
        $obsTrait = [string]$obs.trait
        [void]$observationTraits.Add($obsTrait)

        if (-not (Test-SnakeCaseTrait -Trait $obsTrait)) {
          $lineWarnings += "Line ${lineNumber}: observation trait '$obsTrait' is not snake_case."
        }

        if (Test-IgnoredTrait -Trait $obsTrait -Rules $traitRules) {
          $lineWarnings += "Line ${lineNumber}: observation trait '$obsTrait' is self-telemetry and ignored by promotion."
        }
      }

      if ($obs.category -and $allowedCategories -notcontains $obs.category) {
        $lineIssues += "Line ${lineNumber}: invalid category '$($obs.category)'."
      }

      if ($obs.confidence -and $allowedConfidence -notcontains $obs.confidence) {
        $lineIssues += "Line ${lineNumber}: invalid confidence '$($obs.confidence)'."
      }

      $obsLayer = if ($obs.PSObject.Properties.Name.Contains('layer')) { [string]$obs.layer } else { '' }
      if ($obsLayer -and $allowedLayers -notcontains $obsLayer) {
        $lineWarnings += "Line ${lineNumber}: observation layer '$obsLayer' is not a recognized layer key."
      }

      $hasMetric = $obs.PSObject.Properties.Name.Contains('metric') -and $null -ne $obs.metric
      if ($hasMetric -and $metricAllowedLayers -notcontains $obsLayer) {
        $lineWarnings += "Line ${lineNumber}: metric is only allowed on layers: $($metricAllowedLayers -join ', ')."
      }

      if ($hasMetric -and $metricAllowedLayers -contains $obsLayer) {
        $m = $obs.metric
        if ($obsLayer -eq 'knowledge') {
          foreach ($k in @('knowledge', 'confidence')) {
            if (-not $m.PSObject.Properties.Name.Contains($k) -or ($m.$k -isnot [int] -and $m.$k -isnot [long]) -or $m.$k -lt 0 -or $m.$k -gt 100) {
              $lineWarnings += "Line ${lineNumber}: knowledge metric '$k' must be an integer 0-100."
            }
          }
        }
        if ($severityObservationLayers -contains $obsLayer) {
          $countField = if ($obsLayer -eq 'gap') { 'seen' } else { 'occurred' }
          if (-not $m.PSObject.Properties.Name.Contains($countField) -or ($m.$countField -isnot [int] -and $m.$countField -isnot [long]) -or $m.$countField -lt 1) {
            $lineWarnings += "Line ${lineNumber}: $obsLayer metric '$countField' must be a positive integer."
          }
          $sevField = if ($obsLayer -eq 'gap') { 'importance' } else { 'likelihood' }
          if (-not $m.PSObject.Properties.Name.Contains($sevField) -or $allowedSeverity -notcontains [string]$m.$sevField) {
            $lineWarnings += "Line ${lineNumber}: $obsLayer metric '$sevField' must be one of: $($allowedSeverity -join ', ')."
          }
        }
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

      if ($flag.PSObject.Properties.Name.Contains('trait') -and -not [string]::IsNullOrWhiteSpace([string]$flag.trait)) {
        $flagTrait = [string]$flag.trait

        if (-not (Test-SnakeCaseTrait -Trait $flagTrait)) {
          $lineWarnings += "Line ${lineNumber}: rule_of_three_flags trait '$flagTrait' is not snake_case."
        }

        if (-not $observationTraits.Contains($flagTrait)) {
          $lineWarnings += "Line ${lineNumber}: rule_of_three_flags trait '$flagTrait' is not present in same-entry observations."
        }

        if (Test-IgnoredTrait -Trait $flagTrait -Rules $traitRules) {
          $lineWarnings += "Line ${lineNumber}: rule_of_three_flags trait '$flagTrait' is self-telemetry and ignored by promotion."
        }
      }

      if ($flag.PSObject.Properties.Name.Contains('times_observed') -and (($flag.times_observed -isnot [int] -and $flag.times_observed -isnot [long]) -or $flag.times_observed -lt 1)) {
        $lineIssues += "Line ${lineNumber}: rule_of_three_flags times_observed must be a positive integer."
      }
      elseif ($flag.PSObject.Properties.Name.Contains('times_observed') -and $flag.times_observed -gt 1) {
        $lineWarnings += "Line ${lineNumber}: rule_of_three_flags times_observed should be 1 for local session notices."
      }

      if ($flag.PSObject.Properties.Name.Contains('promote') -and $flag.promote -isnot [bool]) {
        $lineIssues += "Line ${lineNumber}: rule_of_three_flags promote must be boolean."
      }
      elseif ($flag.PSObject.Properties.Name.Contains('promote') -and $flag.promote -eq $true) {
        $lineWarnings += "Line ${lineNumber}: rule_of_three_flags promote should be false; promotion is derived by promote_brainworks.ps1."
      }
    }
  }

  $hasPersonality = $false
  $hasTechnicalOrWorkflow = $false
  $hasCognitiveExtension = $false

  foreach ($obs in $entry.observations) {
    if ($obs.category -eq 'personality') {
      $hasPersonality = $true
    }

    if ($obs.category -in @('workflow', 'technical', 'communication', 'decision_making')) {
      $hasTechnicalOrWorkflow = $true
    }

    if ($obs.PSObject.Properties.Name.Contains('layer')) {
      $ol = [string]$obs.layer
      if ($ol -in @('knowledge', 'gap', 'mistake', 'bias', 'belief', 'habit', 'mental_model', 'identity')) {
        $hasCognitiveExtension = $true
      }
    }
  }

  if (-not $hasPersonality) {
    $lineWarnings += "Line ${lineNumber}: missing personality observation."
  }

  if (-not $hasTechnicalOrWorkflow) {
    $lineWarnings += "Line ${lineNumber}: missing technical or workflow observation."
  }

  if (-not $hasCognitiveExtension) {
    $lineWarnings += "Line ${lineNumber}: no cognitive-extension layer (knowledge/gap/mistake/bias/belief/habit/mental_model/identity). Add one when observed."
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
