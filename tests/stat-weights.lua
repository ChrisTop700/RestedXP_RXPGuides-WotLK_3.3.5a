-- Exercise manifest-loaded databases and the production selection functions.
return function(root)
    local f=assert(io.open(root .. "/Features/ItemUpgrades.lua","rb"))
    local source=f:read("*a"); f:close()
    local function section(first,last)
        local a=assert(source:find(first,1,true))
        local b=assert(source:find(last,a+#first,true))
        return source:sub(a,b-1)
    end
    local addon={game="WOTLK",player={},settings={profile={}},
        itemUpgrades={},comms={PrettyPrint=function() end,PrettyDebug=function() end}}
    assert(loadfile(root .. "/DB/tbc/statWeights.lua"))("RXPGuides",addon)
    local existing={}
    for key,data in pairs(addon.statWeights) do existing[key]=data end
    assert(loadfile(root .. "/DB/wotlk/statWeights_335.lua"))("RXPGuides",addon)
    for key,data in pairs(existing) do
        assert(addon.statWeights[key]==data,"Existing weight set replaced: "..key)
    end
    local count=0
    for key,data in pairs(addon.statWeights) do
        assert(type(data.MIN_LEVEL)=="number" and data.MIN_LEVEL<=data.MAX_LEVEL,key)
        for stat,value in pairs(data) do
            if type(value)=="number" then
                -- Negative speed preferences (fast off-hands) are intentional.
                assert(value==value and math.abs(value)<math.huge,key..": invalid "..stat)
            end
        end
        if not existing[key] and data.MIN_LEVEL<70 and
            (data.Class=="Warrior" or data.Class=="Warlock") then count=count+1 end
    end
    assert(count==21,"Unexpected leveling import count")
    local session={}
    local level,tree=1,0
    local env=setmetatable({addon=addon,session=session,strupper=string.upper,
        ITEM_WEIGHT_ADDITIONS={},
        UnitLevel=function() return level end,
        GetNumTalentTabs=function() return 3 end,
        GetTalentTabInfo=function(i) return nil,nil,nil,nil,i==tree and 10 or 0 end},
        {__index=_G})
    env._G=env
    local chunk=section("local SPEC_MAP =", "-- Setup reverse lookup") ..
        section("function addon.itemUpgrades:LoadStatWeights()", "function addon.itemUpgrades:GetSpecWeights()") ..
        "\nreturn SPEC_MAP"
    local specs=setfenv(assert(loadstring(chunk)),env)()
    for class,trees in pairs(specs) do
        addon.player.class=class
        for n=class=="DEATHKNIGHT" and 55 or 1,80 do
            level=n
            for tab=1,3 do
                tree=tab
                addon.settings.profile.itemUpgradeSpecManual=false
                addon.itemUpgrades:LoadStatWeights()
                assert(addon.itemUpgrades:ActivateSpecWeights(),class.." missing weights at "..n)
                if n>=70 or class=="DEATHKNIGHT" then
                    assert(addon.settings.profile.itemUpgradeSpec==trees[tab],
                        class.." lost native spec at "..n)
                end
            end
        end
    end
    for _,case in ipairs({{"WARRIOR","Arms"},{"WARLOCK","Affliction"}}) do
        addon.player.class=case[1]; level=1; tree=1
        addon.settings.profile.itemUpgradeSpecManual=false
        addon.itemUpgrades:LoadStatWeights()
        assert(addon.itemUpgrades:ActivateSpecWeights())
        assert(session.activeStatWeights.RESISTANCE0_NAME>0,"Starter armor scores zero")
    end
    -- A mode with no eligible sets must never retain the preceding selection.
    addon.player.class="WARRIOR"; level=1; tree=1
    addon.itemUpgrades:LoadStatWeights()
    assert(addon.itemUpgrades:ActivateSpecWeights())
    -- Armor-only fixtures model the reported empty-wrist and better-pants cases.
    -- Amounts are synthetic; assertions concern ordering, not database item stats.
    local items={
        bracers={slot="INVTYPE_WRIST",armor=25},
        pants={slot="INVTYPE_LEGS",armor=20},
        starter={slot="INVTYPE_LEGS",armor=10},
    }
    env.GetItemInfo=function(link)
        local i=items[link]
        if i then return link,link,0,5,1,"Armor","Mail",1,i.slot,nil,1 end
    end
    env.GetItemStats=function(link) return {RESISTANCE0_NAME=items[link].armor} end
    env.GetItemInfoInstant=function() return 999 end
    env.IsEquippedItem=function(link) return link=="starter" end
    env.IsUsableForClass=function() return true end
    addon.itemUpgrades.SubclassNameToID=function() return 3 end
    env.IsWeaponSlot=function() return false end
    env.ARMOR_PROFICIENCY_SPELL={}
    env.IsMeleeSlot=function() return false end
    env.tinsert=table.insert
    env.GetTooltipLines=function() return {} end
    env.ParseLegacyTooltipStats=function() end
    env.ParseItemUniqueness=function() end
    env.GetComparisonTip=function()
        return {SetHyperlink=function() end,ClearLines=function() end}
    end
    env.GetInventoryItemLink=function(_,slot) if slot==7 then return "starter" end end
    env.EMPTY,env.NONE,env.UNKNOWN="Empty","None","Unknown"
    env.INVSLOT_MAINHAND,env.INVSLOT_OFFHAND,env.INVSLOT_RANGED=16,17,18
    addon.gameVersion=30300
    addon.Round=function(n) return n end
    addon.settings.profile.enableTips=true
    addon.settings.profile.enableItemUpgrades=true
    session.itemCache,session.statsRegexes={},{}
    session.equippableSlots={INVTYPE_WRIST=9,INVTYPE_LEGS=7}
    setfenv(assert(loadstring(
        section("function addon.itemUpgrades:GetItemData(", "local function IsSlotRemovedByCandidate") ..
        section("local function IsSlotRemovedByCandidate", "local LEGACY_BIND_CONFIRMATIONS"))),env)()
    for _,link in ipairs({"bracers","pants"}) do
        assert(addon.itemUpgrades:GetItemUpgradeStatus(link)=="upgrade",
            link.." armor benefit not recognized")
        local offer,state=addon.itemUpgrades:GetBestUpgradeComparison(link)
        assert(state=="upgrade" and offer.WeightIncrease>0,link.." has no equip offer")
    end
    addon.settings.profile.hardcore=true
    addon.itemUpgrades:LoadStatWeights()
    assert(not addon.itemUpgrades:ActivateSpecWeights())
    assert(next(session.activeStatWeights)==nil,"Stale weights survived failed selection")
    assert(addon.itemUpgrades:GetItemUpgradeStatus("bracers")=="unknown",
        "Missing weights became equal instead of unknown")
    print("Stat-weight regressions passed: preserved tables, 21 imports, every class/tree/level and missing-weight safety.")
end
