[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$CuratedSelection,
    [Parameter(Mandatory=$true)][string]$CuratedCandidate,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Labels335.ps1')
$destination=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $destination){throw 'Use a new candidate directory.'}
$index=Read-HardcoreUpstream335 $SourceRoot
$recipe=Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-Ferries335.json') -Raw | ConvertFrom-Json
$byId=@{};foreach($e in $recipe.guides){$byId[$e.id]=$e}
$entries=[Collections.Generic.List[object]]::new()
$changes=[Collections.Generic.List[object]]::new()
foreach($id in (Get-HardcoreSourceGraph335 $index).selected) {
    $b=$index[$id]; $body=$b.content; $replacements=@()
    if($byId.ContainsKey($id)) {
        $e=$byId[$id]
        if($e.sourceHash -cne $b.sourceHash){throw 'Source hash differs.'}
        foreach($r in $e.replacements) {
            if($body.Split(@($r.from),[StringSplitOptions]::None).Count-1 -ne $r.occurrences){throw 'Parent recipe changed.'}
            $body=$body.Replace($r.from,$r.to)
        }
        $replacements=@($e.replacements)
    }
    $edits=@(Get-HardcoreLabelEdits335 $body $b.family $b.name)
    foreach($edit in $edits){$changes.Add([ordered]@{family=$b.family;id=$id;reason=$edit.reason})}
    $replacements+=$edits
    if($replacements.Count){$entries.Add([ordered]@{id=$id;sourceHash=$b.sourceHash;replacements=$replacements})}
}
$selection=Get-Content -LiteralPath $CuratedSelection -Raw | ConvertFrom-Json
$selected=Get-Content -LiteralPath (Join-Path $CuratedCandidate 'selected.json') -Raw | ConvertFrom-Json
$byKey=@{};foreach($r in $selected){$byKey[$r.key]=$r}
$bySource=@{};foreach($r in $selection.guides){$bySource[$r.id]=$r}
$text=[IO.File]::ReadAllText([IO.Path]::GetFullPath((Join-Path $CuratedCandidate 'Hardcore335.preview.lua')),$hardcoreUtf8)
$chapters=0
foreach($m in [regex]::Matches($text,'(?ms)^RXPGuides\.RegisterGuide\(\[\[(.*?)^\s*\]\]\)')) {
    $body=$m.Groups[1].Value.Trim()+"`n"
    $group=@(Get-HardcoreHeader335 $body 'group')[0];$name=@(Get-HardcoreHeader335 $body 'name')[0]
    $record=$byKey["$group|$name"]
    if(-not $record -or (Get-HardcoreHash335 $body) -cne $record.outputHash){throw 'Curated body receipt differs.'}
    $entry=$bySource[$record.source]
    if(-not $entry -or $entry.sourceHash -cne $record.sourceHash){throw 'Curated source differs.'}
    $edits=@(Get-HardcoreLabelEdits335 $body 'curated' $name)
    if($edits.Count){
        $entry.replacements=@($entry.replacements)+$edits
        $entry | Add-Member -NotePropertyName reviewedHash -NotePropertyValue '' -Force
        foreach($edit in $edits){$changes.Add([ordered]@{family='curated';id=$record.source;reason=$edit.reason})}
    }
    $chapters++
}
if($chapters -ne 89){throw 'Curated chapter inventory changed.'}
[IO.Directory]::CreateDirectory($destination) | Out-Null
[IO.File]::WriteAllText((Join-Path $destination 'upstream.json'),(ConvertTo-HardcoreJson335 ([ordered]@{schemaVersion=1;guides=@($entries.ToArray())}))+"`n",$hardcoreUtf8)
[IO.File]::WriteAllText((Join-Path $destination 'curated.json'),(ConvertTo-HardcoreJson335 $selection)+"`n",$hardcoreUtf8)
[IO.File]::WriteAllText((Join-Path $destination 'repairs.json'),(ConvertTo-HardcoreJson335 @($changes.ToArray()))+"`n",$hardcoreUtf8)
Write-Output "Generated $($changes.Count) reviewed label/control repairs; historical recipes and live guides unchanged."
