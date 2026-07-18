<#
.SYNOPSIS
  Build an Obsidian-style interactive graph + provenance index for BrainWorks.

  Reads the existing BrainWorks artifacts and emits:
    _generated/brainworks-graph.html  - force-directed network (traits + curated sections + evidence links)
    _generated/brainworks-index.json  - machine-readable graph + provenance data
    _generated/brainworks-report.md   - plain-text summary for the curator

  This script is READ-ONLY against BrainWorks.md and observations.jsonl.
  It does not modify the curated model or the evidence log.

  Design notes (KudzBot, acting as owner):
  - The Obsidian "link" equivalent here is trait -> evidence lines and trait -> curated section.
  - Provenance = each promoted/ready trait carries the distinct dates and source line numbers
    that earned it. This is the backlink-to-source that BrainWorks was missing.
 - No changes to the existing validator/appender/promoter contract. This is a pure view layer.
 #>
param(
  [Parameter(Mandatory = $false)]
  [string]$Path = $env:BRAINWORKS_ROOT,

  [Parameter(Mandatory = $false)]
  [switch]$Open
)

if (-not $Path) {
  $Path = 'C:\Users\Kudzie\OneDrive\BrainWorks'
}

$logPath       = Join-Path $Path 'observations.jsonl'
$traitRulesPath = Join-Path $Path 'trait_rules.json'
$modelPath     = Join-Path $Path 'BrainWorks.md'
$genDir        = Join-Path $Path '_generated'

if (-not (Test-Path $logPath)) { throw "Log file not found: $logPath" }
if (-not (Test-Path $traitRulesPath)) { throw "Trait rules not found: $traitRulesPath" }

if (-not (Test-Path $genDir)) {
  New-Item -ItemType Directory -Force -Path $genDir | Out-Null
}

# --- Load trait alias rules (reuse the same normalization BrainWorks already uses) ---
$rules = Get-Content -Raw $traitRulesPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$aliasMap = @{}
foreach ($item in $rules.aliases) {
  if (-not $item.canonical_trait) { continue }
  $aliasMap[$item.canonical_trait] = $item.canonical_trait
  foreach ($a in $item.aliases) { $aliasMap[$a] = $item.canonical_trait }
}
$ignoredExact = New-Object System.Collections.Generic.HashSet[string]
foreach ($t in $rules.ignored_exact_traits) { [void]$ignoredExact.Add($t) }
$ignoredPatterns = @($rules.ignored_patterns)

function Test-Ignored {
  param([string]$Trait)
  if ([string]::IsNullOrWhiteSpace($Trait)) { return $true }
  if ($ignoredExact.Contains($Trait)) { return $true }
  foreach ($p in $ignoredPatterns) { if ($Trait -match $p) { return $true } }
  return $false
}

function Get-Canonical {
  param([string]$Trait)
  if ($aliasMap.ContainsKey($Trait)) { return $aliasMap[$Trait] }
  return $Trait
}

# --- Parse evidence log into nodes + edges ---
# nodes: traits (with categories, dates, source line numbers)
# edges: trait -> evidence line (provenance), trait -> canonical alias
$traits = @{}
$lineNumber = 0

