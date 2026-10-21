$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scratch=Join-Path $root ('build/hardcore-english-regression/'+[guid]::NewGuid().ToString('N'))
$utf8=New-Object Text.UTF8Encoding($false)
[IO.Directory]::CreateDirectory((Join-Path $scratch 'DB/wotlk')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $scratch 'Guides')) | Out-Null
[IO.File]::WriteAllText((Join-Path $scratch 'GuideList_335.xml'),'<Ui><Script file="Guides\fixture.lua"/></Ui>',$utf8)
[IO.File]::WriteAllText((Join-Path $scratch 'Guides/fixture.lua'),".collect 23676,6 --Moongraze Stag Tenderloin (x6) before accepting the quest`n.collect 16762,1`n",$utf8)
$catalog="quests = {`n    [999999] = `"Fixture-only preserved title`",`n},`nitems = {`n    [16762] = `"Fathom Core`",`n    [23676] = `"Moongraze Stag Tenderloin`",`n    [39371] = `"Keleseth's Persuader`",`n},`n"
$catalogPath=Join-Path $scratch 'DB/wotlk/guideEnglishNames_335.lua'
[IO.File]::WriteAllText($catalogPath,$catalog,$utf8)
$builder=Join-Path $root 'tools/Build-GuideEnglishNames335.ps1'
$first=Join-Path $scratch 'first.lua';$second=Join-Path $scratch 'second.lua'
& $builder -ReferenceRoot $scratch -AddonRoot $scratch -OutputPath $first
& $builder -ReferenceRoot $scratch -AddonRoot $scratch -OutputPath $second
if((Get-FileHash $first).Hash -cne (Get-FileHash $second).Hash){throw 'English regeneration is not deterministic.'}
$text=[IO.File]::ReadAllText($first,$utf8)
foreach($title in @('[1218] = "Marsh Frog Legs"','[999999] = "Fixture-only preserved title"')){
    if(-not $text.Contains($title)){throw 'Regeneration lost a verified or existing quest name.'}
}
foreach($value in @('[16762] = "Fathom Core"','[23676] = "Moongraze Stag Tenderloin"',"[39371] = `"Keleseth's Persuader`"")){
    if(-not $text.Contains($value)){throw 'Full English build lost an existing reviewed entry.'}
}
$fixture=Get-Content (Join-Path $root 'tools/data/Hardcore-EnglishItems335.json') -Raw | ConvertFrom-Json
foreach($entry in $fixture.items){
    $line='[{0}] = "{1}"' -f $entry.id,$entry.name.Replace('\','\\').Replace('"','\"')
    if(-not $text.Contains($line)){throw 'Full English build lost a pinned Hardcore entry.'}
}
foreach($id in @(2931,$fixture.items[0].id)){
    [IO.File]::WriteAllText($catalogPath,$catalog.Replace("},",("    [{0}] = `"Incorrect name`",`n}}," -f $id)),$utf8)
    $output=Join-Path $scratch ("rejected-$id.lua")
    $rejected=$false
    try {& $builder -ReferenceRoot $scratch -AddonRoot $scratch -OutputPath $output} catch {$rejected=$true}
    if(-not $rejected -or (Test-Path -LiteralPath $output)){throw 'Conflicting reviewed name was emitted.'}
}
Write-Output 'Full English regeneration passed: existing names, all pinned additions, deterministic output and conflict rejection without external references.'
