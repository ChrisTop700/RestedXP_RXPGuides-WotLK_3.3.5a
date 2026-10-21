[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [string]$LockPath = ''
)
# Inventory/selection only. Deliberately no release-manifest writes: source
# graph reachability cannot certify training, travel or filtered player paths.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
$destination = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $destination) { throw 'Use a new output directory; previous evidence is immutable.' }
$index = Read-HardcoreUpstream335 $SourceRoot
$graph = Get-HardcoreSourceGraph335 $index
$records = @(Sort-HardcoreRecords335 $index.Values @('id') | ForEach-Object {
    [ordered]@{id=$_.id; sourceHash=$_.sourceHash}
})
$lock = [ordered]@{
    schemaVersion=1; upstreamVersion='v4.11.11'
    attribution='RestedXP Guides. Preserve upstream license and source notices.'
    blocks=$records
}
$json = (ConvertTo-HardcoreJson335 $lock) + "`n"
if ($LockPath) {
    $expected = [IO.File]::ReadAllText([IO.Path]::GetFullPath($LockPath), $hardcoreUtf8) | ConvertFrom-Json
    if ($expected.schemaVersion -ne 1 -or $expected.upstreamVersion -cne 'v4.11.11') { throw 'Invalid source lock.' }
    if ($expected.blocks.Count -ne $records.Count) { throw 'Source block inventory changed.' }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $expected.blocks) {
        if (-not $seen.Add($entry.id) -or -not $index.ContainsKey($entry.id) -or
            $entry.sourceHash -cne $index[$entry.id].sourceHash) {
            throw "Source changed: $($entry.id)"
        }
    }
}
$report = [ordered]@{
    schemaVersion=1
    sourceSignature=Get-HardcoreHash335 $json
    status='staged-source-graph-only'
    scope='Union of authored transitions. Missing alternatives require review; filtered paths and WotLK compatibility are not certified.'
    roots=$graph.roots; selected=$graph.selected; excluded=$graph.excluded
    edges=$graph.edges; issues=$graph.issues
    families=@('tbc','classic' | ForEach-Object {
        $family=$_
        $selected=@($graph.selected | Where-Object {$index[$_].family -ceq $family})
        [ordered]@{family=$family; chapters=$selected.Count; steps=($selected | ForEach-Object {$index[$_].steps} | Measure-Object -Sum).Sum}
    })
}
[IO.Directory]::CreateDirectory($destination) | Out-Null
[IO.File]::WriteAllText((Join-Path $destination 'source-lock.json'), $json, $hardcoreUtf8)
[IO.File]::WriteAllText((Join-Path $destination 'source-graph.json'),
    (ConvertTo-HardcoreJson335 $report) + "`n", $hardcoreUtf8)
Write-Output ("Staged {0} reachable blocks; {1} excluded; {2} graph reviews. No content loaded." -f
    $graph.selected.Count, $graph.excluded.Count, $graph.issues.Count)