Get-Content $logPath | ForEach-Object {
  $lineNumber++
  $line = $_
  if ([string]::IsNullOrWhiteSpace($line)) { return }

  try { $entry = $line | ConvertFrom-Json -ErrorAction Stop }
  catch { return }

  $entryDate = [string]$entry.date
  if ([string]::IsNullOrWhiteSpace($entryDate)) { return }

  foreach ($obs in $entry.observations) {
    $orig = [string]$obs.trait
    if (Test-Ignored $orig) { continue }
    $canon = Get-Canonical $orig
    if (Test-Ignored $canon) { continue }

    $obsLayer = if ($obs.PSObject.Properties.Name.Contains('layer')) { [string]$obs.layer } else { '' }

    if (-not $traits.ContainsKey($canon)) {
      $traits[$canon] = [ordered]@{
        trait       = $canon
        category    = [string]$obs.category
        layer       = $obsLayer
        dates       = New-Object System.Collections.Generic.HashSet[string]
        sources     = New-Object System.Collections.Generic.List[int]
        details     = New-Object System.Collections.Generic.List[string]
        aliases     = New-Object System.Collections.Generic.HashSet[string]
      }
    }
    else {
      if ($obsLayer -and -not $traits[$canon]['layer']) { $traits[$canon]['layer'] = $obsLayer }
    }
    $t = $traits[$canon]
    [void]$t.dates.Add($entryDate)
    if (-not $t.sources.Contains($lineNumber)) { [void]$t.sources.Add($lineNumber) }
    if ($orig -ne $canon) { [void]$t.aliases.Add($orig) }
    $d = [string]$obs.detail
    if ($d -and -not $t.details.Contains($d)) { [void]$t.details.Add($d) }
  }
}

# --- Read curated model sections (provenance target for promoted traits) ---
$sectionNames = New-Object System.Collections.Generic.List[string]
if (Test-Path $modelPath) {
  $modelLines = Get-Content $modelPath
  foreach ($ml in $modelLines) {
    if ($ml -match '^##\s+(.+?)\s*$') {
      [void]$sectionNames.Add($matches[1].Trim())
    }
  }
}

# --- Build graph JSON ---
$nodes = @()
$edges = @()

foreach ($key in ($traits.Keys | Sort-Object)) {
  $t = $traits[$key]
  $dateCount = $t.dates.Count
  $state = if ($dateCount -ge 3) { 'ready' } elseif ($dateCount -eq 2) { 'moderate' } elseif ($dateCount -eq 1) { 'tentative' } else { 'raw' }
  $nodes += [ordered]@{
    id       = "trait:$key"
    label    = $key
    type     = 'trait'
    category = $t.category
    layer    = if ($t.layer) { $t.layer } else { $t.category }
    state    = $state
    dates    = $dateCount
    sources  = @($t.sources | Sort-Object)
    aliases  = @($t.aliases)
    detail   = if ($t.details.Count -gt 0) { $t.details[$t.details.Count - 1] } else { '' }
  }
  # provenance edges: trait -> each evidence source line
  foreach ($src in $t.sources) {
    $edges += [ordered]@{
      source = "trait:$key"
      target = "ev:$src"
      kind   = 'evidence'
    }
  }
}

# evidence line nodes (the raw jsonl lines)
$evLines = Get-Content $logPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$evIndex = 0
foreach ($el in $evLines) {
  $evIndex++
  $nodes += [ordered]@{
    id     = "ev:$evIndex"
    label  = "obs line $evIndex"
    type   = 'evidence'
    size   = $el.Length
  }
}

# section nodes
foreach ($sn in $sectionNames) {
  $nodes += [ordered]@{
    id    = "sec:$sn"
    label = $sn
    type  = 'section'
  }
}

# Layer/category-to-section mapping (from promote_brainworks.ps1)
$sectionMap = @{
  personality = 'Personality Model'
  workflow = 'Preferred Workflows'
  technical = 'Standards'
  communication = 'Communication Style'
  decision_making = 'Decision Making'
}
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

# Emit trait-to-curated-section edges
foreach ($key in $traits.Keys) {
  $t = $traits[$key]
  $traitLayer = $t.layer
  $target = if ($traitLayer -and $layerSectionMap.ContainsKey($traitLayer)) {
    $layerSectionMap[$traitLayer]
  }
  elseif ($sectionMap.ContainsKey($t.category)) {
    $sectionMap[$t.category]
  }
  else {
    'Behavioural Observations'
  }

  if ($sectionNames.Contains($target)) {
    $edges += [ordered]@{
      source = "trait:$key"
      target = "sec:$target"
      kind   = 'curated'
    }
  }
}

