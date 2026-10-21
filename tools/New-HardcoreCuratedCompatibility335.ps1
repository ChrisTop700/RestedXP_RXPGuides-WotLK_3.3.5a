[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$ParentCandidateRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [switch]$RepairBranchLabels
)
# Narrow supplement to the already-curated collection. Does not import any
# upstream itinerary, change canonical identities, or modify historical output.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Warlock335.ps1')
$destination = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $destination) { throw 'Use a new candidate directory.' }
$inputRoot = Join-Path $PSScriptRoot 'data/Hardcore-Curated335'
$selection = Get-Content (Join-Path $inputRoot 'selection.json') -Raw | ConvertFrom-Json
$inputs = Get-Content (Join-Path $inputRoot 'inputs.json') -Raw | ConvertFrom-Json
$before = [IO.File]::ReadAllText([IO.Path]::GetFullPath(
    (Join-Path $ParentCandidateRoot 'Hardcore335.preview.lua')), $hardcoreUtf8)
if ((Get-HardcoreHash335 $before) -cne $inputs.parentPreviewHash) { throw 'Pinned curated parent differs.' }
$selected = Get-Content (Join-Path $ParentCandidateRoot 'selected.json') -Raw | ConvertFrom-Json
$recipes = Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-Compatibility335.json') -Raw | ConvertFrom-Json
$byId, $byKey, $expected = @{}, @{}, @{}
foreach ($entry in $selection.guides) { $byId[$entry.id] = $entry }
foreach ($entry in $selected) { $byKey[$entry.key] = $entry }
$shared = @{}
foreach ($entry in $recipes.guides) { $shared[$entry.id] = $entry }
$changes = [Collections.Generic.List[object]]::new()
$petSteps, $runes = 0, 0
$grimoireSteps = 0
$branchLabels = 0
function Edit([string]$From, [string]$To, [string]$Reason) {
    $count = $script:body.Split(@($From), [StringSplitOptions]::None).Count - 1
    if (-not $From -or $count -lt 1) { throw 'Exact curated compatibility edit no longer matches.' }
    $script:edits.Add([ordered]@{from=$From;to=$To;reason=$Reason;occurrences=$count})
    $script:body = $script:body.Replace($From, $To)
}
foreach ($match in [regex]::Matches($before, '(?ms)^RXPGuides\.RegisterGuide\(\[\[(.*?)^\s*\]\]\)')) {
    $original = $match.Groups[1].Value.Trim()+"`n"
    $header = ($original -split '(?m)^step\b',2)[0]
    $key = @(Get-HardcoreHeader335 $header 'group')[0]+'|'+@(Get-HardcoreHeader335 $header 'name')[0]
    $record = $byKey[$key]
    if (-not $record -or (Get-HardcoreHash335 $original) -cne $record.outputHash) { throw 'Parent chapter receipt differs.' }
    $recipe = $byId[$record.source]
    if (-not $recipe -or $recipe.sourceHash -cne $record.sourceHash) { throw 'Curated source identity differs.' }
    $script:body = $original
    $script:edits = [Collections.Generic.List[object]]::new()
    if ($shared.ContainsKey($record.source)) {
        $entry = $shared[$record.source]
        if ($entry.sourceHash -cne $record.sourceHash) { throw 'Shared facts refer to a different upstream revision.' }
        foreach ($edit in $entry.replacements) {
            if ($edit.reason -match '^(?:Quest33|Correct the existing optional Kodo|Remove a post-WotLK spell sentinel)' -and
                $script:body.Contains($edit.from)) {
                Edit $edit.from $edit.to $edit.reason
            }
        }
    }
    foreach ($step in [regex]::Matches($script:body, '(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)')) {
        $text = $step.Value
        if ($text -notmatch '(?m)^[ \t]*\.train (?:2981|14926|24494)\b' -and
            $text -notmatch '\.trainer >>Upgrade your pet''s abilities|\.train 5118 >>Train your pet spells') { continue }
        if ($text -notmatch '^[ \t]*step << (?:Hunter|Dwarf Hunter|Warlock)\s*\n') { throw 'Unexpected class for obsolete pet instruction.' }
        # These six reviewed steps are pet-only, never taming-quest rewards.
        foreach ($tag in [regex]::Matches($text, '(?m)^[ \t]*\.([A-Za-z]+)\b')) {
            if ($tag.Groups[1].Value -cnotin @('goto','train','trainer','link','unitscan','target','xp','dungeon')) {
                throw "Mixed pet/quest step requires explicit review: $key"
            }
        }
        $start = [regex]::Match($text, '^[ \t]*step[^\n]*\n').Value
        $new = $start + "    #optional`n"
        # Preserve stable labels and branch eligibility, not obsolete pet-only
        # path loops or completewith dependencies.
        foreach ($line in $text.Split("`n")) {
            if ($line -match '^[ \t]*(?:#label[ \t]+|\.(?:xp|dungeon)[ \t]+)') { $new += $line+"`n" }
        }
        if ($text.Contains('Strigid Hunter')) {
            $new += "    +If you do not yet have a permanent pet, you may tame a Strigid Hunter in Teldrassil. Otherwise keep your existing pet. WotLK pets learn their family ability ranks as they level; no Claw-learning detour or abandonment is required. Check this reminder when ready to continue.`n"
        } elseif ($text.Contains('Martha Strain')) {
            $new += "    +Inspect your demon's spellbook after leveling. Do not visit a Classic pet-grimoire vendor for this reminder; ordinary Warlock class training remains in the surrounding steps.`n"
        } else {
            $new += "    +Keep your current pet and inspect its spellbook and talent tab. WotLK pets learn family ability ranks as they level; do not abandon or stable a pet to acquire a rank, or buy pet spells from a Classic pet trainer. Player abilities are learned from your class trainer.`n"
        }
        Edit $text $new 'Replace a reviewed obsolete pet-only instruction with an optional spellbook reminder; preserve legitimate taming quests, rewards, labels and class/dungeon branches.'
        $petSteps++
    }
    $old = "    .train 1130 >> |cRXP_WARN_Make sure you have trained Hunter's Mark. You will need it to get a rune soon|r"
    if ($script:body.Contains($old)) {
        Edit $old "    .train 1130 >>Train Hunter's Mark from your Hunter trainer if you have not learned it" 'Retain valid Hunter spell1130 without the unrelated Season of Discovery rune claim.'
        $runes++
    }
    foreach ($edit in @(Get-HardcoreGrimoireEdits335 $script:body)) {
        Edit $edit.from $edit.to $edit.reason
        $grimoireSteps += $edit.occurrences
    }
    if ($RepairBranchLabels -and $key -ceq 'RestedXP Hardcore Guides (A)|51-52 Blasted Lands') {
        $from="#requires Helboars`n"
        if ($script:body.Split(@($from),[StringSplitOptions]::None).Count-1 -ne 1 -or
            $script:body -notmatch '(?m)^step << Warrior\n#label Helboars\n') {
            throw 'Curated Helboars branch no longer matches its reviewed scope.'
        }
        Edit $from "#requires Helboars << Warrior`n" 'Keep the reward step universal, but require the Warrior-only Helboars objective only on Warrior. All other actions, ordering and travel remain unchanged.'
        $branchLabels++
    }
    if ($script:edits.Count) {
        $recipe.replacements = @($recipe.replacements) + @($script:edits.ToArray())
        $recipe | Add-Member -NotePropertyName reviewedHash -NotePropertyValue '' -Force
        $changes.Add([ordered]@{key=$key;source=$record.source;before=$record.outputHash
            after=Get-HardcoreHash335 $script:body;edits=@($script:edits.ToArray())})
    }
    $expected[$key] = $script:body
}
if ($expected.Count -ne 89 -or $petSteps -ne 6 -or $runes -ne 1 -or
    $grimoireSteps -ne 0 -or $branchLabels -ne [int][bool]$RepairBranchLabels) {
    throw "Reviewed curated scope changed: chapters=$($expected.Count), pet=$petSteps, rune=$runes, grimoire=$grimoireSteps."
}
[IO.Directory]::CreateDirectory($destination) | Out-Null
$selectionPath = Join-Path $destination 'selection.json'
[IO.File]::WriteAllText($selectionPath,(ConvertTo-HardcoreJson335 $selection)+"`n",$hardcoreUtf8)
& (Join-Path $PSScriptRoot 'Build-HardcoreGuides335.ps1') -SourceRoot $SourceRoot `
    -SelectionPath $selectionPath -OutputRoot (Join-Path $destination 'candidate') -Preview
$after = [IO.File]::ReadAllText((Join-Path $destination 'candidate/Hardcore335.preview.lua'),$hardcoreUtf8)
$count = 0
foreach ($match in [regex]::Matches($after,'(?ms)^RXPGuides\.RegisterGuide\(\[\[(.*?)^\s*\]\]\)')) {
    $body = $match.Groups[1].Value.Trim()+"`n"
    $header = ($body -split '(?m)^step\b',2)[0]
    $key = @(Get-HardcoreHeader335 $header 'group')[0]+'|'+@(Get-HardcoreHeader335 $header 'name')[0]
    if (-not $expected.ContainsKey($key) -or $expected[$key] -cne $body) { throw 'Regeneration changed an unselected instruction.' }
    $count++
}
if ($count -ne 89) { throw 'Regeneration changed the chapter count.' }
$report = [ordered]@{schemaVersion=1;status='candidate-not-gameplay-accepted';chapters=89
    parentPreviewHash=Get-HardcoreHash335 $before;candidatePreviewHash=Get-HardcoreHash335 $after
    changed=@($changes.ToArray());unchangedChapters=89-$changes.Count;petSteps=$petSteps
    grimoireSteps=$grimoireSteps;steps=Get-HardcoreStepCount335 $after}
if ($RepairBranchLabels) { $report.branchLabels=$branchLabels }
[IO.File]::WriteAllText((Join-Path $destination 'compatibility-report.json'),
    (ConvertTo-HardcoreJson335 $report)+"`n",$hardcoreUtf8)
Write-Output "Curated compatibility candidate: $($changes.Count) exact changed chapters; $(89-$changes.Count) unchanged. No manifest change or gameplay approval."
