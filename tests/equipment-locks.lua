return function(root)
    local f=assert(io.open(root .. "/Features/ItemUpgrades.lua","rb"))
    local source=f:read("*a"); f:close()
    local a=assert(source:find("function addon.itemUpgrades:IsEquipmentSlotLocked",1,true))
    local b=assert(source:find("-- Returns a conservative four-state result.",a,true))
    local equipment={[1]="quest",[16]="sword",[17]="shield",[11]="ring1",[12]="ring2"}
    local locs={quest="INVTYPE_HEAD",better="INVTYPE_HEAD",twohand="INVTYPE_2HWEAPON",
        sword="INVTYPE_WEAPON",shield="INVTYPE_SHIELD",ring="INVTYPE_FINGER"}
    local session={equipmentLocks={},promptedUpgrades={},equippableSlots={
        INVTYPE_HEAD=1,INVTYPE_2HWEAPON=16,INVTYPE_WEAPON=16,INVTYPE_SHIELD=17,
        INVTYPE_FINGER={[11]=11,[12]=12}}}
    local rows={}
    local refreshes=0
    local addon={itemUpgrades={},inventoryManager={RefreshJunkIcons=function() refreshes=refreshes+1 end}}
    local env=setmetatable({addon=addon,session=session,L=function(s) return s end,
        fmt=string.format,INVSLOT_MAINHAND=16,INVSLOT_OFFHAND=17,
        GetInventoryItemLink=function(_,slot) return equipment[slot] end,
        GetItemInfo=function(link) return link,link,0,nil,nil,nil,nil,nil,locs[link] end,
        GetComparisonIncrease=function(c) return c.WeightIncrease end,
        QueueUpgradeScan=function() end,InvalidateUpgradeDetailTooltip=function() end,
        StaticPopup_Hide=function() assert(session.pendingUpgradeEquip==nil) end,
        wipe=function(t) for k in pairs(t) do t[k]=nil end end},
        {__index=_G})
    env._G=env
    setfenv(assert(loadstring(source:sub(a,b-1))),env)()
    local u=addon.itemUpgrades
    function u:CompareItemWeight() return rows,nil,"upgrade" end
    rows={{SlotCompared=1,WeightIncrease=10}}
    assert(select(2,u:GetBestUpgradeComparison("better"))=="upgrade")
    u:SetEquipmentSlotLocked(1,true)
    assert(session.equipmentLocks[1]=="quest" and u:IsEquipmentSlotLocked(1))
    assert(select(2,u:GetBestUpgradeComparison("better"))=="locked")
    assert(u:IsProtectedByEquipmentLock("better"))
    assert(rows[1].WeightIncrease==10,"Lock changed EP")
    equipment[1]="replacement"
    assert(not u:IsEquipmentSlotLocked(1),"Manual swap retained obsolete lock")
    assert(select(2,u:GetBestUpgradeComparison("better"))=="upgrade")
    u:SetEquipmentSlotLocked(17,true)
    rows={{SlotCompared=16,WeightIncrease=20}}
    assert(select(2,u:GetBestUpgradeComparison("twohand"))=="locked",
        "Two-hander removed locked off-hand")
    assert(select(2,u:GetBestUpgradeComparison("sword"))=="upgrade",
        "Off-hand lock blocked unrelated main-hand swap")
    assert(u:IsProtectedByEquipmentLock("twohand"))
    u:ClearEquipmentLocks()
    equipment[16]="twohand"
    u:SetEquipmentSlotLocked(16,true)
    rows={{SlotCompared=17,WeightIncrease=10}}
    assert(select(2,u:GetBestUpgradeComparison("shield"))=="locked",
        "Off-hand removed locked two-hander")
    u:ClearEquipmentLocks()
    u:SetEquipmentSlotLocked(11,true)
    rows={{SlotCompared=11,WeightIncrease=20},{SlotCompared=12,WeightIncrease=10}}
    local offer,state=u:GetBestUpgradeComparison("ring")
    assert(state=="upgrade" and offer.SlotCompared==12,"Unlocked ring slot was ignored")
    u:SetEquipmentSlotLocked(12,true)
    assert(select(2,u:GetBestUpgradeComparison("ring"))=="locked")
    u:ClearEquipmentLocks()
    assert(not next(session.equipmentLocks) and refreshes>0)
    -- Session reset never restores locks from any profile/character data.
    session.equipmentLocks={}
    assert(not u:IsEquipmentSlotLocked(11))

    local inv=assert(io.open(root .. "/Features/InventoryManager.lua","rb"))
    local text=inv:read("*a"); inv:close()
    a=assert(text:find("local function IsJunk(id, bag, slot)",1,true))
    b=assert(text:find("inventoryManager.IsJunk = IsJunk",a,true))
    env.RXPCData={manualJunkOverrides={},discardPile={}}
    env.GetManualJunkKey=function(id) return id..":instance" end
    env.IsConsumable=function() return false end
    env.IsEquippableLocation=function() return true end
    env.exceptions={}
    env.BODY_ARMOR_EQUIP_LOCS={INVTYPE_HEAD=true}
    env.WEAPON_EQUIP_LOCS={}
    env.Enum={ItemQuality={Poor=0,Common=1}}
    function u:GetItemWearability() return "wearable" end
    function u:GetItemUpgradeStatus() return "downgrade" end
    local junk=setfenv(assert(loadstring(text:sub(a,b-1).."\nreturn IsJunk")),env)()
    u:SetEquipmentSlotLocked(1,true)
    assert(not junk("better"),"Replacement gear was not protected")
    env.RXPCData.manualJunkOverrides["better:instance"]=true
    assert(junk("better"),"Explicit manual override lost")
    env.RXPCData.manualJunkOverrides={}
    u:ClearEquipmentLocks()
    assert(junk("better"),"Unlock did not restore normal junk policy")
    -- A popup opened before the slot was locked must not equip on a stale click.
    a=assert(source:find("function addon.itemUpgrades:EquipBagUpgrade(data)",1,true))
    b=assert(source:find("local function HideUpgradePromptTooltip",a,true))
    setfenv(assert(loadstring(source:sub(a,b-1))),env)()
    env.InCombatLockdown=function() return false end
    env.UnitIsDeadOrGhost=function() return false end
    env.GetCursorInfo=function() end
    env.GetContainerItemLink=function() return "better" end
    env.RefreshWeaponProficiencies=function() end
    env.GetVisibleBindConfirmation=function() end
    env.ConfirmPendingUpgradeEquip=function() end
    function u:UpdateSlotMap() end
    session.itemCache={}
    local equipCalls=0
    env.EquipItemByName=function(link,slot)
        equipCalls=equipCalls+1; equipment[slot]=link
    end
    rows={{SlotCompared=1,WeightIncrease=10}}
    u:SetEquipmentSlotLocked(1,true)
    assert(not u:EquipBagUpgrade({bag=0,bagSlot=1,itemLink="better"}) and equipCalls==0,
        "Stale popup bypassed equipment lock")
    u:SetEquipmentSlotLocked(1,false)
    assert(u:EquipBagUpgrade({bag=0,bagSlot=1,itemLink="better"}) and equipCalls==1,
        "Unlock did not restore explicit equip")
    print("Equipment lock regressions passed: EP, slot swaps, paired hands, rings, session reset and junk protection.")
end
