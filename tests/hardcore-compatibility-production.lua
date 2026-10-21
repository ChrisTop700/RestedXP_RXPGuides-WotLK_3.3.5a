-- Production handlers with explicit 3.3.5 client API fixtures; no imitation of
-- directive completion or coordinate parsing.
return function(root)
    local function read(path)
        local file = assert(io.open(root .. "/" .. path, "rb"))
        local text = file:read("*a"); file:close()
        return text
    end
    local factory = assert(loadfile(root .. "/tests/quest-automation-audit.lua"))
    setfenv(factory, setmetatable({arg = {root, "--fixtures"}}, {__index = _G}))
    local fixture = factory()
    local s = fixture()
    s:loadDirectives()
    local a = s.addon
    local normalizedCalls = 0
    local hbd = {
        GetWorldCoordinatesFromZone = function(_, x, y, zone)
            assert(x >= 0 and x <= 1 and y >= 0 and y <= 1,
                "World yards reached the legacy normalized API")
            normalizedCalls = normalizedCalls + 1
            return x, y, zone
        end,
        GetZoneCoordinatesFromWorld = function(_, x, y)
            assert(x >= 0 and x <= 1 and y >= 0 and y <= 1,
                "World yards reached the legacy normalized API")
            return x, y
        end,
    }
    s.env.LibStub = function() return hbd end
    s.load("Guide/Directives/Handlers.lua")
    a.mapConversion = {}
    a.currentGuideName = "Hardcore coordinate fixture"
    a.error = error
    a.mapId = {["Kalimdor"] = 1414, ["Eastern Kingdoms"] = 1415,
        ["Azuremyst Isle"] = 1943, ["Stormwind City"] = 1453,
        ["Eastern Plaguelands"] = 1423}
    local source = read("UI/Map.lua")
    local first = assert(source:find("local function GetMapCoefficients", 1, true))
    local lastText = 'addon.mapId["EPLNew"] = addon.mapId["Eastern Plaguelands"]'
    local last = assert(source:find(lastText, first, true)) + #lastText - 1
    local adapter = assert(loadstring(source:sub(first, last)))
    setfenv(adapter, setmetatable({addon = a}, {__index = _G})); adapter()
    for _, tag in ipairs({"goto", "waypoint", "groundgoto", "flygoto"}) do
        local e = a.functions[tag]("." .. tag, "Keep display", "Azuremyst Isle",
            "79.5", "51.7", "40", "0")
        assert(e.zone == 1943 and e.x == 79.5 and e.y == 51.7 and e.radius == 40)
        assert(e.wx == 0.795 and e.wy == 0.517 and not e.fixedMapID,
            "Converted point used the unsupported source world-coordinate branch")
    end
    assert(normalizedCalls == 4)
    local ok = pcall(a.functions["goto"], ".goto", "", "1414/1", "-400", "-175", "40", "0")
    assert(not ok, "Fixture failed to reproduce original world-coordinate misuse")
    local id, x, y = a.GetMapInfo("StormwindClassic", 25, 25)
    assert(id == 1453 and math.abs(x - 39.02232393772481) < 1e-10)
    assert(math.abs(y - 43.7789069363158) < 1e-10)
    id, x, y = a.GetMapInfo("Stormwind City", 79.989, 38.468)
    assert(id == 1453 and x == 79.989 and y == 38.468,
        "Already-Wrath coordinates were transformed twice")

    local checks = 0
    for _, spell in ipairs({33388, 688, 348, 172}) do
        for flags = 0, 3 do
            for _, knowledge in ipairs({"absent", "player", "pet"}) do
                local f = fixture()
                f.env.GetSpellSubtext = function() return "" end
                f.env.IsPlayerSpell = function() return knowledge == "player" end
                f.env.IsSpellKnown = function(_, pet) return pet and knowledge == "pet" end
                f.load("Core/Addon.lua")
                f:loadDirectives()
                f.env.C_Spell = {IsSpellDataCached = function() return true end,
                    RequestLoadSpellData = function() error("Unexpected spell request") end}
                f.env.GetSpellInfo = function() return "Fixture spell", "", nil, nil, nil, nil, spell end
                f.addon.player.season = 0
                f.addon.skillList = {}
                f.addon.SetElementComplete = function(frame) frame.element.completed = true end
                local element = f.addon.functions.train(".train", "", tostring(spell), tostring(flags))
                element.step = {active = true}
                f.addon.functions.train({element = element})
                local fulfilled = (knowledge ~= "absent") ~= (flags >= 2)
                assert(not not element.step.completed == (flags % 2 == 1 and fulfilled))
                assert(not not element.completed == (flags % 2 == 0 and fulfilled))
                assert(#f.calls == 0, "Training check invoked an automatic quest action")
                checks = checks + 1
            end
        end
    end
    for _, class in ipairs({"HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "WARLOCK"}) do
        local f = fixture()
        f.env.UnitClass = function() return class, class end
        f.env.UnitRace = function() return "Blood Elf", "BloodElf" end
        f.env.GetNumQuestLogEntries = function() return 1 end
        f.env.ExpandQuestHeader = function() end
        f.env.RXPCompatGetQuestLogTitle = function()
            return "Thirst Unending", 3, nil, false, false, false, nil, 8346
        end
        f.env.GetNumQuestLeaderBoards = function() return 1 end
        f.env.GetQuestLogLeaderBoard = function()
            return "Arcane Torrent used: " .. (f.credit or 0) .. "/1", "monster", f.credit == 1
        end
        f.env.GetInventoryItemID = function() end
        f.env.INVSLOT_LAST_EQUIPPED = 19
        f:loadDirectives()
        f.env.bit.rshift = function(n, bits) return math.floor(n / 2^bits) end
        f.load("Guide/Directives/Handlers.lua")
        f.load("Guide/State.lua")
        local q = f.addon
        q.lastStepUpdate, q.questCompleteItems = f.now, {}
        q.UpdateStepText, q.QueueMessage = function() end, function() end
        q.comms.AnnounceStepEvent = function() end
        q.GetQuestName = function() return "Thirst Unending" end
        f.env.RXPCData.questObjectivesCache = {[0] = 0}
        f.env.RXPCData.stepSkip, f.env.RXPCData.completedWaypoints = {}, {}
        f.log[8346] = true
        local e = f:element("complete", 8346, "Thirst Unending")
        e.flags, e.obj = 0, 1
        local frame = {element = e, step = f.step}
        q.UpdateQuestCompletionData(frame)
        assert(not e.completed, "Racial objective completed without live credit")
        f.credit = 1
        q.UpdateQuestCompletionData(frame)
        assert(e.completed, class .. ": one live Arcane Torrent credit did not complete the objective")
        assert(#f.calls == 0, "Objective check performed an automatic quest action")
    end
    print("Hardcore production compatibility passed: four map handlers, legacy map adapter, " ..
        checks .. " learned-spell cases and six one-credit racial objectives.")
end
