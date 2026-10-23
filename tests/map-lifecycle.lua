-- Production route generators, refresh coordinator, scheduler and HBD registry.
-- Only client frames/placement and unrelated arrow drawing are simulated.
return function(root)
    local function read(path)
        local file = assert(io.open(root .. "/" .. path, "rb"))
        local text = file:read("*a"):gsub("\r\n", "\n")
        file:close()
        return text
    end
    local env = setmetatable({}, {__index = _G})
    env._G = env
    local frames, counts, labels = {}, {}, {}
    local function count(name) counts[name] = (counts[name] or 0) + 1 end
    local function flush()
        local batch = {}
        for _, frame in ipairs(frames) do
            if frame.scripts.OnUpdate and frame:IsVisible() then
                batch[#batch + 1] = {frame, frame.scripts.OnUpdate}
            end
        end
        for _, entry in ipairs(batch) do
            if entry[1]:IsVisible() and entry[1].scripts.OnUpdate == entry[2] then
                entry[2](entry[1], 0.016)
            end
        end
    end
    local addon = {settings = {profile = {numMapPins = 5}},
        services = {Register = function() end}, RXPFrame = {activeSteps = {}}}
    env.addon = addon
    env.UIParent = {shown = true, IsVisible = function(self) return self.shown end}
    env.GetBuildInfo = function() return "3.3.5", "", "", 30300 end
    env.GetTime = function() return 100 end
    env.geterrorhandler = function() return error end
    env.RXPCData = {currentStep = 1, completedWaypoints = {}}
    env.event = "test"
    env.hooksecurefunc = function(object, method, callback)
        local original = assert(object[method], method)
        object[method] = function(...)
            original(...)
            callback(...)
        end
    end
    env.IsInInstance = function() return false end
    local map
    local canvas = {width = 800, height = 600, scale = 1, strata = "HIGH", level = 5, hooks = {}}
    function canvas:GetWidth() return self.width end
    function canvas:GetHeight() return self.height end
    function canvas:GetFrameStrata() return self.strata end
    function canvas:GetFrameLevel() return self.level end
    function canvas:GetEffectiveScale() return self.scale * map.scale end
    function canvas:HookScript(event, callback) self.hooks[event] = callback end
    function canvas:SetSize(width, height)
        self.width, self.height = width, height
        if self.hooks.OnSizeChanged then self.hooks.OnSizeChanged(self, width, height) end
    end
    function canvas:SetFrameStrata(value) self.strata = value end
    function canvas:SetFrameLevel(value) self.level = value end
    function canvas:SetScale(value) self.scale = value end
    map = {shown = false, zone = 1, scale = 1, hooks = {}}
    function map:SetScale(value) self.scale = value end
    function map:OnMapChanged() end
    function map:IsShown() return self.shown end
    function map:IsVisible() return self.shown end
    function map:GetMapID() return self.zone end
    function map:GetCanvas() return canvas end
    function map:HookScript(event, callback) self.hooks[event] = callback end
    function map:SetShown(value)
        self.shown = value
        local callback = self.hooks[value and "OnShow" or "OnHide"]
        if callback then callback(self) end
    end
    env.WorldMapFrame, env.WorldMapDetailFrame = map, canvas
    env.CreateFrame = function(_, _, parent)
        local frame = {events = {}, scripts = {}, parent = parent, shown = true}
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:IsVisible()
            return self.shown and (not self.parent or self.parent:IsVisible())
        end
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:SetScript(event, callback) self.scripts[event] = callback end
        frames[#frames + 1] = frame
        return frame
    end
    local function load(text) return setfenv(assert(loadstring(text)), env) end
    local function section(text, first, last)
        local start = assert(text:find(first, 1, true), first)
        return text:sub(start, assert(text:find(last, start, true), last) - 1)
    end
    load(read("Compat/TimerFacade335.lua"))("RXPGuides", addon)
    -- The extracted HBD section normally captures addon.timer in its prelude,
    -- not a global C_Timer potentially owned by another addon/test.
    env.C_Timer = addon.timer
    local newTimer = addon.timer.NewTimer
    addon.timer.NewTimer = function(...)
        count("scheduled")
        return newTimer(...)
    end
    load(read("Core/Scheduler.lua"))("RXPGuides", addon)
    local pins = {}
    env.LibStub = {NewLibrary = function() return pins end}
    env.resolve = function(zone) return 1, zone end
    env.Astrolabe = {
        PlaceIconOnWorldMap = function(_, _, icon, _, zone)
            count("placements")
            icon.placedWidth, icon.placedHeight = canvas.width, canvas.height
            icon.placedScale = canvas:GetEffectiveScale()
            icon:SetShown(zone == map.zone)
            return zone == map.zone and 0.5 or nil
        end,
        PlaceIconOnMinimap = function(_, icon) icon:Show() end,
        RemoveIconFromMinimap = function(_, icon) icon:Hide() end,
    }
    local bridge = read("libs/HBD335/HereBeDragons-335.lua")
    local bridgeStart = assert(bridge:find("_G.HBD_PINS_WORLDMAP_SHOW_WORLD", 1, true))
    load(bridge:sub(bridgeStart))()
    env.HBDPins = pins
    env.HBD = {GetWorldCoordinatesFromZone = function(_, x, y) return x, y, 1 end}
    env.GetPinHash = function(x, y) return tostring(x) .. ":" .. tostring(y) end
    env.elementIsCloseToOtherPins = function() return false end
    addon.GetSubZones = function() end
    addon.ProcessGeneratedSteps = function() end
    addon.guideState = {RestoreWaypoint = function() count("restore") end}
    local function pool(kind)
        local pool = {active = {}, inactive = {}}
        function pool:ReleaseAll()
            for _, frame in ipairs(self.active) do
                frame:Hide()
                self.inactive[#self.inactive + 1] = frame
            end
            self.active = {}
        end
        function pool:Acquire()
            local frame = table.remove(self.inactive)
            if not frame then
                frame = {}
                count(kind .. " created")
                function frame:Show() self.shown = true end
                function frame:Hide() self.shown = false end
                function frame:SetShown(value) self.shown = not not value end
                function frame:SetParent(parent) self.parent = parent end
                function frame:SetFrameStrata(value) self.strata = value end
                function frame:SetFrameLevel(value) self.level = value end
                function frame:render(data)
                    self.data = data
                    self.pendingLineRender = canvas.width <= 0 or canvas.height <= 0
                    self.renderWidth, self.renderHeight = canvas.width, canvas.height
                    count(kind .. " renders")
                end
            end
            self.active[#self.active + 1] = frame
            return frame
        end
        function pool:EnumerateActive()
            local i = 0
            return function() i = i + 1; return self.active[i] end
        end
        return pool
    end
    env.worldMapFramePool, env.miniMapFramePool, env.lineMapFramePool = pool("world"), pool("mini"), pool("line")
    env.updateArrowData = function() count("arrow") end
    addon.PerfInvoke = function(label, callback, ...)
        labels[label] = (labels[label] or 0) + 1
        return callback(...)
    end
    addon.PerfCount = function(label, amount) counts[label] = (counts[label] or 0) + (amount or 1) end
    local source = read("UI/Map.lua")
    local generators = section(source, "local function generatePins(", "local corpseWP =")
    local coordinator = section(source, "local function resetMap()", "\nlocal scale = 0")
    load(generators .. "\n" .. coordinator)()
    addon.tickers = {ShouldContinue = function() return true end}
    load(section(read("Core/Addon.lua"), "function addon.tickers.CycleThree()", "\nfunction addon.tickers.CycleFour()"))()
    local function guide(name)
        local step = {index = 1, active = true, elements = {}}
        step.elements = {
            {step = step, zone = 1, x = 50, y = 50, wx = 0.5, wy = 0.5, text = name},
            {step = step, zone = 1, x = 60, y = 60, wx = 0.6, wy = 0.6, wpHash = "done"},
            {step = step, zone = 1, segments = {40, 40, 45, 45}, lineAlpha = 1,
                showArrow = true, drawCenterPoint = true},
        }
        return {name = name, steps = {step}}
    end
    local function selectGuide(value)
        addon.currentGuide = value
        addon.RXPFrame.activeSteps = value and {value.steps[1]} or {}
        env.RXPCData.completedWaypoints = {[1] = {done = true}}
    end
    local function size(set) local n = 0; for _ in pairs(set or {}) do n = n + 1 end; return n end
    local function registered(kind) return size(pins[kind][addon]) end
    local function mapEvent()
        for _, frame in ipairs(frames) do
            if frame.events.WORLD_MAP_UPDATE then frame.scripts.OnEvent(frame, "WORLD_MAP_UPDATE") end
        end
    end
    local firstGuide, secondGuide = guide("first"), guide("second")
    -- Initial opening with an outstanding route request consumes it once.
    selectGuide(firstGuide)
    addon.UpdateMap(); map:SetShown(true); flush()
    assert(registered("_worldPins") == 2 and not addon.updateMap)
    map:SetShown(false)
    counts, labels = {}, {}
    selectGuide(firstGuide)
    addon.UpdateMap()
    assert(addon.updateMap and not counts.arrow, "dirty request rebuilt synchronously")
    addon.tickers.CycleThree()
    assert(not addon.updateMap and registered("_worldPins") == 0)
    -- Preserve the existing minimap filter (including its center pin); world
    -- waypoint-history filtering is intentionally distinct from the minimap.
    assert(registered("_minimapPins") == 3, "closed world map removed minimap pins")
    assert(#addon.activeWaypoints == 3, "line/center/navigation or completed filtering changed")
    local restores, lines, minis, arrows = counts.restore, counts["line renders"], counts["mini renders"], counts.arrow
    local scheduled = counts.scheduled or 0
    for _ = 1, 20 do mapEvent() end
    flush()
    assert((counts.scheduled or 0) == scheduled, "closed-map events queued guide presentation work")
    map:SetShown(true)
    for _ = 1, 20 do mapEvent() end
    assert(counts.scheduled == scheduled + 1, "map event burst allocated duplicate guide callbacks")
    flush()
    assert(registered("_worldPins") == 2, "opening failed to materialize cached pins")
    assert(counts.restore == restores and counts["line renders"] == lines and counts["mini renders"] == minis and counts.arrow == arrows,
        "opening repeated route or minimap work")
    local worldRenders = counts["world renders"]
    for _ = 1, 5 do map:SetShown(false); map:SetShown(true); mapEvent(); flush() end
    assert(counts["world renders"] == worldRenders and counts.restore == restores, "unchanged reopen rebuilt pins")
    map.zone = 2; mapEvent(); flush()
    for icon in pairs(pins._worldPins[addon]) do assert(not icon.shown) end
    assert(not env.lineMapFramePool.active[1].shown)
    map.zone = 1; mapEvent(); flush()
    for icon in pairs(pins._worldPins[addon]) do assert(icon.shown) end
    assert(env.lineMapFramePool.active[1].shown)
    canvas.width = 900; mapEvent(); flush()
    assert(counts["line renders"] == lines + 1 and counts.restore == restores, "resize regenerated the route")
    -- Maximize/minimize can change geometry and explicit frame layers without
    -- hiding the map or emitting WORLD_MAP_UPDATE. Registered frames must move.
    scheduled = counts.scheduled
    local beforePlacements, beforeWorld = counts.placements, counts["world renders"]
    canvas:SetSize(1400, 900)
    canvas:SetFrameStrata("FULLSCREEN")
    canvas:SetFrameLevel(20)
    map:SetScale(1.4)
    assert(counts.scheduled == scheduled + 1, "layout-only maximize did not coalesce a refresh")
    flush()
    assert(counts.placements == beforePlacements + 2, "maximize did not reposition the existing guide pins once")
    for icon in pairs(pins._worldPins[addon]) do
        assert(icon.placedWidth == 1400 and icon.placedHeight == 900 and icon.placedScale == 1.4)
        assert(icon.strata == "FULLSCREEN" and icon.level == 25, "pins remained under the enlarged map")
    end
    assert(counts["world renders"] == beforeWorld and counts.restore == restores and
        counts["mini renders"] == minis and counts.arrow == arrows, "maximize rebuilt route or pin frames")
    assert(env.lineMapFramePool.active[1].strata == "FULLSCREEN", "route line kept its old layer")
    -- Fullscreen can hide UIParent while the separate WorldMapFrame stays
    -- visible. The production timer driver inherits UIParent's visibility.
    map:SetShown(false); map.zone = 2; mapEvent(); flush()
    map.zone = 1; env.UIParent.shown = false
    beforePlacements = counts.placements
    map:SetShown(true); flush()
    assert(counts.placements == beforePlacements + 2,
        "fullscreen reopening stalled with the UIParent-owned timer driver hidden")
    for icon in pairs(pins._worldPins[addon]) do assert(icon.shown) end
    env.UIParent.shown = true; flush()
    assert(counts.placements == beforePlacements + 2, "resuming UIParent duplicated map presentation")
    -- UIParent may be hidden after OnShow queues the normal timer. Also check
    -- map events while that timer (including HBD's refresh) cannot dispatch.
    map:SetShown(false); map:SetShown(true); env.UIParent.shown = false; flush()
    map.zone = 2; mapEvent(); flush()
    for icon in pairs(pins._worldPins[addon]) do assert(not icon.shown) end
    map.zone = 1; mapEvent(); flush()
    for icon in pairs(pins._worldPins[addon]) do assert(icon.shown) end
    beforePlacements = counts.placements
    flush(); flush()
    assert(counts.placements == beforePlacements, "fullscreen fallback kept polling")
    for _, frame in ipairs(frames) do
        if frame.parent == map then assert(not frame.scripts.OnUpdate, "map fallback was not disarmed") end
    end
    map:SetShown(false); map:SetShown(true); map:SetShown(false); flush()
    assert(counts.placements == beforePlacements, "cancelled fullscreen opening placed pins")
    env.UIParent.shown = true; flush()
    map:SetShown(true); flush()
    -- A map update while closed can hide registered icons against a transient
    -- view. Reopening an already maximized canvas need not emit another update
    -- or resize; placement must be revalidated even though geometry is cached.
    map:SetShown(false); map.zone = 2; mapEvent(); flush()
    for icon in pairs(pins._worldPins[addon]) do assert(not icon.shown) end
    map.zone = 1
    beforePlacements, scheduled = counts.placements, counts.scheduled
    map:SetShown(true); flush()
    assert(counts.scheduled == scheduled + 1 and counts.placements == beforePlacements + 2,
        "maximized reopen did not revalidate registered pin placement once")
    for icon in pairs(pins._worldPins[addon]) do
        assert(icon.shown and icon.strata == "FULLSCREEN", "maximized reopen retained hidden pins")
    end
    assert(counts["world renders"] == beforeWorld and counts.restore == restores and
        counts["mini renders"] == minis and counts.arrow == arrows,
        "maximized reopen rebuilt route or pin frames")
    -- Revalidation is not a blind Show: off-zone pins must stay hidden.
    map:SetShown(false); map.zone = 2; map:SetShown(true); flush()
    for icon in pairs(pins._worldPins[addon]) do assert(not icon.shown) end
    map:SetShown(false); map.zone = 1; map:SetShown(true); flush()
    for icon in pairs(pins._worldPins[addon]) do assert(icon.shown) end
    beforePlacements = counts.placements
    canvas:SetFrameStrata("FULLSCREEN"); map:SetScale(1.4); flush()
    assert(counts.placements == beforePlacements, "unchanged layout repeated placement")
    canvas:SetSize(900, 600); canvas:SetFrameStrata("HIGH"); canvas:SetFrameLevel(5); map:SetScale(1); flush()
    for icon in pairs(pins._worldPins[addon]) do
        assert(icon.placedWidth == 900 and icon.placedScale == 1 and icon.strata == "HIGH" and icon.level == 10)
    end
    local lineRenders = counts["line renders"]
    canvas:SetFrameStrata("FULLSCREEN"); flush()
    assert(counts["line renders"] == lineRenders and env.lineMapFramePool.active[1].strata == "FULLSCREEN",
        "layer-only change retessellated route lines or kept old strata")
    canvas:SetFrameStrata("HIGH"); flush()
    -- Another map owner (vendor/Questie-style overlays) must not be refreshed.
    local foreignOwner, foreignIcon = {}, env.worldMapFramePool:Acquire()
    pins:AddWorldMapIconMap(foreignOwner, foreignIcon, 1, 0.5, 0.5)
    beforePlacements = counts.placements
    map:SetScale(1.2); flush()
    assert(counts.placements == beforePlacements + 2 and foreignIcon.placedScale == 1,
        "layout refresh touched foreign pin owners")
    pins:RemoveWorldMapIcon(foreignOwner, foreignIcon)
    map:SetScale(1); flush()
    mapEvent(); addon.UpdateMap(true)
    worldRenders = counts["world renders"]
    flush(); assert(counts["world renders"] == worldRenders, "cancelled callback rendered twice")
    addon.UpdateMap(); mapEvent(); flush()
    restores, minis = counts.restore, counts["mini renders"]
    addon.tickers.CycleThree()
    assert(not addon.updateMap and counts.restore == restores and counts["mini renders"] == minis)

    map:SetShown(false); selectGuide(secondGuide); addon.UpdateMap(true)
    map:SetShown(true); map:SetShown(false); flush()
    assert(registered("_worldPins") == 0, "closed callback rendered pending artwork")
    map:SetShown(true); flush()
    for icon in pairs(pins._worldPins[addon]) do assert(icon.data.elements[1].step == secondGuide.steps[1]) end
    mapEvent(); selectGuide(firstGuide); flush()
    assert(registered("_worldPins") == 2)
    for icon in pairs(pins._worldPins[addon]) do assert(icon.data.elements[1].step == firstGuide.steps[1]) end

    local later = guide("later").steps[1]
    later.index = 2
    firstGuide.steps[2] = later
    firstGuide.steps[1].active = false
    env.RXPCData.currentStep = 2
    env.RXPCData.completedWaypoints[2] = {done = true}
    addon.RXPFrame.activeSteps = {later}
    addon.UpdateMap(); mapEvent(); flush()
    assert(registered("_worldPins") == 2)
    for icon in pairs(pins._worldPins[addon]) do assert(icon.data.elements[1].step == later) end
    env.RXPCData.currentStep = 1
    firstGuide.steps[2], firstGuide.steps[1].active = nil, true
    selectGuide(firstGuide)

    map:SetShown(false); addon.UpdateMap(true)
    canvas.width = 0; map:SetShown(true); flush()
    assert(registered("_worldPins") == 0, "registered against an unavailable canvas")
    canvas.width = 800; mapEvent(); flush()
    assert(registered("_worldPins") == 2)

    addon.settings.profile.numMapPins = 0; addon.UpdateMap(true)
    assert(registered("_worldPins") == 0 and #addon.activeWaypoints == 3, "zero artwork disabled navigation")
    addon.settings.profile.hideMiniMapPins = true; addon.UpdateMap(true)
    assert(registered("_minimapPins") == 0)
    addon.settings.profile.numMapPins, addon.settings.profile.hideMiniMapPins = 5, false
    selectGuide({empty = true, steps = {}}); addon.UpdateMap(true)
    assert(registered("_worldPins") == 0 and #addon.activeWaypoints == 0)
    selectGuide(secondGuide); addon.UpdateMap(true)
    mapEvent(); selectGuide(nil); flush()
    assert(registered("_worldPins") == 0 and registered("_minimapPins") == 0 and #addon.activeWaypoints == 0,
        "cleared guide retained old registrations")
    selectGuide(firstGuide); addon.PerfInvoke, addon.PerfCount = nil, nil
    addon.UpdateMap(true)
    assert(registered("_worldPins") == 2, "map behavior depends on capture instrumentation")
    assert(labels["map world pins"] and labels["map minimap pins"] and labels["map lines"])
    print("Map lifecycle passed: closed navigation/minimap, cached opening, coalescing, stale work, filters, resizing and registry reuse.")
end
