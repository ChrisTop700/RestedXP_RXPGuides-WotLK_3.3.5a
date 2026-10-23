$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$utf8=[Text.UTF8Encoding]::new($false)
. (Join-Path $root 'tools/Validation-Scratch335.ps1')
$ownedScratch=New-ValidationScratch335 $root 'hardcore-preflight-regressions'
$scratch=$ownedScratch.Path
$scratchSucceeded=$false
try {
$files=@('Hardcore-Classic.lua','Hardcore-TBC.lua','Hardcore-Curated.lua')
# This fixture tests orchestration, not guide correctness. The real combined
# validator is run separately on all candidates and remains the approval gate.
$validator=@'
param($ManifestPath,$SurfacePath,$MaxErrors)
$root=Split-Path $PSScriptRoot -Parent
$manifest=[xml](Get-Content $ManifestPath -Raw)
$paths=@($manifest.Ui.Script | ForEach-Object {$_.file})
if($paths.Count -ne 44 -or @($paths | Select-Object -Unique).Count -ne 44){throw 'Combined inventory differs.'}
$surface=Get-Content $SurfacePath -Raw | ConvertFrom-Json
if($surface.guideFileCount -ne 44 -or $surface.guideCount -ne 620 -or $surface.guideStepCount -ne 58420){throw 'Wrong candidate baseline.'}
if($surface.directives[0] -cne 'fixture-directive'){throw 'Directive registry was not retained.'}
if($paths[-1] -cne 'candidate/Hardcore-Curated.lua'){throw 'Candidate was not used.'}
if(Test-Path (Join-Path $root 'reject.txt')){throw 'fixture compatibility failure'}
'fixture validator called'
'@ 
function Write-Fixture([string]$Path,[string]$Text){
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}
$cases=@('success','blocked','live-entries','missing-family','foreign-root','normal-inventory','foreign-live-entry')
foreach($case in $cases){
    $fixture=Join-Path $scratch $case
    foreach($script in @('Test-HardcorePublicationContent335.ps1','Hardcore-Publication335.ps1','Hardcore-Upstream335.ps1','Validation-Scratch335.ps1')){
        Write-Fixture (Join-Path $fixture "tools/$script") ([IO.File]::ReadAllText((Join-Path $root "tools/$script")))
    }
    Write-Fixture (Join-Path $fixture 'tools/Validate-Guides335.ps1') $validator
    Write-Fixture (Join-Path $fixture 'tools/data/Hardcore-PublicationBaseline335.json') ([IO.File]::ReadAllText((Join-Path $root 'tools/data/Hardcore-PublicationBaseline335.json')))
    Write-Fixture (Join-Path $fixture 'tests/runtime-surface.json') '{"guideFileCount":41,"guideCount":362,"guideStepCount":24663,"guideKeyHash":"normal-fixture","directives":["fixture-directive"]}'
    $entries=@(1..41 | ForEach-Object {'<Script file="Guides/normal-'+$_+'.lua"/>'})
    if($case -ceq 'normal-inventory'){$entries=$entries[0..39]}
    if($case -ceq 'live-entries'){$entries+=@($files | ForEach-Object {'<Script file="Guides/Hardcore/'+$_+'"/>'})}
    if($case -ceq 'foreign-live-entry'){$entries+='<Script file="Guides/Hardcore/foreign.lua"/>'}
    Write-Fixture (Join-Path $fixture 'GuideList_335.xml') ("<Ui>`n"+($entries -join "`n")+"`n</Ui>")
    foreach($file in $files){
        if($case -ceq 'missing-family' -and $file -ceq 'Hardcore-TBC.lua'){continue}
        Write-Fixture (Join-Path $fixture "candidate/$file") '-- fixture'
    }
    if($case -ceq 'blocked'){Write-Fixture (Join-Path $fixture 'reject.txt') 'reject'}
    $before=@{}
    foreach($file in @('GuideList_335.xml','tests/runtime-surface.json')){$before[$file]=(Get-FileHash (Join-Path $fixture $file)).Hash}
    $candidate=if($case -ceq 'foreign-root'){$scratch}else{Join-Path $fixture 'candidate'}
    $failed=$false
    try {& (Join-Path $fixture 'tools/Test-HardcorePublicationContent335.ps1') -GuideRoot $candidate | Out-Null}
    catch {$failed=$true;if($case -ceq 'blocked' -and $_ -notmatch 'fixture compatibility failure'){throw}}
    $expectedFailure=$case -cnotin @('success','live-entries')
    if($failed -ne $expectedFailure){throw "Preflight case failed: $case"}
    foreach($file in $before.Keys){if((Get-FileHash (Join-Path $fixture $file)).Hash -cne $before[$file]){throw 'Preflight modified live metadata.'}}
}
Write-Output 'Publication preflight regressions passed: seven isolated cases; compatibility failures propagate; live metadata unchanged.'
    $scratchSucceeded=$true
} finally { Complete-ValidationScratch335 $ownedScratch $scratchSucceeded }
