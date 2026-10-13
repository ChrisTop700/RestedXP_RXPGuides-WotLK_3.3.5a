local addonName, addon = ...

-- Return nil ('raw') for non-enUS entries
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true, 'raw')

-- Attack Timer UI inventory; companion locale packs can translate these keys.
L["Optional Tools"] = true
L["Enable Step Doctor"] = true
L["Enable Supplies Checklist"] = true
L["Enable Personal-Best Archives"] = true
L["Optional anonymous run archives. The enabled Speedrunning Suite also requires archive recording."] = true
L["Collects bounded diagnostics and enables the current-step troubleshooting report. Off by default."] = true
L["Enables the class-supplies window and merchant checklist. Required-item junk protection remains available when this is off."] = true
L["Attack Timer"] = true
L["Enable Attack Timer"] = true
L["Show Attack Timers"] = true
L["Show Damage Ranges"] = true
L["Show Attack Intervals"] = true
L["Show Explanatory Text"] = true
L["Enable this tool, then click Open Tool. Counters stay at zero until an attack is observed. Dual-wield hands and parry adjustments are estimates. Raptor Strike, Heroic Strike, Cleave and Maul synchronize on actual strikes, not queued actions. Other spell effects and wand timing are not fully modelled. Zero does not guarantee an attack can fire."] = true
L["Show explanatory notes and ranged activity text below the attack timers. Hiding these notes does not change timer accuracy or behavior."] = true
L["Enable this tool, then click Open Tool. Counters stay at zero until an attack is observed. Dual-wield hand assignment is estimated; wands have no release countdown. Parry haste and most ability-specific resets are not modelled. Zero does not guarantee range, facing or line of sight. Damage excludes target mitigation and critical hits."] = true
L["AzerothCore Melee/Ranged Timer Resets"] = true
L["Main hand"] = true
L["Off hand"] = true
L["Ranged"] = true
L["Timer ready"] = true
L["Timing unknown"] = true
L["Estimated basic-attack timers, not guaranteed attack times. Damage is before target mitigation. Zero means idle or unobserved; a countdown starts on an observed attack."] = true
L["Dual-wield hand assignment is estimated; equal-speed weapons and extra attacks can make it inaccurate."] = true
L["Ranged autoattack inactive or unobserved."] = true
L["Estimated basic-attack timers, not guaranteed attack times. Damage is before target mitigation. Abilities invalidate timing; dual-wield swings and wands may remain unknown."] = true
L["Shows estimated basic melee and Hunter Auto Shot timing, current character-sheet damage ranges, and attack intervals. It never attacks or moves for you."] = true
L["Enable this tool, then click Open Tool. Attack to synchronize. Unknown timers are intentional after equipment, form, speed or ability changes. Dual-wield hand timing and wand timing are not inferred. Ready does not guarantee range, facing or line of sight. Damage excludes target mitigation and critical hits."] = true
L["Changes apply immediately. Coupled resets model AzerothCore basic attacks; turn this off only if your server uses independent melee and ranged timers."] = true

_G["BINDING_NAME_" .. "CLICK RXPItemFrameButton1:LeftButton"] =
    "Active Item Button 1"
_G["BINDING_NAME_" .. "CLICK RXPItemFrameButton2:LeftButton"] =
    "Active Item Button 2"
_G["BINDING_NAME_" .. "CLICK RXPItemFrameButton3:LeftButton"] =
    "Active Item Button 3"
_G["BINDING_NAME_" .. "CLICK RXPItemFrameButton4:LeftButton"] =
    "Active Item Button 4"

_G["BINDING_NAME_" .. "CLICK RXPTargetFrame_FriendlyButton1:LeftButton"] =
    "Active Friendly Target Button 1"
_G["BINDING_NAME_" .. "CLICK RXPTargetFrame_FriendlyButton2:LeftButton"] =
    "Active Friendly Target Button 2"
_G["BINDING_NAME_" .. "CLICK RXPTargetFrame_FriendlyButton3:LeftButton"] =
    "Active Friendly Target Button 3"
_G["BINDING_NAME_" .. "CLICK RXPTargetFrame_FriendlyButton4:LeftButton"] =
    "Active Friendly Target Button 4"

_G["BINDING_NAME_" .. "CLICK RXPTargetFrame_EnemyButton1:LeftButton"] =
    "Active Enemy Target Button 1"
_G["BINDING_NAME_" .. "CLICK RXPTargetFrame_EnemyButton2:LeftButton"] =
    "Active Enemy Target Button 2"
_G["BINDING_NAME_" .. "CLICK RXPTargetFrame_EnemyButton3:LeftButton"] =
    "Active Enemy Target Button 3"
_G["BINDING_NAME_" .. "CLICK RXPTargetFrame_EnemyButton4:LeftButton"] =
    "Active Enemy Target Button 4"

L.delimiter = ' '
-- Words
L.words = {}

-- enUS locale content not needed (yet), parsed guides already enUS
