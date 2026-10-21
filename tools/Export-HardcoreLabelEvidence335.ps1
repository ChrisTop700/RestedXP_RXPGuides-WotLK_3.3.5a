[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$UpstreamRoot,
    [Parameter(Mandatory=$true)][string]$CuratedRoot,
    [Parameter(Mandatory=$true)][string]$ReviewReport,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [switch]$Check
)
# Produces hash-bound evidence inputs, NOT an approval. Every observed profile
# must still pass the real loading/completion regression in the Lua visitor.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
$policy=Get-Content (Join-Path $PSScriptRoot 'data/Hardcore-Label-Decisions335.json') -Raw | ConvertFrom-Json
if($policy.schemaVersion -ne 1 -or $policy.status -cne 'requires-production-regressions'){throw 'Invalid label policy.'}
$reports=Import-Csv -LiteralPath $ReviewReport -Delimiter "`t"
$bodies=@{}
foreach($family in @('classic','tbc','curated')) {
    $path=Get-HardcoreOutputPath335 $(if($family -eq 'curated'){$CuratedRoot}else{$UpstreamRoot}) $family
    $text=[IO.File]::ReadAllText([IO.Path]::GetFullPath($path),$hardcoreUtf8).Replace("`r`n","`n")
    foreach($m in [regex]::Matches($text,'(?ms)RXPGuides\.RegisterGuide\(\[\[(.*?)\]\]\)')){
        $body=$m.Groups[1].Value.Trim()+"`n"
        $name=@(Get-HardcoreHeader335 $body 'name')[0]
        $bodies["$family|$name"]=$body
    }
}
$lines=[Collections.Generic.List[string]]::new()
$lines.Add("family`tcanonicalGuide`tfield`tlabel`tkind`tsourceHash`tsourceAdler`tprofiles`treason")
$seen=@{}
foreach($case in $policy.cases){
    $body=$bodies["$($case.family)|$($case.name)"]
    if(-not $body){throw 'Reviewed chapter missing.'}
    $normalized=[regex]::Replace($case.name,'^(\d)-(\d\d?)', {param($m) '{0:00}-{1:00}' -f [int]$m.Groups[1].Value,[int]$m.Groups[2].Value})
    $rows=@($reports | Where-Object {$_.family -ceq $case.family -and $_.canonicalGuide.Split('|')[-1] -ceq $normalized -and $_.field -ceq 'completewith' -and $_.label -ceq $case.label})
    if($rows.Count -ne 1){throw "Missing or ambiguous reviewed reference: $($case.family) $($case.name) $($case.label)"}
    $row=$rows[0]
    $key="$($case.family)|$($row.canonicalGuide)|$($case.label)"
    if($seen.ContainsKey($key)){throw 'Duplicate label decision.'};$seen[$key]=$true
    [uint64]$a=1;[uint64]$b=0
    foreach($byte in $hardcoreUtf8.GetBytes($body)){$a=($a+$byte)%65521;$b=($b+$a)%65521}
    $adler=$b*65536+$a
    $columns=@($case.family,$row.canonicalGuide,'completewith',$case.label,$case.kind,(Get-HardcoreHash335 $body),[string]$adler,$row.profiles,$case.reason)
    if(@($columns | Where-Object {$_ -match '[\t\r\n]'}).Count){throw 'Invalid evidence field.'}
    $lines.Add($columns -join "`t")
}
$text=($lines -join "`n")+"`n"
$destination=[IO.Path]::GetFullPath($OutputPath)
if($Check){
    if([IO.File]::ReadAllText($destination,$hardcoreUtf8).Replace("`r`n","`n") -cne $text){throw 'Label evidence changed: content, profile inventory or decision differs.'}
}else{
    if(Test-Path -LiteralPath $destination){throw 'Preserve evidence; use a new output path.'}
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    [IO.File]::WriteAllText($destination,$text,$hardcoreUtf8)
}
Write-Output "Bound $($seen.Count) decisions to exact chapter hashes and observed profiles; Lua production checks still required."
