[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$ExpectedOutputHash='',
    [switch]$Check
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Ferries335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Demons335.ps1')
$index=Read-HardcoreUpstream335 $SourceRoot
$pins=Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
if($index.Count -ne $pins.blocks.Count){throw 'Source inventory differs.'}
foreach($pin in $pins.blocks){
    if(-not $index.ContainsKey($pin.id) -or $index[$pin.id].sourceHash -cne $pin.sourceHash){throw 'Pinned source changed.'}
}
$base=Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-Travel335.json') -Raw | ConvertFrom-Json
$byId=@{};foreach($entry in $base.guides){$byId[$entry.id]=$entry}
$entries=[Collections.Generic.List[object]]::new()
$counts=[Collections.Generic.SortedDictionary[string,int]]::new([StringComparer]::Ordinal)
foreach($id in (Get-HardcoreSourceGraph335 $index).selected){
    $block=$index[$id];$body=$block.content;$edits=@()
    if($byId.ContainsKey($id)){
        $entry=$byId[$id]
        if($entry.sourceHash -cne $block.sourceHash){throw 'Base source differs.'}
        foreach($edit in $entry.replacements){
            if($body.Split(@($edit.from),[StringSplitOptions]::None).Count-1 -ne $edit.occurrences){throw 'Base recipe stale.'}
            $body=$body.Replace($edit.from,$edit.to)
        }
        $edits+=@($entry.replacements)
    }
    foreach($edit in @(Get-HardcoreFerryEdits335 $body $block.family $block.name)){
        $edits+=$edit
        $counts[$edit.kind]+=$edit.occurrences
        $body=$body.Replace($edit.from,$edit.to)
    }
    foreach($edit in @(Get-HardcoreDemonEdits335 $body)){
        $edits+=$edit
        $counts[$edit.kind]+=$edit.occurrences
    }
    if($edits.Count){$entries.Add([ordered]@{id=$id;sourceHash=$block.sourceHash;replacements=$edits})}
}
$text=(ConvertTo-HardcoreJson335 ([ordered]@{schemaVersion=1;guides=@($entries.ToArray())}))+"`n"
$destination=[IO.Path]::GetFullPath($OutputPath)
if($Check){
    if([IO.File]::ReadAllText($destination,$hardcoreUtf8) -cne $text){throw 'Ferry recipe stale.'}
} else {
    if(Test-Path -LiteralPath $destination){
        if(-not $ExpectedOutputHash -or
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedOutputHash){
            throw 'Use a new output path or supply the exact previous generated-file hash.'
        }
    }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    [IO.File]::WriteAllText($destination,$text,$hardcoreUtf8)
}
Write-Output ("Exact ferry adaptations: "+(ConvertTo-HardcoreJson335 $counts))
