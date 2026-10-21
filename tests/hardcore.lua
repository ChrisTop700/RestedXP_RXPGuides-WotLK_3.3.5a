-- Production mode service and deathskip callbacks; no server or character edits.
return function(root)
    local function noop() end
    local addon = {
        gameVersion = 30300, settings = {profile = {hardcore = false}},
        services = {Register = noop}, locale = {Get = function(s) return s end},
        guideState = {CancelAdvance = noop, SaveCurrent = noop},
        questAutomation = {ResetForGuideChange = noop},
        RXPFrame = {GenerateMenuTable = noop},
        IsGuideActive = function(g) return not g.disabled end,
    }
    local confirmation, notice, opened, loaded
    addon.comms = {
        ConfirmChoice = function(_, _, _, callback) confirmation = callback end,
        PopupNotification = function(_, _, text) notice = text end,
    }
    addon.guideHub = {OpenHardcoreGuides = function() opened = true end, CreateFrame = function()
        return {Show = function() opened = true end,
            search = {SetText = function(_, text) assert(text == "RestedXP Hardcore Guides") end}}
    end, Refresh = noop}
    addon.LoadGuide = function(_, guide) loaded = guide; addon.currentGuide = guide end
    assert(loadfile(root .. "/Guide/Hardcore.lua"))("RXPGuides", addon)
    local hc = addon.hardcoreGuides
    local normal = {group = "RestedXP Speedrun Guide (H)"}
    local horde = {group = "RestedXP Hardcore Guides (H)", hardcore = true}
    local alliance = {group = "RestedXP Hardcore Guides (A)", hardcore = true}
    addon.currentGuide = {group = normal.group, softcore = ""}
    assert(not hc:IsToggleLocked(), "explicit softcore guide blocked enabling the picker")
    assert(not hc:SetEnabled(true) and not hc:IsEnabled() and not opened,
        "unreleased routes enabled an empty Hardcore mode")
    addon.guides = {horde}
    assert(hc:SetEnabled(true) and opened and not loaded, "enabling loaded a guide")
    assert(not hc:IsToggleLocked(), "opening picker locked a softcore guide")
    addon.currentGuide = normal
    assert(hc:IsEnabled() and hc:AllowsTransition(horde, horde))
    assert(not hc:AllowsTransition(horde, normal), "Hardcore escaped to a normal route")
    assert(not hc:AllowsTransition(horde, alliance), "Hardcore changed faction")
    assert(hc:AllowsTransition(normal, normal), "normal routes changed")
    assert(hc:AllowsTransition(horde, {group = horde.group, hardcore = ""}),
        "parser's empty-string #hardcore flag was rejected")
    local classic = {group = "Original Guides - RestedXP Hardcore Classic Guides (H)", hardcore = true}
    local tbc = {group = "Original Guides - RestedXP Hardcore TBC Guides (H)", hardcore = true}
    for _, from in ipairs({horde, classic, tbc}) do
        assert(hc:AllowsTransition(from, from))
        for _, to in ipairs({horde, classic, tbc}) do
            assert(hc:AllowsTransition(from, to) == (from == to), "family isolation failed")
        end
        assert(not hc:AllowsTransition(normal, from), "normal route entered experimental family")
    end
    hc:SetEnabled(false)
    assert(not hc:BeforeLoad(horde), "selection silently enabled Hardcore")
    assert(not hc:IsEnabled() and not loaded)
    confirmation()
    assert(hc:IsEnabled() and loaded == horde, "confirmed selection failed")
    assert(hc:IsToggleLocked(), "active Hardcore guide allowed a direct mode toggle")
    assert(not hc:SetEnabled(false) and hc:IsEnabled() and notice, "active route lost its mode")
    local soft = {softcore = true, group = normal.group}
    assert(not hc:BeforeLoad(soft))
    local stale = confirmation
    hc:BeforeLoad(horde) -- a newer selection invalidates an older prompt
    stale()
    assert(hc:IsEnabled() and loaded == horde, "stale confirmation changed mode")
    assert(not hc:BeforeLoad(soft))
    confirmation()
    assert(not hc:IsEnabled() and loaded == soft)
    assert(hc:BeforeLoad(horde, true) and hc:IsEnabled(), "reload lost Hardcore mode")
    hc:Apply(false)
    assert(not hc:BeforeLoad(horde))
    horde.disabled = true
    confirmation()
    assert(not hc:IsEnabled(), "invalidated guide changed mode")

    local factory = assert(loadfile(root .. "/tests/quest-automation-audit.lua"))
    setfenv(factory, setmetatable({arg = {root, "--fixtures"}}, {__index = _G}))
    local fixture = factory()
    do
        -- Pin the offline auditor's guard semantics to the production handlers.
        local s = fixture()
        s:loadDirectives()
        local a = s.addon
        local function skipped(tag, ids, reverse)
            s.step.completed = nil
            local element = {step = s.step, questIds = ids, reverse = reverse}
            a.functions[tag]({element = element}, "QUEST_LOG_UPDATE")
            return not not s.step.completed
        end
        s.turnedIn = {[788] = true}
        assert(skipped("isQuestAvailable", {788}), "rewarded quest remained available")
        assert(not skipped("isQuestAvailable", {804}), "availability invented prerequisites")
        assert(not skipped("isQuestAvailable", {788, 804}), "availability is OR of missing history")
        assert(not skipped("isQuestTurnedIn", {788, 804}, true), "reverse history must negate each ID")
        assert(skipped("isQuestTurnedIn", {804}), "missing turn-in did not skip")
        a.GetQuestLogPresence335 = function(id) if id == 788 then return true end end
        assert(not skipped("isOnQuest", {804, 788}), "unknown masked known active quest")
        assert(skipped("isOnQuest", {804, 788}, true), "inverse known active quest failed")
        assert(not skipped("isOnQuest", {804}), "unknown presence was treated as absent")
        local gate = {step = s.step, questId = 788}
        a.GetQuestObjectives = function() return {}, false, true end
        s.step.completed = nil
        a.functions.isQuestComplete({element = gate}, "QUEST_LOG_UPDATE")
        assert(not s.step.completed, "unavailable live objectives became incomplete")
        a.GetQuestObjectives = function() return {}, true, false end
        a.functions.isQuestComplete({element = gate}, "QUEST_LOG_UPDATE")
        assert(s.step.completed, "live incomplete objective did not skip gated step")
        local function completionSkipped(reverse)
            s.step.completed = nil
            gate.reverse = reverse
            a.functions.isQuestComplete({element = gate}, "QUEST_LOG_UPDATE")
            return not not s.step.completed
        end
        a.GetQuestLogPresence335 = function() return false end
        a.GetQuestObjectives = function() error("absent quest read stale objectives") end
        assert(completionSkipped(false), "settled absence did not skip completion guard")
        assert(not completionSkipped(true), "settled absence skipped inverse completion guard")
        -- 788 remains in the confirmed turn-in history above. That history
        -- cannot turn an absent quest into a ready-to-reward log entry.
        assert(s.turnedIn[788] and completionSkipped(false), "reward history became current readiness")
        a.GetQuestLogPresence335 = function() return nil end
        assert(not completionSkipped(false) and not completionSkipped(true),
            "unknown log presence became a definite completion predicate")
        a.GetQuestLogPresence335 = function() return true end
        a.GetQuestObjectives = function() return {}, false, true end
        assert(not completionSkipped(false) and not completionSkipped(true),
            "delayed objectives became definite readiness")
        a.GetQuestObjectives = function() return {}, true, true end
        assert(not completionSkipped(false) and completionSkipped(true),
            "live ready objectives lost forward/inverse guard semantics")
    end
    do
        local s = fixture()
        local a, data = s.addon, s.env.RXPCData
        s.env.time = function() return 100 end
        s.load("Guide/State.lua")
        s.load("Features/Roadmap.lua")
        s.load("Guide/Hardcore.lua")
        local prompt, loadedCount, applied = nil, 0, 0
        a.comms = {ConfirmChoice = function(_, _, _, callback) prompt = callback end}
        a.IsGuideActive = function(g) return not g.disabled end
        local function route(name, hc)
            return {key = name, group = hc and "RestedXP Hardcore Guides (H)" or "Normal",
                name = name, hardcore = hc, softcore = not hc,
                steps = {{stepId = "one", progressIdentity = name .. "|one", elements = {}},
                         {stepId = "two", progressIdentity = name .. "|two", elements = {}}}}
        end
        local normal, hardcore = route("normal", false), route("hardcore", true)
        a.currentGuide = normal
        data.currentStep, data.currentStepId = 2, "two"
        data.stepSkip, data.completedWaypoints = {[1] = true}, {}
        data.guideProgress = {[hardcore.key] = {group = hardcore.group, name = hardcore.name,
            step = 2, stepId = "two", stepSkip = {}, completedWaypoints = {}}}
        a.LoadGuide = function(_, guide, restoring, _, _, selection)
            -- Exercise the second barrier in the production window loader too.
            assert(a.hardcoreGuides:BeforeLoad(guide, restoring))
            if selection then a.guideState:Apply(guide, selection.restart) end
            loadedCount = loadedCount + 1; a.currentGuide = guide
            return guide
        end
        local checkpoint = data.guideProgress[hardcore.key]
        hardcore.disabled = true
        a.guideState:Load(hardcore, true, "manual", function() error("disabled selection applied") end)
        assert(not prompt and loadedCount == 0 and data.currentStep == 2 and data.stepSkip[1],
            "invalid selection changed guide progress")
        hardcore.disabled = nil
        a.guideState:Load(hardcore, false, "manual", function() applied = applied + 1 end)
        assert(prompt and not a.settings.profile.hardcore and a.currentGuide == normal)
        assert(data.currentStep == 2 and data.stepSkip[1] and not data.guideProgress[normal.key],
            "confirmation mutated current progress before consent")
        assert(data.guideProgress[hardcore.key] == checkpoint and loadedCount == 0 and applied == 0)
        prompt()
        assert(a.currentGuide == hardcore and data.currentStep == 2 and data.currentStepId == "two")
        assert(data.guideProgress[normal.key].step == 2 and loadedCount == 1 and applied == 1)
        a.guideState:Load(normal, false, "manual")
        prompt()
        assert(a.currentGuide == normal and data.currentStep == 2)
        a.guideState:Load(hardcore, true, "manual")
        assert(data.currentStep == 2, "restart discarded progress before confirmation")
        prompt()
        assert(a.currentGuide == hardcore and data.currentStep == 1 and not next(data.stepSkip))
        a.guideState:Load(normal, false, "manual")
        prompt()
        local valid = true
        a.guideState:Load(hardcore, false, "manual", function() error("expired selection applied") end,
            function() return valid end)
        valid = false
        prompt()
        assert(a.currentGuide == normal and not a.settings.profile.hardcore,
            "expired party suggestion changed guide or mode")

        s.load("UI/GuideHub.lua")
        local hub, labels = a.guideHub, {}
        local controls = {Show = noop}
        for _, key in ipairs({"favorites", "recent", "factionFilter", "classFilter",
            "levelFilter", "availabilityFilter", "search"}) do
            local name = key
            controls[name] = {SetText = function(_, text) labels[name] = text end}
        end
        hub.CreateFrame = function() return controls end
        hub.Refresh = noop
        hub.Select = function(self, entry) assert(entry == nil); self.selected = nil end
        hub.selected, hub.favoritesOnly, hub.recentOnly = normal, true, true
        hub.availabilityFilter, hub.levelFilter = "unavailable", "current"
        a.hardcoreGuides:OpenGuides()
        assert(not hub.selected and not hub.favoritesOnly and not hub.recentOnly)
        assert(hub.availabilityFilter == "available" and hub.levelFilter == "all")
        assert(labels.search == "" and labels.favorites == "Favorites" and hub.hardcoreFamily == "tbc")

        -- Production PartySync must not acknowledge or jump before the second
        -- (mode) confirmation, nor after expiry/cancellation of its suggestion.
        local now, jumps, acknowledgments = 0, 0, 0
        s.env.GetTime = function() return now end
        s.env.UnitName = function(unit) if unit == "party1" then return "FixtureLeader" end end
        s.env.UnitIsPartyLeader = function(unit) return unit == "party1" end
        s.env.StaticPopupDialogs, s.env.StaticPopup_Show = {}, noop
        a.settings.profile.partyGuideSync = true
        a.guideList = {[hardcore.group] = {names_ = {hardcore.name}}}
        a.GetGuideTable = function(group, name)
            if group == hardcore.group and name == hardcore.name then return hardcore end
        end
        a.GoToStep = function(step) assert(step == 2); jumps = jumps + 1 end
        s.load("Features/PartySync.lua")
        local sync = a.partySync
        sync.Broadcast = function(_, message)
            if message.accepted then acknowledgments = acknowledgments + 1 end
        end
        local function offer()
            sync:ShowSuggestion("FixtureLeader", {guideKey=hardcore.key, step=2})
            s.env.StaticPopupDialogs.RXP_PARTY_SUGGESTION.OnAccept(nil, sync.pendingSuggestion)
            assert(jumps == 0 and acknowledgments == 0, "party acknowledged before mode consent")
        end
        offer()
        now = 31
        prompt()
        assert(a.currentGuide == normal and not a.settings.profile.hardcore, "expired party consent changed mode")
        offer()
        s.env.StaticPopupDialogs.RXP_PARTY_SUGGESTION.OnCancel(nil, sync.pendingSuggestion)
        prompt()
        assert(a.currentGuide == normal and jumps == 0, "cancelled party consent jumped")
        offer()
        prompt()
        assert(a.currentGuide == hardcore and jumps == 1 and acknowledgments == 1,
            "successful party consent did not apply once")
        prompt()
        assert(jumps == 1 and acknowledgments == 1, "party callback replayed")

        a.guideState:Load(normal, false, "manual")
        prompt()
        a.comms.ConfirmChoice = function(_, _, _, callback, payload)
            prompt = function() callback(payload) end
        end
        s.load("Core/Recovery.lua")
        a.catchUp.Analyze = function() return {
            guide=hardcore, step=2, confidence="fixture", evidence={}, uncertain={}
        } end
        a.catchUp:Preview(hardcore)
        prompt() -- Catch-Up approval opens the distinct mode confirmation.
        assert(a.currentGuide == normal and jumps == 1, "Catch-Up jumped before mode consent")
        prompt()
        assert(a.currentGuide == hardcore and jumps == 2, "Catch-Up failed after mode consent")
    end
    local s = fixture()
    s:loadDirectives()
    s.load("Guide/Hardcore.lua")
    do
        local a, loads, notices = s.addon, 0, 0
        local source = {group = "RestedXP Hardcore Guides (H)", name = "First", hardcore = true}
        local follow = {group = source.group, name = "Second", hardcore = true}
        local normal = {group = "Normal", name = "Normal"}
        a.settings.profile.hardcore = true
        a.affix = function(low, high) return low .. "-" .. high end
        a.IsGuideActive = function() return true end
        a.stepLogic.SeasonCheck = function() return true end
        a.GetGuideTable = function(group, name)
            if group == follow.group and name == follow.name then return follow end
            if group == normal.group and name == normal.name then return normal end
        end
        a.LoadGuide = function(_, guide) assert(guide == follow); loads = loads + 1 end
        a.GetGuideName = function(guide) return guide.name end
        a.comms.PrettyPrint = function() notices = notices + 1 end
        source.next = "Normal\\Normal"
        a.functions.next(nil, source)
        a.functions.next(nil, source)
        assert(loads == 0 and notices == 1, "foreign fallback loaded or coverage notice repeated")
        source.next = "Missing"
        a.functions.next(nil, source)
        assert(loads == 0, "unreleased continuation was loaded")
        source.next = "Normal\\Normal;Second"
        a.functions.next(nil, source)
        assert(loads == 1, "valid same-family continuation was not selected")
        a.step = {}
        a.functions.deathskip(".deathskip", "")
        assert(a.step.softcore, "implicit softcore marking changed")
    end
    local calls, scripts = 0, {}
    s.env.IsShiftKeyDown = function() return false end
    s.env.AcceptXPLoss = function() calls = calls + 1 end
    s.addon.SelectGossipType = function() calls = calls + 1 end
    s.addon.SetElementComplete = function() calls = calls + 1 end
    s.addon.settings.profile.enableGossipAutomation = true
    local frame = {element = {step = {active = true}}, SetScript = function(_, name, callback) scripts[name] = callback end}
    local deathskip = s.addon.functions.deathskip
    s.addon.settings.profile.hardcore = false
    deathskip(frame, "CONFIRM_XP_LOSS")
    assert(scripts.OnUpdate, "normal deathskip scheduling changed")
    s.addon.settings.profile.hardcore = true
    scripts.OnUpdate()
    assert(calls == 0 and not scripts.OnUpdate, "queued deathskip bypassed mode change")
    for _, event in ipairs({"GOSSIP_SHOW", "PLAYER_UNGHOST", "CONFIRM_XP_LOSS"}) do deathskip(frame, event) end
    assert(calls == 0, "Hardcore performed a deathskip action")
    s.addon.settings.profile.hardcore = false
    deathskip(frame, "CONFIRM_XP_LOSS")
    scripts.OnUpdate()
    assert(calls == 2, "normal resurrection/completion behavior changed")
    print("Hardcore mode regressions passed: selection, restoration, family isolation and queued deathskip guards.")
end
