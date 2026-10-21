# Offline-only WotLK pet adaptations. Input is one pinned source chapter after
# mechanical map/trainer repairs. Callers must bind returned exact edits to its
# source hash; this helper never edits a live guide or infers learned spells.
function Get-HardcorePetEdits335([string]$Text) {
    $edits = [Collections.Generic.List[object]]::new()
    $working = $Text
    $rankIds = '2981|16829|16830|16831|2976|2977|3666|17263|17264|17265|17266|17267|4187|4188|24547|24549|24556|24557|24558|24559|24560|24561|24562|24631|24632|14925|14926|24494|23111|4195'
    $obsolete = '(?mi)^[ \t]*\.(?:stable\b|train (?:'+$rankIds+')\b|train 5118 >>Train your pet spells|trainer >>[^\n]*(?:pet|demon))'
    $seen = @{}
    foreach ($match in [regex]::Matches($Text, '(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)')) {
        $old = $match.Value
        if ($seen.ContainsKey($old)) { continue }
        $seen[$old] = $true
        $new = $old
        $kind = ''
        if ($old -match $obsolete) {
            if ($old -notmatch '^[ \t]*step << (?:(?:Dwarf|!?NightElf|BloodElf) )?(?:Hunter|Warlock)\s*\n') {
                throw ('Mixed or unrecognized pet-step class requires review: '+($old.Split("`n")[0]))
            }
            if ($old -match '(?m)^[ \t]*\.(?:accept|turnin|complete|collect|use|buy)\b') {
                # These are real WotLK quest rewards. Remove only the obsolete
                # trainer instruction, never the turn-in, NPC or approach.
                if ($old -notmatch '\.turnin (?:9673|9675)\b' -or
                    $old -match '(?m)^[ \t]*\.(?:accept|complete|collect|use|buy|stable)\b') {
                    throw 'Unreviewed mixed quest/pet instruction.'
                }
                $new = [regex]::Replace($old, '(?m)^[ \t]*\.(?:train 4187|trainer >>[^\n]*pet spells)[^\n]*\n', '')
                $kind = 'retain-quest-reward'
            } elseif ($old -match '\.train 2981\b' -and $old.Contains('Strigid Hunter')) {
                # The first permanent pet must not disappear with the rank
                # tutorial. Keep its authored coordinates and creature.
                $new = [regex]::Replace($old, '(?m)^[ \t]*#sticky[^\n]*\n', '')
                $new = [regex]::Replace($new, '(?m)^[ \t]*(?:\.train 2981|\.link |>>)[^\n]*\n', '')
                $new = [regex]::Replace($new, '^([ \t]*step[^\n]*\n)', '$1    #optional'+"`n")
                $new += "    +If you do not have a permanent pet, tame a Strigid Hunter here using Tame Beast. Otherwise keep your current pet. Inspect its spellbook as it levels; no temporary pet or Claw-learning detour is needed.`n"
                $kind = 'retain-first-pet'
            } else {
                foreach ($tag in [regex]::Matches($old, '(?m)^[ \t]*\.([A-Za-z]+)\b')) {
                    if ($tag.Groups[1].Value -cnotin @('goto','train','trainer','stable','link',
                        'unitscan','target','mob','cast','xp','dungeon','zoneskip','subzoneskip')) {
                        throw 'Pet-only removal includes an unreviewed action.'
                    }
                }
                # A player-spell sentinel in a mixed class-training stop is
                # not a pet rank. 5118 is allowed ONLY for the reviewed
                # erroneous "Train your pet spells" instruction.
                foreach ($train in [regex]::Matches($old, '(?m)^[ \t]*\.train (\d+)[^\n]*')) {
                    if ($train.Groups[1].Value -notmatch ('^(?:'+$rankIds+')$') -and
                        $train.Value.Trim() -cne '.train 5118 >>Train your pet spells') {
                        throw 'Pet removal would discard player class training.'
                    }
                }
                $labels = @([regex]::Matches($old, '(?m)^[ \t]*#label [^\n]*\n'))
                $new = ''
                if ($labels.Count) {
                    # Preserve named dependency anchors. The obsolete loop,
                    # trainer detour and spell gates must not survive.
                    $new = [regex]::Match($old, '^[ \t]*step[^\n]*\n').Value + "    #optional`n"
                    foreach ($label in $labels) { $new += $label.Value }
                    foreach ($gate in [regex]::Matches($old,
                        '(?m)^[ \t]*\.(?:xp|dungeon|zoneskip|subzoneskip)[^\n]*\n')) { $new += $gate.Value }
                    $new += "    +Keep your current pet. WotLK pet ability ranks are learned as it levels; this old rank-learning detour is not required.`n"
                }
                $kind = 'remove-rank-sequence'
            }
        } else {
            # Prose inside valid class-training/taming stops is handled line
            # by line; Beast Training quest titles are intentionally untouched.
            $new = [regex]::Replace($new,
                '(?m)^([ \t]*)(>>|\+)[^\n]*(?:onto your Action Bars\. Teach skills to your pet|Remember to train your pet whenever they get Training Points)[^\n]*\n',
                '$1$2Inspect your pet spellbook and talents as it levels. WotLK does not use Classic pet training points.'+"`n")
            $new = [regex]::Replace($new,
                '(?m)^([ \t]*)\+[^\n]*\[Beast Training\][^\n]*\[Revive Pet\][^\n]*\[Feed Pet\][^\n]*\n',
                '$1+Put Revive Pet and Feed Pet on your action bars. Pet ability ranks are learned as the pet levels.'+"`n")
            $new = [regex]::Replace($new,
                '(?m)^([ \t]*)>>[^\n]*This will allow you to train[^\n]*\[Claw Rank 2\][^\n]*\n',
                '$1>>Keep this as your permanent pet if desired. WotLK pet ability ranks are learned as it levels, not by taming temporary pets.'+"`n")
            if ($new -cne $old) { $kind = 'retain-class-or-pet-acquisition' }
        }
        if ($new -ceq $old) { continue }
        $count = $working.Split(@($old), [StringSplitOptions]::None).Count - 1
        if ($count -lt 1) { throw 'Overlapping pet edits.' }
        $edits.Add([ordered]@{from=$old;to=$new;occurrences=$count;kind=$kind
            reason='WotLK Pet::InitLevelupSpellsForLevel learns family/default ranks by pet level. Remove Classic rank-learning and pet-trainer routines, retaining real quest rewards and first-pet acquisition.'
            attribution='AzerothCore src/server/game/Entities/Pet/Pet.cpp; pinned v4.11.11 Survival source.'})
        $working = $working.Replace($old, $new)
    }
    return $edits.ToArray()
}
