[CmdletBinding()]
param(
    [string]$CandidateRoot = '',
    [string]$ServerSourceRoot = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
function Assert($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$recipe = Get-Content (Join-Path $root 'tools/data/Hardcore-Upstream-Compatibility335.json') -Raw | ConvertFrom-Json
$pins = Get-Content (Join-Path $root 'tools/data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
$byId = @{}
foreach ($pin in $pins.blocks) { $byId[$pin.id] = $pin.sourceHash }
$seen = @{}
$coordinates, $projections, $entries, $riding, $wolves = 0, 0, 0, 0, 0
foreach ($guide in $recipe.guides) {
    Assert (-not $seen.ContainsKey($guide.id)) 'Duplicate adaptation identity.'
    $seen[$guide.id] = $true
    Assert ($byId[$guide.id] -ceq $guide.sourceHash) 'Unpinned adaptation.'
    foreach ($change in $guide.replacements) {
        Assert ($change.from -is [string] -and $change.from -and
            $change.to -is [string] -and $change.reason -is [string] -and
            $change.reason -and $change.occurrences -ge 1) 'Invalid exact replacement.'
        if ($change.reason.StartsWith('Convert world-yard')) { $coordinates += $change.occurrences }
        if ($change.from -match '(?m)^[ \t]*\.xpto60(?:hc)?\b') {
            $projections += $change.occurrences
            Assert ($change.to -match 'Manual XP checkpoint' -and $change.to -notmatch '\.xp 60') 'Forecast became premature level60 grind.'
        }
        if ($change.from -match '(?m)^[ \t]*\.zone 721,2\b') {
            $entries += $change.occurrences
            Assert ($change.to -match '(?m)^[ \t]*\+' -and $change.to -notmatch '\.zone') 'Unverified instance map auto-completes.'
        }
        if ($change.from -match '\.train 132245\b') {
            $riding += $change.occurrences
            Assert ($change.to -match '\.train 33388\b' -and $change.to -match '\.xp <20,1' -and
                $change.to -match '\.money <4\b' -and $change.to -match 'mount costs extra') 'Riding budget/skill semantics changed.'
        }
        if ($change.reason.StartsWith('Quest33')) { $wolves += $change.occurrences }
        # None of these narrow adaptations may remove/insert/reorder a quest,
        # objective, collection or abandonment action.
        $actions = '(?m)^[ \t]*\.(?:accept|turnin|complete|collect|abandon)[ \t]+([^>\r\n]+)'
        function Actions([string]$Text) {
            @([regex]::Matches($Text, $actions) | ForEach-Object {
                ($_.Value -split '[ \t]*(?:>>|<<|--)')[0].Trim()
            }) -join "`n"
        }
        Assert ((Actions $change.from) -ceq (Actions $change.to)) 'Mechanical repair changed quest actions.'
    }
}
Assert ($coordinates -eq 369 -and $projections -eq 5 -and $entries -eq 4 -and $riding -eq 5 -and $wolves -gt 0) 'Compatibility repair inventory changed.'
if ($CandidateRoot) {
    $report = Get-Content (Join-Path $CandidateRoot 'compatibility-report.json') -Raw | ConvertFrom-Json
    Assert ($report.guides.Count -eq 169 -and $report.graph.issues.Count -eq 0 -and
        -not $report.gameplayAccepted) 'Candidate identity/status changed.'
    $currentRecipe = [IO.File]::ReadAllText((Join-Path $root 'tools/data/Hardcore-Upstream-Compatibility335.json'), $hardcoreUtf8)
    Assert ($report.recipeHash -ceq (Get-HardcoreHash335 $currentRecipe)) 'Candidate recipe receipt stale.'
    foreach ($family in @('classic','tbc')) {
        $text = [IO.File]::ReadAllText((Get-HardcoreOutputPath335 $CandidateRoot $family), $hardcoreUtf8)
        Assert ($text -notmatch '(?m)^[ \t]*\.(?:xpto60|xpto60hc)\b') 'Unsupported projection remains.'
        Assert ($text -notmatch '(?m)^[ \t]*\.(?:goto|waypoint|groundgoto|flygoto)[ \t]+\d+/\d+,') 'World-coordinate API misuse remains.'
        Assert ($text -notmatch '(?m)^[ \t]*\.train (?:132245|408443)\b') 'Unsupported training sentinel remains.'
        Assert ($text -notmatch '(?m)^[ \t]*\.zone 721,2\b') 'Area-as-map check remains.'
    }
}
if ($ServerSourceRoot) {
    $facts = Get-Content (Join-Path $PSScriptRoot 'fixtures/hardcore-compatibility-facts335.json') -Raw | ConvertFrom-Json
    foreach ($file in $facts.source.files.PSObject.Properties) {
        Assert ((Get-FileHash (Join-Path $ServerSourceRoot $file.Name)).Hash.ToLowerInvariant() -ceq $file.Value) 'Source facts changed; review before updating fixture.'
    }
    $loot = [IO.File]::ReadAllText((Join-Path $ServerSourceRoot 'data/sql/base/db_world/creature_loot_template.sql'))
    foreach ($npc in $facts.northshire.creatures) {
        Assert ($loot -match ('(?m)^\('+$npc.lootEntry+',50432,')) 'Wolves no longer drop the quest item.'
    }
    $trainers = [IO.File]::ReadAllText((Join-Path $ServerSourceRoot 'data/sql/base/db_world/creature_default_trainer.sql'))
    $spells = [IO.File]::ReadAllText((Join-Path $ServerSourceRoot 'data/sql/base/db_world/trainer_spell.sql'))
    Assert ($trainers -match '(?m)^\(3690,42\)' -and
        $spells -match '(?m)^\(42,33388,40000,762,0,0,0,0,20,0\)') 'Riding trainer fact differs.'
}
Write-Output 'Targeted Hardcore compatibility checks passed; pet/starter/travel reviews and gameplay acceptance remain separate.'
