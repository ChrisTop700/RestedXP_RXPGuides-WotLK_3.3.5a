[CmdletBinding()]
param([string]$SourceRoot = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot '../tools/Hardcore-Coordinates335.ps1')
function Assert($Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Message) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert $rejected $Message
}
$maps = Read-HardcoreGeometry335 (Join-Path $PSScriptRoot 'fixtures/hardcore-map-geometry335.json')
Assert ($maps.Count -eq 34) 'Unexpected reviewed map inventory.'
$sample = [ordered]@{name='Fixture Zone';width=1000.0;height=500.0;left=100.0;top=200.0}
Assert ((Convert-HardcoreWorldPoint335 $sample -400 -175) -ceq 'Fixture Zone,50,75') 'Wrong axes or conversion.'
Assert ((Convert-HardcoreWorldPoint335 $sample 100 200) -ceq 'Fixture Zone,0,0') 'Origin changed.'
Assert ((Convert-HardcoreWorldPoint335 $sample -900 -300) -ceq 'Fixture Zone,100,100') 'Far boundary changed.'
$sampleMaps = [ordered]@{'100/1'=$sample}
$line = "    .goto 100/1,-400,-175,40,0 >> Keep |cRXP_WARN_text|r << Hunter"
$text = "step`n$line`n$line`n    .goto Fixture Zone,50,75,40,0`n"
$edits = @(Get-HardcoreCoordinateEdits335 $text $sampleMaps)
Assert ($edits.Count -eq 1 -and $edits[0].occurrences -eq 2) 'Repeated path points lost.'
Assert ($edits[0].to -ceq ($line.Replace('100/1,-400,-175','Fixture Zone,50,75')+"`n")) 'Predicate/radius/prose altered.'
$prefixes = @(Get-HardcoreCoordinateEdits335 ".goto 100/1,-400,-175,40`n.goto 100/1,-400,-175,40,0`n" $sampleMaps)
Assert ($prefixes.Count -eq 2 -and $prefixes[0].occurrences -eq 1 -and $prefixes[1].occurrences -eq 1) 'A shorter radius line consumed another waypoint.'
$culture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
    Assert ((Convert-HardcoreWorldPoint335 $sample -400.25 -175.25) -ceq 'Fixture Zone,50.025,75.05') 'Culture-dependent coordinates.'
} finally { [Threading.Thread]::CurrentThread.CurrentCulture = $culture }
Reject { Convert-HardcoreWorldPoint335 $sample 101 200 } 'Out-of-map coordinate accepted.'
Reject { Convert-HardcoreWorldPoint335 $sample ([double]::NaN) 0 } 'NaN coordinate accepted.'
Reject { Convert-HardcoreWorldPoint335 $sample 0 ([double]::PositiveInfinity) } 'Infinite coordinate accepted.'
Reject { Get-HardcoreCoordinateEdits335 ".goto 999/0,1,2" $sampleMaps } 'Unverified map accepted.'
$invalid = [ordered]@{name='Fixture Zone';width=0;height=500;left=100;top=200}
Reject { Convert-HardcoreWorldPoint335 $invalid 0 0 } 'Degenerate geometry accepted.'
# Independent named-NPC anchors from the existing 3.3.5 Azuremyst guide,
# retained in the workbench geometry review; percentages tolerate its rounding.
foreach ($anchor in @(@(3865.399,6144.7,79.5,51.7), @(3877,6284.4,79.1,46.5))) {
    $point = (Convert-HardcoreWorldPoint335 $maps['1943/1'] $anchor[0] $anchor[1]).Split(',')
    Assert ([math]::Abs([double]::Parse($point[1],[Globalization.CultureInfo]::InvariantCulture)-$anchor[2]) -lt 0.3) 'Azuremyst horizontal anchor mismatch.'
    Assert ([math]::Abs([double]::Parse($point[2],[Globalization.CultureInfo]::InvariantCulture)-$anchor[3]) -lt 0.3) 'Azuremyst vertical anchor mismatch.'
}
if ($SourceRoot) {
    $index = Read-HardcoreUpstream335 $SourceRoot
    $total = 0
    foreach ($id in (Get-HardcoreSourceGraph335 $index).selected) {
        try {
            foreach ($edit in @(Get-HardcoreCoordinateEdits335 $index[$id].content $maps)) {
                $total += $edit.occurrences
            }
        } catch { throw "$id : $_" }
    }
    Assert ($total -eq 369) "Expected 369 world-coordinate occurrences, found $total."
    Write-Output "All $total pinned source coordinates converted within verified bounds."
}
Write-Output 'Hardcore coordinate tests passed: geometry, round-trip, anchors, suffixes, duplicates, culture and rejection cases.'
