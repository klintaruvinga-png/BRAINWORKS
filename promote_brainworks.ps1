param(
  [Parameter(Mandatory = $false)]
  [string]$Path = $env:BRAINWORKS_ROOT
)

if (-not $Path) {
  $Path = 'C:\Users\Kudzie\OneDrive\BrainWorks'
}

$logPath = Join-Path $Path 'observations.jsonl'
$validatePath = Join-Path $Path 'validate_observations.ps1'
$traitRulesPath = Join-Path $Path 'trait_rules.json'

if (-not (Test-Path $logPath)) {
  throw "Log file not found: $logPath"
}

if (-not (Test-Path $validatePath)) {
  throw "Validator not found: $validatePath"
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
    aliasMap = @{}
    canonicalCategoryMap = @{}
    ignoredExact = New-Object System.Collections.Generic.HashSet[string]
    ignoredPatterns = New-Object System.Collections.Generic.List[string]
  }

  if (-not (Test-Path $RulesPath)) {
    return $rules
  }

  $parsed = Get-Content -Raw $RulesPath | ConvertFrom-Json

  foreach ($item in $parsed.aliases) {
    if (-not $item.canonical_trait) {
      continue
    }

    $canonical = [string]$item.canonical_trait
    $rules.aliasMap[$canonical] = $canonical
    if ($item.canonical_category) {
      $rules.canonicalCategoryMap[$canonical] = [string]$item.canonical_category
    }

    foreach ($alias in (ConvertTo-StringArray $item.aliases)) {
      $rules.aliasMap[$alias] = $canonical
    }
  }

  foreach ($trait in (ConvertTo-StringArray $parsed.ignored_exact_traits)) {
    [void]$rules.ignoredExact.Add($trait)
  }

  foreach ($pattern in (ConvertTo-StringArray $parsed.ignored_patterns)) {
    [void]$rules.ignoredPatterns.Add($pattern)
  }

  return $rules
}

function Get-CanonicalTrait {
  param(
    [string]$Trait,
    [hashtable]$AliasMap
  )

  if ($AliasMap.ContainsKey($Trait)) {
    return [string]$AliasMap[$Trait]
  }

  return $Trait
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

function ConvertTo-SortedArray {
  param([object]$Value)

  if ($null -eq $Value) {
    return @()
  }

  return @($Value | Sort-Object)
}

& $validatePath -Path $Path | Out-Null
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
  throw 'Validation failed. Fix observations.jsonl before promotion.'
}

$traitRules = Get-TraitRules -RulesPath $traitRulesPath

$sectionMap = @{
  personality = 'Personality Model'
  workflow = 'Preferred Workflows'
  technical = 'Standards'
  communication = 'Communication Style'
  decision_making = 'Decision Making'
}

$traits = @{}
$conflicts = New-Object System.Collections.Generic.List[object]
$lineNumber = 0

Get-Content $logPath | ForEach-Object {
  $lineNumber++
  $entry = $_ | ConvertFrom-Json
  $entryDate = [string]$entry.date
  if ([string]::IsNullOrWhiteSpace($entryDate)) {
    return
  }

  foreach ($obs in $entry.observations) {
    $originalTrait = [string]$obs.trait

    if (Test-IgnoredTrait -Trait $originalTrait -Rules $traitRules) {
      continue
    }

    $canonicalTrait = Get-CanonicalTrait -Trait $originalTrait -AliasMap $traitRules.aliasMap

    if (Test-IgnoredTrait -Trait $canonicalTrait -Rules $traitRules) {
      continue
    }

    if (-not $traits.ContainsKey($canonicalTrait)) {
      $canonicalCategory = if ($traitRules.canonicalCategoryMap.ContainsKey($canonicalTrait)) {
        [string]$traitRules.canonicalCategoryMap[$canonicalTrait]
      }
      else {
        [string]$obs.category
      }

      $traits[$canonicalTrait] = [ordered]@{
        category = $canonicalCategory
        dates = New-Object System.Collections.Generic.HashSet[string]
        details = New-Object System.Collections.Generic.List[string]
        originalTraits = New-Object System.Collections.Generic.HashSet[string]
        aliasTraits = New-Object System.Collections.Generic.HashSet[string]
        categories = New-Object System.Collections.Generic.HashSet[string]
        hasCanonicalCategory = $traitRules.canonicalCategoryMap.ContainsKey($canonicalTrait)
      }
    }

    [void]$traits[$canonicalTrait]['dates'].Add($entryDate)
    [void]$traits[$canonicalTrait]['originalTraits'].Add($originalTrait)
    [void]$traits[$canonicalTrait]['categories'].Add([string]$obs.category)

    if ($originalTrait -ne $canonicalTrait) {
      [void]$traits[$canonicalTrait]['aliasTraits'].Add($originalTrait)
    }

    if ($obs.detail -and -not $traits[$canonicalTrait]['details'].Contains($obs.detail)) {
      [void]$traits[$canonicalTrait]['details'].Add($obs.detail)
    }
  }
}

