# Modern Classic Incubus additions are not the WotLK Succubus quest chain.
# The adjacent 1716 -> 1738 -> 1739 quest work is immutable in this layer.
function Get-HardcoreDemonEdits335([string]$Text) {
    $working=$Text
    $edits=[Collections.Generic.List[object]]::new()
    $seen=@{}
    foreach($match in [regex]::Matches($Text,'(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)')){
        $old=$match.Value
        if($seen.ContainsKey($old)){continue};$seen[$old]=$true
        $active=[regex]::Replace($old,'(?m)^[ \t]*--[^\n]*\n','')
        if($active -notmatch '(?m)^[ \t]*\.(?:accept|turnin|complete|isOnQuest|isQuestTurnedIn|collect|use|cast)\b[^\n]*\b(?:65602|65603|190307|190308|190186|367062)\b'){continue}
        if($old -notmatch '^[ \t]*step << Warlock[ \t]*\n'){throw 'Unexpected class on Incubus branch.'}
        $new=$old
        if($old -match '\.(?:accept|turnin|complete|isOnQuest)\b[^\n]*\b(?:1716|1738|1739)\b'){
            $new=[regex]::Replace($new,'(?m)^[ \t]*\.(?:accept|turnin) 6560[23][^\n]*\n?','')
            $new=$new.Replace('.isOnQuest 1739,65603','.isOnQuest 1739')
            if($new -match '\b(?:65602|65603|190307|190308|190186|367062)\b'){throw 'Unreviewed mixed Incubus action.'}
        } else {
            if($old -match '(?m)^[ \t]*#(?:label|requires|completewith)\b' -or
                $old -match '(?m)^[ \t]*\.(?:fp|fly|home|hs|trainer|train|dungeon)\b'){
                throw 'Incubus-only removal contains a shared anchor or action.'
            }
            foreach($quest in [regex]::Matches($old,'(?m)^[ \t]*\.(?:accept|turnin|complete)\s+(\d+)')){
                if($quest.Groups[1].Value -cnotin @('65602','65603')){throw 'A valid quest shares the Incubus step.'}
            }
            $new=''
        }
        $count=$working.Split(@($old),[StringSplitOptions]::None).Count-1
        if($count -lt 1){throw 'Overlapping demon replacement.'}
        $edits.Add([ordered]@{from=$old;to=$new;occurrences=$count;kind='unavailable-incubus'
            reason='Remove modern Classic Incubus-only quests/items/spell unavailable on WotLK; preserve the adjacent Succubus quests 1716, 1738 and 1739 and their rewards.'
            attribution='Pinned v4.11.11 source and tests/fixtures/hardcore-demons335.json (AzerothCore 3.3.5 quest/item facts).'})
        $working=$working.Replace($old,$new)
    }
    return $edits.ToArray()
}
