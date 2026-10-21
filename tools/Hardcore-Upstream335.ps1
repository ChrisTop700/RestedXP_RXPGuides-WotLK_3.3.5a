# Shared offline index. Source envelopes are never executed or copied.
# Family comes from the source path, NOT its group: late TBC blocks reuse
# Classic group names. All matching below is ordinal and case-sensitive.
$hardcoreUtf8 = New-Object Text.UTF8Encoding($false, $true)
function Get-HardcoreEnvelope335([string]$Family,[string]$Faction) {
    if ($Family -cnotin @('classic','tbc') -or $Faction -cnotin @('Alliance','Horde')) {
        throw 'Unknown Hardcore envelope identity.'
    }
    $condition = "ac335 $Faction !DK"
    if ($Family -ceq 'classic') { $condition += ' !Draenei !BloodElf' }
    return $condition
}
function ConvertTo-HardcoreJson335($Value) {
    # PS5/pwsh differ in pretty-printing and HTML escaping. Emit one explicit
    # UTF-8 representation so generated evidence hashes do not depend on host.
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) {
        $escaped = [regex]::Replace($Value, '[\x00-\x1f"\\]', {
            param($m)
            $code = [int][char]$m.Value
            if ($code -eq 34) { return '\"' }
            if ($code -eq 92) { return '\\' }
            return '\u' + $code.ToString('x4', [Globalization.CultureInfo]::InvariantCulture)
        })
        return '"' + $escaped + '"'
    }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [Collections.IDictionary]) {
        $pairs = foreach ($key in $Value.Keys) {
            (ConvertTo-HardcoreJson335 ([string]$key)) + ':' + (ConvertTo-HardcoreJson335 $Value[$key])
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = foreach ($item in $Value) { ConvertTo-HardcoreJson335 $item }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [ValueType]) {
        $number = [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
        if ($number -notmatch '^-?\d+(?:\.\d+)?(?:[Ee][+-]?\d+)?$') { throw 'Non-finite or unsupported JSON number.' }
        return $number
    }
    if ($Value -is [pscustomobject]) {
        $pairs = foreach ($property in $Value.PSObject.Properties) {
            (ConvertTo-HardcoreJson335 $property.Name) + ':' + (ConvertTo-HardcoreJson335 $property.Value)
        }
        return '{' + ($pairs -join ',') + '}'
    }
    throw 'Unsupported evidence value.'
}
function Sort-HardcoreStrings335($Values) {
    $sorted = [string[]]@($Values)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    return $sorted
}
function Sort-HardcoreRecords335($Records, [string[]]$Fields) {
    $buckets = [Collections.Generic.SortedDictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($record in $Records) {
        $key = (@($Fields | ForEach-Object { [string]$record.$_ }) -join [char]0)
        if (-not $buckets.ContainsKey($key)) { $buckets.Add($key, [Collections.Generic.List[object]]::new()) }
        $buckets[$key].Add($record)
    }
    foreach ($bucket in $buckets.Values) { foreach ($record in $bucket) { $record } }
}
function Get-HardcoreHash335([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($hardcoreUtf8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-HardcoreHeader335([string]$Header, [string]$Name) {
    $matches = [regex]::Matches($Header, '(?m)^#' + [regex]::Escape($Name) + '[ \t]+([^\n]+)')
    return @($matches | ForEach-Object { $_.Groups[1].Value.Trim() })
}
function Get-HardcoreStepCount335([string]$Text) {
    # Runtime syntax permits indentation. Never silently omit those steps from
    # output receipts or final manifest baselines.
    return [regex]::Matches($Text, '(?m)^[ \t]*step\b').Count
}
function Read-HardcoreUpstream335([string]$SourceRoot) {
    $base = [IO.Path]::GetFullPath($SourceRoot)
    $toc = [IO.File]::ReadAllText((Join-Path $base 'RXPGuides.toc'), $hardcoreUtf8)
    if ($toc -notmatch '(?m)^## Version:[ \t]*v4\.11\.11[ \t]*\r?$') {
        throw 'This integration is pinned to upstream v4.11.11.'
    }
    $index = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($folder in @('Guides/SurvivalGuide', 'Guides/tbc')) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $base $folder) -Filter '*.lua' | Sort-Object Name) {
            if ($folder -eq 'Guides/tbc' -and $file.Name -notlike '*Hardcore*' -and
                $file.Name -cne 'The Burning Crusade.lua') { continue }
            $relative = $folder + '/' + $file.Name
            $family = if ($folder -eq 'Guides/SurvivalGuide') { 'classic' } else { 'tbc' }
            $text = [IO.File]::ReadAllText($file.FullName, $hardcoreUtf8).Replace("`r`n", "`n").Replace("`r", "`n")
            foreach ($match in [regex]::Matches($text, '(?ms)^RXPGuides\.RegisterGuide\(\[\[(.*?)^\s*\]\]\)\s*;?')) {
                $content = $match.Groups[1].Value.Trim()
                $header = ($content -split '(?m)^step\b', 2)[0]
                $groups = @(Get-HardcoreHeader335 $header 'group')
                if ($groups.Count -ne 1 -or $groups[0] -notmatch 'Survival Guide \(([AH])\)$') { continue }
                $faction = if ($Matches[1] -ceq 'A') { 'Alliance' } else { 'Horde' }
                $names = @(Get-HardcoreHeader335 $header 'name')
                if ($names.Count -ne 1) { throw "Ambiguous source name: $relative" }
                $name = $names[0]
                if ($name -notmatch '^(\d+)-(\d+)(?!\d)') { throw "Missing level range: $relative|$name" }
                $low, $high = [int]$Matches[1], [int]$Matches[2]
                $id = "$relative|$($groups[0])|$name"
                if ($index.ContainsKey($id)) { throw "Duplicate source block: $id" }
                $index.Add($id, [pscustomobject][ordered]@{
                    id = $id; file = $relative; family = $family; faction = $faction
                    group = $groups[0]; name = $name; low = $low; high = $high
                    sourceHash = Get-HardcoreHash335 $content
                    steps = Get-HardcoreStepCount335 $content
                    next = @(Get-HardcoreHeader335 $header 'next')
                    content = $content
                })
            }
        }
    }
    if (-not $index.Count) { throw 'No Survival blocks found.' }
    return ,$index
}

function Get-HardcoreSourceGraph335($Index) {
    $lookup = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($block in $Index.Values) {
        if ($block.low -lt 1 -or $block.high -gt 60) { continue }
        $key = "$($block.family)|$($block.faction)|$($block.name)"
        if ($lookup.ContainsKey($key)) { throw "Conflicting family identity: $key" }
        $lookup.Add($key, $block)
    }
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $queue = [Collections.Generic.Queue[object]]::new()
    $roots = @(Sort-HardcoreRecords335 @($lookup.Values | Where-Object { $_.low -eq 1 }) @('id'))
    foreach ($root in $roots) { $queue.Enqueue($root) }
    $edges = [Collections.Generic.List[object]]::new()
    $issues = [Collections.Generic.List[object]]::new()
    while ($queue.Count) {
        $block = $queue.Dequeue()
        if (-not $visited.Add($block.id)) { continue }
        $headers = @($block.next)
        # Do not erase in-body .next directives or overlook their destinations.
        $directives = @([regex]::Matches($block.content, '(?m)^\s*\.next[ \t]+([^\r\n]+)') |
            ForEach-Object { $_.Groups[1].Value })
        $transitions = @($headers) + @($directives)
        if (-not $transitions.Count -and $block.high -ne 60) {
            $issues.Add([ordered]@{id=$block.id; kind='premature-endpoint'; destination=''})
        }
        foreach ($raw in $transitions) {
            # Preserve the condition in evidence. This graph is a superset,
            # not proof that every class/rate branch can take each edge.
            $unconditional = ($raw -split '[ \t]+<<', 2)[0]
            foreach ($part in $unconditional -split ';') {
                $destination = $part.Trim()
                $qualified = $destination.LastIndexOf('\')
                if ($qualified -ge 0) {
                    $group = $destination.Substring(0, $qualified)
                    $destination = $destination.Substring($qualified + 1).Trim()
                    $suffix = if ($block.faction -eq 'Alliance') { 'A' } else { 'H' }
                    if ($group -cne "RestedXP Survival Guide ($suffix)" -and
                        $group -cne "RXP TBC Survival Guide ($suffix)") {
                        $issues.Add([ordered]@{id=$block.id; kind='foreign-group'; destination=$part})
                        continue
                    }
                }
                $targetKey = "$($block.family)|$($block.faction)|$destination"
                $target = $null
                $exists = $lookup.TryGetValue($targetKey, [ref]$target)
                # Only a chapter already ending at 60 may truncate a >60 handoff.
                $terminal = $block.high -eq 60 -and $destination -match '^60-(?:6[1-9]|[7-9]\d)\b'
                $edges.Add([ordered]@{
                    from=$block.id; raw=$raw; destination=$destination
                    to=$(if ($exists) {$target.id} else {''})
                    endpointTruncation=[bool]$terminal
                })
                if ($terminal) { continue }
                if (-not $exists) {
                    $issues.Add([ordered]@{id=$block.id; kind='unresolved-transition'; destination=$destination})
                } else { $queue.Enqueue($target) }
            }
        }
    }
    return [ordered]@{
        roots=@($roots | ForEach-Object {$_.id})
        selected=@(Sort-HardcoreStrings335 $visited)
        excluded=@(Sort-HardcoreStrings335 @($Index.Keys | Where-Object {-not $visited.Contains($_)}))
        edges=@(Sort-HardcoreRecords335 $edges @('from','raw','destination'))
        issues=@(Sort-HardcoreRecords335 $issues @('id','kind','destination'))
    }
}
# Committed outputs and historical previews are mutually exclusive inputs.
# A stale preview beside a published file must not silently win validation.
function Get-HardcoreOutputPath335([string]$Directory,[string]$Family) {
    $published=@{classic='Hardcore-Classic.lua';tbc='Hardcore-TBC.lua';curated='Hardcore-Curated.lua'}
    if(-not $published.ContainsKey($Family)){throw 'Unknown Hardcore family.'}
    $preview=Join-Path $Directory $(if($Family -ceq 'curated'){'Hardcore335.preview.lua'}else{"Hardcore-$Family.preview.lua"})
    $final=Join-Path $Directory $published[$Family]
    $old=Test-Path -LiteralPath $preview -PathType Leaf
    $new=Test-Path -LiteralPath $final -PathType Leaf
    if($old -eq $new){throw "Expected exactly one preview or published input for $Family"}
    if($old){return $preview};return $final
}
