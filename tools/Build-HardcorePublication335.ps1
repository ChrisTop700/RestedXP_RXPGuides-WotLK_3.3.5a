[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot,
      [Parameter(Mandatory=$true)][string]$OutputRoot,
      [string]$LuaCommand='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Publication335.ps1')
$lua=Resolve-HardcoreLua335 $LuaCommand
$out=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $out){throw 'Use a new output directory; preserve previous evidence.'}
$inputs=Join-Path $hardcoreRoot $hardcoreInputs
. (Join-Path $hardcoreRoot 'tools/Validation-Scratch335.ps1')
$ownedScratch=New-ValidationScratch335 $hardcoreRoot 'hardcore-publication'
$work='build/'+[IO.Path]::GetFileName($ownedScratch.Path)
$scratchSucceeded=$false

Push-Location -LiteralPath $hardcoreRoot
try {
    & (Join-Path $PSScriptRoot 'Build-HardcoreUpstream335.ps1') -SourceRoot $SourceRoot -OutputRoot "$work/upstream" -RecipePath "$inputs/upstream.json"
    & (Join-Path $PSScriptRoot 'Build-HardcoreGuides335.ps1') -SourceRoot $SourceRoot -OutputRoot "$work/curated" -SelectionPath "$inputs/curated.json"
    [IO.Directory]::CreateDirectory("$work/published") | Out-Null
    foreach($family in @('classic','tbc')){
        $text=[IO.File]::ReadAllText("$work/upstream/Hardcore-$family.preview.lua",$hardcoreUtf8)
        $text=$text.Replace('Experimental candidate: see compatibility-report.json. Not a gameplay certification.',
            'Experimental 3.3.5-adapted Hardcore family. Source-reviewed; not gameplay certified. See publication receipt in tools/data.')
        [IO.File]::WriteAllText("$work/published/$($hardcoreOutputs[$family])",$text,$hardcoreUtf8)
    }
    [IO.File]::WriteAllBytes("$work/published/Hardcore-Curated.lua",[IO.File]::ReadAllBytes("$work/curated/Hardcore335.lua"))
    & (Join-Path $PSScriptRoot 'Test-HardcorePublicationContent335.ps1') -GuideRoot "$work/published"
    Invoke-HardcoreLua335 $lua @('tests/hardcore-wrath-content.lua','.',"$work/published")
    Invoke-HardcoreLua335 $lua @('-e',"assert(loadfile('tests/hardcore-wrath-production.lua'))()('.')")
    & (Join-Path $PSScriptRoot 'Validate-HardcoreQuestFlow335.ps1') -CandidateRoot "$work/published" -CuratedRoot "$work/published" `
        -ReportPath "$work/labels.tsv" -LuaCommand $lua -LabelEvidencePath "$inputs/evidence.tsv" -LabelReviewReport "$inputs/final-labels.tsv"
    if((Read-HardcorePublicationText335 "$work/labels.tsv") -cne (Read-HardcorePublicationText335 "$inputs/final-labels.tsv")){throw 'Final label inventory differs from reviewed evidence.'}
    Invoke-HardcoreLua335 $lua @('tests/hardcore-registration.lua','.',"$work/published","$work/published","$work/keys.tsv")
    $keys=Import-Csv "$work/keys.tsv" -Delimiter "`t"
    $sourceRecords=@((Read-HardcorePublicationText335 "$work/upstream/compatibility-report.json" | ConvertFrom-Json).guides)
    # PS 5.1 emits a JSON root array as one pipeline object. Enumerate the
    # expression result explicitly before looking up individual chapter keys.
    $curatedRecords=@((Read-HardcorePublicationText335 "$work/curated/selected.json" | ConvertFrom-Json))
    $chapters=[Collections.Generic.List[object]]::new()
    foreach($body in (Get-HardcorePublishedBodies335 "$work/published")){
        $key=@($keys | Where-Object {$_.family -ceq $body.family -and $_.sourceName -ceq $body.sourceName -and $_.group -ceq $body.group})
        if($key.Count -ne 1 -or $key[0].subgroup -cne $body.subgroup){throw 'Missing or ambiguous registered identity.'}
        $source=@(if($body.family -ceq 'curated'){$curatedRecords | Where-Object key -CEQ "$($body.group)|$($body.sourceName)"}
            else{$sourceRecords | Where-Object {$_.family -ceq $body.family -and $_.key -ceq "$($body.group)|$($body.sourceName)"}})
        if($source.Count -ne 1 -or $source[0].outputHash -cne $body.bodyHash){throw 'Generated source/body receipt mismatch.'}
        $chapters.Add([ordered]@{family=$body.family;sourceId=$(if($body.family -ceq 'curated'){$source[0].source}else{$source[0].id})
            sourceHash=$source[0].sourceHash;sourceName=$body.sourceName;group=$body.group;subgroup=$body.subgroup
            name=$key[0].name;key=$key[0].key;bodyHash=$body.bodyHash;steps=$body.steps})
    }
    $dependencies=@(foreach($path in (Get-HardcorePublicationDependencies335)){
        [ordered]@{path=$path;sha256=Get-HardcoreTextHash335 (Join-Path $hardcoreRoot $path)}
    })
    $outputs=@(foreach($family in $hardcoreOutputs.Keys){
        $rows=@($chapters | Where-Object family -CEQ $family)
        [ordered]@{family=$family;file=$hardcoreOutputs[$family];sha256=Get-HardcoreTextHash335 "$work/published/$($hardcoreOutputs[$family])"
            guides=$rows.Count;steps=($rows | ForEach-Object {$_.steps} | Measure-Object -Sum).Sum}
    })
    $receipt=[ordered]@{schemaVersion=1;textHashFormat='utf8-lf';status='experimental-automated-pass';gameplayAccepted=$false;upstreamVersion='v4.11.11'
        attribution='RestedXP Survival sources and attributed 3.3.5 adaptations; retain upstream licensing.'
        dependencies=$dependencies;outputs=$outputs;chapters=@($chapters.ToArray())}
    [IO.Directory]::CreateDirectory($out) | Out-Null
    foreach($file in $hardcoreOutputs.Values){[IO.File]::WriteAllBytes((Join-Path $out $file),[IO.File]::ReadAllBytes("$work/published/$file"))}
    [IO.File]::WriteAllText((Join-Path $out 'receipt.json'),(ConvertTo-HardcoreJson335 $receipt)+"`n",$hardcoreUtf8)
    Write-Output 'Generated experimentally publishable outputs; manifest unchanged and gameplay acceptance still required.'
    $scratchSucceeded=$true
} finally {
    Pop-Location
    Complete-ValidationScratch335 $ownedScratch $scratchSucceeded
}
