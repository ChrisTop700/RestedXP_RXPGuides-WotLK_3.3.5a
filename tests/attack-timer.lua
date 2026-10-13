return function(root)
    local a = {locale = {Get = function(s) return s end}, settings = {profile = {}}}
    assert(loadfile(root .. "/Features/AttackTiming.lua"))("test", a)
    local m, s = a.attackTiming, a.attackTiming:New()
    m:SetSpeeds(s, 2, nil, 3)
    assert(m:Remaining(s, "main", 0) == nil)
    m:Shot(s, 0, true)
    assert(m:Remaining(s, "main", 0) == 2)
    assert(m:Remaining(s, "ranged", 2) == 1)
    m:Swing(s, 2, true)
    assert(m:Remaining(s, "main", 3) == 1)
    assert(m:Remaining(s, "ranged", 4) == 1)
    m:Swing(s, 4, true)
    assert(m:Remaining(s, "ranged", 7) == 0)
    m:SetSpeeds(s, 1.5, nil, 3)
    assert(s.deadlines.main == nil and s.deadlines.ranged == 7)
    m:SetSpeeds(s, 2, 1.5, 3)
    m:Swing(s, 8, true)
    assert(s.deadlines.main == 10 and s.deadlines.off == nil and s.estimatedHands)
    assert(s.deadlines.ranged == 11)
    m:Shot(s, 9, false)
    assert(s.deadlines.main == 10 and s.deadlines.ranged == 12)
    m:Swing(s, 9, false)
    assert(s.deadlines.main == 10 and s.deadlines.off == 10.5)
    m:Swing(s, 10, false)
    assert(s.deadlines.main == 12 and s.deadlines.off == 10.5)

    local now, registrations, tasks = 0, {}, {}
    local taskOwners = {}
    local shotName = "Auto Shot"
    local form = 0
    local eventCallback
    local weapons = {[16] = "sword", [18] = "bow"}
    local env = setmetatable({GetTime = function() return now end,
        GetShapeshiftForm = function() return form end,
        UnitGUID = function() return "player" end,
        GetSpellInfo = function(id) if id == 75 then return shotName elseif id == 6603 then return "Attack"
            elseif id == 2973 then return "Raptor Strike" end end,
        UnitAttackSpeed = function() return 2 end,
        UnitRangedDamage = function() return 3, 100, 150 end,
        UnitDamage = function() return 50, 75, 0, 0 end,
        GetInventoryItemLink = function(_, slot) return weapons[slot] end,
        CreateFrame = function() return {
            SetScript = function(_, script, callback) if script == "OnEvent" then eventCallback = callback end end,
            UnregisterAllEvents = function() registrations = {} end,
            RegisterEvent = function(_, e) registrations[e] = true end,
        } end}, {__index = _G})
    a.scheduler = {CancelOwner = function(_, owner)
            for key, taskOwner in pairs(taskOwners) do
                if taskOwner == owner then tasks[key], taskOwners[key] = nil, nil end
            end
        end,
        After = function(_, owner, key, delay, callback) tasks[key], taskOwners[key] = callback, owner end,
        Ticker = function(_, owner, key, interval, callback) tasks[key], taskOwners[key] = callback, owner end}
    local hooks, shown, writes, rendered = {}, false, 0, ""
    local window = {
        HookScript = function(_, event, callback) hooks[event] = callback end,
        IsShown = function() return shown end,
        Show = function() shown = true; hooks.OnShow() end,
        Hide = function() shown = false; if hooks.OnHide then hooks.OnHide() end end,
    }
    a.toolWindows = {Create = function(_, spec)
            assert(spec.minWidth == 190 and spec.minHeight == 100)
            return window
        end,
        AddScrollingText = function() end,
        SetText = function(_, _, text) writes = writes + 1; rendered = text; assert(type(text) == "string") end}
    local chunk = assert(loadfile(root .. "/Features/AttackTimer.lua"))
    setfenv(chunk, env)("test", a)
    local t = a.attackTimer
    t:ApplySettings()
    assert(next(registrations) == nil and not t:IsEnabled())
    a.settings.profile.enableAttackTimer = true
    t:ApplySettings()
    assert(registrations.COMBAT_LOG_EVENT_UNFILTERED)
    t:Toggle()
    assert(shown and tasks.display and writes == 1)
    assert(rendered:find("Main hand  |  0.0s", 1, true))
    assert(not rendered:find("Full interval", 1, true))
    t:Render()
    assert(writes == 1) -- unchanged text does not rebuild scroll layout
    t:Toggle()
    assert(not shown and next(tasks) == nil)
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "localized shot", "", 1, 75)
    assert(t.state.deadlines.ranged == 3 and t.state.deadlines.main == 2)
    now = 1
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", 1, "RANGE_DAMAGE", "player")
    assert(t.state.deadlines.ranged == 3) -- projectile arrival never restarts launch
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", 1, "SWING_DAMAGE", "pet")
    assert(t.state.deadlines.ranged == 3)
    now = 2
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", 2, "SWING_MISSED", "player")
    assert(t.state.deadlines.ranged == 5)
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "wand", "", 2, 5019)
    assert(t.state.deadlines.ranged == 5)
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 16)
    assert(t.state.deadlines.ranged == 5)
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "unknown", "", 2, 123)
    assert(t.state.deadlines.ranged == 5)
    for _, localizedName in ipairs({"Auto Shot", "Automatischer Schuss", "自动射击"}) do
        shotName = localizedName
        now = now + 4
        -- The actual stock-client payload has no fifth spell-ID argument.
        t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", shotName, "", 1234)
        local deadline = now + 3
        assert(t.state.deadlines.ranged == deadline)
        now = now + 0.05
        t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SPELL_CAST_SUCCESS",
            "player", "", 0, "target", "", 0, 75, shotName, 1)
        assert(t.state.deadlines.ranged == deadline) -- dual notifications, one reset
        now = now + 1
        assert(m:Remaining(t.state, "ranged", now) < 2)
    end
    now = now + 4
    shotName = nil -- delayed spell-name cache: combat-log ID is sufficient
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SPELL_CAST_SUCCESS",
        "player", "", 0, "target", "", 0, 75, "", 1)
    local deadline = now + 3
    assert(t.state.deadlines.ranged == deadline)
    shotName = "Auto Shot"
    now = now + 0.05
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", shotName, "", 456)
    assert(t.state.deadlines.ranged == deadline) -- reverse delivery order
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SPELL_CAST_SUCCESS",
        "pet", "", 0, "target", "", 0, 75, shotName, 1)
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "pet", shotName, "", 456)
    assert(t.state.deadlines.ranged == deadline)
    now = now + 1
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "RANGE_MISSED",
        "player", "", 0, "target", "", 0, 75, shotName, 1)
    assert(t.state.deadlines.ranged == deadline)
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Other spell", "", 75)
    assert(t.state.deadlines.ranged == deadline) -- counter 75 is not Auto Shot
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 16)
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", shotName, "", 457)
    assert(t.state.deadlines.ranged == now + 3) -- invalidation clears dedup state
    now = now + 4
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SWING_DAMAGE",
        "player", "", 0, "target", "", 0, 25, 0, 1)
    local meleeDeadline = now + 2
    assert(t.state.deadlines.main == meleeDeadline)
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Attack", "", 123)
    assert(t.state.deadlines.main == meleeDeadline)
    t:OnEvent("UNIT_DAMAGE", "player")
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 5)
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 16)
    t:ApplySettings()
    assert(t.state.deadlines.main == meleeDeadline)
    assert(t.weapons.main == "sword" and t.weapons.ranged == "bow")
    now = now + 0.5
    t:OnEvent("PLAYER_REGEN_ENABLED")
    assert(t.state.deadlines.main == meleeDeadline)
    t:Toggle()
    assert(rendered:find("1.5s", 1, true))
    now = now + 4
    t:Render()
    assert(rendered:find("Main hand  |  0.0s", 1, true))
    assert(not rendered:find("Timing unknown", 1, true))
    env.UnitAttackSpeed = function() return 2, 1.5 end
    weapons[17] = "dagger"
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 17)
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SWING_MISSED", "player")
    assert(t.state.deadlines.main == now + 2 and t.state.estimatedHands)
    now = now + 0.5
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SWING_DAMAGE", "player")
    assert(t.state.deadlines.off == now + 1.5)
    t:Render()
    assert(rendered:find("Dual-wield hand assignment is estimated", 1, true))
    local rangedDeadline = t.state.deadlines.ranged
    weapons[16] = "axe"
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 16)
    assert(t.state.deadlines.main == nil and t.state.deadlines.ranged == rangedDeadline)
    assert(t.weapons.main == "axe")
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SWING_DAMAGE", "player")
    assert(t.state.deadlines.main == now + 2)
    now = now + 0.5
    env.UnitAttackSpeed = function() return 1, 1.5 end
    t:OnEvent("UNIT_ATTACK_SPEED", "player")
    assert(t.state.deadlines.main == now + 0.75) -- live haste, same weapon
    tasks.display()
    assert(rendered:find("Main hand  |  0.8s", 1, true))
    -- Exercise actual frame dispatch, not just the public handler directly.
    env.UnitAttackSpeed = function() return 2 end
    weapons[17] = nil
    eventCallback(t.eventFrame, "PLAYER_ENTERING_WORLD")
    assert(not t.state.deadlines.main and not t.state.deadlines.ranged)
    eventCallback(t.eventFrame, "COMBAT_LOG_EVENT_UNFILTERED", now,
        "SWING_DAMAGE", "player", "", 0, "target", "", 0, 25, 0, 1)
    assert(rendered:find("Main hand  |  2.0s", 1, true))
    local firstSwing = t.state.deadlines.main
    now = now + 0.1
    eventCallback(t.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "Raptor Strike", "", 1)
    eventCallback(t.eventFrame, "COMBAT_LOG_EVENT_UNFILTERED", now,
        "SPELL_CAST_SUCCESS", "player", "", 0, "target", "", 0, 2973, "Raptor Strike", 1)
    assert(t.state.deadlines.main == firstSwing) -- queued out of range, no reset
    now = now + 2
    eventCallback(t.eventFrame, "COMBAT_LOG_EVENT_UNFILTERED", now,
        "SPELL_MISSED", "player", "", 0, "target", "", 0, 2973, "Raptor Strike", 1, "MISS")
    assert(t.state.deadlines.main == now + 2) -- actual strike consumes swing
    eventCallback(t.eventFrame, "PLAYER_ENTERING_WORLD")
    eventCallback(t.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", shotName, "", 2)
    assert(rendered:find("Ranged  |  3.0s", 1, true))
    now = now + 0.5
    tasks.display()
    assert(rendered:find("Ranged  |  2.5s", 1, true))
    now = now + 4
    eventCallback(t.eventFrame, "COMBAT_LOG_EVENT_UNFILTERED", now,
        "SPELL_CAST_SUCCESS", false, "player", "", 0, 0, "target", "", 0, 0, 75, shotName, 1)
    assert(t.state.deadlines.ranged == now + 3)
    now = now + 1
    eventCallback(t.eventFrame, "COMBAT_LOG_EVENT_UNFILTERED", now,
        "SWING_DAMAGE", false, "player", "", 0, 0, "target", "", 0, 0, 25, 0, 1)
    assert(t.state.deadlines.main == now + 2)
    -- Reproduce the user's trace: first shot, then a redundant form update
    -- one millisecond later. Both countdowns must survive unchanged.
    eventCallback(t.eventFrame, "PLAYER_ENTERING_WORLD")
    eventCallback(t.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", shotName, "", 3)
    local firstMain, firstRanged = t.state.deadlines.main, t.state.deadlines.ranged
    now = now + 0.001
    eventCallback(t.eventFrame, "UPDATE_SHAPESHIFT_FORM")
    assert(t.state.deadlines.main == firstMain and t.state.deadlines.ranged == firstRanged)
    for i = 1, 3 do eventCallback(t.eventFrame, "UPDATE_SHAPESHIFT_FORM") end
    assert(t.state.deadlines.ranged == firstRanged)
    assert(rendered:find("Ranged  |  3.0s", 1, true))
    form = nil -- unavailable API data is not evidence of a real form change
    eventCallback(t.eventFrame, "UPDATE_SHAPESHIFT_FORM")
    assert(t.state.deadlines.ranged == firstRanged)
    form = 1 -- a genuine change still invalidates old attack timing
    eventCallback(t.eventFrame, "UPDATE_SHAPESHIFT_FORM")
    assert(next(t.state.deadlines) == nil)
    eventCallback(t.eventFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", shotName, "", 4)
    form = 0
    eventCallback(t.eventFrame, "UPDATE_SHAPESHIFT_FORM")
    assert(next(t.state.deadlines) == nil)
    local messages = {}
    env.print = function(...) messages[#messages + 1] = tostring((...)) end
    t:StartDiagnostics()
    assert(tasks.report and t.trace and #t.trace.rows == 1)
    t:Toggle()
    assert(not shown and not tasks.display and tasks.report)
    t:Toggle()
    assert(shown and tasks.display and tasks.report)
    local oldDeadline = t.state.deadlines.ranged
    eventCallback(t.eventFrame, "COMBAT_LOG_EVENT_UNFILTERED", now,
        "RANGE_DAMAGE", "player", "PRIVATE", 0, "target", "PRIVATE", 0, 75, shotName, 1)
    assert(t.state.deadlines.ranged == oldDeadline)
    for i = 1, 40 do
        now = now + 0.1
        eventCallback(t.eventFrame, "START_AUTOREPEAT_SPELL")
    end
    assert(#t.trace.rows == 32)
    for _, row in ipairs(t.trace.rows) do assert(not row:find("PRIVATE", 1, true)) end
    now = t.trace.expires + 1
    t:TraceTiming("expired test")
    assert(not t.trace.rows[32]:find("expired", 1, true))
    tasks.report()
    assert(t.trace == nil and #messages > 32)
    -- Live presentation controls must not erase synchronized weapon state or
    -- restart the display ticker. Hidden prose must remove all footer notes.
    now = now + 4
    t:ObserveShot(now, true)
    t.repeating = false
    t.state.estimatedHands = true
    local stateBefore, deadlineBefore, displayBefore = t.state, t.state.deadlines.ranged, tasks.display
    a.settings.profile.attackTimerShowHelp = false
    t:ApplySettings()
    assert(t.state == stateBefore and t.state.deadlines.ranged == deadlineBefore)
    assert(tasks.display == displayBefore)
    assert(rendered:find("Ranged  |  3.0s", 1, true))
    assert(not rendered:find("Estimated basic", 1, true))
    assert(not rendered:find("inactive", 1, true))
    assert(not rendered:find("Dual-wield", 1, true))
    a.settings.profile.attackTimerShowHelp = true
    t:ApplySettings()
    assert(rendered:find("Estimated basic", 1, true) and rendered:find("inactive", 1, true))
    assert(t.state.deadlines.ranged == deadlineBefore)
    -- Repaired audit regressions: late duplicate, incoming parry and real
    -- replacement strikes, never the queued spell-success notification.
    now = now + 0.3
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SPELL_CAST_SUCCESS",
        "player", "", 0, "target", "", 0, 75, shotName, 1)
    assert(t.state.deadlines.ranged == deadlineBefore)
    local parryDeadline = t.state.deadlines.main
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SWING_MISSED",
        "enemy", "", 0, "player", "", 0, "PARRY")
    assert(t.state.deadlines.main < parryDeadline)
    assert(t.state.deadlines.ranged == deadlineBefore)
    t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SPELL_DAMAGE",
        "player", "", 0, "target", "", 0, 78, "Heroic Strike", 1)
    assert(t.state.deadlines.main == now + 2)
    for _, id in ipairs({78, 845, 6807}) do
        now = now + 3
        local before = t.state.deadlines.main
        t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "queued", "", 2, id)
        assert(t.state.deadlines.main == before)
        t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", now, "SPELL_MISSED",
            "player", "", 0, "target", "", 0, id, "", 1, "MISS")
        assert(t.state.deadlines.main == now + 2)
        local stamp = now
        now = now + 0.1
        t:OnEvent("COMBAT_LOG_EVENT_UNFILTERED", stamp, "SPELL_DAMAGE",
            "player", "", 0, "target2", "", 0, id, "", 1)
        assert(t.state.deadlines.main == stamp + 2) -- Cleave's second target
    end
    now = now + 4
    t:ObserveShot(now, true, "unit")
    now = now + 0.1
    t:ObserveShot(now, true, "unit")
    assert(t.state.deadlines.ranged == now + 3) -- fast distinct same-source shot
    local beforeMissing = t.state.deadlines.ranged
    env.UnitRangedDamage = function() return 0, 100, 150 end
    t:OnEvent("UNIT_RANGEDDAMAGE", "player")
    assert(t.state.deadlines.ranged == beforeMissing and tasks.refresh)
    now = now + 0.2
    env.UnitRangedDamage = function() return 3, 100, 150 end
    tasks.refresh()
    assert(t.state.deadlines.ranged == beforeMissing)
    env.GetInventoryItemTexture = function(_, slot) if slot == 18 then return "icon" end end
    weapons[18] = nil
    t:OnEvent("UNIT_RANGEDDAMAGE", "player")
    assert(t.weapons.ranged == "bow" and t.state.deadlines.ranged == beforeMissing)
    env.GetInventoryItemTexture = function() return nil end
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 18)
    assert(t.state.speeds.ranged == nil and t.state.deadlines.ranged == nil)
    weapons[18] = "bow"
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 18)
    t:ObserveShot(now, true, "unit")
    env.UnitRangedDamage = function() return 0, 100, 150 end
    t:OnEvent("UNIT_RANGEDDAMAGE", "player")
    now = now + 1.1
    tasks.refresh()
    assert(t.state.speeds.ranged == nil and t.state.deadlines.ranged == nil)
    local parry = m:New()
    m:SetSpeeds(parry, 2, nil, 3)
    m:Swing(parry, 0, true)
    m:Parry(parry, 0)
    assert(math.abs(parry.deadlines.main - 1.2) < 0.00001)
    m:Parry(parry, 0.7)
    assert(math.abs(parry.deadlines.main - 1.1) < 0.00001)
    m:Parry(parry, 1)
    assert(math.abs(parry.deadlines.main - 1.1) < 0.00001)
    assert(parry.deadlines.ranged == 3)
    t:StartDiagnostics()
    a.settings.profile.enableAttackTimer = false
    t:ApplySettings()
    assert(next(registrations) == nil and next(tasks) == nil)
    assert(t.trace == nil)
    t:Toggle()
    assert(not shown)
    print("Attack timer regressions passed.")
end