$ready = @()
$building = @()

foreach ($traitName in ($traits.Keys | Sort-Object)) {
  $trait = $traits[$traitName]
  $dateList = ConvertTo-SortedArray $trait['dates']
  $count = $trait['dates'].Count
  $category = [string]$trait['category']
  $target = if ($sectionMap.ContainsKey($category)) { $sectionMap[$category] } else { 'Behavioural Observations' }
  $proposedText = if ($trait['details'].Count -gt 0) { $trait['details'][$trait['details'].Count - 1] } else { $traitName }
  $originalList = ConvertTo-SortedArray $trait['originalTraits']
  $aliasList = ConvertTo-SortedArray $trait['aliasTraits']
  $categoryList = ConvertTo-SortedArray $trait['categories']

  if (-not $trait['hasCanonicalCategory'] -and $categoryList.Count -gt 1) {
    $conflicts.Add([ordered]@{
      trait = $traitName
      categories = $categoryList
      resolution = 'Add canonical_category in trait_rules.json before promotion.'
    }) | Out-Null
    continue
  }

  if ($count -ge 3) {
    $ready += [ordered]@{
      trait = $traitName
      category = $category
      dates = $dateList
      target = $target
      proposed = $proposedText
      confidence = 'Strong'
      original_traits = $originalList
      aliases = $aliasList
    }
  }
  else {
    $building += [ordered]@{
      trait = $traitName
      count = $count
      original_traits = $originalList
      aliases = $aliasList
    }
  }
}

Write-Output '---'
Write-Output ("BRAINWORKS PROMOTION PROPOSAL - {0}" -f (Get-Date -Format 'yyyy-MM-dd'))
Write-Output ''
Write-Output 'READY TO PROMOTE (3+ distinct dates):'

if ($ready.Count -eq 0) {
  Write-Output ' None'
}
else {
  foreach ($item in $ready) {
    $itemAliases = @($item['aliases'])
    Write-Output (" Trait: {0}" -f $item['trait'])
    if ($itemAliases.Count -gt 0) {
      Write-Output (" Aliases observed: {0}" -f ($itemAliases -join ', '))
    }
    Write-Output (" Original traits: {0}" -f (@($item['original_traits']) -join ', '))
    Write-Output (" Category: {0}" -f $item['category'])
    Write-Output (" Observed dates: {0}" -f (@($item['dates']) -join ', '))
    Write-Output (" Proposed text: {0}" -f $item['proposed'])
    Write-Output (" Target section: {0}" -f $item['target'])
    Write-Output (" Confidence: {0}" -f $item['confidence'])
    Write-Output ''
  }
}

Write-Output 'STILL BUILDING (1-2 distinct dates):'

if ($building.Count -eq 0) {
  Write-Output ' None'
}
else {
  foreach ($item in $building) {
    $itemAliases = @($item['aliases'])
    $suffix = ''
    if ($itemAliases.Count -gt 0) {
      $suffix = " (aliases: {0})" -f ($itemAliases -join ', ')
    }
    Write-Output (" Trait: {0} - {1} dates so far{2}" -f $item['trait'], $item['count'], $suffix)
  }
}

Write-Output ''
Write-Output 'CONFLICTS:'
if ($conflicts.Count -eq 0) {
  Write-Output ' None detected automatically. Curator review required.'
}
else {
  foreach ($item in $conflicts) {
    Write-Output (" Trait: {0}" -f $item['trait'])
    Write-Output (" Categories: {0}" -f (@($item['categories']) -join ', '))
    Write-Output (" Resolution: {0}" -f $item['resolution'])
  }
}
Write-Output ''
Write-Output 'OWNER SECTIONS:'
Write-Output ' None proposed automatically. Curator review required.'
Write-Output '---'
