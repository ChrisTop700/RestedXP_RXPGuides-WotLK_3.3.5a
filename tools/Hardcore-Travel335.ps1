# Narrow ordinary-travel layer. Boat handoff review is deliberately separate:
# neither a word such as "teleport" nor a valid Theramore ferry is a defect.
function Get-HardcoreTravelEdits335([string]$Text) {
    $working = $Text
    $seen = @{}
    $edits = [Collections.Generic.List[object]]::new()
    $matches = [regex]::Matches($Text,'(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)') |
        Sort-Object @{Expression={$_.Length};Descending=$true},Index
    foreach ($match in $matches) {
        $old = $match.Value
        if ($seen.ContainsKey($old)) { continue }
        $seen[$old] = $true
        if ($old -match '(?m)^[ \t]*#softcore\b|^[ \t]*\.deathskip\b|^[ \t]*step <<[^\n]*\bskip\b') { continue }
        $active = [regex]::Replace($old,'(?m)^[ \t]*--[^\n]*\n','')
        $body = ''
        $kind = ''
        if ($active -match '\.link /run InviteUnit' -or
            $active -match '\+Zone into The Stockades\. You will now "Ghetto Hearth"' -or
            $active -match 'leave your group and/or hearth/ghetto hearth to Theramore') {
            $kind = 'instance-return'
            if ($active -match 'Stockades') {
                if ($active -match '\.link /run InviteUnit') {
                    $body = "    >>Take The Bravery from Stormwind Harbor to Auberdine. On WotLK this ferry connects Stormwind and Darkshore, not Menethil Harbor. Do not enter The Stockades or leave a group to force a return.`n    .zone Darkshore >>Arrive in Darkshore by the Stormwind Harbor ferry`n"
                } else {
                    $body = "    +Walk through Stormwind to the harbor and find The Bravery, the Auberdine ferry. If you entered The Stockades, backtrack through its entrance first. Check this instruction when at the harbor; no hearth binding or dungeon ejection is required.`n"
                }
            } elseif ($active -match 'Wailing Caverns') {
                $body = "    >>Backtrack through Wailing Caverns and leave by the entrance. Follow the surface paths back to the Crossroads, then the road east to Ratchet. Do not use an instance-ejection macro. A ready hearthstone bound to Ratchet is optional, not required.`n    .goto The Barrens,62.37,37.62,40 >>Return to Ratchet by ordinary travel`n"
            } elseif ($active -match 'Blackfathom Deeps' -and $active -match 'Splintertree') {
                $body = "    >>Backtrack through Blackfathom Deeps and the entrance tunnels. Follow the Zoram Strand south to Zoram'gar Outpost for the next turn-ins. You do not need to return to Splintertree first or assume a learned flight or hearth binding.`n    .goto Ashenvale,11.56,34.29,40 >>Return to Zoram'gar Outpost by ordinary travel`n"
            } elseif ($active -match 'Blackfathom Deeps' -and $active -match '\.zone Darkshore') {
                $body = "    >>Backtrack through Blackfathom Deeps if you entered it, then leave the entrance tunnels. Return to the Ashenvale road, follow it north into Darkshore, and continue to Auberdine. Do not use a dungeon-ejection macro or assume a ready hearthstone.`n    .goto Darkshore,37.70,43.39,40 >>Return to Auberdine by ordinary travel`n"
            } elseif ($active -match "Zul'Farrak") {
                $body = "    >>Backtrack through Zul'Farrak and leave by the entrance. Follow the approach road back southeast to Gadgetzan, avoiding unnecessary packs. Do not force an instance ejection; a ready hearthstone bound to Gadgetzan is optional.`n    .goto Tanaris,51.413,28.752,40 >>Return to Gadgetzan by ordinary travel`n"
            } elseif ($active -match 'leave your group and/or hearth/ghetto hearth to Theramore') {
                $body = "    >>Backtrack through Razorfen Downs to its entrance. Take the Gold Road north through the southern Barrens, then the eastbound road into Dustwallow Marsh. Follow the road to Theramore for the authored turn-ins. Do not assume a hearth binding or leave a group to force a return.`n    .subzone 513 >>Reach Theramore Isle by ordinary travel`n"
            } else { throw 'Unreviewed instance-return destination.' }
        } elseif ($active -match 'website unstuck page' -and $active -match '^step << Shaman') {
            $kind = 'shaman-water-return'
            if ($active -match '\.isOnQuest 63\b') {
                $body = "    >>Travel to Silverpine Forest by ordinary roads. From Undercity, use the elevator to Tirisfal Glades and follow the western road south into Silverpine. A flight to The Sepulcher is optional only if already learned. Continue with the Call of Water instructions; no website relocation is required.`n    .zone Silverpine Forest >>Reach Silverpine Forest`n"
            } elseif ($active -match '\.goto Silverpine Forest,45\.62,42\.59') {
                $body = "    >>After accepting Call of Water (96), retrace your route away from the coastal shrine and rejoin the road to The Sepulcher. Do not use logout or website relocation. The next flight is optional if learned; otherwise follow the road south to Hillsbrad and then north to Tarren Mill.`n    .goto Silverpine Forest,45.62,42.59,40 >>Return to The Sepulcher on foot`n"
            } else { throw 'Unreviewed Shaman relocation instruction.' }
        }
        if (-not $body) { continue }
        # This layer cannot remove mixed quest work or a new unknown action.
        foreach ($tag in [regex]::Matches($active,'(?m)^[ \t]*\.([A-Za-z]+)\b')) {
            if ($tag.Groups[1].Value -cnotin @('goto','zone','subzone','link','cooldown',
                'bindlocation','dungeon','isOnQuest','zoneskip','subzoneskip')) {
                throw 'Mixed action in ordinary-travel replacement requires review.'
            }
        }
        $new = [regex]::Match($old,'^[ \t]*step[^\n]*\n').Value
        # Named anchors, class/season selection and dungeon/quest gates survive.
        # Hearth cooldown/bind and old instance-only gates are not prerequisites
        # for walking. The following authored rewards remain in place.
        foreach ($line in [regex]::Matches($old,'(?m)^[ \t]*(?:#[^\n]*|\.(?:dungeon|isOnQuest)\b[^\n]*)\n')) {
            $new += $line.Value
        }
        if ($kind -eq 'shaman-water-return') {
            foreach ($line in [regex]::Matches($old,'(?m)^[ \t]*\.zoneskip[^\n]*\n')) { $new += $line.Value }
        }
        $new += $body
        $count = $working.Split(@($old),[StringSplitOptions]::None).Count-1
        if ($count -lt 1) { throw 'Overlapping ordinary-travel replacements.' }
        $edits.Add([ordered]@{from=$old;to=$new;occurrences=$count;kind=$kind
            reason='Replace a reachable forced return with ordinary travel; preserve class/dungeon/quest conditions, labels and the following quest actions. Do not require a ready hearth or discovered flight.'
            attribution='Pinned v4.11.11 source and adjacent authored destinations; WotLK ferry endpoints in tests/fixtures/hardcore-travel335.json.'})
        $working = $working.Replace($old,$new)
    }
    return $edits.ToArray()
}
