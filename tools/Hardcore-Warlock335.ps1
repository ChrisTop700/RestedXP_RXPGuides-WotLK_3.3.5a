# Offline compatibility transforms. Callers bind these exact replacements to
# pinned chapter hashes; this is not a runtime quest or spell simulator.
function Get-HardcoreWarlockStarterEdit335([string]$Text) {
    $name = [regex]::Match($Text,'(?m)^#name ([^\n]+)').Groups[1].Value.Trim()
    $race = switch -Regex ($name) {
        '^1-6 (Orc/Troll|Durotar)$' { 'orc'; break }
        '^1-6 (Undead|Tirisfal Glades)$' { 'undead'; break }
        '^1-(6 Northshire|11 Elwynn Forest)$' { 'human'; break }
        '^1-(6 Coldridge Valley|10 Dun Morogh)$' { 'gnome'; break }
        '^1-6 Eversong Woods$' { 'bloodelf'; break }
        default { '' }
    }
    if (-not $race) { return }
    $config = @{
        orc=@{zone='Durotar';vendor='Duokna';v='42.59,67.34';trainer='Nartok';t='40.65,68.52';mob='Mottled Boar';g='43.57,67.28';quest=788}
        undead=@{zone='Tirisfal Glades';vendor='Joshua Kien';v='32.29,65.44';trainer='Maximillion';t='30.91,66.34';mob='Young Scavenger';g='30.70,69.28';quest=364}
        human=@{zone='Elwynn Forest';vendor='Brother Danil';v='47.486,41.566';trainer='Drusilla La Salle';t='49.873,42.649';mob='Diseased Young Wolf';g='46.2,40.4';quest=33}
        gnome=@{zone='Dun Morogh';vendor='Durnan Furcutter';v='28.769,66.377';trainer='Alamar Grimm';t='28.650,66.145';mob='Ragged Young Wolf';g='29.68,74.20';quest=179}
        bloodelf=@{zone='Eversong Woods';vendor='Shara Sunwing';v='38.66,20.33';trainer="Summoner Teli'Larien";t='38.93,21.44';mob='Mana Wyrm';g='37.70,23.26';quest=8326}
    }[$race]
    $steps = [regex]::Matches($Text,'(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)')
    if (-not $steps.Count) { throw 'Starter has no steps.' }
    $result = $Text.Substring(0,$steps[0].Index)
    $inserted = $false
    $lateTraining = 0
    foreach ($match in $steps) {
        $old = $match.Value
        $new = $old
        $warlockOnly = $old -match '^[ \t]*step << Warlock[ \t]*\n'
        # Remove unavailable quest-exclusive instructions, never mixed rewards.
        if ($race -eq 'orc') {
            if ($old -match '\.(?:accept|complete|isOnQuest) 1485\b' -or
                $old -match '\.turnin 1499\b' -or
                ($warlockOnly -and $old.Contains('en route to the Burning Blade Coven'))) {
                $new = ''
            } elseif ($old -match '(?m)^[ \t]*#label Ruzan2\s*$') {
                $new = "step << Warlock`n    #label Ruzan2`n    #optional`n    +Continue the ordinary Valley of Trials quests with your Imp. The removed Imp quest chain is not required on WotLK.`n"
            } elseif ($warlockOnly -and $old -match 'Hraug' -and $old -notmatch 'Grimoire|#label Hraug3') {
                # Keep ordinary vendor opportunities, but use an actual vendor.
                $new = "step << Warlock`n    .goto Durotar,42.59,67.34`n    >>Sell vendor trash to Duokna if needed. Keep useful equipment and quest items.`n    .vendor >>Vendor trash`n    .target Duokna`n"
                if ($old -match '#completewith next') { $new = '' }
            } elseif ($old -match '(?m)^[ \t]*\.train 348\b') {
                $new = "step << Warlock`n    #label Nartok`n    #optional`n    +Summon Imp was trained after accepting Cutting Teeth. Continue with the ordinary quests before buying later spells.`n"
            }
            if ($new -and ($old -match '\.(?:accept|complete|turnin) 792\b|#completewith Imps\b')) {
                $new = $new.Replace('step << !Warlock','step')
            }
            if ($old -match '#completewith Sarkoth\b') { $new = $new.Replace(' << !Warlock','') }
            if ($old -match '^step << Warrior/Shaman/Warlock') {
                $new = [regex]::Replace($new.Replace('step << Warrior/Shaman/Warlock','step << Warrior/Shaman'),
                    '(?m)^[^\n]* << Warlock\n','')
            }
        } elseif ($race -eq 'human') {
            if ($old -match '\.(?:accept|complete|turnin) 1598\b|\.target Dane Winslow\b|Remain inside the Tent') { $new = '' }
        } elseif ($race -eq 'gnome') {
            if ($old -match '\.accept 1599\b|\.complete 1599\b' -or
                ($warlockOnly -and $old -match 'Unequip your Body Armor|Vendor your Body Armor|Enter the Frostmane Cave|\.hs >> Hearth to Coldridge Valley')) {
                $new = ''
            } elseif ($old -match '\.turnin 1599\b') {
                $new = [regex]::Replace($new,'(?m)^[ \t]*\.turnin 1599[^\n]*\n','')
                $new = $new.Replace('.goto Dun Morogh,28.650,66.145',".goto Dun Morogh,28.792,68.497,20,0`n    .goto Dun Morogh,28.650,66.145")
            }
        } elseif ($race -eq 'undead') {
            if ($old -match '\.accept 1470\b') {
                $new = [regex]::Replace($new,'(?m)^[ \t]*(?:\.accept 1470|\.goto Tirisfal Glades,30.98,66.41|\.target \+Venya Marthand)[^\n]*\n','')
                $new = $new.Replace('Talk to |cRXP_FRIENDLY_Venya|r and |cRXP_FRIENDLY_Sarvis|r << Warlock','Talk to |cRXP_FRIENDLY_Sarvis|r << Warlock')
            } elseif ($old -match '\.(?:complete|turnin) 1470\b|\.target Kayla Smithe\b|\.train 348\b' -or
                ($warlockOnly -and $old.Contains('25 copper worth of vendor items (including your armor)'))) {
                # Vendor is a shared dependency name, so retain an optional anchor.
                $new = if ($old -match '(?m)^[ \t]*#label Vendor\s*$') {
                    "step << Warlock`n    #label Vendor`n    #optional`n    +Keep useful equipment. The Imp training budget is handled after the first ordinary quest pickup.`n"
                } else { '' }
            } elseif ($old -match '\.isOnQuest 1470\b') {
                $new = $new.Replace('.isOnQuest 1470',".money <0.0025`n    .itemcount 159,<5")
            }
            if ($old -match '^step << Warrior/Warlock/Priest/Mage') {
                $new = $new.Replace('Warrior/Warlock/Priest/Mage','Warrior/Priest/Mage').Replace('Warrior/Warlock','Warrior')
            }
        } elseif ($race -eq 'bloodelf') {
            $new = [regex]::Replace($new,'(?m)^[ \t]*\.(?:accept|complete|turnin) 8344\b[^\n]*\n','')
            if ($old -match '\.accept 8344\b') {
                $new = [regex]::Replace($new,'(?m)^[ \t]*\.trainer[^\n]*\n','')
            }
            if ($old -match '\.complete 8344,1\b') {
                $new = [regex]::Replace($new,'(?m)^[ \t]*>>[^\n]*Essences[^\n]*\n',
                    "    >>Kill Arcane Wraiths and Tainted Arcane Wraiths. Loot them for Arcane Slivers.`n")
            }
            if ($old -match '\.complete 8344,2\b') {
                $new = $new.Replace('its |cRXP_LOOT_Essence|r and |T132884:0|t','its |T132884:0|t')
            }
            if ($old -match '\.turnin 8344\b' -and $old -notmatch '\.train 172\b') { $new = '' }
        }
        # Old delayed summons assumed the unavailable quest granted the spell.
        # The replacement summon immediately follows actual Imp training.
        if ($warlockOnly -and $old -match '\.cast 688\b' -and $old -notmatch '#softcore') { $new = '' }
        if ($new -and ($new -match '\.train 172\b|\.trainer[^\n]*(?:Corruption)')) {
            $lateTraining++
            $new = [regex]::Replace($new,'(?m)^[ \t]*\.(?:xp 4\b|train 172\b|trainer[^\n]*Corruption)[^\n]*\n','')
            $new += "    .train 348 >>Train Immolate`n    .train 172 >>Train Corruption`n"
            if ($race -eq 'orc' -and $new -notmatch '#label Nartok2\b') {
                $new = $new.Replace("step << Warlock`n","step << Warlock`n    #label Nartok2`n")
            }
            $guard = "step << Warlock`n    .train 172,1`n    .goto $($config.zone),$($config.g),0`n    >>If needed, kill ordinary $($config.mob) creatures until level 4 before returning to the trainer. Do not assume quest rewards or server XP rates already granted this level.`n    .xp 4`n    .mob $($config.mob)`n"
            $funding = "step << Warlock`n    .goto $($config.zone),$($config.v),0`n    >>Sell vendor trash to $($config.vendor) if needed. Keep useful equipment and quest items. Budget up to 10 copper for Immolate and 1 silver for Corruption, only for spells you have not learned.`n    +Check this instruction when you can afford the remaining training, then visit $($config.trainer).`n"
            $new = $guard + $funding + $new
        }
        # A shared supply instruction must not require Warlocks to sell armor.
        if ($new -and $old -match 'including your armor' -and $old -match 'Warlock') {
            $new = [regex]::Replace($new,'(?m)^([^\n]*including your armor[^\n]*)$', {
                param($m)
                $line = $m.Value
                if ($line -match '<<' -and $line -notmatch 'Warlock') { return $line }
                $safe = $line.Replace('including your armor','keep useful equipment and quest items')
                if ($warlockOnly -or $line -match '<< Warlock\s*$') { return $safe }
                if ($line -notmatch '<<') { return $line+" << !Warlock`n"+$safe+' << Warlock' }
                return $line.Replace('/Warlock','').Replace('Warlock/','')+"`n"+
                    ([regex]::Replace($safe,'<<.*$','<< Warlock'))
            })
        }
        $result += $new
        if (-not $inserted -and $new -match ('(?m)^[ \t]*\.accept '+$config.quest+'\b')) {
            $approach = ''
            if ($race -eq 'orc') { $approach = "    .goto Durotar,41.52,68.36,12,0`n    .goto Durotar,41.24,68.16,12,0`n    .goto Durotar,40.82,68.03,12,0`n" }
            if ($race -eq 'gnome') { $approach = "    .goto Dun Morogh,28.792,68.497,20,0`n" }
            $result += "step << Warlock`n    .train 688,1`n    .goto $($config.zone),$($config.g),0`n    .goto $($config.zone),$($config.v),0`n    >>Work on the ordinary quests and kill nearby $($config.mob) creatures if needed. Sell vendor trash to $($config.vendor) until you have 1 silver in coins for Summon Imp. Keep useful equipment and quest items; reserve this money before buying water or other spells.`n    .mob $($config.mob)`n    +When you have 1 silver in coins, check this instruction and visit $($config.trainer).`n"
            $result += "step << Warlock`n    .train 688,1`n"+$approach+
                "    .goto $($config.zone),$($config.t)`n    >>Talk to $($config.trainer). Summon Imp is trained from level 1 for up to 1 silver on WotLK instead of awarded by the old Imp quest. Training requires your own click.`n    .train 688 >>Train Summon Imp`n    .target $($config.trainer)`nstep << Warlock`n    .cast 688 >>Summon your Imp before continuing the ordinary quests`n"
            $inserted = $true
        }
    }
    if (-not $inserted -or $lateTraining -ne 1) { throw "Missing/ambiguous training sequence: $name" }
    if ($result -match '\.(?:accept|turnin|complete|isOnQuest) (?:1485|1499|1598|1599|1470|8344)\b') {
        throw "Unavailable Imp quest retained: $name"
    }
    return [ordered]@{from=$Text;to=$result;occurrences=1;kind='warlock-starter'
        reason='Replace removed Imp quest chains with verified WotLK training after ordinary quest pickup; preserve valid rewards, labels and the upstream itinerary.'
        attribution='Pinned v4.11.11 Survival sources; AzerothCore trainer_spell list32, quest starters/enders and NPC vendor flags; tests/fixtures/hardcore-warlock335.json.'}
}