$graph = [ordered]@{
  generated   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
  root        = $Path
  evidence_lines = $evIndex
  sections    = $sectionNames.Count
  traits      = $nodes.Where({ $_.type -eq 'trait' }).Count
  nodes       = $nodes
  edges       = $edges
}

$jsonPath = Join-Path $genDir 'brainworks-index.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($jsonPath, ($graph | ConvertTo-Json -Depth 100), $utf8NoBom)

# --- Plain-text report ---
$reportPath = Join-Path $genDir 'brainworks-report.md'
$report = @"
# BrainWorks Graph Report

Generated: $($graph.generated)
Evidence lines: $($graph.evidence_lines)
Curated sections: $($graph.sections)
Distinct traits (post-alias): $($graph.traits)

## Trait states (rule-of-three promotion readiness)

$(($nodes.Where({ $_.type -eq 'trait' }) | ForEach-Object { "- [$($_.state)] $($_.label) ($($_.category), $($_.dates) dates, sources: $($_.sources -join ','))" }) -join "`n"))

## Curated sections

$($sectionNames -join "`n")

## Provenance

Every trait node links to its source evidence line(s) in observations.jsonl.
Ready traits (3+ distinct dates) are promotion-eligible per promote_brainworks.ps1.
"@
[System.IO.File]::WriteAllText($reportPath, $report, $utf8NoBom)

