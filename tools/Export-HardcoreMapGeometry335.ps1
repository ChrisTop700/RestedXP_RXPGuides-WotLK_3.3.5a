[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$MapDataPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
# Extract only geometry used by pinned guides. Third-party data is read-only;
# the resulting fixture has no dependency on its provider at runtime or in CI.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Coordinates335.ps1')
if (Test-Path -LiteralPath $OutputPath) { throw 'Use a new fixture path; do not overwrite reviewed geometry.' }
$index = Read-HardcoreUpstream335 $SourceRoot
$lock = Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
foreach ($block in $lock.blocks) {
    if (-not $index.ContainsKey($block.id) -or
        $index[$block.id].sourceHash -cne $block.sourceHash) { throw 'Pinned source differs.' }
}
$required = @{}
foreach ($id in (Get-HardcoreSourceGraph335 $index).selected) {
    foreach ($point in [regex]::Matches($index[$id].content,
        '(?m)^[ \t]*\.(?:goto|groundgoto|flygoto|waypoint)[ \t]+(\d+/\d+),')) {
        $required[$point.Groups[1].Value] = $true
    }
}
$mapText = [IO.File]::ReadAllText([IO.Path]::GetFullPath($MapDataPath), $hardcoreUtf8).Replace("`r`n", "`n")
$culture = [Globalization.CultureInfo]::InvariantCulture
$found = @{}
foreach ($match in [regex]::Matches($mapText, '(?ms)^\s*\[(\d+)\]\s*=\s*\{(.*?)^\s*\},')) {
    $body = $match.Groups[2].Value
    $instance = [regex]::Match($body, '\["instance"\]\s*=\s*(-?\d+)').Groups[1].Value
    $key = $match.Groups[1].Value + '/' + $instance
    if (-not $required.ContainsKey($key)) { continue }
    if ($found.ContainsKey($key)) { throw 'Duplicate map record.' }
    $values = foreach ($n in 1..4) {
        $number = [regex]::Match($body, '\[' + $n + '\]\s*=\s*(-?[\d.]+)').Groups[1].Value
        [double]::Parse($number, $culture)
    }
    $found[$key] = [ordered]@{
        name = [regex]::Match($body, '\["name"\]\s*=\s*"([^"]+)"').Groups[1].Value
        width = $values[0]; height = $values[1]; left = $values[2]; top = $values[3]
    }
    $null = Convert-HardcoreWorldPoint335 $found[$key] $values[2] $values[3]
}
$maps = [ordered]@{}
foreach ($key in (Sort-HardcoreStrings335 $required.Keys)) {
    if (-not $found.ContainsKey($key)) { throw "Geometry missing: $key" }
    $maps[$key] = $found[$key]
}
$fixture = [ordered]@{
    schemaVersion = 1
    source = [ordered]@{
        project = 'Questie 3.3.5 compatibility map data'
        file = 'Compat/UiMapData.lua'; sha256 = Get-HardcoreHash335 $mapText
        attribution = 'Legacy map geometry facts; retain source attribution. No Questie code is loaded or modified.'
    }
    convention = 'horizontal/vertical world yards; percent=100*(left/top-world)/width/height'
    maxRoundTripErrorYards = 0.001
    maps = $maps
}
$destination = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
[IO.File]::WriteAllText($destination, (ConvertTo-HardcoreJson335 $fixture) + "`n", $hardcoreUtf8)
Write-Output "Extracted $($maps.Count) attributed map records; no source files changed."
