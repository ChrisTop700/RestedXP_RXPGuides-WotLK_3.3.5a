$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Locations335.ps1')
$root=Split-Path $PSScriptRoot -Parent
$fixture=[IO.File]::ReadAllText((Join-Path $root 'tools/data/Hardcore-Locations335.json')) | ConvertFrom-Json
$catalog=[IO.File]::ReadAllText((Join-Path $root 'Compat/LocationLocales335.lua'))
$result=Merge-HardcoreLocations335 $catalog $fixture
if($result -cne $catalog.Replace("`r`n","`n")){throw 'Committed location additions differ from fixture.'}
if((Merge-HardcoreLocations335 $result $fixture) -cne $result){throw 'Location merge is not idempotent.'}
$pairs=Read-HardcoreLuaPairs335 "    Westfall = `"bare`",`n    [`"Redridge Mountains`"] = `"quoted`",`n    [`"name`"] = `"lower`",`n    [`"Name`"] = `"upper`",`n"
if($pairs.Count -ne 4 -or $pairs['Westfall'] -cne 'bare' -or $pairs['Redridge Mountains'] -cne 'quoted' -or
    $pairs['name'] -cne 'lower' -or $pairs['Name'] -cne 'upper'){throw 'Lua translation key extraction lost bare/quoted/case identity.'}
foreach($mutate in @(
    {param($f) $f.areas[0].name='conflicting name'},
    {param($f) $f.areas[0].locales.deDE='conflicting translation'},
    {param($f) $f.areas+=@($f.areas[0])},
    {param($f) $f.areas[0].locales.frFR=''},
    {param($f) $f.legacyRevision=25}
)){
    $f=[IO.File]::ReadAllText((Join-Path $root 'tools/data/Hardcore-Locations335.json')) | ConvertFrom-Json
    & $mutate $f
    $rejected=$false
    try {Merge-HardcoreLocations335 $catalog $f | Out-Null} catch {$rejected=$true}
    if(-not $rejected){throw 'Invalid location fixture was accepted.'}
}
Write-Output 'Location fixture passed: preservation, idempotence, bare/quoted keys and five conflict/malformed cases.'