# --- Interactive HTML graph (self-contained, no external CDN at runtime) ---
$htmlPath = Join-Path $genDir 'brainworks-graph.html'
$graphJson = $graph | ConvertTo-Json -Depth 100
# neutralise any </script> sequence inside data so embedded JSON can't break the page
$graphJsonEscaped = $graphJson -replace '</', '<\/'

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>BrainWorks Graph</title>
<style>
  body { margin:0; background:#0f1115; color:#e6e6e6; font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }
  #hud { position:fixed; top:0; left:0; right:0; padding:8px 12px; background:rgba(15,17,21,.92); border-bottom:1px solid #2a2f3a; z-index:10; font-size:12px; display:flex; gap:16px; align-items:center; }
  #hud b { color:#7fd1ff; }
  #legend { display:flex; gap:12px; }
  .dot { display:inline-block; width:10px; height:10px; border-radius:50%; margin-right:4px; vertical-align:middle; }
  #wrap { position:absolute; top:42px; left:0; right:0; bottom:0; }
  svg { width:100%; height:100%; display:block; }
  .link { stroke:#39414f; stroke-opacity:.6; }
  .link.evidence { stroke:#2f6f4f; stroke-opacity:.5; }
  .node circle { stroke:#0f1115; stroke-width:1.5; cursor:pointer; }
  .node text { fill:#c9d1d9; font-size:10px; pointer-events:none; }
  .state-ready { stroke:#3fb950; }
  .state-moderate { stroke:#d29922; }
  .state-tentative { stroke:#58a6ff; }
  .state-raw { stroke:#6e7681; }
  .type-evidence { fill:#6e7681; }
  .type-section { fill:#bc8cff; }
</style>
</head>
<body>
<div id="hud">
  <span><b>BrainWorks Graph</b></span>
  <span id="stats"></span>
  <span id="legend">
    <span><span class="dot state-ready"></span>ready (3+)</span>
    <span><span class="dot state-moderate"></span>moderate (2)</span>
    <span><span class="dot state-tentative"></span>tentative (1)</span>
    <span><span class="dot type-evidence"></span>evidence line</span>
    <span><span class="dot type-section"></span>curated section</span>
    <span style="opacity:.7">| layers:</span>
    <span><span class="dot" style="background:#7ee787"></span>knowledge</span>
    <span><span class="dot" style="background:#ff7b72"></span>gap</span>
    <span><span class="dot" style="background:#ffa657"></span>mistake</span>
    <span><span class="dot" style="background:#d2a8ff"></span>bias</span>
    <span><span class="dot" style="background:#79c0ff"></span>belief</span>
    <span><span class="dot" style="background:#56d4dd"></span>identity</span>
  </span>
</div>
<div id="wrap"><svg id="graph"></svg></div>
<div id="tip"></div>

<script>
const DATA = $graphJsonEscaped;
const svg = document.getElementById('graph');
const tip = document.getElementById('tip');
const stats = document.getElementById('stats');
stats.textContent = 'traits: ' + DATA.traits + ' | evidence lines: ' + DATA.evidence_lines + ' | sections: ' + DATA.sections + ' | edges: ' + DATA.edges.length;

const W = () => svg.clientWidth, H = () => svg.clientHeight;
const nodes = DATA.nodes.map(n => ({ ...n }));
const idIndex = new Map(nodes.map((n,i) => [n.id, i]));
const links = DATA.edges
  .filter(e => idIndex.has(e.source) && idIndex.has(e.target))
  .map(e => ({ source: idIndex.get(e.source), target: idIndex.get(e.target), kind: e.kind }));

// simple force-directed layout (no external libs)
let alpha = 1;
nodes.forEach((n,i) => {
  const a = (i / nodes.length) * Math.PI * 2;
  n.x = W()/2 + Math.cos(a) * 220 + (Math.random()*20-10);
  n.y = H()/2 + Math.sin(a) * 220 + (Math.random()*20-10);
});

const svgNS = 'http://www.w3.org/2000/svg';
const linkEls = links.map(l => {
  const ln = document.createElementNS(svgNS, 'line');
  ln.setAttribute('class', 'link' + (l.kind === 'evidence' ? ' evidence' : ''));
  svg.appendChild(ln); return ln;
});
const nodeEls = nodes.map(n => {
  const g = document.createElementNS(svgNS, 'g'); g.setAttribute('class','node');
  const c = document.createElementNS(svgNS, 'circle');
  let r = 6, cls = '';
  const layerColor = { knowledge:'#7ee787', gap:'#ff7b72', mistake:'#ffa657', bias:'#d2a8ff', belief:'#79c0ff', identity:'#56d4dd', habit:'#f0883e', mental_model:'#a5d6ff', personality:'#3fb950', workflow:'#58a6ff', technical:'#d29922', communication:'#bc8cff', decision_making:'#ff9bce' };
  if (n.type === 'trait') { r = n.state === 'ready' ? 11 : n.state === 'moderate' ? 9 : 7; cls = 'state-' + n.state; c.setAttribute('fill', layerColor[n.layer] || '#6e7681'); }
  else if (n.type === 'evidence') { r = 4; cls = 'type-evidence'; }
  else { r = 8; cls = 'type-section'; }
  c.setAttribute('r', r); c.setAttribute('class', cls);
  const t = document.createElementNS(svgNS, 'text');
  t.setAttribute('dx', r + 3); t.setAttribute('dy', 3);
  t.textContent = n.type === 'evidence' ? '' : n.label;
  g.appendChild(c); g.appendChild(t); svg.appendChild(g);
  g.addEventListener('mousemove', ev => {
    tip.style.display = 'block';
    tip.style.left = Math.min(ev.clientX + 12, window.innerWidth - 330) + 'px';
    tip.style.top = (ev.clientY + 12) + 'px';
    tip.innerHTML = '';
    const b = document.createElement('b');
    b.textContent = n.label;
    tip.appendChild(b);
    tip.appendChild(document.createElement('br'));
    const typeSpan = document.createElement('span');
    typeSpan.textContent = 'type: ' + n.type;
    tip.appendChild(typeSpan);
    if (n.type === 'trait') {
      tip.appendChild(document.createElement('br'));
      const layerSpan = document.createElement('span');
      layerSpan.textContent = 'layer: ' + (n.layer||'-');
      tip.appendChild(layerSpan);
      tip.appendChild(document.createElement('br'));
      const catSpan = document.createElement('span');
      catSpan.textContent = 'category: ' + n.category;
      tip.appendChild(catSpan);
      tip.appendChild(document.createElement('br'));
      const stateSpan = document.createElement('span');
      stateSpan.textContent = 'state: ' + n.state;
      tip.appendChild(stateSpan);
      tip.appendChild(document.createElement('br'));
      const datesSpan = document.createElement('span');
      datesSpan.textContent = 'dates: ' + n.dates;
      tip.appendChild(datesSpan);
      tip.appendChild(document.createElement('br'));
      const srcSpan = document.createElement('span');
      srcSpan.textContent = 'sources: ' + (n.sources||[]).join(', ');
      tip.appendChild(srcSpan);
      if (n.aliases && n.aliases.length) {
        tip.appendChild(document.createElement('br'));
        const aliasSpan = document.createElement('span');
        aliasSpan.textContent = 'aliases: ' + n.aliases.join(', ');
        tip.appendChild(aliasSpan);
      }
      if (n.detail) {
        tip.appendChild(document.createElement('br'));
        const detailSpan = document.createElement('i');
        detailSpan.textContent = n.detail;
        tip.appendChild(detailSpan);
      }
    }
  });
  g.addEventListener('mouseleave', () => tip.style.display = 'none');
  return g;
});

function tick() {
  // repulsion
  for (let i=0;i<nodes.length;i++){
    for (let j=i+1;j<nodes.length;j++){
      let dx = nodes[i].x - nodes[j].x, dy = nodes[i].y - nodes[j].y;
      let d2 = dx*dx + dy*dy + 0.01, d = Math.sqrt(d2);
      let f = 240 / d2; dx/=d; dy/=d;
      nodes[i].x += dx*f*alpha; nodes[i].y += dy*f*alpha;
      nodes[j].x -= dx*f*alpha; nodes[j].y -= dy*f*alpha;
    }
  }
  // spring on links
  for (const l of links){
    const a = nodes[l.source], b = nodes[l.target];
    let dx = b.x - a.x, dy = b.y - a.y, d = Math.sqrt(dx*dx+dy*dy)+0.01;
    let target = 70, f = (d - target) * 0.02 * alpha;
    dx/=d; dy/=d;
    a.x += dx*f; a.y += dy*f; b.x -= dx*f; b.y -= dy*f;
  }
  // center gravity
  for (const n of nodes){ n.x += (W()/2 - n.x)*0.005*alpha; n.y += (H()/2 - n.y)*0.005*alpha; }
  const pad = 30;
  for (const n of nodes){ n.x = Math.max(pad, Math.min(W()-pad, n.x)); n.y = Math.max(pad+20, Math.min(H()-pad, n.y)); }
  // render
  links.forEach((l,i) => { const a=nodes[l.source], b=nodes[l.target]; linkEls[i].setAttribute('x1',a.x); linkEls[i].setAttribute('y1',a.y); linkEls[i].setAttribute('x2',b.x); linkEls[i].setAttribute('y2',b.y); });
  nodes.forEach((n,i) => { nodeEls[i].setAttribute('transform','translate('+n.x+','+n.y+')'); });
  alpha *= 0.992;
  if (alpha > 0.02) requestAnimationFrame(tick);
}
tick();
window.addEventListener('resize', () => { alpha = Math.max(alpha, 0.3); tick(); });
</script>
</body>
</html>
"@
[System.IO.File]::WriteAllText($htmlPath, $html, $utf8NoBom)

Write-Output "Generated:"
Write-Output "  $htmlPath"
Write-Output "  $jsonPath"
Write-Output "  $reportPath"
Write-Output ""
Write-Output "Traits (distinct, post-alias): $($graph.traits)"
Write-Output "Evidence lines: $($graph.evidence_lines)"
Write-Output "Curated sections: $($graph.sections)"
Write-Output "Edges: $($edges.Count)"

if ($Open) {
  Start-Process $htmlPath
}
