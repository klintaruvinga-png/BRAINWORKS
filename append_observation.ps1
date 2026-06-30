param(
  [Parameter(Mandatory = $false)]
  [string]$Json,

  [Parameter(Mandatory = $false)]
  [string]$Path = $env:BRAINWORKS_ROOT
)

if (-not $Path) {
  $Path = 'C:\Users\Kudzie\OneDrive\BrainWorks'
}

$logPath = Join-Path $Path 'observations.jsonl'
$traitRulesPath = Join-Path $Path 'trait_rules.json'

if (-not (Test-Path $Path)) {
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
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
    return $rules
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

if ($Json) {
  $payload = $Json.Trim()
}
else {
  $payload = [Console]::In.ReadToEnd().Trim()
}

if ([string]::IsNullOrWhiteSpace($payload)) {
  throw 'No JSON payload supplied.'
}

try {
  $parsed = $payload | ConvertFrom-Json -ErrorAction Stop
}
catch {
  throw "Invalid JSON payload: $($_.Exception.Message)"
}

if ($parsed -is [System.Array]) {
  throw 'Invalid observation payload: top-level JSON must be one object, not an array.'
}

$traitRules = Get-TraitRules -RulesPath $traitRulesPath

$requiredTopLevel = @('date', 'agent', 'session_type', 'observations', 'session_summary', 'rule_of_three_flags')
$requiredObservation = @('category', 'trait', 'detail', 'confidence')
$allowedCategories = @('personality', 'workflow', 'technical', 'communication', 'decision_making')
$allowedConfidence = @('Tentative', 'Moderate', 'Strong', 'Confirmed')

foreach ($field in $requiredTopLevel) {
  if (-not $parsed.PSObject.Properties.Name.Contains($field)) {
    throw "Invalid observation payload: missing top-level field '$field'."
  }
}

if ($parsed.date -notmatch '^\d{4}-\d{2}-\d{2}$') {
  throw "Invalid observation payload: date must use YYYY-MM-DD format."
}

foreach ($field in @('agent', 'session_type', 'session_summary')) {
  if ([string]::IsNullOrWhiteSpace([string]$parsed.$field)) {
    throw "Invalid observation payload: '$field' must not be empty."
  }
}

if ($parsed.observations -isnot [System.Array] -or $parsed.observations.Count -lt 1) {
  throw "Invalid observation payload: 'observations' must be a non-empty array."
}

$hasPersonality = $false
$hasTechnicalOrWorkflow = $false
$observationTraits = New-Object System.Collections.Generic.HashSet[string]

foreach ($observation in $parsed.observations) {
  foreach ($field in $requiredObservation) {
    if (-not $observation.PSObject.Properties.Name.Contains($field)) {
      throw "Invalid observation payload: observation missing field '$field'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$observation.$field)) {
      throw "Invalid observation payload: observation field '$field' must not be empty."
    }
  }

  $observationTrait = [string]$observation.trait
  [void]$observationTraits.Add($observationTrait)

  if (-not (Test-SnakeCaseTrait -Trait $observationTrait)) {
    throw "Invalid observation payload: observation trait '$observationTrait' must be snake_case."
  }

  if (Test-IgnoredTrait -Trait $observationTrait -Rules $traitRules) {
    throw "Invalid observation payload: observation trait '$observationTrait' is self-telemetry and must not be appended as user evidence."
  }

  if ($allowedCategories -notcontains $observation.category) {
    throw "Invalid observation payload: invalid category '$($observation.category)'."
  }

  if ($allowedConfidence -notcontains $observation.confidence) {
    throw "Invalid observation payload: invalid confidence '$($observation.confidence)'."
  }

  if ($observation.category -eq 'personality') {
    $hasPersonality = $true
  }

  if ($observation.category -in @('workflow', 'technical', 'communication', 'decision_making')) {
    $hasTechnicalOrWorkflow = $true
  }
}

if (-not $hasPersonality) {
  throw "Invalid observation payload: at least one personality observation is required."
}

if (-not $hasTechnicalOrWorkflow) {
  throw "Invalid observation payload: at least one technical or workflow observation is required."
}

if ($parsed.rule_of_three_flags -isnot [System.Array]) {
  throw "Invalid observation payload: 'rule_of_three_flags' must be an array."
}

foreach ($flag in $parsed.rule_of_three_flags) {
  foreach ($field in @('trait', 'times_observed', 'promote')) {
    if (-not $flag.PSObject.Properties.Name.Contains($field)) {
      throw "Invalid observation payload: rule_of_three_flags entry missing field '$field'."
    }
  }

  $flagTrait = [string]$flag.trait

  if ([string]::IsNullOrWhiteSpace($flagTrait)) {
    throw "Invalid observation payload: rule_of_three_flags trait must not be empty."
  }

  if (-not (Test-SnakeCaseTrait -Trait $flagTrait)) {
    throw "Invalid observation payload: rule_of_three_flags trait '$flagTrait' must be snake_case."
  }

  if (-not $observationTraits.Contains($flagTrait)) {
    throw "Invalid observation payload: rule_of_three_flags trait '$flagTrait' must also appear in this entry's observations."
  }

  if (Test-IgnoredTrait -Trait $flagTrait -Rules $traitRules) {
    throw "Invalid observation payload: rule_of_three_flags trait '$flagTrait' is self-telemetry and must not be appended as user evidence."
  }

  if (($flag.times_observed -isnot [int] -and $flag.times_observed -isnot [long]) -or $flag.times_observed -ne 1) {
    throw "Invalid observation payload: rule_of_three_flags times_observed must be 1 for local session notices."
  }

  if ($flag.promote -isnot [bool]) {
    throw "Invalid observation payload: rule_of_three_flags promote must be boolean."
  }

  if ($flag.promote -ne $false) {
    throw "Invalid observation payload: rule_of_three_flags promote must be false; promotion is derived by promote_brainworks.ps1."
  }
}

$compactPayload = $parsed | ConvertTo-Json -Depth 100 -Compress

$resolvedLogPath = [System.IO.Path]::GetFullPath($logPath).ToLowerInvariant()
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
  $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($resolvedLogPath))
}
finally {
  $sha.Dispose()
}

$hash = [BitConverter]::ToString($hashBytes).Replace('-', '')
$mutex = [System.Threading.Mutex]::new($false, "Local\BrainWorksObservations-$hash")
$lockTaken = $false

try {
  $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
  if (-not $lockTaken) {
    throw "Timed out waiting for observation log append lock: $logPath"
  }

  Add-Content -Path $logPath -Value $compactPayload
}
finally {
  if ($lockTaken) {
    $mutex.ReleaseMutex()
  }

  $mutex.Dispose()
}

Write-Output "Appended observation to $logPath"
