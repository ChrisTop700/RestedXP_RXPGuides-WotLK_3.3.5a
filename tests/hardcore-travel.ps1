[CmdletBinding()]
param([string]$RecipePath = '', [string]$ServerSourceRoot = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot '../tools/Hardcore-Travel335.ps1')
if (-not $RecipePath) { $RecipePath = Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-Travel335.json' }
function Assert($Value,[string]$Message) { if (-not $Value) { throw $Message } }
$recipe = Get-Content $RecipePath -Raw | ConvertFrom-Json
$pins = Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
$pinIndex = @{}
foreach ($pin in $pins.blocks) { $pinIndex[$pin.id]=$pin.sourceHash }
$counts=@{}
foreach ($entry in $recipe.guides) {
    Assert ($pinIndex[$entry.id] -ceq $entry.sourceHash) 'Unpinned travel replacement.'
    foreach ($edit in $entry.replacements) {
        if ($edit.kind -cnotin @('instance-return','shaman-water-return')) { continue }
        $counts[$edit.kind]+=$edit.occurrences
        $generated=@(Get-HardcoreTravelEdits335 $edit.from)
        Assert ($generated.Count -eq 1 -and $generated[0].to -ceq $edit.to) 'Travel regeneration changed.'
        Assert ($edit.to -notmatch '\.link|InviteUnit|LeaveParty') 'Relocation macro retained.'
        foreach ($line in [regex]::Matches($edit.from,'(?m)^[ \t]*(?:#[^\n]*|\.(?:dungeon|isOnQuest)\b[^\n]*)\n')) {
            Assert ($edit.to.Contains($line.Value)) 'Dungeon/quest gate or named anchor lost.'
        }
        Assert ([regex]::Match($edit.from,'^[ \t]*step[^\n]*').Value -ceq
            [regex]::Match($edit.to,'^[ \t]*step[^\n]*').Value) 'Class selection changed.'
        Assert (@(Get-HardcoreTravelEdits335 $edit.to).Count -eq 0) 'Safe replacement was treated as another shortcut.'
    }
}
Assert ($counts['instance-return'] -eq 8 -and $counts['shaman-water-return'] -eq 4) 'Travel review scope changed.'
$ejection="step << Warlock`n.dungeon !DM`n.goto StormwindClassic,39.834,54.360`n.zone Darkshore >>Ghetto Hearth from The Stockades`n.link /run InviteUnit('aa') >>click`n"
foreach ($guard in @("step << skip`n", "step`n#softcore`n", "step`n.deathskip`n")) {
    Assert (@(Get-HardcoreTravelEdits335 ($ejection.Replace("step << Warlock`n",$guard))).Count -eq 0) 'Unreachable softcore/skip branch rewritten.'
}
foreach ($mixed in @('.accept 123', '.turnin 123', '.collect 123,1', '.cast 123', '.fly Stormwind')) {
    $rejected=$false
    try { Get-HardcoreTravelEdits335 ($ejection+$mixed+"`n") | Out-Null } catch { $rejected=$true }
    Assert $rejected 'Unknown mixed quest/travel action silently removed.'
}
foreach ($valid in @(
    "step`n.goto Dustwallow Marsh,71.4,56.1`n.zone Wetlands >>Take the boat to Menethil Harbor`n",
    "step`n.goto Azuremyst Isle,20.405,54.184`n.zone Darkshore >>Take the boat to Darkshore`n",
    "step`n>>Use the altar at the end of the dungeon to teleport to the entrance.`n.complete 123,1`n",
    "step`n--.link /run InviteUnit('aa') >>historical comment`n.goto Darkshore,32.44,43.71`n"
)) {
    Assert (@(Get-HardcoreTravelEdits335 $valid).Count -eq 0) 'Valid ferry, dungeon action or comment rewritten.'
}
$facts=Get-Content (Join-Path $PSScriptRoot 'fixtures/hardcore-travel335.json') -Raw | ConvertFrom-Json
Assert ($facts.ferries.Count -eq 4) 'Ferry fixture incomplete.'
if ($ServerSourceRoot) {
    $path=Join-Path $ServerSourceRoot $facts.sourcePath
    Assert ((Get-FileHash $path).Hash.ToLowerInvariant() -ceq $facts.sourceSha256) 'Stale transport fixture.'
    $sql=Get-Content $path -Raw
    foreach ($ferry in $facts.ferries) {
        Assert ($sql.Contains(','+[string]$ferry.entry+',')) 'Ferry absent from source.'
    }
}
Write-Output 'Travel fixtures passed: eight ordinary instance returns, four Shaman water-chain instructions, retained gates and valid ferries.'
