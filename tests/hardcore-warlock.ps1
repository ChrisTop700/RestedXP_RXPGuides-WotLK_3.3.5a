[CmdletBinding()]
param(
    [string]$RecipePath = '',
    [string]$ServerSourceRoot = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot '../tools/Hardcore-Warlock335.ps1')
if (-not $RecipePath) { $RecipePath = Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-Warlock335.json' }
function Assert($Value,[string]$Message) { if (-not $Value) { throw $Message } }
$recipe = Get-Content $RecipePath -Raw | ConvertFrom-Json
$pins = Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
$counts = @{starter=0;grimoire=0}
foreach ($entry in $recipe.guides) {
    $pin = @($pins.blocks | Where-Object {$_.id -ceq $entry.id})
    Assert ($pin.Count -eq 1 -and $pin[0].sourceHash -ceq $entry.sourceHash) 'Unpinned correction.'
    foreach ($edit in $entry.replacements) {
        if ($edit.kind -ceq 'warlock-starter') {
            $counts.starter++
            $new = Get-HardcoreWarlockStarterEdit335 $edit.from
            Assert ($new.to -ceq $edit.to) ('Starter regeneration differs: '+$entry.id)
            Assert ($edit.to -notmatch '\.(accept|turnin|complete|isOnQuest) (1485|1499|1470|1598|1599|8344)\b') 'Removed quest retained.'
            Assert ($edit.to.Contains('.train 688 >>Train Summon Imp')) 'Learned Imp check missing.'
            Assert ($edit.to.IndexOf('.train 688 >>') -lt $edit.to.IndexOf('.cast 688 >>')) 'Summon precedes training.'
            foreach ($reward in @(3090,3099,3105,3115,8563,10073,8336,8338)) {
                $pattern = '(?m)^[ \t]*\.turnin '+$reward+'\b'
                Assert ([regex]::Matches($edit.from,$pattern).Count -eq [regex]::Matches($edit.to,$pattern).Count) 'Valid reward lost.'
            }
        } elseif ($edit.kind -ceq 'demon-grimoire') {
            $counts.grimoire += $edit.occurrences
            $new = @(Get-HardcoreGrimoireEdits335 $edit.from)
            Assert ($new.Count -eq 1 -and $new[0].to -ceq $edit.to) 'Grimoire regeneration differs.'
            Assert ($edit.to -notmatch '\.(collect|use|buy|train|itemcount) \d+') 'Obsolete training action retained.'
            foreach ($label in [regex]::Matches($edit.from,'(?m)^[ \t]*#label [^\n]+')) {
                Assert ($edit.to.Contains($label.Value)) 'Dependency label lost.'
            }
        }
    }
}
Assert ($counts.starter -eq 9 -and $counts.grimoire -eq 90) 'Reviewed inventory changed.'
$short = "step << Warlock`n    >>Buy Grimoires`n    .collect 16302,1`n"
$overlap = $short+"step << Warlock`n    >>Buy Grimoires`n    .collect 16302,1`n    .group`n"
foreach ($edit in @(Get-HardcoreGrimoireEdits335 $overlap)) {
    Assert ($overlap.Split(@($edit.from),[StringSplitOptions]::None).Count-1 -eq $edit.occurrences) 'Prefix overlap corrupted later edit.'
    $overlap = $overlap.Replace($edit.from,$edit.to)
}
Assert ($overlap -notmatch '\.collect|\.group') 'Obsolete purchase gate survived overlapping steps.'
foreach ($quest in @(1473,9062)) {
    $sample = "step << Warlock`n    >>Loot the Grimoire`n    .complete $quest,1`n"
    Assert (@(Get-HardcoreGrimoireEdits335 $sample).Count -eq 0) 'Quest grimoire removed.'
}
foreach ($warning in @(
    'WotLK pet abilities do not use the TBC vendor Grimoire system.',
    'Do not buy the obsolete Grimoire of Sacrifice.',
    'Inspect the spellbook; no Grimoire purchase is required.'
)) {
    Assert (@(Get-HardcoreGrimoireEdits335 ("step << Warlock`n    #optional`n    +"+$warning+"`n")).Count -eq 0) 'Existing safe reminder was rewritten.'
}
foreach ($action in @('.collect 999999,1','.train 688','.cast 688')) {
    $rejected = $false
    try { Get-HardcoreGrimoireEdits335 ("step << Warlock`n    >>Buy Grimoires`n    "+$action+"`n") | Out-Null }
    catch { $rejected = $true }
    Assert $rejected 'Unknown mixed action was silently removed.'
}
if ($ServerSourceRoot) {
    $facts = Get-Content (Join-Path $PSScriptRoot 'fixtures/hardcore-warlock335.json') -Raw | ConvertFrom-Json
    foreach ($file in $facts.files.PSObject.Properties) {
        Assert ((Get-FileHash (Join-Path $ServerSourceRoot $file.Name)).Hash.ToLowerInvariant() -ceq $file.Value) ('Stale source fact: '+$file.Name)
    }
    $vendors = Get-Content (Join-Path $ServerSourceRoot 'data/sql/base/db_world/npc_vendor.sql') -Raw
    foreach ($item in $facts.demonTraining.itemsWithoutVendorRows) {
        Assert ($vendors -notmatch ('(?m)^\(\d+,\d+,'+$item+',')) 'Obsolete grimoire acquired a vendor row.'
    }
}
Write-Output 'Warlock fixtures passed: nine starters, 90 demon-training instructions, reward/anchor preservation and fail-closed mixed actions.'
