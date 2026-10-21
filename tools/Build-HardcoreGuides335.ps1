[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [string]$SelectionPath = '',
    [string]$LocalSourcesPath = '',
    [switch]$Preview
)
# Reproducible selected content only. No dependency on ignored historical files.
# Public local inputs preserve their original source identities and hashes.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
if (-not $SelectionPath) { $SelectionPath = Join-Path $PSScriptRoot 'data/Hardcore-Published335/curated.json' }
if (-not $LocalSourcesPath) { $LocalSourcesPath = Join-Path $PSScriptRoot 'data/Hardcore-Curated335/local-sources.json' }
$destination = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $destination) { throw 'Use a new candidate directory; never overwrite historical evidence.' }
$utf8 = $hardcoreUtf8
$sourceVersion = 'v4.11.11'
$instanceShortcut = '(?i)ghetto\s*hearth|^\s*\.link\s+/run\b[^\r\n]*\b(?:InviteUnit|LeaveParty)\s*\('
$unstuckShortcut = '(?i)character unstuck|unstuck self.service|self.service.*unstuck|^\s*\.link\s+https?://[^\s]*battle\.net/support/[^\s]*(?:/834/solution|/32275)'
function Get-SourceHash([string]$Text) { Get-HardcoreHash335 $Text }
function Get-Header([string]$Text, [string]$Name) {
    $found = [regex]::Match($Text, '(?m)^#' + [regex]::Escape($Name) + '\s+([^\r\n]+)')
    if ($found.Success) { return $found.Groups[1].Value.Trim() }
    return ''
}
$index = Read-HardcoreUpstream335 $SourceRoot
$blocks = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
$inventory = [Collections.Generic.List[object]]::new()
foreach ($id in (Sort-HardcoreStrings335 $index.Keys)) {
    $block = $index[$id]
    $blocks.Add($id, $block.content)
    $inventory.Add([ordered]@{id=$id;sourceHash=$block.sourceHash;origin='upstream'})
}
$localSources = [IO.File]::ReadAllText([IO.Path]::GetFullPath($LocalSourcesPath), $utf8) | ConvertFrom-Json
if ($localSources.schemaVersion -ne 1 -or $localSources.blocks.Count -ne 11) { throw 'Invalid pinned local sources.' }
foreach ($block in $localSources.blocks) {
    if (-not $block.id.StartsWith('local/') -or $blocks.ContainsKey($block.id) -or
        (Get-SourceHash $block.content) -cne $block.sourceHash) { throw 'Corrupt or duplicate local source block.' }
    $blocks.Add($block.id, $block.content)
    $inventory.Add([ordered]@{id=$block.id;sourceHash=$block.sourceHash;origin='pinned-local-block'})
}
$catalog = [ordered]@{schemaVersion=1;upstreamVersion=$sourceVersion
    attribution='RestedXP Guides and existing RXPGuides 3.3.5 native-route adaptations; retain original licenses and notices.'
    guides=@($inventory.ToArray())}
