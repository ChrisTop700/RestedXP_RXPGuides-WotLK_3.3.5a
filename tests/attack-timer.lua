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
    assert(s.deadlines.main == nil and s.deadlines.off == nil)
    assert(s.deadlines.ranged == 11)
    m:Shot(s, 9, false)
    assert(s.deadlines.main == nil and s.deadlines.ranged == 12)

    local now, registrations, tasks = 0, {}, {}
    local env = setmetatable({GetTime = function() return now end,
        UnitGUID = function() return "player" end,
        UnitAttackSpeed = function() return 2 end,
        UnitRangedDamage = function() return 3, 100, 150 end,
        UnitDamage = function() return 50, 75, 0, 0 end,
        GetInventoryItemLink = function() return "weapon" end,
        CreateFrame = function() return {
            SetScript = function() end,
            UnregisterAllEvents = function() registrations = {} end,
            RegisterEvent = function(_, e) registrations[e] = true end,
        } end}, {__index = _G})
    a.scheduler = {CancelOwner = function() tasks = {} end,
        Ticker = function(_, owner, key, interval, callback) tasks[key] = callback end}
    local hooks, shown, writes = {}, false, 0
    local window = {
        HookScript = function(_, event, callback) hooks[event] = callback end,
        IsShown = function() return shown end,
        Show = function() shown = true; hooks.OnShow() end,
        Hide = function() shown = false; if hooks.OnHide then hooks.OnHide() end end,
    }
    a.toolWindows = {Create = function() return window end,
        AddScrollingText = function() end,
        SetText = function(_, _, text) writes = writes + 1; assert(type(text) == "string") end}
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
    assert(next(t.state.deadlines) == nil)
    t:OnEvent("PLAYER_EQUIPMENT_CHANGED", 16)
    assert(next(t.state.deadlines) == nil)
    t:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "unknown", "", 2, 123)
    assert(next(t.state.deadlines) == nil)
    a.settings.profile.enableAttackTimer = false
    t:ApplySettings()
    assert(next(registrations) == nil and next(tasks) == nil)
    t:Toggle()
    assert(not shown)
    print("Attack timer regressions passed.")
end
