[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BeforeUpstream,
    [Parameter(Mandatory=$true)][string]$BeforeCurated,
    [Parameter(Mandatory=$true)][string]$AfterUpstream,
    [Parameter(Mandatory=$true)][string]$AfterCurated,
    [Parameter(Mandatory=$true)][string]$RecipePath,
    [Parameter(Mandatory=$true)][string]$CuratedSelection
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
function Bodies([string]$Directory,[string]$Family){
    $text=[IO.File]::ReadAllText((Get-HardcoreOutputPath335 $Directory $Family),$hardcoreUtf8).Replace("`r`n","`n")
    $result=@{}
    foreach($m in [regex]::Matches($text,'(?ms)RXPGuides\.RegisterGuide\(\[\[(.*?)\]\]\)')){
        $body=$m.Groups[1].Value.Trim()+"`n"
        $key=@(Get-HardcoreHeader335 $body 'group')[0]+'|'+@(Get-HardcoreHeader335 $body 'name')[0]
        if($result.ContainsKey($key)){throw 'Duplicate chapter.'}
        $result[$key]=$body
    }
    return $result
}
$recipe=Get-Content -LiteralPath $RecipePath -Raw | ConvertFrom-Json
$selection=Get-Content -LiteralPath $CuratedSelection -Raw | ConvertFrom-Json
$upstream=Get-Content (Join-Path $BeforeUpstream 'compatibility-report.json') -Raw | ConvertFrom-Json
$curated=Get-Content (Join-Path $BeforeCurated 'selected.json') -Raw | ConvertFrom-Json
$entries=@{};foreach($entry in $recipe.guides){$entries[$entry.id]=$entry}
$curatedEntries=@{};foreach($entry in $selection.guides){$curatedEntries[$entry.id]=$entry}
$checked=0;$changed=0;$edits=0
foreach($family in @('classic','tbc','curated')){
    $before=Bodies $(if($family -ceq 'curated'){$BeforeCurated}else{$BeforeUpstream}) $family
    $after=Bodies $(if($family -ceq 'curated'){$AfterCurated}else{$AfterUpstream}) $family
    $records=if($family -ceq 'curated'){@($curated)}else{@($upstream.guides | Where-Object {$_.family -ceq $family})}
    foreach($record in $records){
        $key=$record.key
        $old=$before[$key];$new=$after[$key]
        if(-not $old -or -not $new){throw 'Chapter removed, added or renamed.'}
        if((Get-HardcoreHash335 $old) -cne $record.outputHash){throw 'Historical baseline receipt differs.'}
        $entry=if($family -ceq 'curated'){$curatedEntries[$record.source]}else{$entries[$record.id]}
        $expected=$old
        foreach($edit in $entry.replacements){
            if($edit.kind -cne 'reviewed-label-repair'){continue}
            $from=$edit.from;$to=$edit.to
            # Builders normalize only a chapter's final trailing whitespace.
            if(-not $expected.Contains($from) -and $expected.TrimEnd().EndsWith($from.TrimEnd())){
                $from=$from.TrimEnd();$to=$to.TrimEnd()
            }
            if(($expected.Split(@($from),[StringSplitOptions]::None).Count-1) -ne 1){throw "Reviewed replacement does not match baseline: $key"}
            $expected=$expected.Replace($from,$to);$edits++
        }
        if($expected.TrimEnd() -cne $new.TrimEnd()){throw "Unreviewed generated difference: $key"}
        if((Get-HardcoreStepCount335 $old) -ne (Get-HardcoreStepCount335 $new)){throw 'Label work changed the step inventory.'}
        if($old -cne $new){$changed++}
        $checked++;$before.Remove($key);$after.Remove($key)
    }
    if($before.Count -or $after.Count){throw 'Unreceipted chapters.'}
}
if($checked -ne 258 -or $edits -ne 109){throw 'Reviewed collection inventory differs.'}
Write-Output "Exact label preservation passed: $checked chapters; $changed changed; only $edits reviewed replacements; step counts unchanged."
