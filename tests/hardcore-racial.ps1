[CmdletBinding()]
param([string]$ServerSourceRoot = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot '../tools/Hardcore-Racial335.ps1')
function Assert($Value, [string]$Message) { if (-not $Value) { throw $Message } }
$recipe = Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-Racial335.json') -Raw | ConvertFrom-Json
$entries = @($recipe.guides | Where-Object {$_.replacements.kind -contains 'bloodelf-racial-objective'})
Assert ($entries.Count -eq 1) 'Racial scope changed.'
$entry = $entries[0]
$pins = Get-Content (Join-Path $PSScriptRoot '../tools/data/Hardcore-Upstream-v4.11.11.json') -Raw | ConvertFrom-Json
$pin = @($pins.blocks | Where-Object {$_.id -ceq $entry.id})
Assert ($pin.Count -eq 1 -and $pin[0].sourceHash -ceq $entry.sourceHash) 'Unpinned racial correction.'
$edit = @($entry.replacements | Where-Object {$_.kind -ceq 'bloodelf-racial-objective'})[0]
$regenerated = Get-HardcoreBloodElfRacialEdit335 $edit.from
Assert ($regenerated.to -ceq $edit.to) 'Racial correction is stale.'
function OtherActions([string]$Text) {
    @([regex]::Matches($Text,'(?m)^[ \t]*\.(?:accept|turnin|complete|collect|use|buy|abandon)[^\n]*') |
        Where-Object {$_.Value -notmatch '\.complete 8346,'} |
        ForEach-Object {$_.Value.Trim()}) -join "`n"
}
Assert ((OtherActions $edit.from) -ceq (OtherActions $edit.to)) 'Racial correction changed other quest actions or rewards.'
$body = $edit.to
Assert ([regex]::Matches($body,'(?m)^[ \t]*\.complete 8346,1\b').Count -eq 1) 'Racial objective not deduplicated.'
Assert ($body.IndexOf('.accept 8346') -lt $body.IndexOf('.complete 8346,1') -and
    $body.IndexOf('.complete 8346,1') -lt $body.IndexOf('.turnin 8346')) 'Racial objective/reward ordering changed.'
$step = @([regex]::Matches($body,'(?ms)^step\b[^\n]*\n.*?(?=^step\b|\z)') |
    Where-Object {$_.Value.Contains('.complete 8346,1')})
Assert ($step.Count -eq 1 -and $step[0].Value.StartsWith("step`n") -and
    $step[0].Value -notmatch '<<|#optional|#completewith|#requires') 'One or more classes can miss the new blocking objective.'
Assert ($step[0].Value.Contains('living Mana Wyrm') -and $step[0].Value -notmatch '\.cast') 'Racial checkpoint assumes a cast alone proves objective credit.'
Assert ($body -notmatch 'Cast[^\n]*\[Mana Tap\]|--Mana Tap creature') 'Obsolete racial instructions remain.'
$rejected = $false
try { $null = Get-HardcoreBloodElfRacialEdit335 ($edit.from.Replace('.accept 8346','.accept 999999')) }
catch { $rejected = $true }
Assert $rejected 'Missing pickup was accepted.'
if ($ServerSourceRoot) {
    $scripts = Join-Path $ServerSourceRoot 'data/sql/base/db_world/smart_scripts.sql'
    Assert ((Get-FileHash $scripts).Hash.ToLowerInvariant() -ceq
        '622b5865f171b0b7a4dd93ecba55afd673c393c579485c17f827b31cb6e47dd2') 'Racial credit fixture is stale.'
    $rows = [regex]::Matches((Get-Content $scripts -Raw),'(?m)^\(15274,[^\n]*')
    foreach ($spell in @(28730,25046)) {
        Assert (@($rows | Where-Object {$_.Value -match (',8,0,100,1,'+$spell+',') -and
            $_.Value.Contains(',11,61314,')}).Count -eq 1) 'Mana Wyrm Arcane Torrent credit differs.'
    }
}
Write-Output 'Blood Elf racial checks passed: one shared blocking objective; existing quest actions and rewards preserved.'
