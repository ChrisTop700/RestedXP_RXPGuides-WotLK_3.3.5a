[CmdletBinding()]
param([string]$GuideRoot='', [string]$ReceiptPath='', [string]$LuaCommand='',
      [switch]$IntegrityOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Publication335.ps1')
if(-not $GuideRoot){$GuideRoot=Join-Path $hardcoreRoot 'Guides/Hardcore'}
if(-not $ReceiptPath){$ReceiptPath=Join-Path $hardcoreRoot 'tools/data/Hardcore-Publication335.json'}
$receipt=Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
if($receipt.schemaVersion -ne 1 -or $receipt.textHashFormat -cne 'utf8-lf' -or $receipt.status -cne 'experimental-automated-pass' -or
    $receipt.gameplayAccepted -cne $false -or $receipt.upstreamVersion -cne 'v4.11.11') {throw 'Invalid publication status/schema.'}
$expected=@(Get-HardcorePublicationDependencies335)
if($receipt.dependencies.Count -ne $expected.Count){throw 'Missing publication dependency.'}
for($i=0;$i -lt $expected.Count;$i++){
    $entry=$receipt.dependencies[$i]
    if($entry.path -cne $expected[$i] -or $entry.sha256 -cne (Get-HardcoreTextHash335 (Join-Path $hardcoreRoot $expected[$i]))){
        throw "Stale or foreign publication dependency: $($expected[$i])"
    }
}
if($receipt.outputs.Count -ne 3 -or $receipt.chapters.Count -ne 258){throw 'Incomplete family inventory.'}
$bodies=@(Get-HardcorePublishedBodies335 $GuideRoot)
if($bodies.Count -ne 258){throw 'Unexpected published chapter inventory.'}
$keys=@{};$sources=@{};$counts=@{classic=92;tbc=77;curated=89}
$lock=Get-Content (Join-Path $hardcoreRoot 'tools/data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
$local=Get-Content (Join-Path $hardcoreRoot 'tools/data/Hardcore-Curated335/local-sources.json') -Raw | ConvertFrom-Json
$sourceHashes=@{};foreach($s in @($lock.blocks)+@($local.blocks)){$sourceHashes[$s.id]=$s.sourceHash}
for($i=0;$i -lt $bodies.Count;$i++){
    $body=$bodies[$i];$entry=$receipt.chapters[$i]
    foreach($field in @('family','sourceName','group','subgroup','bodyHash','steps')){
        if($body[$field] -cne $entry.$field){throw "Published chapter differs: $($body.sourceName) / $field"}
    }
    if($sourceHashes[$entry.sourceId] -cne $entry.sourceHash){throw 'Foreign or changed pinned source.'}
    $identity="$($entry.family)|$($entry.sourceId)"
    if($keys.ContainsKey($entry.key) -or $sources.ContainsKey($identity)){throw 'Duplicate canonical/source identity.'}
    $keys[$entry.key]=$true;$sources[$identity]=$true
    if($entry.key -cne "$($entry.group)|$($entry.subgroup)|$($entry.name)"){throw 'Malformed canonical key.'}
}
foreach($family in $hardcoreOutputs.Keys){
    $output=@($receipt.outputs | Where-Object family -CEQ $family)
    $chapters=@($bodies | Where-Object family -CEQ $family)
    if($output.Count -ne 1 -or $output[0].file -cne $hardcoreOutputs[$family] -or
        $output[0].guides -ne $counts[$family] -or $chapters.Count -ne $counts[$family] -or
        $output[0].steps -ne ($chapters | ForEach-Object {$_.steps} | Measure-Object -Sum).Sum -or
        $output[0].sha256 -cne (Get-HardcoreTextHash335 (Join-Path $GuideRoot $hardcoreOutputs[$family]))){throw 'Published family hash/count mismatch.'}
}
$inputs=Join-Path $hardcoreRoot $hardcoreInputs
& (Join-Path $PSScriptRoot 'Export-HardcoreLabelEvidence335.ps1') -UpstreamRoot $GuideRoot -CuratedRoot $GuideRoot `
    -ReviewReport "$inputs/final-labels.tsv" -OutputPath "$inputs/evidence.tsv" -Check
$review=Get-Content "$inputs/review-index.json" -Raw | ConvertFrom-Json
if($review.counts.unresolved -ne 0 -or $review.findings.Count -ne 82 -or $review.gameplayAccepted){throw 'Incomplete final review.'}
foreach($finding in $review.findings){
    $chapter=@($receipt.chapters | Where-Object {$_.family -ceq $finding.family -and $_.key -ceq $finding.canonicalGuide})
    if($chapter.Count -ne 1 -or $chapter[0].bodyHash -cne $finding.sourceHash -or
        $finding.classification -cnotin @('repaired','verified-harmless')){throw 'Stale/unresolved review finding.'}
}
if($IntegrityOnly){Write-Output 'Publication integrity checked only; not production-test or release approval.'; return}
& (Join-Path $PSScriptRoot 'Test-HardcorePublicationContent335.ps1') -GuideRoot $GuideRoot
& (Join-Path $hardcoreRoot 'tests/hardcore-labels.ps1') -RecipePath "$inputs/upstream.json" -CuratedSelection "$inputs/curated.json"
$manifest=[xml](Get-Content (Join-Path $hardcoreRoot 'GuideList_335.xml') -Raw)
$scripts=@($manifest.SelectNodes('//*[local-name()="Script"]') | ForEach-Object {$_.file.Replace('\','/')})
foreach($file in $hardcoreOutputs.Values){if(@($scripts | Where-Object {$_ -ceq "Guides/Hardcore/$file"}).Count -ne 1){throw 'Publication manifest missing or duplicated.'}}
if($scripts.Count -ne 44 -or [IO.File]::ReadAllText((Join-Path $hardcoreRoot 'Core/Addon.lua')) -notmatch 'local cacheVersion = 36\b'){
    throw 'Publication manifest/cache version differs.'
}
$lua=Resolve-HardcoreLua335 $LuaCommand
. (Join-Path $hardcoreRoot 'tools/Validation-Scratch335.ps1')
$ownedScratch=New-ValidationScratch335 $hardcoreRoot 'hardcore-published-check'
$work='build/'+[IO.Path]::GetFileName($ownedScratch.Path)
$scratchSucceeded=$false

Push-Location -LiteralPath $hardcoreRoot
try {
    Invoke-HardcoreLua335 $lua @('tests/hardcore-wrath-content.lua','.',$GuideRoot)
    Invoke-HardcoreLua335 $lua @('-e',"assert(loadfile('tests/hardcore-wrath-production.lua'))()('.')")
    & (Join-Path $PSScriptRoot 'Validate-HardcoreQuestFlow335.ps1') -CandidateRoot $GuideRoot -CuratedRoot $GuideRoot `
        -LuaCommand $lua -ReportPath "$work/labels.tsv" -LabelEvidencePath "$inputs/evidence.tsv" -LabelReviewReport "$inputs/final-labels.tsv"
    if((Read-HardcorePublicationText335 "$work/labels.tsv") -cne (Read-HardcorePublicationText335 "$inputs/final-labels.tsv")){throw 'Publication label profile inventory differs.'}
    Invoke-HardcoreLua335 $lua @('tests/hardcore-registration.lua','.',$GuideRoot,$GuideRoot,"$work/keys.tsv")
    $actual=Import-Csv "$work/keys.tsv" -Delimiter "`t"
    foreach($row in $actual){
        $chapter=@($receipt.chapters | Where-Object key -CEQ $row.key)
        if($chapter.Count -ne 1){throw 'Unreceipted runtime key.'}
        foreach($field in @('family','sourceName','group','subgroup','name','key')){
            if($row.$field -cne $chapter[0].$field){throw 'Receipt disagrees with real registration.'}
        }
    }
    if($actual.Count -ne 258){throw 'Missing actual runtime identity.'}
    Write-Output 'Hardcore publication passed: 258 experimental chapters; zero unresolved labels. Gameplay acceptance remains separate.'
    $scratchSucceeded=$true
} finally {
    Pop-Location
    Complete-ValidationScratch335 $ownedScratch $scratchSucceeded
}
