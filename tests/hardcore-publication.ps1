[CmdletBinding()]
param([string]$GuideRoot='', [string]$ReceiptPath='')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/Hardcore-Publication335.ps1')
if(-not $GuideRoot){$GuideRoot=Join-Path $hardcoreRoot 'Guides/Hardcore'}
if(-not $ReceiptPath){$ReceiptPath=Join-Path $hardcoreRoot 'tools/data/Hardcore-Publication335.json'}
$validate=Join-Path $hardcoreRoot 'tools/Validate-HardcorePublication335.ps1'
& $validate -GuideRoot $GuideRoot -ReceiptPath $ReceiptPath -IntegrityOnly
$source=Get-Content -LiteralPath $ReceiptPath -Raw
. (Join-Path $hardcoreRoot 'tools/Validation-Scratch335.ps1')
$ownedScratch=New-ValidationScratch335 $hardcoreRoot 'hardcore-receipt-regressions'
$scratch=$ownedScratch.Path
$scratchSucceeded=$false
try {
[IO.File]::WriteAllText((Join-Path $scratch 'lf.txt'),"fixture`n",$hardcoreUtf8)
[IO.File]::WriteAllText((Join-Path $scratch 'crlf.txt'),"fixture`r`n",$hardcoreUtf8)
if((Get-HardcoreTextHash335 (Join-Path $scratch 'lf.txt')) -cne (Get-HardcoreTextHash335 (Join-Path $scratch 'crlf.txt'))){
    throw 'Publication text hashes differ across checkout line endings.'
}
$mutations=@(
    {param($r) $r.schemaVersion=2},
    {param($r) $r.textHashFormat='raw'},
    {param($r) $r.gameplayAccepted=$true},
    {param($r) $r.dependencies[0].sha256=('0'*64)},
    {param($r) $r.dependencies=@($r.dependencies | Select-Object -Skip 1)},
    {param($r) $r.outputs[0].sha256=('0'*64)},
    {param($r) $r.outputs[0].guides=0},
    {param($r) $r.chapters[0].bodyHash=('0'*64)},
    {param($r) $r.chapters[0].sourceId='foreign/source'},
    {param($r) $r.chapters[0].key=$r.chapters[1].key},
    {param($r) $r.chapters=@($r.chapters | Select-Object -Skip 1)}
)
$count=0
foreach($mutate in $mutations){
    $receipt=$source | ConvertFrom-Json
    & $mutate $receipt
    $path=Join-Path $scratch ('invalid-'+$count+'.json')
    [IO.File]::WriteAllText($path,(ConvertTo-HardcoreJson335 $receipt)+"`n",$hardcoreUtf8)
    $rejected=$false
    try { & $validate -GuideRoot $GuideRoot -ReceiptPath $path -IntegrityOnly | Out-Null }
    catch {$rejected=$true}
    if(-not $rejected){throw "Invalid publication receipt accepted: mutation $count"}
    $count++
}
Write-Output "Publication receipt regressions passed: $count corrupt/stale/foreign receipts rejected."
    $scratchSucceeded=$true
} finally { Complete-ValidationScratch335 $ownedScratch $scratchSucceeded }
