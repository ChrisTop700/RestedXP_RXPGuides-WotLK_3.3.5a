[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidateRoot,
    [Parameter(Mandatory=$true)][string]$CuratedRoot,
    [string]$ReportPath='build/hardcore-quest-flow/labels.tsv',
    [string]$LuaCommand='',
    [string]$LabelEvidencePath='',
    [string]$LabelReviewReport='',
    [switch]$AllowLabelReviews
)
# Separate from the normal 1-80 checker: quest providers/rewards and branch
# identities from one Hardcore family cannot validate another family.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($ReportPath -cnotmatch '^build/[A-Za-z0-9_./-]+\.tsv$' -or $ReportPath.Contains('..')){
    throw 'ReportPath must be a relative build/*.tsv artifact.'
}
if(-not $LuaCommand){
    $lua=Get-Command lua5.1,lua -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $lua){throw 'Lua 5.1 is required for production-parser Hardcore quest-flow checks.'}
    $LuaCommand=$lua.Source
}
$candidate=[IO.Path]::GetFullPath($CandidateRoot)
$curated=[IO.Path]::GetFullPath($CuratedRoot)
if($LabelEvidencePath){
    if(-not $LabelReviewReport){throw 'Label evidence requires its full review inventory.'}
    & (Join-Path $PSScriptRoot 'Export-HardcoreLabelEvidence335.ps1') `
        -UpstreamRoot $candidate -CuratedRoot $curated -ReviewReport $LabelReviewReport `
        -OutputPath $LabelEvidencePath -Check
}
$destination=Join-Path $root $ReportPath
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
Push-Location -LiteralPath $root
try {
    & $LuaCommand -e 'assert(_VERSION == [[Lua 5.1]], [[Lua 5.1 required]])'
    if($LASTEXITCODE -ne 0){throw 'Wrong Lua interpreter.'}
    $arguments=@('tests/hardcore-upstream-loading.lua','.', $candidate,$curated,
        '--quest-flow',$ReportPath)
    $arguments+= $(if($AllowLabelReviews){'--audit-labels'}else{'--require-clean-labels'})
    if($LabelEvidencePath){$arguments+=[IO.Path]::GetFullPath($LabelEvidencePath)}
    & $LuaCommand @arguments
    if($LASTEXITCODE -ne 0){throw 'Hardcore quest-flow/branch validation failed; do not publish the candidates.'}
} finally {Pop-Location}
