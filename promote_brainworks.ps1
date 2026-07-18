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
    throw "Trait rules file not found: $RulesPath"
  }

  $parsed = Get-Content -Raw $RulesPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

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

# Layer -> BrainWorks.md section. Layers take precedence over category when present.
$layerSectionMap = @{
  identity = 'Identity'
  knowledge = 'Knowledge & Confidence Map'
  gap = 'Knowledge Gaps'
  mistake = 'Mistake Library'
  bias = 'Thinking Biases'
  belief = 'Belief Evolution'
  habit = 'Work Habits'
  mental_model = 'Mental Models'
}

# Quantitative layers updated by recency, not by date-count promotion.
$recencyLayers = New-Object System.Collections.Generic.HashSet[string]
foreach ($l in @('knowledge', 'gap', 'mistake', 'belief')) { [void]$recencyLayers.Add($l) }

# Latest metric per canonical trait (recency overwrite) for quantitative layers.
$metricState = @{}

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

    $obsLayer = if ($obs.PSObject.Properties.Name.Contains('layer')) { [string]$obs.layer } else { '' }
    $resolvedCategory = if ($obsLayer -and $layerSectionMap.ContainsKey($obsLayer)) {
      $obsLayer
    }
    elseif ($traitRules.canonicalCategoryMap.ContainsKey($canonicalTrait)) {
      [string]$traitRules.canonicalCategoryMap[$canonicalTrait]
    }
    else {
      [string]$obs.category
    }

    if (-not $traits.ContainsKey($canonicalTrait)) {
      $traits[$canonicalTrait] = [ordered]@{
        category = $resolvedCategory
        layer = $obsLayer
        dates = New-Object System.Collections.Generic.HashSet[string]
        details = New-Object System.Collections.Generic.List[string]
        originalTraits = New-Object System.Collections.Generic.HashSet[string]
        aliasTraits = New-Object System.Collections.Generic.HashSet[string]
        categories = New-Object System.Collections.Generic.HashSet[string]
        hasCanonicalCategory = $traitRules.canonicalCategoryMap.ContainsKey($canonicalTrait)
      }
    }
    else {
      # keep a layer if one was seen
      if ($obsLayer -and -not $traits[$canonicalTrait]['layer']) {
        $traits[$canonicalTrait]['layer'] = $obsLayer
        if ($layerSectionMap.ContainsKey($obsLayer)) { $traits[$canonicalTrait]['category'] = $obsLayer }
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

    # Recency metric capture for quantitative layers (overwrites by latest date).
    if ($obsLayer -and $recencyLayers.Contains($obsLayer) -and $obs.PSObject.Properties.Name.Contains('metric') -and $null -ne $obs.metric) {
      $isNewer = (-not $metricState.ContainsKey($canonicalTrait)) -or ($entryDate -gt $metricState[$canonicalTrait].date)
      if ($isNewer) {
        $metricState[$canonicalTrait] = [ordered]@{
          date = $entryDate
          layer = $obsLayer
          metric = $obs.metric
          detail = [string]$obs.detail
        }
      }
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
  $traitLayer = if ($trait['layer']) { [string]$trait['layer'] } else { '' }
  $target = if ($traitLayer -and $layerSectionMap.ContainsKey($traitLayer)) {
    $layerSectionMap[$traitLayer]
  }
  elseif ($sectionMap.ContainsKey($category)) {
    $sectionMap[$category]
  }
  else {
    'Behavioural Observations'
  }
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
    Write-Output (" Aliases observed: {0}" -f ($itemAliases -join ', '))
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
    Write-Output (" Existing: (not yet tracked)" -f '')
    Write-Output (" New evidence: (not yet tracked)" -f '')
    Write-Output (" Resolution: {0}" -f $item['resolution'])
      }
    }
    Write-Output ''
    Write-Output 'QUANTITATIVE METRIC STATE (recency, not promotion-gated):'

    if ($metricState.Count -eq 0) {
      Write-Output ' None yet. Quantitative layers (knowledge/gap/mistake/belief) accrue metric state as agents log them.'
    }
    else {
      foreach ($key in ($metricState.Keys | Sort-Object)) {
        $ms = $metricState[$key]
        $m = $ms.metric
        $metricJson = $m | ConvertTo-Json -Compress -Depth 5
        Write-Output (" Trait: {0} | layer: {1} | date: {2} | metric: {3}" -f $key, $ms.layer, $ms.date, $metricJson)
      }
    }
    Write-Output '---'
