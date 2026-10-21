[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidateRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
# Promote reviewed inputs only. This never activates guides or claims gameplay
# acceptance; the publication builder reruns the strict production-path gate.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
$out=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $out){throw 'Use a new publication-input directory.'}
$report=Import-Csv (Join-Path $CandidateRoot 'final-labels.tsv') -Delimiter "`t"
if(@($report | Where-Object classification -cne 'verified-harmless').Count){throw 'Unresolved references block promotion.'}
& (Join-Path $PSScriptRoot 'Export-HardcoreLabelEvidence335.ps1') -UpstreamRoot (Join-Path $CandidateRoot 'upstream') `
    -CuratedRoot (Join-Path $CandidateRoot 'curated') -ReviewReport (Join-Path $CandidateRoot 'final-labels.tsv') `
    -OutputPath (Join-Path $CandidateRoot 'evidence.tsv') -Check
$index=Get-Content (Join-Path $CandidateRoot 'review-index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($index.counts.unresolved -ne 0 -or $index.findings.Count -ne 82 -or $index.gameplayAccepted){throw 'Incomplete review inventory.'}
$selection=Get-Content (Join-Path $CandidateRoot 'curated.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$records=Get-Content (Join-Path $CandidateRoot 'curated/selected.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($records.Count -ne 89 -or $selection.guides.Count -ne 89){throw 'Curated inventory changed.'}
foreach($entry in $selection.guides){
    $record=@($records | Where-Object source -CEQ $entry.id)
    if($record.Count -ne 1 -or $record[0].sourceHash -cne $entry.sourceHash){throw 'Ambiguous curated source review.'}
    $entry | Add-Member -NotePropertyName reviewedHash -NotePropertyValue $record[0].outputHash -Force
}
[IO.Directory]::CreateDirectory($out) | Out-Null
[IO.File]::WriteAllText((Join-Path $out 'curated.json'),(ConvertTo-HardcoreJson335 $selection)+"`n",$hardcoreUtf8)
foreach($name in @('upstream.json','final-labels.tsv','evidence.tsv','review-index.json')){
    [IO.File]::WriteAllBytes((Join-Path $out $name),[IO.File]::ReadAllBytes((Join-Path $CandidateRoot $name)))
}
Write-Output 'Promoted source-reviewed recipes and label evidence; gameplay acceptance remains false.'