$generated = [Collections.Generic.List[string]]::new()
$selectedRecords = [Collections.Generic.List[object]]::new()
$routes = [Collections.Generic.List[object]]::new()
$keys = @{}
if ($SelectionPath) {
    $selection = [IO.File]::ReadAllText([IO.Path]::GetFullPath($SelectionPath), $utf8) | ConvertFrom-Json
    if ($selection.schemaVersion -ne 1) { throw 'Unsupported Hardcore selection schema.' }
    foreach ($entry in $selection.guides) {
        if (-not $blocks.ContainsKey([string]$entry.id)) { throw "Unknown source block: $($entry.id)" }
        $content = $blocks[$entry.id]
        if ((Get-SourceHash $content) -cne $entry.sourceHash) { throw "Source changed; review required: $($entry.id)" }
        if ($entry.faction -notin @('Alliance','Horde')) { throw 'Invalid faction.' }
        # A reviewed initial segment may stop at an exact authored step label.
        # The full source remains hash-pinned; never trim by an unstable line
        # number or allow a missing/ambiguous boundary to select another route.
        if ($entry.PSObject.Properties['stopBeforeLabel']) {
            $label = $entry.stopBeforeLabel
            if ($label -isnot [string] -or $label -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
                throw 'Invalid segment boundary label.'
            }
            $matches = @([regex]::Matches($content, '(?ms)^step\b[^\n]*\n.*?(?=^step\b|\z)') |
                Where-Object { $_.Value -match ('(?m)^\s*#label[ \t]+' + [regex]::Escape($label) + '[ \t]*$') })
            if ($matches.Count -ne 1 -or $matches[0].Index -le $content.IndexOf("`nstep") + 1) {
                throw 'Missing, ambiguous or empty segment boundary.'
            }
            $content = $content.Substring(0, $matches[0].Index).TrimEnd() + "`n"
        }
        foreach ($replacement in $entry.replacements) {
            $from = [string]$replacement.from
            $expected = 1
            if ($replacement.PSObject.Properties['occurrences']) {
                # Windows PowerShell and pwsh can deserialize JSON integers
                # as different CLR integer types. Neither accepts fractions.
                if (($replacement.occurrences -isnot [int] -and $replacement.occurrences -isnot [long]) -or
                    $replacement.occurrences -lt 1 -or $replacement.occurrences -gt 100) {
                    throw "Replacement occurrences must be an integer from 1 to 100: $($entry.id)"
                }
                $expected = $replacement.occurrences
            }
            if (-not $from -or ($content.Split(@($from), [StringSplitOptions]::None).Count - 1) -ne $expected) {
                throw "Replacement must match exactly $expected occurrence(s): $($entry.id)"
            }
            $content = $content.Replace($from, [string]$replacement.to)
        }
        $stepAt = $content.IndexOf("`nstep")
        if ($stepAt -lt 0) { throw 'Selected guide has no steps.' }
        $header = $content.Substring(0, $stepAt + 1)
        # Combining headers must not erase a class/race/season restriction.
        # Any complex predicate needs an explicit, exact reviewed replacement
        # in the recipe before this intentionally narrow normalization runs.
        $sourceConditions = @([regex]::Matches($header, '(?m)^<<\s*([^\n]+)') |
            ForEach-Object { $_.Groups[1].Value.Trim() })
        if ($sourceConditions.Count -ne 1 -or $sourceConditions[0] -cne [string]$entry.faction) {
            throw "Unsupported source eligibility; curate the header explicitly: $($entry.id)"
        }
        $header = [regex]::Replace($header, '(?m)^(?:#(?:classic|tbc|wotlk|hardcore|softcore|group|subgroup|next)\b[^\n]*|<<[^\n]*)\n?', '')
        $faction = [string]$entry.faction
        $suffix = if ($faction -eq 'Alliance') { 'A' } else { 'H' }
        $group = "RestedXP Hardcore Guides ($suffix)"
        $name = Get-Header $header 'name'
        $key = "$group|$name"
        $range = [regex]::Match($name, '^(\d{1,2})-(\d{1,2})(?!\d)')
        if (-not $range.Success -or [int]$range.Groups[1].Value -lt 1 -or
            [int]$range.Groups[2].Value -gt 60 -or
            [int]$range.Groups[1].Value -gt [int]$range.Groups[2].Value) {
            throw "Hardcore curation is limited to Azeroth level 1-60 chapters: $key"
        }
        if ($keys.ContainsKey($key)) { throw "Duplicate curated identity: $key" }
        $keys[$key] = $true
        if ([string]$entry.subgroup -notmatch '^Hardcore \d+-\d+$') { throw 'Invalid level subgroup.' }
        $header = "#hardcore`n<< ac335 $faction !DK`n#group $group`n#subgroup $($entry.subgroup)`n" + $header.Trim() + "`n"
        if ($entry.next) { $header += "#next $($entry.next)`n" }
        $body = $content.Substring($stepAt + 1)
        if (-not $entry.next) {
            if ([int]$range.Groups[2].Value -eq 60) {
                $body += "`nstep`n    +This Hardcore Azeroth route ends at level 60. There is no automatic Outland or Northrend continuation. Deathless guidance does not enforce server rules or guarantee survival.`n"
            } else {
                $body += "`nstep`n    +This is the end of the currently curated Hardcore chapter. Later chapters are not yet available; do not assume a normal speedrun continuation is deathless-safe.`n"
            }
        }
        # Upstream starters often begin with a wrong-race warning step. Putting
        # the disclaimer there hides it from precisely the intended players.
        # Use an unconditional, explicitly acknowledged introduction instead.
        $body = "step`n    +Deathless guidance only: RXPGuides does not enforce server Hardcore rules or guarantee survival. Check this instruction to continue.`n" + $body
        $output = $header + "`n" + $body.TrimEnd() + "`n"
        # These starter zones are intentionally allowed: Eversong, Ghostlands,
        # Azuremyst and Bloodmyst. Expansion continents are not in this family.
        $outsideAzeroth = 'Hellfire Peninsula|Zangarmarsh|Terokkar Forest|Nagrand|Blade.s Edge Mountains|Netherstorm|Shadowmoon Valley|Shattrath City|Borean Tundra|Howling Fjord|Dragonblight|Grizzly Hills|Zul.Drak|Sholazar Basin|The Storm Peaks|Icecrown|Crystalsong Forest|Wintergrasp|Dalaran'
        if ($output -match ('(?mi)^\s*\.(?:goto|groundgoto|flygoto|waypoint|zone|fly|fp|hs)\s+(?:'+$outsideAzeroth+')(?=[,/ \t\r\n]|$)')) {
            throw "Hardcore curation contains travel outside the Azeroth rollout: $key"
        }
        if ($entry.nativeEarlyRoute) {
            if ($entry.nativeEarlyRoute -isnot [bool] -or $faction -ne 'Horde') {
                throw "Invalid native early-route declaration: $key"
            }
            # This policy is explicit per early chapter, not a ban on later
            # legitimate Horde travel to the Eastern Kingdoms.
            $foreign = 'Tirisfal Glades|Undercity|Silvermoon City|Eversong Woods|Ghostlands'
            $foreignIds = '1420|1458|1954|1941|1942'
            if ($output -match ('(?mi)^\s*\.(?:goto|groundgoto|flygoto|waypoint|zone|fly|fp|hs)\s+(?:' +
                $foreign + '|' + $foreignIds + ')(?=[,/ \t\r\n]|$)') -or
                $output -match ('(?mi)^(?:#next\s+|\s*\.next\s+)[^\r\n]*(?:' + $foreign + ')')) {
                throw "Native early route contains an Eastern Kingdoms transfer: $key"
            }
        }
        # Death shortcuts can be authored as prose or ordinary .goto text.
        # Match specific travel instructions, not quest titles such as
        # "Princess Must Die!" or warnings about enemy respawn timers.
        $deathTravel = '(?mi)^\s*\.(?:deathskip|logout)\b|logout\s*skip|\bdie and respawn\b|\buse Life Tap to die\b|\bafraid to die if\b'
        if (-not $Preview -and $output -match $deathTravel) {
            throw "Curated chapter still contains a death/logout shortcut: $key"
        }
        if (-not $Preview -and ($output -split "`n" | Where-Object { $_ -match $instanceShortcut })) {
            throw "Curated chapter still contains an instance-ejection shortcut: $key"
        }
        if (-not $Preview -and ($output -split "`n" | Where-Object { $_ -match $unstuckShortcut })) {
            throw "Curated chapter still contains an external-unstuck shortcut: $key"
        }
        if (-not $Preview -and $entry.reviewedHash -cne (Get-SourceHash $output)) {
            throw "Curated output must be reviewed and pinned before generation: $key; hash=$(Get-SourceHash $output)"
        }
        $generated.Add("RXPGuides.RegisterGuide([[`n$output]])")
        $routes.Add([pscustomobject]@{ Key = $key; Group = $group; Next = [string]$entry.next; Body = $body })
        $selectedRecords.Add([ordered]@{key = $key; source = $entry.id; sourceHash = $entry.sourceHash; outputHash = Get-SourceHash $output; reviewed = -not [bool]$Preview})
    }
}
# Check both header and directive handoffs. A resolved key is only structural
# evidence: carried quests, location and solo XP continuity still need review.
foreach ($route in $routes) {
    $handoffs = [Collections.Generic.List[string]]::new()
    if ($route.Next) { $handoffs.Add($route.Next) }
    foreach ($match in [regex]::Matches($route.Body, '(?m)^\s*\.next\s+([^\n]+)')) {
        $handoffs.Add(($match.Groups[1].Value -split '\s*(?:<<|>>|--)')[0].Trim())
    }
    foreach ($handoff in $handoffs) {
        foreach ($raw in $handoff.Split(';')) {
            $candidate = $raw.Trim()
            $group = $route.Group
            if ($candidate.Contains('\')) {
                $parts = $candidate.Split(@('\'), 2, [StringSplitOptions]::None)
                $group, $candidate = $parts[0].Trim(), $parts[1].Trim()
            }
            if ($group -cne $route.Group) { throw "Hardcore handoff leaves its faction family: $($route.Key)" }
            if (-not $candidate -or -not $keys.ContainsKey("$group|$candidate")) {
                throw "Hardcore handoff is not included in this staged selection: $($route.Key) -> $candidate"
            }
            if ("$group|$candidate" -ceq $route.Key) { throw "Hardcore chapter loops into itself: $($route.Key)" }
        }
    }
}
# Prepare and validate everything before replacing any generated output.
[void][IO.Directory]::CreateDirectory($destination)
[IO.File]::WriteAllText((Join-Path $destination 'inventory.json'), ($catalog | ConvertTo-Json -Depth 8) + "`n", $utf8)
if ($SelectionPath) {
    $outputName = if ($Preview) { 'Hardcore335.preview.lua' } else { 'Hardcore335.lua' }
    [IO.File]::WriteAllText((Join-Path $destination $outputName), "-- Generated offline by Build-HardcoreGuides335.ps1; do not edit directly.`n-- Source: RestedXP $sourceVersion. Preview=$([bool]$Preview); never load an unreviewed preview.`n" + ($generated -join "`n`n") + "`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $destination 'selected.json'), (@($selectedRecords.ToArray()) | ConvertTo-Json -Depth 5) + "`n", $utf8)
}
Write-Host "Hardcore inventory: $($inventory.Count) source guides; $($generated.Count) selected blocks (preview=$([bool]$Preview)). No manifest was modified."
