$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$validator = Join-Path $root 'tools/Test-ReleaseArchive335.ps1'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$output = Join-Path $root 'build/release-archive-tests'
[void][IO.Directory]::CreateDirectory($output)
$prefix = [Guid]::NewGuid().ToString('N')
$source = Join-Path $output ($prefix + '-valid.zip')
$candidate = Join-Path $output ($prefix + '-invalid.zip')
$policy = Join-Path $output ($prefix + '-exclusions.txt')
$safeRoot = $root.Replace('\', '/')
$passed = $false
try {
    & git -c "safe.directory=$safeRoot" -C $root archive --worktree-attributes --format=zip --prefix=RXPGuides/ "--output=$source" HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Could not build release archive fixture.' }
    & $validator -ArchivePath $source

    function Test-RejectedArchive335([string]$Name, [scriptblock]$Mutate, [string]$Expected) {
        [IO.File]::Copy($source, $candidate, $true)
        $archive = [IO.Compression.ZipFile]::Open($candidate, [IO.Compression.ZipArchiveMode]::Update)
        try { & $Mutate $archive } finally { $archive.Dispose() }
        $failure = $null
        try { & $validator -ArchivePath $candidate } catch { $failure = $_.Exception.Message }
        if (-not $failure -or $failure -notmatch $Expected) {
            throw "Archive rejection '$Name' failed; expected '$Expected', got '$failure'."
        }
    }
    Test-RejectedArchive335 'runtime dependency removed' {
        param($archive) $archive.GetEntry('RXPGuides/Compat/Bootstrap.lua').Delete()
    } 'Required release file is missing: Compat/Bootstrap.lua'
    Test-RejectedArchive335 'bundled assets removed' {
        param($archive)
        $asset = @($archive.Entries | Where-Object { $_.FullName -like 'RXPGuides/Textures/*' -and $_.Name })[0]
        if (-not $asset) { throw 'Asset fixture is missing.' }
        $asset.Delete()
    } 'Required release file is missing: Textures/'
    Test-RejectedArchive335 'developer payload leaked' {
        param($archive) [void]$archive.CreateEntry('RXPGuides/tools/private-build.txt')
    } 'Developer-only archive entry:'
    Test-RejectedArchive335 'private archive leaked' {
        param($archive) [void]$archive.CreateEntry('RXPGuides/.local/cleanup-archives/private.zip')
    } 'Developer-only archive entry:'
    Test-RejectedArchive335 'dormant asset leaked' {
        param($archive) [void]$archive.CreateEntry('RXPGuides/Textures/Hardcore/intro_ui.tga')
    } 'Excluded source/asset leaked:'
    Test-RejectedArchive335 'extra root' {
        param($archive) [void]$archive.CreateEntry('OtherAddon/leak.txt')
    } 'outside the single RXPGuides root:'
    Test-RejectedArchive335 'duplicate runtime entry' {
        param($archive) [void]$archive.CreateEntry('RXPGuides/Compat/Bootstrap.lua')
    } 'Duplicate archive entry:'
    Test-RejectedArchive335 'missing nested XML dependency' {
        param($archive)
        $entry = $archive.GetEntry('RXPGuides/GuideList_335.xml')
        $entry.Delete()
        $writer = [IO.StreamWriter]::new($archive.CreateEntry('RXPGuides/GuideList_335.xml').Open())
        try { $writer.Write('<Ui><Script file="Guides/Missing-Archive-Dependency.lua" /></Ui>') }
        finally { $writer.Dispose() }
    } 'Missing archive dependency: Guides/Missing-Archive-Dependency.lua'
    $reviewed = @(Get-Content (Join-Path $root 'packaging/release-exclusions.txt'))
    foreach ($case in @(
        @{extra='Compat/Bootstrap.lua'; expected='Loaded resource cannot be excluded: Compat/Bootstrap.lua'},
        @{extra='UI/HardcoreIntro.lua'; expected='duplicate release exclusion'},
        @{extra='../private.txt'; expected='Invalid or duplicate release exclusion'}
    )) {
        [IO.File]::WriteAllLines($policy, [string[]]@($reviewed + $case.extra))
        $failure=$null
        try { & $validator -ArchivePath $source -ExclusionPath $policy } catch { $failure=$_.Exception.Message }
        if(-not $failure -or $failure -notmatch $case.expected){throw "Release exclusion rejection failed: $failure"}
    }
    Write-Host 'Release archive regressions passed: real git archive, eight payload rejections and three exclusion-policy rejections.'
    $passed = $true
} finally {
    # Exact, uniquely named artifacts created above; no recursive cleanup.
    foreach ($path in @($source, $candidate, $policy)) {
        if ($passed -and [IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    }
}