function Get-HardcoreGrimoireEdits335([string]$Text) {
    $edits = [Collections.Generic.List[object]]::new()
    $seen = @{}
    $working = $Text
    # A shorter step can be a literal prefix of another step with an extra
    # gate. Replace longer bodies first, counting against the current result.
    $matches = [regex]::Matches($Text,'(?ms)^[ \t]*step\b[^\n]*\n.*?(?=^[ \t]*step\b|\z)') |
        Sort-Object @{Expression={$_.Length};Descending=$true},Index
    foreach ($match in $matches) {
        $old = $match.Value
        if ($seen.ContainsKey($old)) { continue }
        $seen[$old] = $true
        if ($old -notmatch '^[ \t]*step << Warlock(?: TBC)?[ \t]*\n' -or
            $old -notmatch '(?i)grimoire|\.vendor[^\n]*Buy any pet upgrades') { continue }
        # Existing curated reminders say NOT to buy grimoires. Mentioning
        # the word without a purchase/use/training action is not a defect.
        if ($old -notmatch '(?m)^[ \t]*\.(?:collect|buy|use|itemcount|train|vendor|cast)\b') { continue }
        # The word also names legitimate quest objectives. Never remove those.
        if ($old -match '\.(?:accept|turnin|complete) \d+') { continue }
        foreach ($item in [regex]::Matches($old,'(?m)^[ \t]*\.(?:collect|buy|use|itemcount) (\d+)')) {
            if ([int]$item.Groups[1].Value -notin @(16302,16316,16321,16346,16351,16357)) {
                throw 'Unreviewed mixed item in demon-training instruction.'
            }
        }
        foreach ($tag in [regex]::Matches($old,'(?m)^[ \t]*\.([A-Za-z]+)\b')) {
            if ($tag.Groups[1].Value -cnotin @('goto','target','vendor','collect','buy','use','itemcount','train',
                'money','xp','group','dungeon','zoneskip','subzoneskip','isQuestComplete')) {
                throw 'Unreviewed action in demon-training instruction.'
            }
        }
        foreach ($spell in [regex]::Matches($old,'(?m)^[ \t]*\.train (\d+)')) {
            if ([int]$spell.Groups[1].Value -notin @(6307,7799,20270,20381,17767,20317)) {
                throw 'Unreviewed player/pet spell in demon-training instruction.'
            }
        }
        $new = [regex]::Match($old,'^[ \t]*step[^\n]*\n').Value + "    #optional`n"
        foreach ($label in [regex]::Matches($old,'(?m)^[ \t]*#label [^\n]*\n')) { $new += $label.Value }
        foreach ($gate in [regex]::Matches($old,'(?m)^[ \t]*\.(?:dungeon|zoneskip|subzoneskip|isQuestComplete)[^\n]*\n')) { $new += $gate.Value }
        # Retain genuine trash-selling opportunities, not grimoire-only visits.
        if ($old -match '(?m)^[ \t]*\.vendor >>[ \t]*Vendor (?:Trash|trash)') {
            if ($old.Contains('.target Hraug')) {
                $new += "    .goto Durotar,42.59,67.34`n    .target Duokna`n"
            } else {
                foreach ($line in [regex]::Matches($old,'(?m)^[ \t]*\.(?:goto|target)[^\n]*\n')) { $new += $line.Value }
            }
            $new += "    .vendor >>Sell vendor trash if needed; keep useful equipment and quest items`n"
        }
        $new += "    +Inspect your demon's spellbook as it levels. WotLK learns demon ability ranks automatically; no training grimoire purchase or use is required.`n"
        $count = $working.Split(@($old),[StringSplitOptions]::None).Count-1
        if ($count -lt 1) { throw 'Overlapping demon-training edits.' }
        $edits.Add([ordered]@{from=$old;to=$new;occurrences=$count
            kind='demon-grimoire';reason='Remove obsolete demon-training purchases/use while retaining quest grimoires, named anchors and actual trash-vendor stops.'
            attribution='AzerothCore Pet::InitLevelupSpellsForLevel and npc_vendor; pinned v4.11.11 source; tests/fixtures/hardcore-warlock335.json.'})
        $working = $working.Replace($old,$new)
    }
    return $edits.ToArray()
}
