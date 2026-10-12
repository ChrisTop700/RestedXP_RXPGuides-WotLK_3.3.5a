local addonName, addon = ...

-- Return nil ('raw') for non-enUS entries
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true, 'raw')

-- Attack Timer UI inventory; companion locale packs can translate these keys.
L["Attack Timer"] = true
L["Enable Attack Timer"] = true
L["Show Attack Timers"] = true
L["Show Damage Ranges"] = true
L["Show Attack Intervals"] = true
L["AzerothCore Melee/Ranged Timer Resets"] = true
L["Main hand"] = true
L["Off hand"] = true
L["Ranged"] = true
L["Timer ready"] = true
L["Timing unknown"] = true
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
