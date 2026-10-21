[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Racial335.ps1')
$index = Read-HardcoreUpstream335 $SourceRoot
$base = Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-Pets335.json') -Raw | ConvertFrom-Json
$pins = Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
if ($index.Count -ne $pins.blocks.Count) { throw 'Source inventory differs.' }
foreach ($pin in $pins.blocks) {
    if (-not $index.ContainsKey($pin.id) -or $index[$pin.id].sourceHash -cne $pin.sourceHash) { throw 'Pinned source changed.' }
}
$selected = @((Get-HardcoreSourceGraph335 $index).selected)
$id = @($selected | Where-Object {
    $index[$_].family -ceq 'tbc' -and $index[$_].name -ceq '1-6 Eversong Woods'
})
if ($id.Count -ne 1) { throw 'Ambiguous Blood Elf starter.' }
$id = $id[0]
$body = $index[$id].content
$entries = [Collections.Generic.List[object]]::new()
$found = $false
foreach ($entry in $base.guides) {
    if ($entry.id -ceq $id) {
        if ($entry.sourceHash -cne $index[$id].sourceHash) { throw 'Base recipe identity differs.' }
        foreach ($edit in $entry.replacements) {
            if ($body.Split(@($edit.from),[StringSplitOptions]::None).Count-1 -ne $edit.occurrences) { throw 'Stale base recipe.' }
            $body = $body.Replace($edit.from,$edit.to)
        }
        $entry.replacements = @($entry.replacements) + @(Get-HardcoreBloodElfRacialEdit335 $body)
        $found = $true
    }
    $entries.Add($entry)
}
if (-not $found) {
    $entries.Add([ordered]@{id=$id;sourceHash=$index[$id].sourceHash
        replacements=@(Get-HardcoreBloodElfRacialEdit335 $body)})
}
# Same ordinal ordering as the pinned graph rather than host-culture ordering.
$byId = @{}
foreach ($entry in $entries) { $byId[$entry.id] = $entry }
$ordered = @($selected | Where-Object {$byId.ContainsKey($_)} | ForEach-Object {$byId[$_]})
$text = (ConvertTo-HardcoreJson335 ([ordered]@{schemaVersion=1;guides=$ordered}))+"`n"
$destination = [IO.Path]::GetFullPath($OutputPath)
if ($Check) {
    if ([IO.File]::ReadAllText($destination,$hardcoreUtf8) -cne $text) { throw 'Racial recipe stale.' }
} else {
    if (Test-Path -LiteralPath $destination) { throw 'Use a new output path.' }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    [IO.File]::WriteAllText($destination,$text,$hardcoreUtf8)
}
Write-Output 'Exact Blood Elf racial correction prepared; Warlock starter and travel adaptations remain separate.'
