[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorldSqlRoot,
    [Parameter(Mandatory=$true)][string]$SourceRevision,
    [Parameter(Mandatory=$true)][string[]]$GuidePaths,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
# Extract only display facts from a local SQL text file. Never connect to a
# database, execute SQL, or copy dump headers/account/machine information.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
if($SourceRevision -cnotmatch '^[a-f0-9]{40}$'){throw 'A full attributed source revision is required.'}
$destination=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $destination){throw 'Use a new fixture output path.'}
$catalog=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../DB/wotlk/guideEnglishNames_335.lua'),$hardcoreUtf8)
$known=@{}
$block=[regex]::Match($catalog,'(?s)\bitems\s*=\s*\{(.*?)\n\s*\},')
if(-not $block.Success){throw 'English item catalog missing.'}
foreach($m in [regex]::Matches($block.Groups[1].Value,'\[(\d+)\]\s*=\s*"')){
    $known[[int]$m.Groups[1].Value]=$true
}
$needed=@{}
foreach($path in $GuidePaths){
    $text=[IO.File]::ReadAllText([IO.Path]::GetFullPath($path),$hardcoreUtf8)
    foreach($m in [regex]::Matches($text,'(?m)^[ \t]*\.collect[ \t]+(\d+)')){
        $id=[int]$m.Groups[1].Value
        if(-not $known.ContainsKey($id)){$needed[$id]=$true}
    }
}
$sql=Join-Path $WorldSqlRoot 'item_template.sql'
$columns=[Collections.Generic.List[string]]::new()
$schema=$false;$found=$false;$rows=@{}
$token="'(?:\\.|''|[^'\\])*'|NULL|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"
$tokens=[regex]::new("\G(?:\(|,)(?<value>$token)(?=,|\))")
foreach($line in [IO.File]::ReadLines($sql,$hardcoreUtf8)){
    if($line -ceq 'CREATE TABLE `item_template` ('){$schema=$true;$found=$true;continue}
    if($schema){
        if($line -match '^\s+`([^`]+)`\s'){$columns.Add($Matches[1]);continue}
        if($line -match '^\)'){
            $schema=$false
            if($columns[0] -cne 'entry' -or -not $columns.Contains('name')){throw 'Unsupported item schema.'}
        }
        continue
    }
    if(-not $line.StartsWith('(')){continue}
    if(-not $found -or $line -notmatch '^\((\d+),'){throw 'Unsupported item row.'}
    $id=[int]$Matches[1]
    if(-not $needed.ContainsKey($id)){continue}
    $fields=$tokens.Matches($line)
    if($fields.Count -ne $columns.Count -or
        $line.Substring($fields[$fields.Count-1].Index+$fields[$fields.Count-1].Length) -notmatch '^\)[,;]$'){
        throw "Unsupported selected item row: $id"
    }
    $value=$fields[$columns.IndexOf('name')].Groups['value'].Value
    if(-not $value.StartsWith("'")){throw 'Item name must be text.'}
    $name=$value.Substring(1,$value.Length-2).Replace("''","'")
    $name=[regex]::Replace($name,'\\(.)',{
        param($m)
        if($m.Groups[1].Value -cnotin @("'",'"','\')){throw 'Unsupported escape in display name.'}
        $m.Groups[1].Value
    })
    if(-not $name -or $name -match '[\x00-\x1f]' -or $rows.ContainsKey($id)){throw 'Invalid or duplicate item name.'}
    $rows[$id]=$name
}
if(-not $found -or $schema){throw 'Incomplete item schema.'}
$missing=@($needed.Keys | Where-Object {-not $rows.ContainsKey($_)} | Sort-Object)
if($missing.Count){throw "No verified item names for IDs: $($missing -join ',')"}
$fixture=[ordered]@{
    schemaVersion=1
    source="https://github.com/azerothcore/azerothcore-wotlk/blob/$SourceRevision/data/sql/base/db_world/item_template.sql"
    sourceRevision=$SourceRevision
    sourceSha256=(Get-FileHash -LiteralPath $sql -Algorithm SHA256).Hash.ToLowerInvariant()
    attribution='AzerothCore world item_template display-name facts (AGPL-3.0 source); no runtime database access.'
    scope='Missing English display names only. Does not validate item availability or guide gameplay.'
    items=@(foreach($id in ($rows.Keys | Sort-Object)){[ordered]@{id=$id;name=$rows[$id]}})
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
[IO.File]::WriteAllText($destination,(ConvertTo-HardcoreJson335 $fixture)+"`n",$hardcoreUtf8)
Write-Output ("Extracted {0} missing English item-name facts; live catalog unchanged." -f $rows.Count)
