# Only the pinned Blood Elf starter should call this transformation. It repairs
# the action for quest8346, not the Warlock's itinerary or other quest chains.
function Get-HardcoreBloodElfRacialEdit335([string]$Text) {
    if ($Text -notmatch '(?m)^[ \t]*\.accept 8346\b') { throw 'Missing Thirst Unending pickup.' }
    $body = $Text
    $removed = 0
    foreach ($match in [regex]::Matches($Text,'(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)')) {
        $old = $match.Value
        if ($old -notmatch '(?m)^[ \t]*\.complete 8346,1\b') { continue }
        $removed += [regex]::Matches($old,'(?m)^[ \t]*\.complete 8346,1\b').Count
        $others = [regex]::Matches($old,'(?m)^[ \t]*\.complete (?!8346,)\d+,')
        if (-not $others.Count) {
            if ($old -match '(?m)^[ \t]*(?:#label|\.(?:accept|turnin|collect|use|buy))\b') {
                throw 'Objective-only racial step contains unreviewed shared actions.'
            }
            $body = $body.Replace($old,'')
            continue
        }
        $new = [regex]::Replace($old,'(?m)^[ \t]*\.complete 8346,1[^\n]*\n','')
        $new = $new.Replace('Cast |T135738:0|t[Mana Tap] and kill','Kill')
        # Keep loot instructions in accessory lines; only the obsolete cast
        # clause is removed, never sliver or other quest objectives.
        $new = [regex]::Replace($new,
            '(?m)^([ \t]*)\*[^\n]*\[Mana Tap\][^\n]*?\. (Loot [^\n]*)\n','$1>>$2'+"`n")
        $new = [regex]::Replace($new,'(?m)^[ \t]*\*[^\n]*\[Mana Tap\][^\n]*\n','')
        if ($new.Contains('Mana Tap')) { throw 'Unreviewed mixed Mana Tap prose.' }
        $body = $body.Replace($old,$new)
    }
    if ($removed -ne 13 -or $body.Contains('Mana Tap')) { throw 'Pinned racial objective inventory changed.' }
    $pickups = @([regex]::Matches($body,'(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)') |
        Where-Object {$_.Value -match '(?m)^[ \t]*\.accept 8346\b'})
    if ($pickups.Count -ne 1) { throw 'Ambiguous racial pickup.' }
    $checkpoint = @'
step
    .goto Eversong Woods,37.70,23.26,0
    >>Use Arcane Torrent once next to a living Mana Wyrm after accepting Thirst Unending. Stay within its short range and let the quest log confirm credit before killing the creature. WotLK does not use Mana Tap or six casts on arbitrary mana creatures.
    .complete 8346,1 --Use Arcane Torrent on a Mana Wyrm (1)
    .mob Mana Wyrm
'@ + "`n"
    $body = $body.Replace($pickups[0].Value,$pickups[0].Value+$checkpoint)
    return [ordered]@{from=$Text;to=$body;occurrences=1;kind='bloodelf-racial-objective'
        reason='Quest8346 requires one Mana Wyrm Arcane Torrent credit, not six Mana Taps. Keep the authored reward circuit and all other class/quest actions.'
        attribution='AzerothCore quest_template8346 and smart_scripts15274 spell-hit entries28730/25046 casting61314; pinned v4.11.11 source.'}
}
