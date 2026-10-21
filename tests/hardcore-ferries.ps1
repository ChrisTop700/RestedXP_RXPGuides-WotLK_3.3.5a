[CmdletBinding()]
param([string]$RecipePath='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot '../tools/Hardcore-Ferries335.ps1')
if(-not $RecipePath){$RecipePath=Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-Ferries335.json'}
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$recipe=Get-Content $RecipePath -Raw | ConvertFrom-Json
$pins=Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
$index=@{};foreach($pin in $pins.blocks){$index[$pin.id]=$pin}
$kinds=@('ferry-arrival','ferry-approach','ordinary-road','ordinary-return',
    'tram-checkpoint','tram-quest-gates','obsolete-ferry-flight','optional-flight-fallback','retained-flight-stop','dungeon-condition','label-reference','branch-label')
$counts=@{}
foreach($entry in $recipe.guides){
    $pin=$index[$entry.id]
    Assert ($pin -and $pin.sourceHash -ceq $entry.sourceHash) 'Unpinned ferry adaptation.'
    $name=($entry.id -split '\|')[-1]
    $family=if($entry.id.StartsWith('Guides/SurvivalGuide/')){'classic'}else{'tbc'}
    foreach($edit in $entry.replacements){
        if($edit.kind -cnotin $kinds){continue}
        $counts[$edit.kind]+=$edit.occurrences
        $generated=@(Get-HardcoreFerryEdits335 $edit.from $family $name)
        Assert ($generated.Count -eq 1 -and $generated[0].to -ceq $edit.to) 'Ferry recipe does not regenerate.'
        Assert (@(Get-HardcoreFerryEdits335 $edit.to $family $name).Count -eq 0) 'Ferry adaptation is not idempotent.'
        Assert ($edit.to -notmatch '\.link .*battle\.net|character unstuck|Wetlands to Westfall swim') 'Obsolete relocation remains.'
        foreach($line in [regex]::Matches($edit.from,'(?m)^[ \t]*\.(?:accept|turnin|complete|collect|fp|vendor|train|home)\b[^\n]*')){
            Assert ($edit.to.Contains($line.Value)) 'Meaningful authored action removed.'
        }
    }
}
Assert ($counts['ferry-arrival'] -eq 31) 'Ferry inventory changed (8 Classic and 23 TBC arrival variants).'
Assert ($counts['tram-quest-gates'] -eq 3 -and $counts['tram-checkpoint'] -eq 1) 'Tram repair incomplete.'
Assert ($counts['ordinary-road'] -eq 4) 'Ordinary Dun Algaz approaches missing.'
Assert ($counts['dungeon-condition'] -eq 12) 'Mulgore RFC condition inventory changed.'
Assert ($counts['label-reference'] -eq 4) 'Verified Piercing/Tiragarde reference inventory changed.'
Assert ($counts['branch-label'] -eq 4) 'Reviewed Earthroot/Helboars/AntiVenom branch inventory changed.'
$unterminated="step`n.goto Darkshore,32.75,42.21`n.zone Wetlands >> Take the boat to Menethil Harbor`n.bindlocation 2104 --HS not in Menethil"
$repair=@(Get-HardcoreFerryEdits335 $unterminated 'tbc' '29-30 Ashenvale')
Assert ($repair.Count -eq 1 -and
    $repair[0].to.Contains(".bindlocation 2104 --HS not in Menethil`n    >>Take The Bravery")) 'Appended travel instruction joined a predicate comment.'
foreach($valid in @(
    "step`n.goto Dustwallow Marsh,71.4,56.1`n.zone Wetlands >> Take the boat to Menethil Harbor`n",
    "step`n.goto Azuremyst Isle,20.405,54.184`n.zone Darkshore >> Take the boat to Darkshore`n",
    "step`n.goto Darkshore,32.75,42.21`n.zone Teldrassil >> Take the boat to Rut'theran`n"
)){
    Assert (@(Get-HardcoreFerryEdits335 $valid 'tbc' '20-21 Darkshore').Count -eq 0) 'Valid ferry changed.'
}
Write-Output 'Ferry checks passed: 31 obsolete arrival variants, retained quest/FP/vendor actions, tram predicates, roads and valid ferries.'
