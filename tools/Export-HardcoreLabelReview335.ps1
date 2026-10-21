[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BaselineReport,
    [Parameter(Mandatory=$true)][string]$CurrentReport,
    [Parameter(Mandatory=$true)][string]$UpstreamRoot,
    [Parameter(Mandatory=$true)][string]$CuratedRoot,
    [Parameter(Mandatory=$true)][string]$RecipePath,
    [Parameter(Mandatory=$true)][string]$CuratedSelection,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
# Classification/evidence index only: never an approval or gameplay receipt.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
$destination=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $destination){throw 'Preserve historical reviews; use a new output path.'}
$baseline=Import-Csv -LiteralPath $BaselineReport -Delimiter "`t"
$current=Import-Csv -LiteralPath $CurrentReport -Delimiter "`t"
function Key($Row){return "$($Row.family)|$($Row.canonicalGuide)|$($Row.field)|$($Row.label)"}
$pending=@{};foreach($row in $current){$key=Key $row;if($pending.ContainsKey($key)){throw 'Duplicate current finding.'};$pending[$key]=$row}
$bodies=@{};$sourceByKey=@{};$entries=@{}
$recipe=Get-Content -LiteralPath $RecipePath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($entry in $recipe.guides){$entries[$entry.id]=$entry}
$selection=Get-Content -LiteralPath $CuratedSelection -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($entry in $selection.guides){$entries['curated|'+$entry.id]=$entry}
foreach($family in @('classic','tbc','curated')){
    $directory=if($family -ceq 'curated'){$CuratedRoot}else{$UpstreamRoot}
    $text=[IO.File]::ReadAllText((Get-HardcoreOutputPath335 $directory $family),$hardcoreUtf8)
    $records=if($family -ceq 'curated'){
        @(Get-Content (Join-Path $directory 'selected.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
    }else{
        @((Get-Content (Join-Path $directory 'compatibility-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json).guides | Where-Object {$_.family -ceq $family})
    }
    $recordsByKey=@{};foreach($record in $records){$recordsByKey[$record.key]=$record}
    foreach($m in [regex]::Matches($text,'(?ms)RXPGuides\.RegisterGuide\(\[\[(.*?)\]\]\)')){
        $body=$m.Groups[1].Value.Trim()+"`n"
        $group=@(Get-HardcoreHeader335 $body 'group')[0]
        $name=@(Get-HardcoreHeader335 $body 'name')[0]
        $subgroup=@(Get-HardcoreHeader335 $body 'subgroup')[0]
        $record=$recordsByKey["$group|$name"]
        if(-not $record -or (Get-HardcoreHash335 $body) -cne $record.outputHash){throw 'Candidate body differs from its receipt.'}
        $normalized=[regex]::Replace($name,'^(\d)-(\d\d?)',{param($m) '{0:00}-{1:00}' -f [int]$m.Groups[1].Value,[int]$m.Groups[2].Value})
        $key="$family|$group|$subgroup|$normalized"
        if($bodies.ContainsKey($key)){throw 'Duplicate runtime identity.'}
        $bodies[$key]=$record.outputHash
        $sourceByKey[$key]=if($family -ceq 'curated'){'curated|'+$record.source}else{$record.id}
    }
}
$findings=[Collections.Generic.List[object]]::new();$counts=[ordered]@{repaired=0;'verified-harmless'=0;unresolved=0}
$seen=@{}
foreach($row in $baseline){
    $key=Key $row
    if($seen.ContainsKey($key)){throw 'Duplicate baseline finding.'};$seen[$key]=$true
    $chapter="$($row.family)|$($row.canonicalGuide)"
    $hash=$bodies[$chapter]
    if(-not $hash){throw 'Baseline chapter no longer exists; removal is not a repair.'}
    $live=$pending[$key]
    $status=if(-not $live){'repaired'}elseif($live.classification -ceq 'verified-harmless'){'verified-harmless'}else{'unresolved'}
    $reasons=@()
    if($status -ceq 'repaired'){
        $entry=$entries[$sourceByKey[$chapter]]
        $token='(?m)^\s*#(?:completewith|requires|label) '+[regex]::Escape($row.label)+'(?:\s|$)'
        $reasons=@($entry.replacements | Where-Object {$_.kind -ceq 'reviewed-label-repair' -and ($_.from -match $token -or $_.to -match $token)} | ForEach-Object {$_.reason} | Sort-Object -Unique)
        if(-not $reasons.Count){throw "Missing exact repair attribution: $key"}
    }elseif($status -ceq 'verified-harmless'){
        if($live.evidenceHash -cne $hash){throw 'Harmless evidence belongs to different content.'}
    }
    $originalProfiles=@($row.profiles.Split(';'))
    $profiles=if($live){@($live.profiles.Split(';'))}else{@()}
    foreach($profile in $profiles){if($profile -cnotin $originalProfiles){throw 'Unexpected finding profile; review the new baseline explicitly.'}}
    $counts[$status]++
    $findings.Add([ordered]@{family=$row.family;canonicalGuide=$row.canonicalGuide;field=$row.field;label=$row.label
        classification=$status;sourceHash=$hash;source=$sourceByKey[$chapter];originalProfiles=$originalProfiles
        currentProfiles=$profiles;resolvedProfiles=@($originalProfiles | Where-Object {$_ -cnotin $profiles})
        automaticRouteProfiles=$(if($live -and $live.automaticRouteProfiles){@($live.automaticRouteProfiles.Split(';'))}else{@()})
        manualSelectionOnlyProfiles=$(if($live -and $live.manualSelectionOnlyProfiles){@($live.manualSelectionOnlyProfiles.Split(';'))}else{@()})
        reasons=$reasons;evidenceHash=$(if($live){$live.evidenceHash}else{''})})
    $pending.Remove($key)
}
if($pending.Count){throw 'New findings cannot be omitted from the review inventory.'}
$report=[ordered]@{schemaVersion=1;status='review-index-not-publication-approval';gameplayAccepted=$false
    baselineHash=(Get-FileHash -LiteralPath $BaselineReport -Algorithm SHA256).Hash.ToLowerInvariant()
    currentReportHash=(Get-FileHash -LiteralPath $CurrentReport -Algorithm SHA256).Hash.ToLowerInvariant()
    recipeHash=(Get-FileHash -LiteralPath $RecipePath -Algorithm SHA256).Hash.ToLowerInvariant()
    selectionHash=(Get-FileHash -LiteralPath $CuratedSelection -Algorithm SHA256).Hash.ToLowerInvariant()
    counts=$counts;findings=@($findings.ToArray())}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
[IO.File]::WriteAllText($destination,(ConvertTo-HardcoreJson335 $report)+"`n",$hardcoreUtf8)
Write-Output ("Label review: {0} repaired; {1} verified harmless; {2} unresolved. Not publication approval." -f $counts.repaired,$counts['verified-harmless'],$counts.unresolved)
