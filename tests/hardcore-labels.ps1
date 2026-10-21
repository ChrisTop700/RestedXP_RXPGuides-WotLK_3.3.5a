[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RecipePath,
      [Parameter(Mandatory=$true)][string]$CuratedSelection)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Labels335.ps1')
function Assert($Value,[string]$Message){if(-not $Value){throw $Message}}
$count=0
foreach($path in @($RecipePath,$CuratedSelection)){
    $recipe=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    foreach($entry in $recipe.guides){
        foreach($edit in $entry.replacements){
            if($edit.kind -cne 'reviewed-label-repair'){continue}
            Assert ($entry.sourceHash -match '^[0-9a-f]{64}$') 'Unbound label repair.'
            Assert ($edit.occurrences -eq 1 -and $edit.reason -and $edit.attribution) 'Ambiguous or unattributed repair.'
            # Labels and two modern-control prose lines are the only mutable
            # fields. Conditions, all directives, actions and step headers
            # must be byte-identical and retain their authored order.
            $before=@([regex]::Matches($edit.from,'(?m)^[ \t]*(?:\.|step\b)[^\n]*') | ForEach-Object {$_.Value})
            $after=@([regex]::Matches($edit.to,'(?m)^[ \t]*(?:\.|step\b)[^\n]*') | ForEach-Object {$_.Value})
            Assert (($before -join "`n") -ceq ($after -join "`n")) 'Label repair changed an authored action or condition.'
            if($edit.from -match '#requires AntiVenomEnd\s'){
                Assert ($edit.to -notmatch '#requires AntiVenomEnd') 'Preparation depends on its future crafting/use step.'
                Assert ($edit.to -match '\.(?:aura|itemcount)\b') 'First Aid guard was removed.'
            }
            $count++
        }
    }
}
Assert ($count -eq 109) 'Reviewed repair inventory changed; review before updating this assertion.'
Write-Output "Label repair preservation passed: $count source-bound replacements; operational lines unchanged."
