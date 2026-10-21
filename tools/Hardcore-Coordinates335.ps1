# Offline only: source world-yard coordinates must never reach the legacy
# runtime's continent-normalized world API. No client map functions are changed.
function Convert-HardcoreWorldPoint335($Map, [double]$WorldX, [double]$WorldY) {
    $culture = [Globalization.CultureInfo]::InvariantCulture
    foreach ($value in @($WorldX, $WorldY, $Map.width, $Map.height, $Map.left, $Map.top)) {
        if ($null -eq $value -or [double]::IsNaN([double]$value) -or
            [double]::IsInfinity([double]$value)) { throw 'Invalid map geometry or point.' }
    }
    if ($Map.width -le 0 -or $Map.height -le 0 -or
        -not ($Map.name -is [string]) -or $Map.name -match '[,\r\n]' -or
        -not $Map.name.Trim()) { throw 'Invalid map dimensions/name.' }
    $x = 100 * ($Map.left - $WorldX) / $Map.width
    $y = 100 * ($Map.top - $WorldY) / $Map.height
    if ($x -lt 0 -or $x -gt 100 -or $y -lt 0 -or $y -gt 100) {
        throw "World point is outside verified map: $($Map.name)"
    }
    $textX, $textY = $x.ToString('0.######', $culture), $y.ToString('0.######', $culture)
    $roundX = $Map.left - [double]::Parse($textX, $culture) * $Map.width / 100
    $roundY = $Map.top - [double]::Parse($textY, $culture) * $Map.height / 100
    if ([math]::Abs($roundX - $WorldX) -gt 0.001 -or
        [math]::Abs($roundY - $WorldY) -gt 0.001) { throw 'Coordinate round-trip exceeds 0.001 yards.' }
    return $Map.name + ',' + $textX + ',' + $textY
}

function Get-HardcoreCoordinateEdits335([string]$Text, $Maps) {
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $pattern = '(?m)^[ \t]*\.(?:goto|groundgoto|flygoto|waypoint)[ \t]+(\d+/\d+),(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?=[,\t ]|$)[^\n]*'
    $seen = @{}
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        $from = $match.Value
        $newline = if ($match.Index + $match.Length -lt $Text.Length -and
            $Text[$match.Index + $match.Length] -eq [char]10) { "`n" } else { '' }
        $from += $newline
        if ($seen.ContainsKey($from)) { continue }
        $seen[$from] = $true
        $key = $match.Groups[1].Value
        if (-not $Maps.Contains($key)) { throw "Missing verified geometry: $key" }
        $replacement = Convert-HardcoreWorldPoint335 $Maps[$key] `
            ([double]::Parse($match.Groups[2].Value, $culture)) `
            ([double]::Parse($match.Groups[3].Value, $culture))
        $oldPoint = $key + ',' + $match.Groups[2].Value + ',' + $match.Groups[3].Value
        # Replace only this coordinate tuple. Trailing radii/conditions/prose
        # and repeated waypoints remain byte-identical.
        $offset = $match.Groups[1].Index - $match.Index
        $after = $match.Value.Substring(0, $offset) + $replacement +
            $match.Value.Substring($offset + $oldPoint.Length) + $newline
        [ordered]@{
            from = $from; to = $after
            occurrences = ($Text.Split(@($from), [StringSplitOptions]::None).Count - 1)
            reason = 'Convert world-yard coordinates using attributed legacy map bounds; preserve path order, radii and predicates. Round-trip error below 0.001 yards.'
        }
    }
}

function Read-HardcoreGeometry335([string]$Path) {
    $fixture = [IO.File]::ReadAllText([IO.Path]::GetFullPath($Path),
        [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
    if ($fixture.schemaVersion -ne 1 -or -not $fixture.source.sha256 -or
        $fixture.source.sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Invalid geometry provenance.' }
    $maps = [ordered]@{}
    foreach ($property in $fixture.maps.PSObject.Properties) {
        if ($property.Name -notmatch '^\d+/\d+$') { throw 'Invalid map key.' }
        $maps[$property.Name] = $property.Value
        # Also validates all dimensions even when this map is not used.
        $null = Convert-HardcoreWorldPoint335 $property.Value $property.Value.left $property.Value.top
    }
    return $maps
}
