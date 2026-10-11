-- Production skill scanning, subtype resolution and item eligibility; no client required.
return function(root)
    local file = assert(io.open(root .. "/Features/ItemUpgrades.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
    local function section(first, last)
        local a = assert(source:find(first, 1, true))
        local b = assert(source:find(last, a + #first, true))
        return source:sub(a, b - 1)
    end
    local env = setmetatable({}, {__index = _G})
    env._G = env
    local armor = {Generic=0,Cloth=1,Leather=2,Mail=3,Plate=4,Shield=6,
        Libram=7,Idol=8,Totem=9,Sigil=10}
    local weapon = {Axe1H=0,Axe2H=1,Bows=2,Guns=3,Mace1H=4,Mace2H=5,
        Polearm=6,Sword1H=7,Sword2H=8,Staff=10,Unarmed=13,Generic=14,
        Dagger=15,Thrown=16,Crossbow=18,Wand=19,Fishingpole=20}
    local slot = 0
    for name in source:gmatch("_G%.(INVSLOT_[A-Z0-9_]+)") do
        if not env[name] then slot=slot+1; env[name]=slot end
    end
    env.INVSLOT_FIRST_EQUIPPED, env.INVSLOT_LAST_EQUIPPED = 1, 19
    local class, level, skills, known, equipment = "MAGE", 5, {}, {}, {}
    local selected, collapsed, failScan = 1, true, false
    local names = {[9078]="Cloth",[9077]="Leather",[8737]="Mail",
        [750]="Plate Mail",[9116]="Shields",[201]="One-Handed Swords"}
    env.UnitClass=function() return class,class end
    env.UnitLevel=function() return level end
    env.GetSpellInfo=function(id) return names[id] end
    env.IsSpellKnown=function(id) return known[id] or false end
    env.IsPlayerSpell=false
    env.GetNumSpellTabs=false
    env.GetAuctionItemSubClasses=function() return "Miscellaneous","Cloth","Leather","Mail","Plate","Shields","Relic" end
    env.GetNumSkillLines=function() return collapsed and 1 or #skills+1 end
    env.GetSkillLineInfo=function(i)
        if i==1 then return "Skills",true,not collapsed end
        if failScan then error("delayed skill data") end
        return skills[i-1],false,nil,1
    end
    env.GetSelectedSkill=function() return selected end
    env.SetSelectedSkill=function(i) selected=i end
    env.ExpandSkillHeader=function() collapsed=false end
    env.CollapseSkillHeader=function() collapsed=true end
    env.GetInventoryItemLink=function(_,i) return equipment[i] end
    env.GetItemInfo=function(link)
        local subtype = link == "unknown" and "Unmapped armor" or link
        local loc = link == "One-Handed Swords" and "INVTYPE_WEAPON" or
            link == "Shields" and "INVTYPE_SHIELD" or "INVTYPE_FEET"
        return link,link,0,5,1,"Armor",subtype,1,loc,nil,1
    end
    env.GetItemInfoInstant=function() return 999 end
    env.GetItemStats=function() return {ARMOR=72} end
    env.wipe=function(t) for k in pairs(t) do t[k]=nil end end
    env.strlower=string.lower
    env.ItemArmorSubclass, env.ItemWeaponSubclass = armor, weapon
    env.IsEquippedItem=function() return false end
    env.NativeIsUsableItem=function() return false end
    env.IsWeaponSlot=function(loc) return loc=="INVTYPE_WEAPON" or loc=="INVTYPE_WEAPONOFFHAND" end
    env.GetTooltipLines=function() return {} end
    env.ParseLegacyTooltipStats=function() end
    env.ParseItemUniqueness=function() end
    local addon = {gameVersion=30300,itemUpgrades={},player={class=class,level=level},
        settings={profile={}},Round=function(n) return n end}
    local session = {trainedWeapons={},trainedWeaponSources={},trainedArmor={},
        trainedArmorSources={},itemCache={},statsRegexes={},activeStatWeights={ARMOR=.01}}
    env.addon,env.session=addon,session
    local chunk = section("local function KnowsLegacySpell", "-- Map quasi-friendly") ..
        section("function addon.itemUpgrades:UpdateSlotMap()", "function addon.itemUpgrades:Setup()") ..
        section("local WEAPON_SUBCLASS_BY_NAME", "local function CalculateDPSWeight") ..
        section("function addon.itemUpgrades:GetItemData(", "local function IsSlotRemovedByCandidate") ..
        "\nreturn RefreshWeaponProficiencies, IsUsableForClass"
    local refresh, usable = setfenv(assert(loadstring(chunk)),env)()
    local function reset()
        addon.itemUpgrades:UpdateSlotMap(); refresh(); env.wipe(session.itemCache)
        assert(collapsed and selected==1, "Skill UI was not restored")
    end
    known[9078]=true; skills={"Cloth","Daggers"}; reset()
    assert(usable(2,"INVTYPE_FEET","Leather")==false, "Mage leather accepted")
    assert(addon.itemUpgrades:GetItemData("Leather",{}).unusable)
    assert(addon.itemUpgrades:GetItemData("unknown",{}).proficiencyUnknown,
        "Unknown armor reached scoring")
    assert(addon.itemUpgrades:GetItemData("Cloth",{}).totalWeight==.72)
    assert(session.trainedWeapons[weapon.Sword1H]==false, "Unlearned sword not recorded")
    assert(usable(weapon.Sword1H,"INVTYPE_WEAPON")==false, "False became unknown")
    skills={"Cloth","Daggers","One-Handed Swords"}; reset()
    assert(usable(weapon.Sword1H,"INVTYPE_WEAPON")==true)
    assert(usable(weapon.Sword1H,"INVTYPE_WEAPONOFFHAND")==false, "Weapon granted dual wield")
    skills={"Unarmed"}; known={}; reset()
    assert(usable(weapon.Unarmed,"INVTYPE_WEAPON")~=true, "Unarmed granted fist weapons")
    failScan=true; reset()
    assert(not session.scanningProficiencies, "Failed scan left reentrancy guard set")
    failScan=false
    class="WARRIOR"; skills={"Mail","Leather","Cloth","Axes","Shields"}; reset()
    assert(session.trainedArmor[armor.Mail] and session.trainedArmorSources[armor.Mail]=="skill")
    assert(usable(armor.Mail,"INVTYPE_FEET","Mail")==true)
    assert(usable(armor.Shield,"INVTYPE_SHIELD","Shields")==true)
    assert(addon.itemUpgrades.SubclassNameToID("Shields","INVTYPE_SHIELD")==armor.Shield)
    assert(usable(armor.Plate,"INVTYPE_FEET","Plate")==false)
    class="HUNTER"; level=40; skills={"Leather","Axes"}; reset()
    assert(usable(armor.Mail,"INVTYPE_FEET","Mail")==false, "Level alone granted mail")
    known[8737]=true; skills={"Leather","Mail","Axes"}; reset()
    assert(usable(armor.Mail,"INVTYPE_FEET","Mail")==true)
    known={}; equipment[1]="Mail"; reset()
    assert(usable(armor.Mail,"INVTYPE_FEET","Mail")==true, "Equipped evidence lost")
    equipment={}
    -- With no exposed armor skill rows, retain the private-core per-item
    -- fallback for trained mail whose hidden passive is unavailable.
    skills={}; env.NativeIsUsableItem=function() return true end; reset()
    assert(usable(armor.Mail,"INVTYPE_FEET","Mail")==true)
    skills={"Leather","Axes"}; reset()
    assert(usable(armor.Mail,"INVTYPE_FEET","Mail")==false,
        "Broad item hint overrode complete skill evidence")
    for _,name in ipairs({"Leder","Cuero","Cuir","Кожа","가죽","皮甲","皮革"}) do
        names[9077]=name; skills={name}; reset()
        assert(addon.itemUpgrades.SubclassNameToID(name,"INVTYPE_FEET")==armor.Leather)
        assert(session.trainedArmor[armor.Leather], "Localized skill not recognized")
    end
    local inventoryFile=assert(io.open(root .. "/Features/InventoryManager.lua","rb"))
    local inventory=inventoryFile:read("*a"); inventoryFile:close()
    local a=assert(inventory:find("local function IsJunk(id, bag, slot)",1,true))
    local b=assert(inventory:find("inventoryManager.IsJunk = IsJunk",a,true))
    env.RXPCData={manualJunkOverrides={},discardPile={}}
    env.Enum={ItemQuality={Poor=0,Common=1}}
    env.BODY_ARMOR_EQUIP_LOCS={INVTYPE_FEET=true}
    env.WEAPON_EQUIP_LOCS={}
    env.exceptions={}
    env.GetManualJunkKey=function(id) return id .. ":instance" end
    env.IsEquippableLocation=function() return true end
    env.IsConsumable=function() return false end
    local status="unknown"
    addon.itemUpgrades.GetItemUpgradeStatus=function() return status end
    local junk=setfenv(assert(loadstring(inventory:sub(a,b-1) .. "\nreturn IsJunk")),env)()
    class="MAGE"; skills={"Cloth"}; known={[9078]=true}; reset()
    assert(junk("unknown")==false, "Unknown equipment marked junk")
    assert(junk("Leather")==true, "Confirmed unusable armor not classified")
    status="upgrade"; assert(junk("Cloth")==false, "Usable upgrade marked junk")
    status="downgrade"; assert(junk("Cloth")==true)
    status="equal"; assert(junk("Cloth")==true, "Existing grey/white equal policy changed")
    env.RXPCData.manualJunkOverrides["Cloth:instance"]=false
    assert(junk("Cloth")==false, "Manual keep override lost")
    -- Exercise the production debounce callback: stale events cannot rebuild
    -- repeatedly, and skill-header events during scanning cannot recurse.
    local callbacks, refreshes = {}, 0
    env.C_Timer={After=function(_, fn) callbacks[#callbacks+1]=fn end}
    env.RefreshWeaponProficiencies=function() refreshes=refreshes+1 end
    env.InvalidateUpgradeDetailTooltip=function() end
    env.QueueUpgradeScan=function() end
    addon.SendEvent=function() end
    session.promptedUpgrades={}
    session.proficiencyRefreshSerial=0
    local eventSource=section("function addon.itemUpgrades:WEAPON_PROFICIENCY_CHANGED()",
        "function addon.itemUpgrades:LoadStatWeights()")
    setfenv(assert(loadstring(eventSource)),env)()
    addon.itemUpgrades:WEAPON_PROFICIENCY_CHANGED()
    addon.itemUpgrades:WEAPON_PROFICIENCY_CHANGED()
    callbacks[1](); callbacks[2]()
    assert(refreshes==1, "Skill event burst was not coalesced")
    session.scanningProficiencies=true
    addon.itemUpgrades:WEAPON_PROFICIENCY_CHANGED()
    assert(#callbacks==2, "Skill scan scheduled recursive work")
    print("Equipment proficiency regressions passed: armor, weapons, locales, unknown data and skill UI.")
end
