[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidateRoot,
    [Parameter(Mandatory=$true)][string]$HistoricalRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
# One-time extraction of necessary pinned inputs, never whole historical files.
# The public builder does not need either input directory after this export.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
$destination = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $destination) { throw 'Output already exists; use a new input snapshot directory.' }
$selection = Get-Content (Join-Path $CandidateRoot 'selection.json') -Raw | ConvertFrom-Json
$selected = Get-Content (Join-Path $CandidateRoot 'selected.json') -Raw | ConvertFrom-Json
$scope = Get-Content (Join-Path $CandidateRoot 'change-scope.json') -Raw | ConvertFrom-Json
$preview = [IO.File]::ReadAllText([IO.Path]::GetFullPath(
    (Join-Path $CandidateRoot 'Hardcore335.preview.lua')), $hardcoreUtf8)
if ($selection.schemaVersion -ne 1 -or $selection.guides.Count -ne 89 -or
    $selected.Count -ne 89 -or (Get-HardcoreHash335 $preview) -cne $scope.candidatePreviewHash) {
    throw 'Candidate recipe/output identity differs.'
}
$bySource = @{}
foreach ($record in $selected) {
    if ($bySource.ContainsKey($record.source)) { throw 'Duplicate selected source.' }
    $bySource[$record.source] = $record
}
$localBlocks = [Collections.Generic.List[object]]::new()
$historical = [IO.Path]::GetFullPath($HistoricalRoot).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
foreach ($entry in $selection.guides) {
    if (-not $bySource.ContainsKey($entry.id) -or
        $bySource[$entry.id].sourceHash -cne $entry.sourceHash) { throw 'Selection source receipt changed.' }
    if (-not $entry.id.StartsWith('local/')) { continue }
    $parts = $entry.id.Split('|')
    if ($parts.Count -ne 3) { throw 'Malformed local source identity.' }
    $relative = $parts[0].Substring(6)
    $path = [IO.Path]::GetFullPath((Join-Path $historical $relative))
    if (-not $path.StartsWith($historical, [StringComparison]::OrdinalIgnoreCase)) { throw 'Local input escapes source root.' }
    $text = [IO.File]::ReadAllText($path, $hardcoreUtf8).Replace("`r`n", "`n").Replace("`r", "`n")
    $matches = @()
    foreach ($match in [regex]::Matches($text, '(?ms)^RXPGuides\.RegisterGuide\(\[\[(.*?)^\s*\]\]\)\s*;?')) {
        $body = $match.Groups[1].Value.Trim()
        if ((Get-HardcoreHash335 $body) -ceq $entry.sourceHash) { $matches += $body }
    }
    if ($matches.Count -ne 1) { throw "Pinned historical block missing or ambiguous: $($entry.id)" }
    $localBlocks.Add([ordered]@{id=$entry.id;sourceHash=$entry.sourceHash;content=$matches[0]})
}
if ($localBlocks.Count -ne 11) { throw 'Unexpected local source block count.' }
$sources = [ordered]@{
    schemaVersion=1
    attribution='Selected RestedXP source blocks and existing RXPGuides 3.3.5 native-route adaptations. Preserve their original licenses and attribution. Build inputs only; never load directly.'
    blocks=@($localBlocks.ToArray())
}
$receipt = [ordered]@{
    schemaVersion=1; chapters=89; parentPreviewHash=$scope.candidatePreviewHash
    status='candidate-not-gameplay-accepted'
    sources=@($selection.guides | ForEach-Object { [ordered]@{id=$_.id;sourceHash=$_.sourceHash} })
}
# No machine paths, prior audit reports, server exports, or runtime data.
[IO.Directory]::CreateDirectory($destination) | Out-Null
foreach ($output in @(
    @{name='selection.json';value=$selection},
    @{name='local-sources.json';value=$sources},
    @{name='inputs.json';value=$receipt}
)) {
    [IO.File]::WriteAllText((Join-Path $destination $output.name),
        (ConvertTo-HardcoreJson335 $output.value)+"`n", $hardcoreUtf8)
}
Write-Output 'Exported 89 exact recipes and 11 pinned local blocks; historical sources and guides unchanged.'
