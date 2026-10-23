-- Production refresh paths and private timer/scheduler; only client APIs mocked.
return function(root)
    local function read(path)
        local f = assert(io.open(root .. "/" .. path, "rb"))
        local text = f:read("*a"):gsub("\r\n", "\n"); f:close(); return text
    end
    local function section(path, first, last)
        local text = read(path)
        local a = assert(text:find(first, 1, true), first)
        return text:sub(a, assert(text:find(last, a, true), last) - 1)
    end
    local env = setmetatable({}, {__index = _G}); env._G = env
    local frames, errors, now = {}, {}, 0
    local function noop() end
    local function frame()
        local f = {scripts = {}, shown = true}
        function f:SetScript(key, fn) self.scripts[key] = fn end
        function f:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
        function f:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
        function f:IsShown() return self.shown end
        function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function f:CreateFontString() return frame() end
        function f:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
        for _, key in ipairs({"SetSize", "SetPoint", "SetFrameStrata", "SetMovable", "SetClampedToScreen",
            "EnableMouse", "RegisterForDrag", "SetBackdrop", "SetText", "SetJustifyH", "Enable", "Disable",
            "StartMoving", "StopMovingOrSizing", "SetShown", "SetHeight", "SetWidth"}) do f[key] = noop end
        frames[#frames + 1] = f
        return f
    end
    env.UIParent = frame()
    env.CreateFrame = function(_, _, parent) local f = frame(); f.parent = parent; return f end
    env.GetTime = function() return now end
    env.GetBuildInfo = function() return "3.3.5", "", "", 30300 end
    env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
    env.UISpecialFrames = {}
    env.FauxScrollFrame_GetOffset = function(f) return f.offset or 0 end
    env.FauxScrollFrame_SetOffset = function(f, n) f.offset = n end
    env.FauxScrollFrame_Update = noop
    env.FauxScrollFrame_OnVerticalScroll = function(f, n, _, fn) f.offset = n; fn() end
    local addon = {services = {Register = noop}, locale = {Get = function(s) return s end},
        settings = {profile = {}}, itemUpgrades = {AH = {}}}
    env.addon = addon
    local function load(text) return setfenv(assert(loadstring(text)), env) end
    load(read("Compat/TimerFacade335.lua"))("RXPGuides", addon)
    load(read("Core/Scheduler.lua"))("RXPGuides", addon)
    local scheduled = 0
    local newTimer = addon.timer.NewTimer
    addon.timer.NewTimer = function(...) scheduled = scheduled + 1; return newTimer(...) end
    local function tick()
        now = now + 1
        for _, f in ipairs(frames) do
            if f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, 1) end
        end
    end

    local menus, catalogues, reports = 0, 0, 0
    local gold = {Refresh = function() reports = reports + 1 end}
    env.gold, env.RXPCData = gold, {GA = false}
    addon.RXPFrame = {GenerateMenuTable = function() menus = menus + 1 end}
    addon.guideHub = {Refresh = function() catalogues = catalogues + 1 end}
    local goldText = read("Features/GoldAssistant.lua")
    local goldStart = assert(goldText:find("function gold:ProfessionsChanged(", 1, true))
    load(goldText:sub(goldStart))()
    for i = 1, 100 do gold:ProfessionsChanged("SKILL_LINES_CHANGED") end
    assert(scheduled == 1); tick()
    assert(menus == 0 and catalogues == 0 and reports == 1)
    env.RXPCData.GA = true
    for i = 1, 100 do gold:ProfessionsChanged("SKILL_LINES_CHANGED") end
    tick(); assert(menus == 1 and catalogues == 1)
    gold:ProfessionsChanged("SKILL_LINES_CHANGED"); env.RXPCData.GA = false
    tick(); assert(menus == 1, "execution rechecks Gold Assistant mode")
    gold:ProfessionsChanged("PLAYER_LEVEL_UP")
    assert(menus == 2 and catalogues == 2, "level-up refresh survives in normal mode")
    gold:ProfessionsChanged("SKILL_LINES_CHANGED"); env.RXPCData.GA = true
    tick(); assert(menus == 3, "entering farming mode before delivery retains eligibility")

    local refreshes, overlays, junk, upgrades = 0, 0, 0, 0
    local advisorInvalidations = 0
    addon.gearAdvisor = {Refresh = function() advisorInvalidations = advisorInvalidations + 1 end}
    env.session = {promptedUpgrades = {}, itemCache = {stale = true}}
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end end
    env.RefreshWeaponProficiencies = function() refreshes = refreshes + 1 end
    env.InvalidateUpgradeDetailTooltip = noop
    env.QueueUpgradeScan = function() upgrades = upgrades + 1 end
    addon.itemUpgrades.UpdateSlotMap = noop
    addon.inventoryManager = {UpdateAllBags = function() overlays = overlays + 1 end}
    addon.SendEvent = function() junk = junk + 1 end
    load(section("Features/ItemUpgrades.lua", "function addon.itemUpgrades:WEAPON_PROFICIENCY_CHANGED()",
        "function addon.itemUpgrades:LoadStatWeights()"))()
    env.UIParent:Hide()
    for _, event in ipairs({"SKILL_LINES_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "TRAINER_CLOSED"}) do
        addon.itemUpgrades:WEAPON_PROFICIENCY_CHANGED(event)
    end
    assert(addon.scheduler:Has(addon.itemUpgrades, "proficiencies")); tick(); assert(refreshes == 0)
    env.UIParent:Show(); tick()
    assert(refreshes == 1 and overlays == 1 and junk == 1 and upgrades == 0)
    assert(advisorInvalidations == 1, "settled capability changes invalidate advisor comparisons even with prompts off")
    assert(not next(env.session.itemCache) and not addon.scheduler:Has(addon.itemUpgrades, "proficiencies"))
    addon.settings.profile.enableItemUpgrades = true
    addon.itemUpgrades:WEAPON_PROFICIENCY_CHANGED(); tick()
    assert(refreshes == 2 and upgrades == 1, "separate skill-ups must still invalidate")
    assert(advisorInvalidations == 2)

    local comparisons, scans, equips, clicks = 0, 0, 0, 0
    env.UnitLevel = function() return 10 end
    env.BACKPACK_CONTAINER, env.NUM_BAG_SLOTS = 0, 0
    env.GetContainerNumSlots = function() scans = scans + 1; return 2 end
    local bagLink, rewardLink = "item:1", "item:2"
    env.GetContainerItemLink = function() return bagLink end
    env.GetItemInfo = function(link) return link, link, 1, 1, 1, "Armor", "Mail", 1, "INVTYPE_WRIST" end
    env.GetNumQuestChoices = function() return 1 end
    env.GetQuestItemLink = function() return rewardLink end
    addon.itemUpgrades.GetActiveSpecSource = function() return "Arms", "default" end
    addon.itemUpgrades.GetBestUpgradeComparison = function() comparisons = comparisons + 1; return {SlotCompared = 9}, "upgrade" end
    addon.itemUpgrades.GetComparisonIncrease = function() return 1 end
    addon.itemUpgrades.EquipBagUpgrade = function(_, entry) equips = equips + 1; assert(entry.itemLink == "item:1") end
    env.QuestInfo_GetRewardButton = function() return {IsShown = function() return true end, Click = function() clicks = clicks + 1 end} end
    load(read("Features/GearAdvisor.lua"))("RXPGuides", addon)
    local advisor = addon.gearAdvisor; advisor:Setup()
    assert(advisor.eventFrame.events.PLAYER_LEVEL_UP, "level-gated entries are invalidated")
    local before = scheduled
    for i = 1, 100 do advisor.eventFrame.scripts.OnEvent() end
    assert(scheduled == before and scans == 0, "hidden events schedule no work")
    assert(advisor.dataDirty)
    advisor.frame:Show(); assert(scans == 1 and comparisons == 2)
    assert(not advisor.dataDirty)
    for i = 1, 100 do advisor.eventFrame.scripts.OnEvent() end
    assert(scheduled == before + 1); tick(); assert(scans == 2 and comparisons == 4)
    for i = 1, 100 do advisor.frame.scroll.scripts.OnVerticalScroll(advisor.frame.scroll, 0) end
    assert(scans == 2 and comparisons == 4, "scrolling paints without comparisons")
    advisor:RequestRefresh(); advisor:Refresh(); tick(); assert(scans == 3, "explicit refresh supersedes events")
    advisor:RequestRefresh(); advisor.frame:Hide(); tick(); assert(scans == 3)
    bagLink = "item:3"; advisor.frame:Show(); assert(scans == 4 and advisor.entries[1].link == bagLink)
    advisor:SetView("rewards"); assert(scans == 4 and comparisons == 9)
    local oldReward = advisor.entries[1]; rewardLink = "item:4"
    advisor:Equip(oldReward); assert(clicks == 0, "stale choice cannot select another reward")
    advisor:Equip(advisor.entries[1]); assert(clicks == 1)
    advisor.frame:Hide(); tick()
    local getItemInfo = env.GetItemInfo
    env.GetItemInfo = function() end
    advisor:SetView("bags"); advisor.frame:Show()
    assert(#advisor.entries == 0, "uncached equipment is not guessed")
    env.GetItemInfo = getItemInfo
    advisor.eventFrame.scripts.OnEvent(advisor.eventFrame, "GET_ITEM_INFO_RECEIVED")
    tick(); assert(#advisor.entries == 2, "delayed item data repopulates the current view")
    addon.itemUpgrades.AH.GetAdvisorResults = function() return {} end
    advisor:SetView("auction")
    local oldScans = scans
    advisor.frame.scroll.scripts.OnVerticalScroll(advisor.frame.scroll, 0)
    assert(scans == oldScans and #advisor.entries == 0, "auction view never scans bags")
    advisor.frame:Hide()

    env.ahSession = {scanData = {["item:9"] = {itemID = 9, lowestPrice = 1}}, itemRetries = 0, scanSerial = 1}
    env.session.equippableSlots = {INVTYPE_WRIST = true}
    env.C_Timer = addon.timer
    local requests, ready = 0, false
    addon.itemUpgrades.GetItemData = function(_, link)
        requests = requests + 1; assert(link == "item:9")
        if ready then return {totalWeight = 2, itemEquipLoc = "INVTYPE_WRIST"} end
    end
    env.GetComparisonIncrease = function() return 1 end
    addon.itemUpgrades.AH.DisplayEmbeddedResults = noop
    load(section("Features/ItemUpgrades.lua", "function addon.itemUpgrades.AH:Setup()",
        "function addon.itemUpgrades.AH:AUCTION_HOUSE_SHOW()"))()
    local events = {}
    addon.itemUpgrades.AH.RegisterEvent = function(_, event) events[event] = true end
    addon.settings.profile.enableTips, addon.settings.profile.enableItemUpgradesAH = true, true
    addon.itemUpgrades.AH:Setup()
    assert(not events.GET_ITEM_INFO_RECEIVED and not addon.itemUpgrades.AH.GET_ITEM_INFO_RECEIVED)
    assert(not read("Features/ItemUpgrades.lua"):find("infoItemsReceived", 1, true))
    for i = 1, 500 do
        if events.GET_ITEM_INFO_RECEIVED then addon.itemUpgrades.AH:GET_ITEM_INFO_RECEIVED(nil, i, true) end
    end
    assert(requests == 0, "unrelated item responses do no AH prefetching")
    load(section("Features/ItemUpgrades.lua", "local function calculate(itemLink, scanData)",
        "function addon.itemUpgrades.AH:GetAdvisorResults()"))()
    addon.itemUpgrades.AH:Analyze(); assert(requests == 1)
    ready = true; tick(); assert(requests == 2 and env.ahSession.scanData["item:9"].state == "upgrade")
    ready = false; env.ahSession.itemRetries = 0
    addon.itemUpgrades.AH:Analyze()
    for i = 1, 12 do tick() end
    assert(env.ahSession.itemRetries == 8 and requests == 11, "missing item data retries are bounded")
    env.ahSession.itemRetries = 0; addon.itemUpgrades.AH:Analyze()
    local atCancel = requests; env.ahSession.cancelled = true; tick(); assert(requests == atCancel)
    env.ahSession.cancelled = false; env.ahSession.itemRetries = 0; addon.itemUpgrades.AH:Analyze()
    local atReplace = requests; env.ahSession.scanSerial = 2; tick(); assert(requests == atReplace)

    env.MapPinPool = {}
    addon.GetTexture = function(name) return name end
    addon.colors = {mapPins = {1, 1, 1}}
    env.PinOnEnter, env.PinOnLeave = noop, noop
    local createFrame = env.CreateFrame
    env.CreateFrame = function(...)
        local f = createFrame(...)
        f.SetMouseClickEnabled, f.SetScale, f.SetAlpha, f.SetBackdropColor = noop, noop, noop, noop
        f.CreateFontString = function()
            local text = frame()
            text.SetTextColor, text.SetFont = noop, noop
            text.GetTextColor = function() return 1, 1, 1 end
            text.GetStringWidth, text.GetStringHeight = function() return 10 end, function() return 10 end
            text.SetText = function(self, value) self.value = value end
            return text
        end
        return f
    end
    load(section("UI/Map.lua", "MapPinPool.creationFunc = function", "MapLinePool.create = function"))()
    load(section("UI/Map.lua", "MapPinPool.resetterFunc = function", "MapLinePool.create = function"))()
    local pin = env.MapPinPool.creationFunc()
    local weak = setmetatable({}, {__mode = "v"})
    pin:render({elements = {{step = {index = 1}}}}, false); weak[1] = pin.activeObject
    env.MapPinPool.resetterFunc(nil, pin)
    collectgarbage("collect") -- test process only; never added to the addon
    assert(not weak[1] and not pin.activeObject and not pin.currentPin)
    local nextDescriptor = {elements = {{step = {index = 2}}}}
    pin:render(nextDescriptor, true)
    assert(pin.activeObject == nextDescriptor and pin.text.value == 2, "reused minimap pin displays new descriptor")
    assert(#errors == 0, table.concat(errors, "\n"))
    print("Refresh performance: catalogue/inventory scheduling, AH retries and pin retention passed.")
end
