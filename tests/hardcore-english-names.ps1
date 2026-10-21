$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-EnglishNames335.ps1')
$fixture=Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-EnglishItems335.json') -Raw | ConvertFrom-Json
$catalog=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../DB/wotlk/guideEnglishNames_335.lua'))
$merged=Merge-HardcoreEnglishItems335 $catalog $fixture
if((Merge-HardcoreEnglishItems335 $merged $fixture) -cne $merged){throw 'English merge not idempotent.'}
foreach($m in [regex]::Matches($catalog,'\[\d+\]\s*=\s*"(?:\\.|[^"\\])*",')){
    if(-not $merged.Contains($m.Value)){throw 'Existing catalog value changed.'}
}
$first=$fixture.items[0]
$same="items = {`n        [$($first.id)] = `"$($first.name)`",`n    },"
$result=Merge-HardcoreEnglishItems335 $same $fixture
if([regex]::Matches($result,'\['+[string]$first.id+'\]\s*=').Count -ne 1){throw 'Matching existing name duplicated.'}
$conflict=$same.Replace($first.name,'Incorrect fixture name')
$rejected=$false
try {Merge-HardcoreEnglishItems335 $conflict $fixture | Out-Null} catch {$rejected=$true}
if(-not $rejected){throw 'Conflicting catalog name was overwritten.'}
Write-Output ("English name merge passed: {0} pinned facts, preservation, deduplication and conflict rejection." -f $fixture.items.Count)
$quests=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../tools/data/Hardcore-QuestFacts335.json')) | ConvertFrom-Json
$merged=Merge-HardcoreEnglishQuests335 $catalog $quests
if((Merge-HardcoreEnglishQuests335 $merged $quests) -cne $merged){throw 'Quest-name merge not idempotent.'}
foreach($m in [regex]::Matches($catalog,'\[\d+\]\s*=\s*"(?:\\.|[^"\\])*",')){
    if(-not $merged.Contains($m.Value)){throw 'Existing quest catalog entry changed.'}
}
$rejected=$false
try {Merge-HardcoreEnglishQuests335 "quests = {`n [1218] = `"Soothing Spices`",`n}," $quests | Out-Null} catch {$rejected=$true}
if(-not $rejected){throw 'Conflicting quest title was overwritten.'}
& (Join-Path $PSScriptRoot 'hardcore-english-regeneration.ps1')
