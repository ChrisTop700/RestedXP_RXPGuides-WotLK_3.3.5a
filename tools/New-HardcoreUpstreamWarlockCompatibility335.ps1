[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Warlock335.ps1')
$index = Read-HardcoreUpstream335 $SourceRoot
$pins = Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
if ($index.Count -ne $pins.blocks.Count) { throw 'Source inventory differs.' }
foreach ($pin in $pins.blocks) {
    if (-not $index.ContainsKey($pin.id) -or $index[$pin.id].sourceHash -cne $pin.sourceHash) { throw 'Pinned source changed.' }
}
$base = Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-Racial335.json') -Raw | ConvertFrom-Json
$byId = @{}
foreach ($entry in $base.guides) { $byId[$entry.id] = $entry }
$entries = [Collections.Generic.List[object]]::new()
$counts = @{}
foreach ($id in (Get-HardcoreSourceGraph335 $index).selected) {
    $block = $index[$id]
    $body = $block.content
    $edits = @()
    if ($byId.ContainsKey($id)) {
        $entry = $byId[$id]
        if ($entry.sourceHash -cne $block.sourceHash) { throw 'Base source differs.' }
        foreach ($edit in $entry.replacements) {
            if ($body.Split(@($edit.from),[StringSplitOptions]::None).Count-1 -ne $edit.occurrences) { throw 'Base recipe stale.' }
            $body = $body.Replace($edit.from,$edit.to)
        }
        $edits += @($entry.replacements)
    }
    try {
        $starter = Get-HardcoreWarlockStarterEdit335 $body
        if ($starter) { $body = $starter.to; $edits += $starter; $counts[$starter.kind]++ }
        foreach ($edit in @(Get-HardcoreGrimoireEdits335 $body)) {
            $edits += $edit
            $counts[$edit.kind] += $edit.occurrences
        }
    } catch { throw ("Warlock review for $id : "+$_.Exception.Message) }
    if ($edits.Count) { $entries.Add([ordered]@{id=$id;sourceHash=$block.sourceHash;replacements=$edits}) }
}
if ($counts['warlock-starter'] -ne 9) { throw 'Starter inventory changed.' }
$text = (ConvertTo-HardcoreJson335 ([ordered]@{schemaVersion=1;guides=@($entries.ToArray())}))+"`n"
$destination = [IO.Path]::GetFullPath($OutputPath)
if ($Check) {
    if ([IO.File]::ReadAllText($destination,$hardcoreUtf8) -cne $text) { throw 'Warlock recipe stale.' }
} else {
    if (Test-Path -LiteralPath $destination) { throw 'Use a new recipe output path.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    [IO.File]::WriteAllText($destination,$text,$hardcoreUtf8)
}
Write-Output ("Exact Warlock adaptations: "+(ConvertTo-HardcoreJson335 $counts))
