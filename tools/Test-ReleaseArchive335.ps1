param(
    [string]$ArchivePath,
    [string]$Revision = 'HEAD'
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Invoke-ArchiveGit335([string[]]$Arguments) {
    $result = @(& git -c "safe.directory=$($root.Replace('\', '/'))" -C $root @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments[0]) failed ($LASTEXITCODE)." }
    return $result
}

$temporaryArchive = $false
if (-not $ArchivePath) {
    $output = Join-Path $root 'build/release-archive-validation'
    [void][IO.Directory]::CreateDirectory($output)
    $ArchivePath = Join-Path $output ('RXPGuides-' + [Guid]::NewGuid().ToString('N') + '.zip')
    # Local tests must exercise newly edited export-ignore rules before a commit.
    # Tagged releases still use the attributes recorded in the release commit.
    Invoke-ArchiveGit335 @('archive', '--worktree-attributes', '--format=zip',
        '--prefix=RXPGuides/', "--output=$ArchivePath", $Revision) | Out-Null
    $temporaryArchive = $true
}
$ArchivePath = [IO.Path]::GetFullPath($ArchivePath)

$runtimeFolders = '^(Compat|Core|DB|Features|Fonts|Guide|Guides|libs|locale|Textures|UI)/'
$forbidden = '^(\.git(?:/|$)|\.github/|\.gitattributes$|\.gitignore$|tools/|tests/|packaging/|build/|Hardcore_Workbench/|\.validation-cache/|LOCALIZATIONS\.lock$)'
$requiredRoot = @('RXPGuides.toc', 'Bindings.xml', 'GuideList_335.xml',
    'Talents_wotlk_335.xml', 'LICENSE', 'README.md', 'FEATURES_335.md',
    'LOCALIZATION.md', 'CHANGELOG.md')
$tracked = @(Invoke-ArchiveGit335 @('ls-tree', '-r', '--name-only', $Revision))
$expected = @($tracked | Where-Object { $_ -cmatch $runtimeFolders -or $_ -cin $requiredRoot })
$zip = $null
try {
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $entries = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName
        if (-not $name.StartsWith('RXPGuides/', [StringComparison]::Ordinal) -or
            $name.Contains('\') -or $name -match '(^|/)\.\.?(/|$)') {
            throw "Archive entry is outside the single RXPGuides root: $name"
        }
        $relative = $name.Substring('RXPGuides/'.Length)
        if (-not $relative) { continue }
        if ($relative -cmatch $forbidden) { throw "Developer-only archive entry: $relative" }
        if ($name.EndsWith('/')) { continue }
        if ($entries.ContainsKey($relative)) { throw "Duplicate archive entry: $relative" }
        $entries.Add($relative, $entry)
    }
    foreach ($path in @($expected) + $requiredRoot) {
        if (-not $entries.ContainsKey($path)) { throw "Required release file is missing: $path" }
    }
    $tocs = @($entries.Keys | Where-Object { $_ -match '\.toc$' })
    if ($tocs.Count -ne 1 -or $tocs[0] -cne 'RXPGuides.toc') {
        throw 'The archive must contain only the supported RXPGuides.toc manifest.'
    }

    function Read-ArchiveText335([string]$Path) {
        if (-not $entries.ContainsKey($Path)) { throw "Missing archive dependency: $Path" }
        $reader = [IO.StreamReader]::new($entries[$Path].Open())
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    function Resolve-ArchivePath335([string]$Parent, [string]$Child) {
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($part in (($Parent + '/' + $Child.Replace('\', '/')) -split '/')) {
            if (-not $part -or $part -eq '.') { continue }
            if ($part -eq '..') {
                if ($parts.Count -eq 0) { throw "Dependency escapes addon root: $Child" }
                $parts.RemoveAt($parts.Count - 1)
            } else { $parts.Add($part) }
        }
        return $parts -join '/'
    }
    $loaded = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function Read-ArchiveResource335([string]$Path) {
        if (-not $entries.ContainsKey($Path)) { throw "Missing archive dependency: $Path" }
        if (-not $loaded.Add($Path) -or -not $Path.EndsWith('.xml')) { return }
        [xml]$xml = Read-ArchiveText335 $Path
        $parent = ''
        if ($Path.Contains('/')) { $parent = $Path.Substring(0, $Path.LastIndexOf('/')) }
        foreach ($node in $xml.SelectNodes('//*[local-name()="Script" or local-name()="Include"]')) {
            $child = [string]$node.GetAttribute('file')
            if ($child) { Read-ArchiveResource335 (Resolve-ArchivePath335 $parent $child) }
        }
    }
    $toc = Read-ArchiveText335 'RXPGuides.toc'
    if ($toc -notmatch '(?m)^## Interface: 30300\s*$') { throw 'Archive targets an unexpected client.' }
    foreach ($line in ($toc -split '\r?\n')) {
        $value = $line.Trim()
        if ($value -and -not $value.StartsWith('#')) {
            Read-ArchiveResource335 (Resolve-ArchivePath335 '' $value)
        }
    }
    Write-Host ("Release archive passed: {0} files, {1} manifest resources; runtime, assets, licenses and user docs preserved." -f
        $entries.Count, $loaded.Count)
} finally {
    if ($zip) { $zip.Dispose() }
    # Only remove the uniquely named archive this invocation created itself.
    if ($temporaryArchive -and [IO.File]::Exists($ArchivePath)) { [IO.File]::Delete($ArchivePath) }
}
