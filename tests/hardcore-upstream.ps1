[CmdletBinding()]
param([string]$SourceRoot = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot '../tools/Guide-Families335.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
foreach ($family in @('Classic','TBC')) {
    foreach ($faction in @('A','H')) {
        $group = "Original Guides - RestedXP Hardcore $family Guides ($faction)"
        Assert (Test-AdaptedHardcoreGroup335 $group) 'Adapted family not recognized.'
        Assert (-not (Test-OriginalGuideSnapshot335 $group)) 'Adapted family bypasses validation as a snapshot.'
    }
}
Assert (Test-OriginalGuideSnapshot335 'Original Guides - RestedXP Horde 1-30') 'Ordinary snapshot exemption changed.'
Assert (-not (Test-AdaptedHardcoreGroup335 'Original Guides - RestedXP Hardcore Classic Guides (Neutral)')) 'Foreign faction classified as adapted.'
Assert (-not (Test-OriginalGuideSnapshot335 'RestedXP Hardcore Guides (H)')) 'Curated guide classified as original.'
foreach ($faction in @('Alliance','Horde')) {
    Assert ((Get-HardcoreEnvelope335 'classic' $faction) -ceq "ac335 $faction !DK !Draenei !BloodElf") 'Classic expansion-race exclusion missing.'
    Assert ((Get-HardcoreEnvelope335 'tbc' $faction) -ceq "ac335 $faction !DK") 'TBC racial coverage narrowed.'
}
Assert ((Get-HardcoreStepCount335 "step`n step << Hunter`n`tstep`n>>not a step`n") -eq 3) 'Indented runtime steps missing from inventory.'
$sample = [ordered]@{text="Quote`" slash\ tab`t apostrophe' &"; empty=@(); boolean=$false; count=1.5; missing=$null}
$serialized = ConvertTo-HardcoreJson335 $sample
$restored = $serialized | ConvertFrom-Json
Assert ($restored.text -ceq $sample.text -and $restored.empty.Count -eq 0 -and
    $restored.boolean -eq $false -and $restored.count -eq 1.5 -and $null -eq $restored.missing) 'Canonical JSON changed values.'
$culture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    Assert ((ConvertTo-HardcoreJson335 $sample) -ceq $serialized) 'Host culture affected evidence.'
} finally { [Threading.Thread]::CurrentThread.CurrentCulture = $culture }
function Block([string]$Id, [string]$Family, [string]$Name, [int]$Low, [int]$High, [string[]]$Next) {
    return [pscustomobject]@{id=$Id; family=$Family; faction='Horde'; name=$Name
        low=$Low; high=$High; next=$Next; content=''; steps=1}
}
$index = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($entry in @(
    (Block 'c1' 'classic' '1-6 Starter' 1 6 @('59-60 Finish')),
    (Block 'c2' 'classic' '59-60 Finish' 59 60 @()),
    (Block 't1' 'tbc' '1-6 Starter' 1 6 @('RXP TBC Survival Guide (H)\59-60 Finish')),
    (Block 't2' 'tbc' '59-60 Finish' 59 60 @('60-61 After')),
    (Block 't3' 'tbc' '60-61 After' 60 61 @()),
    (Block 'orphan' 'tbc' '40-41 Alternative' 40 41 @('Missing'))
)) { $index.Add($entry.id, $entry) }
$graph = Get-HardcoreSourceGraph335 $index
Assert (($graph.selected -join ',') -ceq 'c1,c2,t1,t2') 'Families/roots or post-60 truncation changed.'
Assert ($graph.issues.Count -eq 0) 'Unreachable alternatives became required.'
Assert (@($graph.edges | Where-Object {$_.from -ceq 'c1' -and $_.to -ceq 'c2'}).Count -eq 1) 'Classic crossed into TBC.'
Assert (@($graph.edges | Where-Object {$_.from -ceq 't1' -and $_.to -ceq 't2'}).Count -eq 1) 'Qualified TBC continuation failed.'
$index['t1'].next = @('59-60 Finish;6-12 Missing')
$graph = Get-HardcoreSourceGraph335 $index
Assert ($graph.issues.Count -eq 1 -and $graph.issues[0].destination -ceq '6-12 Missing') 'Missing fallback was silently erased.'
$index['t1'].next = @('RestedXP Survival Guide (A)\59-60 Finish')
$graph = Get-HardcoreSourceGraph335 $index
Assert (@($graph.issues | Where-Object {$_.kind -ceq 'foreign-group'}).Count -eq 1) 'Faction crossing was permitted.'
$index['t1'].next = @()
$index['t1'].content = ".next 59-60 Finish"
$graph = Get-HardcoreSourceGraph335 $index
Assert ($graph.selected -contains 't2') 'In-body transition omitted.'
$reverse = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($key in @($index.Keys | Sort-Object -Descending)) { $reverse.Add($key, $index[$key]) }
Assert (($graph | ConvertTo-Json -Depth 12 -Compress) -ceq
    ((Get-HardcoreSourceGraph335 $reverse) | ConvertTo-Json -Depth 12 -Compress)) 'Insertion order affected evidence.'
$reverse.Add('duplicate', (Block 'duplicate' 'classic' '1-6 Starter' 1 6 @()))
$rejected = $false
try { Get-HardcoreSourceGraph335 $reverse | Out-Null } catch { $rejected = $true }
Assert $rejected 'Duplicate canonical identity accepted.'
if ($SourceRoot) {
    $real = Read-HardcoreUpstream335 $SourceRoot
    $lock = Get-Content -Raw (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-v4.11.11.json') | ConvertFrom-Json
    Assert ($real.Count -eq $lock.blocks.Count) 'Pinned inventory changed.'
    foreach ($entry in $lock.blocks) {
        Assert ($real.ContainsKey($entry.id) -and $real[$entry.id].sourceHash -ceq $entry.sourceHash) 'Source block changed.'
    }
    $realGraph = Get-HardcoreSourceGraph335 $real
    Assert ($realGraph.roots.Count -eq 14 -and $realGraph.selected.Count -eq 169) 'Selected graph changed; review pinning.'
    Assert ($realGraph.issues.Count -eq 2) 'Expected unresolved alternatives changed.'
}
Write-Output 'Hardcore source-graph tests passed: isolation, roots, exclusions, missing edges, determinism and duplicate rejection.'
