# Reviewed reference repairs only. Callers bind each exact replacement to the
# pinned source block; this layer neither changes routes nor invents actions.
function Get-HardcoreLabelEdits335([string]$Text,[string]$Family,[string]$Name) {
    $edits=[Collections.Generic.List[object]]::new()
    $addedLabels=@{}
    foreach($match in [regex]::Matches($Text,'(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)')) {
        $old=$match.Value; $new=$old; $reason=''
        if($Family -ceq 'tbc' -and $Name -ceq '24-27 Redridge/Duskwood' -and
            $old -match '(?m)^[ \t]*#requires AntiVenomEnd[ \t]*$') {
            $new=[regex]::Replace($new,'(?m)^[ \t]*#requires AntiVenomEnd[ \t]*\n','')
            $reason='Remove a stale previous-chapter dependency. Preserve First Aid aura/item guards; do not depend on the later crafting/use step and create a cycle.'
        }
        if($Family -ceq 'tbc' -and $Name -ceq '29-30 Ashenvale' -and
            $old -match '(?m)^[ \t]*#requires slimes[ \t]*$') {
            $new=[regex]::Replace($new,'(?m)^[ \t]*#requires slimes[ \t]*\n','')
            $reason='Remove the stale Classic Rotting Slime dependency absent from this TBC chapter. Preserve the entire quest1017 journey and reward.'
        }
        if($Name -ceq '15-19 The Barrens' -and $old.Contains('#completewith BarenLongshore')) {
            if($Text -notmatch '(?m)^[ \t]*#label BaronLongshore[ \t]*$'){throw 'Baron Longshore destination missing.'}
            $new=$new.Replace('#completewith BarenLongshore','#completewith BaronLongshore')
            $reason='Correct the spelling of the existing BaronLongshore destination; no action changes.'
        }
        $label=''
        if($Family -ceq 'classic' -and $Name -ceq '1-6 Shadowglen' -and
            $old.StartsWith("step << Hunter`n") -and $old.Contains('.train 1978')) {$label='htraining'}
        if($Family -ceq 'classic' -and $Name -ceq '1-6 Orc/Troll' -and
            $old.StartsWith("step << Rogue`n") -and $old.Contains('.train 1757') -and
            -not $old.Contains('.train 1776')) {$label='Rwag2'}
        if($Name -ceq '10-12 Eversong Woods' -and $old.StartsWith("step << Undead Warlock`n") -and
            $old.Contains('.train 6222')) {$label='FalconPMTrain2'}
        if($Family -ceq 'classic' -and $Name -ceq '11-13 Loch Modan (Dwarf/Gnome)' -and
            $old -match '(?m)^\s*\.turnin 6392\b') {$label='RTB'}
        if((($Family -ceq 'classic' -and $Name -ceq '1-6 Tauren') -or
            ($Family -ceq 'tbc' -and $Name -ceq '1-6 Mulgore')) -and
            $old -match '(?m)^\s*\.turnin 1520\b') {$label='CallofEarth'}
        if($Family -ceq 'classic' -and $Name -ceq '19-20 Redridge' -and
            $old.Contains('.goto StormwindClassic,66.27,62.12,-1') -and
            $old.Contains('.zoneskip Stormwind City,1') -and
            -not $old.Contains('Fly to Redridge if you are in Stormwind')) {$label='FlyR'}
        if($Family -ceq 'classic' -and $Name -ceq '47-49 Tanaris' -and
            $old -match '(?m)^\s*\.accept 1170\b') {$label='DWMpickups2'}
        if($Family -ceq 'tbc' -and $Name -ceq '50-51 Searing Gorge' -and
            $old -match '(?m)^\s*\.accept 7722\b') {$label='SearingAccept'}
        if($Family -ceq 'classic' -and $Name -cin @('6-13 Orc/Troll','6-13 Undead') -and
            $old.Contains('#completewith next') -and $old -match '(?m)^\s*\.complete 374,1\b') {$label='Scarletrings'}
        if($Family -ceq 'classic' -and $Name -ceq '30-32 Duskwood' -and
            $old.Contains('#completewith murlocs') -and $old -match '(?m)^\s*\.fly Wetlands\b') {$label='FlytoSouthshoreA'}
        if($Family -ceq 'classic' -and $Name -ceq '38-39 Swamp of Sorrows' -and
            $old -match '(?m)^\s*\.turnin 1457\b') {$label='ReclaimersDesolace'}
        if((($Family -ceq 'classic' -and $Name -ceq '30-32 Duskwood') -or
            ($Family -cin @('tbc','curated') -and $Name -ceq '24-27 Redridge/Duskwood')) -and
            $old.Contains('.dungeon Gnomer') -and $old.Contains('.hs >> Hearth to Ironforge') -and
            $old.Contains('.zoneskip Dun Morogh')) {$label='Finished'}
        if($Family -ceq 'classic' -and $Name -ceq '11-13 Darkshore (Night Elf)' -and
            $old.Contains('.hs >> Hearth to Auberdine')) {$label='start'}
        if($Family -ceq 'tbc' -and $Name -ceq '35-37 STV' -and
            $old -match '(?m)^\s*\.turnin 189\b') {$label='BBend'}
        if($Family -cin @('tbc','curated') -and $Name -ceq '42-43 Stranglethorn Vale part 2' -and
            $old -match '(?m)^\s*\.turnin 209\b') {$label='BloodSailPart1'}
        if($Family -cin @('tbc','curated') -and $Name -ceq '45-46 Feralas' -and
            $old -match '(?m)^\s*\.turnin 3002\b') {$label='OrgrimmarStops335'}
        if($Family -ceq 'tbc' -and $Name -ceq '38-38 Swamp of Sorrows' -and
            $old -match '(?m)^\s*\.fp Nethergarde\b') {$label='NethergardeFlight335'}
        # Final branch-local repairs. Destinations are existing actions, never
        # empty synthetic steps or labels borrowed from a different chapter.
        $targets=@{}
        if($Family -ceq 'classic' -and $Name -ceq '19-20 Redridge') {
            $targets.BMenace='ExitSW'
            if($old.StartsWith("step << !NightElf`n") -and $old.Contains('.fly Redridge')) {$label='ExitSW'}
        }
        if($Family -cin @('classic','curated') -and $Name -ceq '59-60 Winterspring/Silithus part 2' -and
            $old.StartsWith("step << Mage`n") -and
            ($old.Contains('+Manual XP checkpoint: Grind') -or ($Family -ceq 'curated' -and $old.Contains('.xp 60 >> Reach level60'))) -and
            $old.Contains('.goto Felwood,62.77,10.57')) {$label='Grindto60'}
        if($Family -ceq 'classic' -and $Name -ceq '23-25 Hillsbrad' -and
            $old.StartsWith("step << Mage`n") -and $old.Contains('.cast 3563')) {$label='FlytoUC'}
        if($Family -ceq 'classic' -and $Name -ceq '31-34 Hillsbrad/Arathi' -and
            $old -match '(?m)^\s*\.accept 509\b') {$label='AcceptAgony'}
        if($Family -ceq 'classic' -and $Name -ceq '6-13 Tauren') {
            $targets.Bloodhooffinalturnins1='Bloodhoofturnins1'
            $targets.EscortErland='Entersilverpine'
            if($old.Contains('#completewith Collars1') -and $old.StartsWith("step << Shaman`n")) {
                $targets.Collars1='ReagentPouch335'
            }
            if($old.Contains('.solo') -and $old -match '(?m)^\s*\.complete 1525,2\b') {$label='ReagentPouch335'}
        }
        if(($Family -ceq 'classic' -and $Name -ceq '6-13 Tauren') -or
            ($Family -ceq 'tbc' -and $Name -ceq '6-12 Mulgore')) {
            if($old -match '(?m)^\s*#completewith Well\s*$') {
                $targets.Well="Well << Tauren`n    #completewith Stones << !Tauren"
            }
        }
        if($Family -cin @('classic','curated') -and $Name -ceq '15-19 The Barrens') {
            $targets.DisruptTheAttacks="DisruptTheAttacks << !Tauren !Hunter !Shaman`n    #completewith PlainstriderBeaks335 << Tauren/Hunter/Shaman"
            if($old.Contains('#loop') -and $old -match '(?m)^\s*\.complete 844,1\b') {$label='PlainstriderBeaks335'}
        }
        if($Family -ceq 'classic' -and $Name -ceq '58-59 Felwood/Winterspring') {$targets.ArcaneRunes='COTF'}
        if($Family -ceq 'classic' -and $Name -ceq '43-45 Tanaris/Dustwallow') {
            $targets.TanarisResupply='TanarisFieldSampling335'
            if($old.Contains('.goto Tanaris,47.99,33.20,0') -and $old.Contains('.complete 654,1')) {$label='TanarisFieldSampling335'}
        }
        if($Family -ceq 'tbc' -and $Name -ceq '20-21 Darkshore') {
            $targets.WileyStart='RedridgeRendevous'
            $targets.GryanAll="GryanAll << Rogue`n    #completewith MoonbrookAssembly335 << !Rogue"
            $targets.DeadminesEnd="DeadminesEnd << !Mage`n    #completewith DeadminesMageExit335 << Mage"
            if($old -match '(?m)^\s*\.subzone 2257\b') {$label='DeeprunDM'}
            if($old -match '(?m)^\s*\.subzone 20\b') {$label='MoonbrookAssembly335'}
            if($old.StartsWith("step << Mage`n") -and $old.Contains('.cast 3561')) {$label='DeadminesMageExit335'}
        }
        if($Family -ceq 'tbc' -and $Name -ceq '30-31 Wetlands') {
            $targets.CleansingtheEye='StormwindVendor335'
            if($old.Contains('.bronzetube') -and $old.Contains('Billibub')) {$label='StormwindVendor335'}
        }
        if($Family -ceq 'tbc' -and $Name -ceq '52-53 Azshara') {
            $targets.ArcaneRunes='ForestSongDeparture335'
            if($old -match '(?m)^\s*\.fly Forest Song\b') {$label='ForestSongDeparture335'}
        }
        if($Family -ceq 'tbc' -and $Name -ceq '6-10 Eversong Woods') {
            $targets.Defending='UndercityOrb335'
            if($old.StartsWith("step << Undead Warlock/Undead Warrior`n") -and
                $old -match '(?m)^\s*\.zone Undercity\b') {$label='UndercityOrb335'}
        }
        if($Family -ceq 'tbc' -and $Name -ceq '6-12 Mulgore') {
            $targets.Clawsx="Clawsx << Tauren`n    #completewith BloodhoofReturn335 << !Tauren"
            $targets.AlphaTeeth='BloodhoofCleanup335'
            if($old.Contains('#completewith Thunderhorn') -and $old.Contains('.subzone 222')) {$label='BloodhoofReturn335'}
            if($old -match '(?m)^\s*\.turnin 766\b' -and $old.Contains('.isQuestComplete 766') -and
                -not $old.Contains('#label Mazzturnin')) {$label='BloodhoofCleanup335'}
        }
        if($Family -ceq 'tbc' -and $Name -ceq '10-12 Eversong Woods') {$targets.FairBreezeHunter1='AmaniTurnins'}
        if($Family -ceq 'tbc' -and $Name -ceq '14-16 The Barrens') {$targets.PorttoSilvermoon2='PorttoSilvermoon'}
        if($Family -cin @('tbc','curated') -and $Name -ceq '29-31 Thousand Needles' -and
            $old.Contains('.goto The Barrens,63.09,37.16') -and $old.Contains('.fly Orgrimmar')) {$label='FlyOrg2'}
        if($Family -cin @('tbc','curated') -and $Name -ceq '42-43 Stranglethorn Vale part 2' -and
            $old.Contains('#completewith FlyDWM1')) {
            if(-not $old.Contains('.subzone 378') -or -not $old.Contains('.dungeon !RFD')) {throw 'Unexpected Camp Taurajo arrival.'}
            $new=[regex]::Replace($new,'(?m)^[ \t]*#completewith FlyDWM1[ \t]*\n','')
            $reason='Keep the existing optional Camp Taurajo arrival as an actual local travel checkpoint. Preserve riding, location and RFD gates; the flight belongs to the next chapter.'
        }
        if($Family -ceq 'curated' -and $Name -ceq '43-45 Dustwallow Marsh part 2') {
            $targets.DWM2End='DrazZilbReward335'
            if($old -match '(?m)^\s*\.turnin 1172\b') {$label='DrazZilbReward335'}
        }
        foreach($from in @($targets.Keys | Sort-Object)) {
            $pattern='(?m)(^[ \t]*#completewith )'+[regex]::Escape($from)+'([ \t]*)(?=\n|$)'
            if($new -match $pattern) {
                $replacement=$targets[$from]
                $new=[regex]::Replace($new,$pattern,{param($m) $m.Groups[1].Value+$replacement+$m.Groups[2].Value})
                $reason='Resolve the exact reference to an existing branch-local destination. Preserve class/race restrictions, quest rewards, travel gates and authored action order; no cross-chapter or cross-family label borrowing.'
            }
        }
        if($label) {
            if($addedLabels.ContainsKey($label)){
                throw "Ambiguous destination anchor: $label"
            }
            $addedLabels[$label]=$true
            if($old -match '(?m)^[ \t]*#label\b'){throw "Destination already owns an anchor: $Family / $Name / $label"}
            $at=$new.IndexOf("`n")+1
            $new=$new.Insert($at,"    #label $label`n")
            $reason='Restore the reference anchor on its existing destination step, preserving every spell, quest, action and gate. Do not broaden the destination eligibility.'
        }
        if($Name -cin @('1-6 Undead','1-6 Tirisfal Glades') -and
            $old.StartsWith("step << Warrior/Priest/Mage`n") -and $old.Contains('#completewith Training1') -and
            $old.Contains('.goto Tirisfal Glades,32.22,65.64,8')) {
            $new=$new.Replace('#completewith Training1',"#completewith Training1 << Warrior`n    #completewith Vendor << Priest/Mage")
            $reason='Scope the building approach to the existing Warrior trainer or Priest/Mage water vendor in that building. Preserve class-only training and the subsequent Sarvis quest actions.'
        }
        if($Name -cin @('38-39 Dustwallow Marsh','39-41 Hillsbrad/Alterac/Arathi part 2') -and
            $old.Contains('#completewith Compendium') -and $old -match '(?m)^\s*\.complete 1113,1\b') {
            $new=$new.Replace('#completewith Compendium',"#completewith Compendium << !Undead`n#completewith Bosses << Undead")
            $reason='Keep Hearts of Zeal active through the Scarlet Monastery bosses for Undead, who cannot take Compendium of the Fallen. Do not broaden quest1049 eligibility.'
        }
        if($Family -ceq 'classic' -and $Name -ceq '1-6 Orc/Troll' -and
            $old.StartsWith("step << Warlock/Warrior/Shaman/Hunter`n") -and $old.Contains('#completewith Ruzan2')) {
            $new=$new.Replace('#completewith Ruzan2',"#completewith Ruzan2 << Warlock`n    #completewith Gornek2 << !Warlock")
            $reason='Scope non-Warlock funding reminders to their next shared Gornek stop, the destination previously selected by the missing-label fallback. Keep all class-specific money requirements and training instructions.'
        }
        if($Family -cin @('tbc','curated') -and $Name -ceq '45-46 Feralas' -and
            $old.Contains('#completewith STVZepp2')) {
            $new=$new.Replace('#completewith STVZepp2','#completewith OrgrimmarStops335')
            $reason='Finish the Ratchet/Orgrimmar arrival reminders at the existing first Orgrimmar reward stop. The later zeppelin is in another chapter and cannot supply a local anchor; all vendor, training and reward stops remain.'
        }
        if($Family -ceq 'tbc' -and $Name -ceq '38-38 Swamp of Sorrows' -and
            $old.Contains('#completewith ExitBL')) {
            $new=$new.Replace('#completewith ExitBL','#completewith NethergardeFlight335')
            $reason='Keep the Blasted Lands approach through the existing Nethergarde flight-master stop, before the authored exit. Preserve first-time flight discovery and all onward travel.'
        }
        if($Name -ceq '24-27 Redridge/Duskwood' -and $old.Contains('"Enable Interact Key"')) {
            $new=[regex]::Replace($new,'(?m)^[ \t]*>>[^\n]*(?:Press Escape, then go into -> Options -> Controls|"Enable Interact Key")[^\n]*\n','')
            $at=$new.IndexOf("`n")+1
            $new=$new.Insert($at,"    >>On the 3.3.5 client, interact with the chest manually by right-clicking it when in range. There is no modern Enable Interact Key option to enable.`n")
            $reason='Replace modern Classic control-menu instructions with ordinary 3.3.5 manual chest interaction. Retain the Rogue quest and surrounding warnings.'
        }
        if($new -cne $old) {
            $count=$Text.Split(@($old),[StringSplitOptions]::None).Count-1
            if($count -ne 1){throw 'Ambiguous reviewed label step.'}
            $edits.Add([ordered]@{from=$old;to=$new;occurrences=1;kind='reviewed-label-repair';reason=$reason
                attribution='Pinned RestedXP v4.11.11 source and production 3.3.5 branch/label behavior.'})
        }
    }
    return $edits.ToArray()
}
