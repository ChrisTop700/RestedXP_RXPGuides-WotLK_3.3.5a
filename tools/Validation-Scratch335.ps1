# Internal offline helper. Only invocation-owned, successful scratch work is removed.
function Assert-ValidationScratchPath335([string]$Root, [string]$Path) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $build = Join-Path $rootPath 'build'
    $absolute = [IO.Path]::GetFullPath($Path)
    $comparison = if ([IO.Path]::DirectorySeparatorChar -eq '\') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if (-not $absolute.StartsWith($build + [IO.Path]::DirectorySeparatorChar, $comparison)) {
        throw 'Scratch path must be a child of the repository build directory.'
    }
    $walk = $absolute
    while ($walk -and $walk -ne $rootPath) {
        if ((Test-Path -LiteralPath $walk) -and
            ((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Scratch path contains a reparse point.'
        }
        $walk = [IO.Path]::GetDirectoryName($walk)
    }
    if ((Get-Item -LiteralPath $rootPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Scratch root is a reparse point.'
    }
    return $absolute
}

function New-ValidationScratch335([string]$Root, [string]$Prefix) {
    if ($Prefix -cnotmatch '^[a-z0-9][a-z0-9-]+$') { throw 'Invalid scratch prefix.' }
    $token = [Guid]::NewGuid().ToString('N')
    $path = Assert-ValidationScratchPath335 $Root (Join-Path $Root "build/$Prefix-$token")
    if (Test-Path -LiteralPath $path) { throw 'Scratch directory already exists.' }
    [void][IO.Directory]::CreateDirectory($path)
    [IO.File]::WriteAllText((Join-Path $path '.rxp-scratch-owner'), $token)
    return [pscustomobject]@{ Root=[IO.Path]::GetFullPath($Root); Path=$path; Token=$token }
}

function Complete-ValidationScratch335($Scratch, [bool]$Succeeded = $false) {
    if (-not $Succeeded) { return } # Failed diagnostics remain available.
    $path = Assert-ValidationScratchPath335 $Scratch.Root $Scratch.Path
    $marker = Join-Path $path '.rxp-scratch-owner'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
        [IO.File]::ReadAllText($marker) -cne $Scratch.Token) { throw 'Scratch ownership mismatch.' }
    function Assert-OwnedTree335([string]$Directory) {
        foreach ($entry in (Get-ChildItem -LiteralPath $Directory -Force)) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Scratch tree contains a reparse point.' }
            if ($entry.PSIsContainer) { Assert-OwnedTree335 $entry.FullName }
        }
    }
    Assert-OwnedTree335 $path
    Remove-Item -LiteralPath $path -Recurse -Force
}
