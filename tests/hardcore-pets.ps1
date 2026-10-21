[CmdletBinding()]
param(
    [string]$SourceRoot = '',
    [string]$CandidateRoot = '',
    [string]$ServerSourceRoot = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot '../tools/Hardcore-Pets335.ps1')
function Assert($Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Adapt([string]$Text) {
    foreach ($edit in @(Get-HardcorePetEdits335 $Text)) {
        Assert ($Text.Split(@($edit.from),[StringSplitOptions]::None).Count-1 -eq $edit.occurrences) 'Pet edit is not exact.'
        $Text = $Text.Replace($edit.from,$edit.to)
    }
    return $Text
}
function Actions([string]$Text) {
    @([regex]::Matches($Text,'(?m)^[ \t]*\.(?:accept|turnin|complete|collect|use|buy|abandon)[^\n]*') |
        ForEach-Object {$_.Value.Trim()}) -join "`n"
}
$quest = @'
step << BloodElf Hunter
    .goto Silvermoon City,82.20,28.06
    .turnin 9673 >>Turn in Beast Training
    .train 4187 >> Train your pet spells
    .target Halthenis
'@ + "`n"
$result = Adapt $quest
Assert ($result -match '\.turnin 9673' -and $result -match '\.target Halthenis' -and
    $result -notmatch '\.train') 'Valid Beast Training reward or travel was removed.'
$class = @'
step << Hunter
    .goto Silvermoon City,82.39,26.09
    >>Drag [Beast Training] onto your Action Bars. Teach skills to your pet
    .train 14281 >> Train your class spells
    .xp <12,1
'@ + "`n"
$result = Adapt $class
Assert ($result.Contains('.train 14281') -and $result.Contains('.xp <12,1') -and
    $result.Contains('.goto Silvermoon City')) 'Class-training stop was removed with obsolete pet prose.'
$first = @'
step << Hunter
    #sticky
    .goto Teldrassil,41.2,44.4,0
    >>Tame a Strigid Hunter
    .train 2981 >>Attack mobs with it to learn Claw
    .unitscan Strigid Hunter
'@ + "`n"
$result = Adapt $first
Assert ($result.Contains('permanent pet') -and $result.Contains('.goto Teldrassil') -and
    $result.Contains('.unitscan Strigid Hunter') -and $result -notmatch '\.train|#sticky') 'First-pet acquisition was lost.'
$sequence = @'
step << Hunter
    #completewith RankLoop
    .stable >>Stable your pet for rank learning
step << Hunter
    #label RankLoop
    #loop
    .xp <27,1
    .train 16830 >>Learn Claw
step << Hunter
    .stable >>Abandon the temporary pet and retrieve your regular pet
    .train 16830,3
'@ + "`n"
$result = Adapt $sequence
Assert ($result -notmatch '\.stable|\.train|#loop|#completewith' -and $result -match '#label RankLoop' -and
    $result.Contains('.xp <27,1')) 'Rank sequence or its external label/gate was not handled safely.'
Assert ((Adapt $result) -ceq $result) 'Pet adaptation is not idempotent.'
$mixed = $quest.Replace('.turnin 9673', '.turnin 999999')
$rejected = $false
try { $null = Adapt $mixed } catch { $rejected = $true }
Assert $rejected 'Unknown mixed quest/pet step was silently changed.'
$mixed = $sequence.Replace('.train 16830 >>Learn Claw',".train 16830 >>Learn Claw`n.train 14281 >>Train class spells")
$rejected = $false
try { $null = Adapt $mixed } catch { $rejected = $true }
Assert $rejected 'Player spell training was silently removed.'
$legitimate = "step << Hunter`n.accept 9675 >>Accept Beast Training`nstep << Hunter`n.cast 1515 >>Tame your first permanent pet`n"
Assert ((Adapt $legitimate) -ceq $legitimate) 'Unrelated taming quest or first pet changed.'
$indented = "step << Hunter`n.stable >>Stable your pet for rank learning`n step << Warrior`n.train 6673 >>Train Battle Shout`n"
Assert ((Adapt $indented) -ceq " step << Warrior`n.train 6673 >>Train Battle Shout`n") 'Indented next step was swallowed by pet removal.'

$recipe = Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-Pets335.json') -Raw | ConvertFrom-Json
$pins = Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
$hashes, $seen, $counts = @{}, @{}, @{}
foreach ($pin in $pins.blocks) { $hashes[$pin.id] = $pin.sourceHash }
foreach ($entry in $recipe.guides) {
    Assert (-not $seen.ContainsKey($entry.id) -and $hashes[$entry.id] -ceq $entry.sourceHash) 'Duplicate/unpinned pet recipe identity.'
    $seen[$entry.id] = $true
    foreach ($edit in $entry.replacements) {
        if (-not $edit.PSObject.Properties['kind']) { continue }
        Assert ($edit.kind -cin @('retain-quest-reward','retain-first-pet','remove-rank-sequence',
            'retain-class-or-pet-acquisition') -and $edit.attribution -and $edit.occurrences -ge 1) 'Unknown pet recipe category.'
        $counts[$edit.kind] += $edit.occurrences
        Assert ((Actions $edit.from) -ceq (Actions $edit.to)) 'Committed pet recipe changed quest/reward actions.'
        Assert ((Adapt $edit.from) -ceq $edit.to) 'Committed exact pet recipe no longer matches its transformer.'
    }
}
Assert ($counts['retain-quest-reward'] -eq 2 -and $counts['retain-first-pet'] -eq 2 -and
    $counts['remove-rank-sequence'] -eq 158 -and $counts['retain-class-or-pet-acquisition'] -eq 8) 'Committed pet inventory changed.'
if ($SourceRoot) {
    $index = Read-HardcoreUpstream335 $SourceRoot
    $base = Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-Compatibility335.json') -Raw | ConvertFrom-Json
    foreach ($entry in $base.guides) {
        Assert ($index[$entry.id].sourceHash -ceq $entry.sourceHash) 'Unpinned test input.'
        foreach ($edit in $entry.replacements) {
            $index[$entry.id].content = $index[$entry.id].content.Replace($edit.from,$edit.to)
        }
    }
    $counts = @{}
    foreach ($id in (Get-HardcoreSourceGraph335 $index).selected) {
        $old = $index[$id].content
        $new = Adapt $old
        foreach ($edit in @(Get-HardcorePetEdits335 $old)) { $counts[$edit.kind] += $edit.occurrences }
        Assert ((Actions $old) -ceq (Actions $new)) "Quest/reward actions changed: $id"
        $labels = '(?m)^[ \t]*#label[^\n]*'
        $oldLabels = @([regex]::Matches($old,$labels)|ForEach-Object {$_.Value.Trim()}) -join "`n"
        $newLabels = @([regex]::Matches($new,$labels)|ForEach-Object {$_.Value.Trim()}) -join "`n"
        Assert ($oldLabels -ceq $newLabels) "A dependency label was lost: $id"
        Assert ((Adapt $new) -ceq $new) "Residual pet edits: $id"
        # Ordinary first-pet casts and all non-pet player spell instructions
        # survive. Tame casts attached to a rank-learning .train are removed.
        foreach ($step in [regex]::Matches($old,'(?ms)^step\b[^\n]*\n.*?(?=^step\b|\z)')) {
            if ($step.Value -match '\.cast 1515\b' -and $step.Value -notmatch '\.train') {
                Assert ($new.Contains([regex]::Match($step.Value,'(?m)^[ \t]*\.cast 1515[^\n]*').Value)) "First-pet cast lost: $id"
            }
        }
    }
    Assert ($counts['retain-quest-reward'] -eq 2 -and $counts['retain-first-pet'] -eq 2 -and
        $counts['remove-rank-sequence'] -eq 158 -and $counts['retain-class-or-pet-acquisition'] -eq 8) 'Reviewed pet inventory changed.'
}
if ($CandidateRoot) {
    $report = Get-Content (Join-Path $CandidateRoot 'compatibility-report.json') -Raw | ConvertFrom-Json
    $recipeText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-Pets335.json'),$hardcoreUtf8)
    Assert ($report.recipeHash -ceq (Get-HardcoreHash335 $recipeText)) 'Pet candidate receipt is stale.'
    foreach ($family in @('classic','tbc')) {
        $text = Get-Content (Get-HardcoreOutputPath335 $CandidateRoot $family) -Raw
        Assert ($text -notmatch '(?m)^[ \t]*\.stable\b|petopia.com/classic/training|Attack mobs.*learn') 'Obsolete rank sequence remains.'
        if ($family -eq 'tbc') {
            foreach ($id in @(9673,9675)) {
                Assert ($text -match "\.accept $id\b" -and $text -match "\.turnin $id\b") 'Beast Training quest rewards lost.'
            }
        }
    }
}
if ($ServerSourceRoot) {
    $path = Join-Path $ServerSourceRoot 'src/server/game/Entities/Pet/Pet.cpp'
    Assert ((Get-FileHash $path).Hash.ToLowerInvariant() -ceq
        '92c16f0733c2954d96ffb1a61b8702cbc81474b936591da1a130ff782c261ec8') 'Pet implementation changed: review facts.'
    $text = Get-Content $path -Raw
    Assert ($text.Contains('void Pet::InitLevelupSpellsForLevel()') -and
        $text.Contains('learnSpell(itr->second)') -and $text.Contains('learnSpell(spellInfo->Id)')) 'Expected automatic pet learning missing.'
}
Write-Output 'Hardcore pet compatibility tests passed: rewards, class training, first pets, rank sequences and labels.'
