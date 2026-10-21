[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$BaseRecipePath = '',
    [string]$ReplaceHash = '',
    [switch]$Check
)
# Produces exact, source-pinned candidate adaptations, not release approval.
# This pass deliberately does not guess pet-sequence or transport rewrites.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Coordinates335.ps1')
if (-not $BaseRecipePath) { $BaseRecipePath = Join-Path $PSScriptRoot 'data/Hardcore-Upstream-Adaptations335.json' }
$index = Read-HardcoreUpstream335 $SourceRoot
$lock = Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
if ($index.Count -ne $lock.blocks.Count) { throw 'Source inventory changed.' }
foreach ($record in $lock.blocks) {
    if (-not $index.ContainsKey($record.id) -or $index[$record.id].sourceHash -cne $record.sourceHash) {
        throw 'Pinned source changed.'
    }
}
$baseRecipe = Get-Content -LiteralPath $BaseRecipePath -Raw | ConvertFrom-Json
if ($baseRecipe.schemaVersion -ne 1) { throw 'Unsupported base recipe.' }
$baseById = @{}
foreach ($entry in $baseRecipe.guides) {
    if ($baseById.ContainsKey($entry.id)) { throw 'Duplicate base adaptation.' }
    $baseById[$entry.id] = $entry
}
$maps = Read-HardcoreGeometry335 (Join-Path $PSScriptRoot '../tests/fixtures/hardcore-map-geometry335.json')
$entries = [Collections.Generic.List[object]]::new()
function Edit([string]$From, [string]$To, [string]$Reason, [int]$Count = 1) {
    if (-not $From -or ($script:body.Split(@($From), [StringSplitOptions]::None).Count - 1) -ne $Count) {
        throw "Exact compatibility edit differs in $id : $Reason"
    }
    $script:edits.Add([ordered]@{from=$From;to=$To;reason=$Reason;occurrences=$Count})
    $script:body = $script:body.Replace($From, $To)
}
function Edit-Matches([string]$Pattern, [scriptblock]$Transform, [string]$Reason) {
    $seen = @{}
    foreach ($match in [regex]::Matches($script:body, $Pattern)) {
        if ($seen.ContainsKey($match.Value)) { continue }
        $seen[$match.Value] = $true
        $replacement = & $Transform $match
        $count = $script:body.Split(@($match.Value), [StringSplitOptions]::None).Count - 1
        Edit $match.Value $replacement $Reason $count
    }
}
foreach ($id in (Get-HardcoreSourceGraph335 $index).selected) {
    $block = $index[$id]
    $script:body = $block.content
    $script:edits = [Collections.Generic.List[object]]::new()
    if ($baseById.ContainsKey($id)) {
        $base = $baseById[$id]
        if ($base.sourceHash -cne $block.sourceHash) { throw 'Base recipe source changed.' }
        foreach ($change in $base.replacements) {
            $count = if ($change.PSObject.Properties['occurrences']) { [int]$change.occurrences } else { 1 }
            Edit $change.from $change.to $change.reason $count
        }
        $baseById.Remove($id)
    }
    foreach ($change in @(Get-HardcoreCoordinateEdits335 $script:body $maps)) {
        Edit $change.from $change.to $change.reason $change.occurrences
    }
    Edit-Matches '(?m)^([ \t]*)\.zone 721,2[^\n]*\n' {
        param($m)
        if ($m.Value -match 'looking for a group') {
            return $m.Groups[1].Value + "+Optional dungeon: find a group for Gnomeregan. Check this instruction when your group is ready; no group is formed automatically.`n"
        }
        return $m.Groups[1].Value + "+Enter Gnomeregan with your group through the ordinary entrance. Check this instruction after entering; the stock client cannot confirm this area ID as a zone map.`n"
    } 'Replace Gnomeregan AreaTable-as-map checks with explicit manual confirmation; retain optional dungeon gates.'
    Edit-Matches '(?m)^([ \t]*)\.train 408443[^\n]*\n' {
        param($m)
        return $m.Groups[1].Value + ".trainer >>Optionally train affordable class spells. Check learned spells in your spellbook; this visit does not prove a particular spell was learned.`n"
    } 'Remove a post-WotLK spell sentinel from the existing optional Shaman trainer visit; do not invent a replacement spell.'

    Edit-Matches '(?m)^([ \t]*)\.xpto60(?:hc)?[ \t]*>>[ \t]*([^\n]+)\n' {
        param($m)
        return $m.Groups[1].Value + "+Manual XP checkpoint: " + $m.Groups[2].Value +
            ". Compare your current XP with the rewards of quests you have actually completed before deciding. Classic projected totals are not used on WotLK; keep the following turn-ins and check this instruction when ready.`n"
    } 'Replace unsupported Classic quest-XP projection with an explicit manual decision; preserve the authored hand-in circuit.'
    if ($block.family -ceq 'classic' -and $block.faction -ceq 'Alliance' -and
        $script:body.Contains('+Congratulations on finishing the RestedXP 1-60 Hardcore Survival Guide!')) {
        $old = "step`n+Congratulations on finishing the RestedXP 1-60 Hardcore Survival Guide! Thank you for using RestedXP."
        $new = @'
step
>>Finish the preceding quest turn-ins before doing any more grinding. If you are still below level 60, return to the previously visited Felpaw Village by ordinary travel: take the Darnassus portal to Rut'theran, the boat to Auberdine, and the roads through Ashenvale into Felwood. A learned flight is optional; do not assume a hearth binding or use a death shortcut.
>>Kill ordinary Deadwood Furbolgs only while you can safely manage them. Check your actual XP rather than the removed Classic reward projection.
.xp 60 >>Reach level 60 after collecting the authored quest rewards
.mob Deadwood Shaman
.mob Deadwood Den Watcher
.mob Deadwood Avenger
step
+Congratulations on finishing the RestedXP 1-60 Hardcore Survival Guide! Thank you for using RestedXP.
'@
        Edit $old $new 'Require actual level 60 after the preserved final reward circuit, with an ordinary-travel grind fallback instead of predicted Classic XP.'
    }
    # Only Northshire-source starters: Dun Morogh's Timber Wolves belong to a
    # different quest and must not be renamed by a global creature substitution.
    if ($block.id -match '/(?:A-Hardcore-Human|A-Classic-Alliance-1-13_Human)\.lua\|' -and
        $script:body -match '(?m)^[ \t]*\.complete 33,1\b') {
        $pairs = [ordered]@{
            'Young Wolves'='Diseased Young Wolves'; 'Timber Wolves'='Diseased Timber Wolves'
            'Young Wolf'='Diseased Young Wolf'; 'Timber Wolf'='Diseased Timber Wolf'
            'Tough Wolf Meat'='Diseased Wolf Pelts'; '|cRXP_LOOT_Meat|r'='|cRXP_LOOT_Diseased Wolf Pelts|r'
        }
        # Each source line is transformed once, preventing double prefixes.
        Edit-Matches '(?m)^[^\n]*(?:Young Wol(?:f|ves)|Timber Wol(?:f|ves)|Tough Wolf Meat|\|cRXP_LOOT_Meat\|r)[^\n]*\n' {
            param($m)
            $line = $m.Value
            foreach ($key in $pairs.Keys) { $line = $line.Replace($key, $pairs[$key]) }
            return $line
        } 'Quest33 requires eight Diseased Wolf Pelts50432; creatures299/69 are Diseased Young/Timber Wolves on WotLK. Preserve objectives and rewards.'
    }
    # Both the approach and the stop retain their authored placement and labels.
    # Only the existing Tauren Kodo-training branch is eligible.
    foreach ($step in @([regex]::Matches($script:body, '(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)'))) {
        if ($step.Value -notmatch '^[ \t]*step << Tauren' -or
            $step.Value -notmatch '\.skill riding,75,1' -or
            $step.Value -notmatch '\.train 132245\b|\.subzone 222\b') { continue }
        $new = $step.Value.Replace('.xp <30,1', '.xp <20,1').Replace('.money <38', '.money <4')
        $new = $new.Replace('.xp <40,1', '.xp <20,1').Replace('.money <90', '.money <4')
        $new = $new.Replace(".train 132245 >>Train |T136103:0|t[Kodo Riding]",
            '.train 33388 >>Train Apprentice Riding from Kar Stormsinger if not already learned')
        $new = $new.Replace("Talk to |cRXP_FRIENDLY_Xar'Ti|r and |cRXP_FRIENDLY_Zjolnir|r",
            'Talk to |cRXP_FRIENDLY_Kar Stormsinger|r and |cRXP_FRIENDLY_Harb Clawhoof|r')
        $new = $new.Replace('.vendor >>|cRXP_BUY_Buy a|r |T132253:0|t[|cFF0070FFKodo|r]',
            '.vendor >>Optionally buy a Kodo from Harb Clawhoof only if you can afford the displayed price after training. Apprentice Riding requires level 20 and costs up to 4 gold; the mount costs extra.')
        if ($new -cne $step.Value -and $script:body.Contains($step.Value)) {
            $count = $script:body.Split(@($step.Value), [StringSplitOptions]::None).Count - 1
            Edit $step.Value $new 'Correct the existing optional Kodo stop to WotLK trainer3690/list42:33388, level20,40000c; mount affordability remains a separate manual choice.' $count
        }
    }
    if ($script:edits.Count) {
        $entries.Add([ordered]@{id=$id;sourceHash=$block.sourceHash;replacements=@($script:edits.ToArray())})
    }
}
if ($baseById.Count) { throw 'Base recipe contains unselected identities.' }
$recipe = [ordered]@{schemaVersion=1;guides=@($entries.ToArray())}
$text = (ConvertTo-HardcoreJson335 $recipe) + "`n"
$destination = [IO.Path]::GetFullPath($OutputPath)
if ($Check) {
    if ([IO.File]::ReadAllText($destination, $hardcoreUtf8) -cne $text) { throw 'Compatibility recipe is stale.' }
} else {
    if (Test-Path -LiteralPath $destination) {
        if ($ReplaceHash -notmatch '^[0-9a-f]{64}$' -or
            (Get-HardcoreHash335 ([IO.File]::ReadAllText($destination, $hardcoreUtf8))) -cne $ReplaceHash) {
            throw 'Use a new output path, or supply the exact existing generated recipe hash. Never update historical candidate evidence.'
        }
    } elseif ($ReplaceHash) { throw 'Expected generated recipe is missing.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    [IO.File]::WriteAllText($destination, $text, $hardcoreUtf8)
}
Write-Output "Exact compatibility recipes: $($entries.Count) chapters. Remaining pet/starter/travel reviews still block publication."
