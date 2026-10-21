# WotLK transport adaptations, applied after the pinned ordinary-travel layer.
# Generate exact, source-bound replacements; never operate on installed guides.
function Get-HardcoreFerryEdits335([string]$Text,[string]$Family,[string]$Name) {
    $working=$Text
    $edits=[Collections.Generic.List[object]]::new()
    $seen=@{}
    $roadToMenethil='From Ironforge, take the road east through Dun Morogh to Loch Modan, then north through the Dun Algaz tunnels into Wetlands. Follow the road west to Menethil Harbor. Stay on the roads and avoid unnecessary enemies; no mountain jump or learned flight is required.'
    $roadToIronforge='From Menethil Harbor, follow the Wetlands road east to Dun Algaz, then the tunnels south into Loch Modan. Follow the road west through Dun Morogh into Ironforge. Use a flight only if you already know it; walking is the fallback.'
    $toStormwind="$roadToIronforge Enter the Deeprun Tram in Tinker Town, ride to the Stormwind end, and exit into Stormwind."
    $neLoch=($Family -ceq 'classic' -and $Name -ceq '13-13 Loch Modan (Night Elf)')
    $neDark=($Family -ceq 'classic' -and $Name -ceq '11-13 Darkshore (Night Elf)')
    $dm=($Family -ceq 'tbc' -and $Name -ceq '20-21 Darkshore')
    foreach($match in [regex]::Matches($Text,'(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)')) {
        $old=$match.Value
        if($seen.ContainsKey($old)){continue};$seen[$old]=$true
        if($old -match '(?m)^[ \t]*#softcore\b|^[ \t]*\.deathskip\b|^[ \t]*step <<[^\n]*\bskip\b'){continue}
        $new=$old;$kind=''
        if($Family -ceq 'tbc' -and $Name -ceq '6-12 Mulgore' -and
            $old.Contains('.dungeon RFC !Hunter !Druid')) {
            # Hunter/Druid training trips remain available without RFC. Other
            # classes use the paired !RFC quest-only branch when RFC is off.
            $kind='dungeon-condition'
            $new=$new.Replace('.dungeon RFC !Hunter !Druid','.dungeon RFC << !Hunter !Druid')
        }
        $east=$old -match '(?m)^[ \t]*\.zone Wetlands[ \t]*>>[^\n]*boat[^\n]*Menethil' -and
            $old -match '(?m)^[ \t]*\.goto (?:Darkshore|1439),'
        $west=$old -match '(?m)^[ \t]*\.zone Darkshore[ \t]*>>[^\n]*boat' -and
            ($old -match '(?m)^[ \t]*\.goto (?:Wetlands|1437),' -or
             ($Family -ceq 'classic' -and $Name -ceq '13-15 Westfall' -and $old.StartsWith('step << !NightElf')))
        if($east -or $west) {
            $kind='ferry-arrival'
            # Preserve skills, XP, item gates, branch headers and quest predicates.
            # Ferry-only steps must not hide a quest action in removed prose.
            if($old -match '(?m)^[ \t]*\.(?:accept|turnin|complete|collect|buy|vendor|fp|home|train|trainer|cast|use)\b'){
                throw 'Mixed ferry/quest action needs an explicit adaptation.'
            }
            $new=[regex]::Replace($new,'(?m)^[ \t]*\.(?:goto|zone)\b[^\n]*\n?','')
            $new=$new.Replace('Menethil Harbor boat','Stormwind Harbor boat').
                Replace('boat to Menethil Harbor','boat to Stormwind Harbor')
            # The last authored predicate may have no trailing newline. Keep
            # added instructions out of its comment/argument text.
            $new=$new.TrimEnd("`n")+"`n"
            if($east) {
                # These are intermediate zones, not evidence of reaching the
                # retained Menethil stops. More distant authored bypasses survive.
                $new=[regex]::Replace($new,'(?m)^[ \t]*\.zoneskip (?:Stormwind City|Ironforge|Dun Morogh|Loch Modan|Wetlands)[^\n]*\n?','')
                if($dm -and $old -match '(?m)^\.dungeon !DM') {
                    $new+="    >>Take The Bravery from Auberdine to Stormwind Harbor. WotLK has no Auberdine-Menethil ferry. Continue to the authored Warlock quest and trainer in Stormwind; no Menethil flight is needed.`n    .zone Stormwind City >>Arrive in Stormwind by ferry`n"
                } else {
                    $new+="    >>Take The Bravery from Auberdine to Stormwind Harbor. Cross Stormwind to the Deeprun Tram, ride to Ironforge, and exit into the city. $roadToMenethil`n    .goto Wetlands,4.560,57.160,40 >>Reach Menethil Harbor for the following authored stops`n"
                }
            } else {
                $new+="    >>There is no Menethil-Auberdine ferry in WotLK. If still in Menethil, $toStormwind Walk to Stormwind Harbor and take The Bravery to Auberdine. If already in Stormwind, go directly to the harbor. A hearthstone or learned flight is not required.`n    .zone Darkshore >>Arrive in Darkshore on The Bravery`n"
            }
        } elseif($old -match '(?m)^[ \t]*\.goto (?:Wetlands|1437),[^\n]*' -and
            $old -match '(?i)(?:Wait for|dock for)[^\n]*boat to (?:Darkshore|Auberdine)' -and
            $old -notmatch '(?m)^[ \t]*\.zone\b') {
            $kind='ferry-approach'
            $new=[regex]::Replace($new,'(?m)^[ \t]*\.goto[^\n]*\n?','')
            $new=$new.TrimEnd("`n")+"`n"
            $new+="    +$toStormwind Walk to Stormwind Harbor and find The Bravery for Auberdine. Check this travel reminder when at the harbor.`n"
        } elseif($old -match '(?m)^[ \t]*\.goto (?:Darkshore|1439),' -and
            $old -match '(?i)(?:Wait for|dock of)[^\n]*Menethil Harbor boat') {
            $kind='ferry-approach'
            $new=$new.Replace('Menethil Harbor boat','Stormwind Harbor boat')
        } elseif($old -match '(?i)Dun Morogh -> Wetlands skip') {
            $kind='ordinary-road'
            $start=[regex]::Match($old,'^[ \t]*step[^\n]*\n').Value
            $metadata=[regex]::Matches($old,'(?m)^[ \t]*#[^\n]*\n') | ForEach-Object {$_.Value}
            $new=$start+($metadata -join '')+"    >>$roadToMenethil`n    .goto Wetlands,9.490,59.694,40 >>Reach Menethil Harbor by the Dun Algaz road`n"
        }
        if(($neDark -or $dm) -and ($old -match 'character unstuck self service' -or
            $old -match 'Jump off the end of the dock and swim to the waypoint')) {
            $kind='ordinary-return'
            $new=[regex]::Match($old,'^[ \t]*step[^\n]*\n').Value
            $new+=([regex]::Matches($old,'(?m)^[ \t]*(?:#[^\n]*|\.dungeon[^\n]*)\n') | ForEach-Object {$_.Value}) -join ''
            if($old -match 'Jump off') {
                $new+="    +Leave Menethil by the road for Dun Algaz. Do not jump from the dock or swim down the coast. Check this reminder when ready to travel.`n"
            } else {
                $new+="    >>$roadToIronforge`n    .zone Ironforge >>Reach Ironforge by ordinary travel`n"
            }
        }
        if(($neLoch -or $dm) -and $old -match '(?i)Wetlands to Westfall swim') {
            $kind='ordinary-return'
            $new=[regex]::Match($old,'^[ \t]*step[^\n]*\n').Value
            $new+=([regex]::Matches($old,'(?m)^[ \t]*(?:#[^\n]*|\.dungeon[^\n]*)\n') | ForEach-Object {$_.Value}) -join ''
            # At this point the preceding chapter/step has reached Ironforge.
            $new+="    >>From Ironforge, enter the Deeprun Tram in Tinker Town. Ride to the Stormwind end and exit into Stormwind. If resuming in Wetlands, first follow the Dun Algaz road through Loch Modan and Dun Morogh to Ironforge. No coastal swim or external relocation is needed.`n    .zone Stormwind City >>Reach Stormwind by the Tram`n"
        }
        if($neLoch -and $old -match 'Run up the shore and make your way to Elwynn Forest') {
            $kind='ordinary-return'
            $new="step`n    +You have arrived in Stormwind by the Tram. Continue with the following vendor, flight-path and Tram quest stops; the old Westfall shoreline detour is not needed. Check this reminder to continue.`n"
        } elseif($neLoch -and $old -match '\.zone Stormwind City >> Run to Stormwind') {
            $kind='ordinary-return'
            $new="step`n    .zone Stormwind City >>Be in Stormwind for the following vendor and flight-path stops`n"
        }
        if($neLoch -and $old -match '\.zone Ironforge >> Enter the Deeprun Tram') {
            $kind='tram-checkpoint'
            $new="step`n    >>Enter the Deeprun Tram from Stormwind. Ride to the Ironforge end, but stay inside the Tram for Monty's quests. Do not exit into Ironforge yet.`n    +Check this instruction when you are at Monty's platform at the Ironforge end of the Tram`n"
        } elseif($neLoch -and $old -match '\.(?:accept|complete|turnin) 666[12]\b') {
            $kind='tram-quest-gates'
            $new=[regex]::Replace($new,'(?m)^[ \t]*\.(?:subzoneskip (?:809|2257)|zoneskip Ironforge)[^\n]*\n?','')
        }
        if($dm -and $old -match '(?m)^\.dungeon !DM' -and $old -match '\.fly Stormwind') {
            $kind='obsolete-ferry-flight'
            $new=[regex]::Replace($new,'(?m)^[ \t]*(?:\.(?:goto|fly|target)\b|>>)[^\n]*\n?','')
            $new=$new.TrimEnd("`n")+"`n"
            $new+="    >>The ferry has already brought you to Stormwind. Walk to the Slaughtered Lamb for the following quest and training.`n    .zone Stormwind City >>Continue in Stormwind`n"
        }
        if($dm -and $old -match '(?m)^\.dungeon DM' -and $old -match '\.fly Ironforge') {
            $kind='optional-flight-fallback'
            $new=[regex]::Replace($new,'(?m)^[ \t]*(?:\.(?:goto|fly|target|zoneskip)\b|>>)[^\n]*\n?','')
            $new=$new.TrimEnd("`n")+"`n"
            $new+="    >>$roadToIronforge`n    .zone Ironforge >>Reach Ironforge for the following training and flight-path stops`n"
            # This leg is a prerequisite, not an optional flight-only reminder.
            $new=[regex]::Replace($new,'(?m)^[ \t]*#optional[^\n]*\n?','')
        }
        if($dm -and $old -match 'Run up the shore and make your way to Sentinel Hill') {
            $kind='ordinary-return'
            $new=[regex]::Match($old,'^[ \t]*step[^\n]*\n').Value+
                ".dungeon DM`n    #completewith next`n    >>Leave Stormwind through its main gate. Follow the Elwynn road west across the bridge into Westfall, then the road south to Sentinel Hill. Do not swim down the coast.`n    .goto Westfall,56.55,52.64,40 >>Reach Sentinel Hill by road`n"
        }
        if($dm -and $old -match '^step << NightElf/Draenei' -and
            $old -match '\.fp (?:Sentinel Hill|Ironforge)' -and
            $old -match '(?m)^[ \t]*\.(?:zoneskip|subzoneskip)\b') {
            $kind='retained-flight-stop'
            $new=[regex]::Replace($new,'(?m)^[ \t]*\.(?:zoneskip|subzoneskip)[^\n]*\n?','')
            if($old -match '\.fp Ironforge'){
                $new=$new.Replace(".dungeon DM`n",".dungeon DM`n    >>After the Sentinel Hill flight-path stop, return by the Westfall and Elwynn roads to Stormwind. Take the Tram to Ironforge for this flight-path stop, then return to the Tram for the following Stormwind quests.`n")
            }
        }
        if($old -match '(?m)^[ \t]*#requires Percing[ \t]*\n' -and
            (($Family -ceq 'classic' -and $Name -ceq '1-6 Undead') -or
             ($Family -ceq 'tbc' -and $Name -ceq '1-6 Tirisfal Glades'))) {
            $kind='label-reference'
            $new=$new.Replace('#requires Percing','#requires Piercing')
        }
        if((($Family -ceq 'classic' -and $Name -ceq '6-13 Tauren') -or
            ($Family -ceq 'tbc' -and $Name -ceq '6-12 Mulgore')) -and
            $old -match '\.goto Durotar,58\.08,57\.13,120 >> Travel to Tiragarde Keep' -and
            $old -notmatch '#label TravelToTiragarde') {
            $kind='label-reference'
            $new=$new.Replace('#completewith Benedict',"#label TravelToTiragarde`n    #completewith Benedict")
        }
        if($Family -ceq 'classic' -and $Name -ceq '15-18 Darkshore' -and
            $old.Contains('>>Finish off collecting 5 |T134187:0|t[Earthroot]') -and
            $old.Contains('.collect 2449,5,6123,1') -and
            $old -notmatch '#label earthroot') {
            $kind='branch-label'
            $new=$new.Replace("step << Druid`n","step << Druid`n    #label earthroot`n")
        }
        if($Name -ceq '51-52 Blasted Lands' -and
            $old -match '(?m)^#requires Helboars[ \t]*$') {
            $kind='branch-label'
            $new=$new.Replace('#requires Helboars', '#requires Helboars << Warrior')
        }
        if($Family -ceq 'tbc' -and $Name -ceq '24-27 Redridge/Duskwood' -and
            $old.StartsWith("step << Rogue`n") -and
            $old -match '(?m)^[ \t]*#requires AntiVenomEnd2[ \t]*$') {
            $kind='branch-label'
            $new=$new.Replace('#requires AntiVenomEnd2', '#requires AntiVenomEnd2 << !Dwarf')
        }
        if($new -cne $old) {
            $count=$working.Split(@($old),[StringSplitOptions]::None).Count-1
            if($count -lt 1){throw 'Overlapping ferry adaptation.'}
            $reason=if($kind -eq 'branch-label'){
                'Anchor the existing final Earthroot collection before its reward; restrict Helboars and AntiVenomEnd2 dependencies to the same class/race branches as their targets. Preserve every action and its order.'
            }elseif($kind -eq 'label-reference'){
                'Repair the demonstrated reference to the existing Piercing quest anchor or restore the missing TravelToTiragarde anchor on its existing travel step; no actions are removed or reordered.'
            }elseif($kind -eq 'dungeon-condition'){
                'Restore the missing condition separator on the RFC gate. Hunter/Druid Thunder Bluff training remains independent of RFC; other classes retain their paired !RFC quest-only alternatives.'
            }else{
                'Connect the authored stops using WotLK ferries, the Tram and ordinary roads; retain family, class, dungeon and quest actions. Remove obsolete transit-only skip assumptions.'
            }
            $edits.Add([ordered]@{from=$old;to=$new;occurrences=$count;kind=$kind
                reason=$reason
                attribution='RestedXP v4.11.11 pinned source; transport facts in tests/fixtures/hardcore-travel335.json; production zone/subzoneskip semantics.'})
            $working=$working.Replace($old,$new)
        }
    }
    return $edits.ToArray()
}
