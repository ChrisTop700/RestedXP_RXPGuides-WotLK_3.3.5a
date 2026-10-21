[CmdletBinding()]
param([string]$RecipePath='', [string]$WorldSqlRoot='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot '../tools/Hardcore-Demons335.ps1')
if(-not $RecipePath){$RecipePath=Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-Ferries335.json'}
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$recipe=Get-Content $RecipePath -Raw | ConvertFrom-Json
$count=0;$mixed=0
foreach($entry in $recipe.guides){
    foreach($edit in $entry.replacements){
        if($edit.kind -cne 'unavailable-incubus'){continue}
        $generated=@(Get-HardcoreDemonEdits335 $edit.from)
        Assert ($generated.Count -eq 1 -and $generated[0].to -ceq $edit.to) 'Demon recipe drift.'
        Assert (@(Get-HardcoreDemonEdits335 $edit.to).Count -eq 0) 'Demon repair not idempotent.'
        foreach($line in [regex]::Matches($edit.from,'(?m)^[ \t]*\.(?:accept|turnin|complete) (?:1716|1738|1739)\b[^\n]*')){
            Assert ($edit.to.Contains($line.Value)) 'WotLK Succubus action removed.'
        }
        $count+=$edit.occurrences
        if($edit.to){$mixed+=$edit.occurrences}
    }
}
Assert ($count -eq 16 -and $mixed -eq 3) 'Incubus replacement inventory changed.'
$facts=Get-Content (Join-Path $PSScriptRoot 'fixtures/hardcore-demons335.json') -Raw | ConvertFrom-Json
if($WorldSqlRoot){
    foreach($table in @('quest_template','item_template')){
        $path=Join-Path $WorldSqlRoot ($table+'.sql')
        $expected=if($table -eq 'quest_template'){$facts.questTemplateSha256}else{$facts.itemTemplateSha256}
        Assert ((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ceq $expected) 'Source fixture is stale.'
        $absent=if($table -eq 'quest_template'){$facts.absentQuests}else{$facts.absentItems}
        $present=@{}
        foreach($line in [IO.File]::ReadLines($path)){
            if($line -match '^\((\d+),'){$present[[int]$Matches[1]]=$true}
        }
        foreach($id in $absent){Assert (-not $present.ContainsKey([int]$id)) 'An excluded ID is present in the pinned source.'}
        if($table -eq 'quest_template'){
            foreach($id in $facts.presentQuests){Assert ($present.ContainsKey([int]$id)) 'Retained quest absent from source.'}
        }
    }
}
Write-Output 'Demon compatibility passed: 13 unavailable-only steps removed, three mixed steps preserve WotLK quests and rewards.'
