[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GuideRoot,
      [int]$MaxErrors=30)
# Exercise the ordinary compatibility checker against the proposed combined
# manifest BEFORE activation. Label/route checks alone cannot approve content.
# The live manifest, cache version and normal runtime snapshot are never edited.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Publication335.ps1')
$candidate=[IO.Path]::GetFullPath($GuideRoot)
$prefix=$hardcoreRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
if(-not ($candidate+[IO.Path]::DirectorySeparatorChar).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
    throw 'Candidate content must be inside the repository.'
}
$manifest=[xml](Get-Content (Join-Path $hardcoreRoot 'GuideList_335.xml') -Raw)
$paths=[Collections.Generic.List[string]]::new()
foreach($node in $manifest.SelectNodes('//*[local-name()="Script"]')){
    $relative=$node.file.Replace('\','/')
    if($relative.StartsWith('Guides/Hardcore/',[StringComparison]::Ordinal)){
        if($relative.Substring(16) -cnotin @($hardcoreOutputs.Values)){throw 'Unexpected live Hardcore manifest entry.'}
        continue
    }
    $paths.Add($relative)
}
if($paths.Count -ne 41){throw 'Normal manifest inventory changed; review publication baseline.'}
foreach($file in $hardcoreOutputs.Values){
    $path=Join-Path $candidate $file
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing candidate: $file"}
    $paths.Add($path.Substring($prefix.Length).Replace('\','/'))
}
$baseline=Get-Content (Join-Path $hardcoreRoot 'tools/data/Hardcore-PublicationBaseline335.json') -Raw | ConvertFrom-Json
if($baseline.schemaVersion -ne 1){throw 'Unknown candidate baseline schema.'}
$surface=Get-Content (Join-Path $hardcoreRoot 'tests/runtime-surface.json') -Raw | ConvertFrom-Json
foreach($key in @('guideFileCount','guideCount','guideStepCount','guideKeyHash')){$surface.$key=$baseline.$key}
. (Join-Path $hardcoreRoot 'tools/Validation-Scratch335.ps1')
$ownedScratch=New-ValidationScratch335 $hardcoreRoot 'hardcore-content-preflight'
$work=$ownedScratch.Path
$scratchSucceeded=$false
try {
$lines=@('<Ui>')+@($paths | ForEach-Object {'<Script file="'+[Security.SecurityElement]::Escape($_)+'"/>'})+@('</Ui>')
[IO.File]::WriteAllText((Join-Path $work 'manifest.xml'),($lines -join "`n")+"`n",$hardcoreUtf8)
[IO.File]::WriteAllText((Join-Path $work 'surface.json'),(ConvertTo-HardcoreJson335 $surface)+"`n",$hardcoreUtf8)
& (Join-Path $PSScriptRoot 'Validate-Guides335.ps1') -ManifestPath (Join-Path $work 'manifest.xml') `
    -SurfacePath (Join-Path $work 'surface.json') -MaxErrors $MaxErrors
Write-Output 'Combined candidate compatibility passed; this is not gameplay acceptance.'
    $scratchSucceeded=$true
} finally { Complete-ValidationScratch335 $ownedScratch $scratchSucceeded }
