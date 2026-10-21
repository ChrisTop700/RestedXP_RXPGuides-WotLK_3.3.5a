[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [string]$RecipePath = '',
    [string]$LockPath = ''
)
# Reproducible candidates only. The caller must review compatibility evidence
# and filtered paths before adding these files to a release manifest.
$ErrorActionPreference = 'Stop'
if (-not $LockPath) { $LockPath = Join-Path $PSScriptRoot 'data/Hardcore-Upstream-v4.11.11.json' }
if (-not $RecipePath) { $RecipePath = Join-Path $PSScriptRoot 'data/Hardcore-Published335/upstream.json' }
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
$destination = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $destination) { throw 'Output already exists; use a new candidate directory.' }
$index = Read-HardcoreUpstream335 $SourceRoot
$lock = [IO.File]::ReadAllText([IO.Path]::GetFullPath($LockPath), $hardcoreUtf8) | ConvertFrom-Json
if ($lock.schemaVersion -ne 1 -or $lock.upstreamVersion -cne 'v4.11.11' -or
    $index.Count -ne $lock.blocks.Count) { throw 'Pinned source inventory differs.' }
$locked = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($entry in $lock.blocks) {
    if (-not $locked.Add($entry.id) -or -not $index.ContainsKey($entry.id) -or $index[$entry.id].sourceHash -cne $entry.sourceHash) {
        throw "Pinned source block changed: $($entry.id)"
    }
}
$originalGraph = Get-HardcoreSourceGraph335 $index
$applied = [Collections.Generic.List[object]]::new()
$recipeHash = ''
if ($RecipePath) {
    $recipeText = [IO.File]::ReadAllText([IO.Path]::GetFullPath($RecipePath), $hardcoreUtf8).Replace("`r`n","`n")
    $recipeHash = Get-HardcoreHash335 $recipeText
    $recipe = $recipeText | ConvertFrom-Json
    if ($recipe.schemaVersion -ne 1) { throw 'Unsupported adaptation recipe.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $recipe.guides) {
        if (-not $seen.Add($entry.id) -or -not $index.ContainsKey($entry.id) -or
            $originalGraph.selected -cnotcontains $entry.id) { throw 'Duplicate, unknown or unreachable recipe identity.' }
        $block = $index[$entry.id]
        if ($entry.sourceHash -cne $block.sourceHash) { throw 'Adaptation source hash changed.' }
        foreach ($change in $entry.replacements) {
            if (-not ($change.reason -is [string]) -or -not $change.reason.Trim() -or
                -not ($change.from -is [string]) -or -not $change.from -or
                -not ($change.to -is [string])) { throw 'Every exact adaptation requires text and a reason.' }
            $count = 1
            if ($change.PSObject.Properties['occurrences']) {
                if (($change.occurrences -isnot [int] -and $change.occurrences -isnot [long]) -or
                    $change.occurrences -lt 1 -or $change.occurrences -gt 100) { throw 'Invalid occurrence count.' }
                $count = [int]$change.occurrences
            }
            if (($block.content.Split(@($change.from), [StringSplitOptions]::None).Count - 1) -ne $count) {
                throw "Exact adaptation no longer matches: $($block.id)"
            }
            $block.content = $block.content.Replace($change.from, $change.to)
            $applied.Add([ordered]@{id=$block.id; reason=$change.reason; occurrences=$count
                before=Get-HardcoreHash335 $change.from; after=Get-HardcoreHash335 $change.to})
        }
        $header = ($block.content -split '(?m)^step\b',2)[0]
        if (@(Get-HardcoreHeader335 $header 'name')[0] -cne $block.name -or
            @(Get-HardcoreHeader335 $header 'group')[0] -cne $block.group) { throw 'Recipes cannot rename source identities.' }
        $block.next = @(Get-HardcoreHeader335 $header 'next')
    }
}
$graph = Get-HardcoreSourceGraph335 $index
if (($graph.selected -join "`n") -cne ($originalGraph.selected -join "`n")) {
    throw 'An adaptation changed the selected itinerary. Review selection explicitly instead.'
}
$outputs = @{classic=[Collections.Generic.List[string]]::new(); tbc=[Collections.Generic.List[string]]::new()}
$receipts = [Collections.Generic.List[object]]::new()
$reviews = [Collections.Generic.List[object]]::new()
foreach ($id in $graph.selected) {
    $block = $index[$id]
    $split = $block.content -split '(?m)(?=^step\b)',2
    if ($split.Count -ne 2) { throw "Missing guide body: $id" }
    $header, $body = $split[0], $split[1]
    $conditions = @([regex]::Matches($header,'(?m)^<<[ \t]+([^\n]+)') | ForEach-Object {$_.Groups[1].Value.Trim()})
    if ($conditions.Count -ne 1 -or $conditions[0] -cne $block.faction) { throw "Explicit header adaptation required: $id" }
    $suffix = if ($block.faction -eq 'Alliance') {'A'} else {'H'}
    $flavor = if ($block.family -eq 'tbc') {'TBC'} else {'Classic'}
    $group = "Original Guides - RestedXP Hardcore $flavor Guides ($suffix)"
    # Preserve authored filters, levels, labels and body directives. Expansion
    # gates are replaced only at the guide envelope, not on individual lines.
    $header = [regex]::Replace($header, '(?m)^(?:#(?:classic|tbc|wotlk|hardcore|softcore|group|subgroup|defaultfor)\b[^\n]*|<<[^\n]*)\n?', '')
    foreach ($oldGroup in @("RestedXP Survival Guide ($suffix)", "RXP TBC Survival Guide ($suffix)")) {
        $header = $header.Replace($oldGroup + '\', $group + '\')
        # Explicit in-body handoffs use the same namespace as header handoffs.
        $body = [regex]::Replace($body, '(?m)^([ \t]*\.next[ \t]+)([^\n]+)', {
            param($match)
            return $match.Groups[1].Value + $match.Groups[2].Value.Replace($oldGroup + '\', $group + '\')
        })
    }
    $header = [regex]::Replace($header, '(?m)^#next[ \t]+[^\n]+\n?', {
        param($match)
        $raw = $match.Value.Trim()
        if ($block.high -eq 60 -and $raw -match '^#next[ \t]+(?:[^\\;]+\\)?60-(?:6[1-9]|[7-9]\d)(?:[ \t]|$)') {
            if ($raw.Contains(';') -or $raw.Contains('<<')) { throw 'Ambiguous post-60 endpoint.' }
            return ''
        }
        return $match.Value
    })
    $condition = Get-HardcoreEnvelope335 $block.family $block.faction
    $header = "#hardcore`n<< $condition`n#group $group`n#subgroup Experimental $flavor Survival`n" + $header.Trim() + "`n"
    $intro = "step`n    +Experimental upstream $flavor route adapted for 3.3.5. Deathless guidance does not enforce server rules or guarantee survival. Check this instruction to continue.`n"
    if (-not @(Get-HardcoreHeader335 $header 'next').Count -and $block.high -eq 60) {
        $body += "`nstep`n    +This experimental $flavor Hardcore route ends at level 60. Select another guide manually if you wish to continue.`n"
    }
    $content = $header + "`n" + $intro + $body.TrimEnd() + "`n"
    $lineNumber = 0
    foreach ($line in $content -split "`n") {
        $lineNumber++
        $kind = if ($line -match '(?i)^\s*\.(deathskip|logout)\b|logout\s*skip|ghetto\s*hearth|unstuck|spirit healer|\bdie and\b|\bdrown yourself\b') { 'deathless-travel-review' }
            elseif ($line -match '^\s*\.train\s+(?:2981|14926|24494|408443|132245)(?:[ ,]|$)' -or
                $line -match '(?i)learn.*(?:Bite|Claw).*(?:rank|Rank)|abandon.*pet') { 'wotlk-training-review' }
            elseif ($line -match '^\s*\.(?:goto|zone|path|loop|line)\s+(?:721|1414|1415|1429)(?:,|$)') { 'map-compatibility-review' }
            else { '' }
        if ($kind) { $reviews.Add([ordered]@{id=$id; line=$lineNumber; kind=$kind; text=$line.Trim()}) }
    }
    $outputs[$block.family].Add("-- Source: $($block.file); block SHA256: $($block.sourceHash)`nRXPGuides.RegisterGuide([[`n$content]])`n")
    $receipts.Add([ordered]@{
        id=$id; key="$group|$($block.name)"; family=$block.family
        sourceHash=$block.sourceHash; outputHash=Get-HardcoreHash335 $content
        steps=Get-HardcoreStepCount335 $content
    })
}
$report = [ordered]@{
    schemaVersion=1; status='candidate-not-release-ready'; gameplayAccepted=$false
    recipeHash=$recipeHash; changes=@($applied.ToArray())
    guides=@($receipts.ToArray()); graph=$graph; compatibilityReviews=@($reviews.ToArray())
}
[IO.Directory]::CreateDirectory($destination) | Out-Null
foreach ($family in @('classic','tbc')) {
    $notice = "-- Generated from RestedXP v4.11.11 Survival sources. Retain upstream attribution and licensing.`n-- Experimental candidate: see compatibility-report.json. Not a gameplay certification.`n"
    [IO.File]::WriteAllText((Join-Path $destination ("Hardcore-" + $family + ".preview.lua")),
        $notice + ($outputs[$family] -join "`n"), $hardcoreUtf8)
}
[IO.File]::WriteAllText((Join-Path $destination 'compatibility-report.json'),
    (ConvertTo-HardcoreJson335 $report) + "`n", $hardcoreUtf8)
Write-Output ("Generated {0} separate-family candidates; {1} source graph reviews; {2} compatibility review lines. Manifest unchanged." -f
    $receipts.Count, $graph.issues.Count, $reviews.Count)
