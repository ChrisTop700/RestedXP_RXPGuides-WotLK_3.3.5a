[CmdletBinding()]
param([string]$CatalogPath='', [string]$FixturePath='',
    [Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-EnglishNames335.ps1')
if(-not $CatalogPath){$CatalogPath=Join-Path $PSScriptRoot '../DB/wotlk/guideEnglishNames_335.lua'}
if(-not $FixturePath){$FixturePath=Join-Path $PSScriptRoot 'data/Hardcore-EnglishItems335.json'}
$output=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $output){throw 'Generate to a new file and review before replacing the catalog.'}
$catalog=[IO.File]::ReadAllText([IO.Path]::GetFullPath($CatalogPath),$hardcoreUtf8)
$fixture=[IO.File]::ReadAllText([IO.Path]::GetFullPath($FixturePath),$hardcoreUtf8) | ConvertFrom-Json
$result=Merge-HardcoreEnglishItems335 $catalog $fixture
$quests=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'data/Hardcore-QuestFacts335.json'),$hardcoreUtf8) | ConvertFrom-Json
$result=Merge-HardcoreEnglishQuests335 $result $quests
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output,$result,$hardcoreUtf8)
Write-Output 'Generated English item/quest-name merge without changing the source catalog.'
