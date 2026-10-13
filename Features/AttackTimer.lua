local _, addon = ...

local tool = {}
addon.attackTimer = tool
local model = addon.attackTiming
local L = addon.locale.Get
local OWNER = "attack-timer"
local TRACE_OWNER = "attack-timer-diagnostics"
local CACHE_OWNER = "attack-timer-cache"
local NEXT_SWING = {2973, 78, 845, 6807} -- Raptor Strike, Heroic Strike, Cleave, Maul
-- Counts only: no combat text, names, GUIDs or persisted event history.
local counts = {combat = 0, player = 0, swing = 0, shot = 0, spell = 0, draw = 0}
local EVENTS = {"COMBAT_LOG_EVENT_UNFILTERED", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE", "UNIT_STATS",
    "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "PLAYER_EQUIPMENT_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_REGEN_ENABLED"}

local function CurrentForm()
    if type(GetShapeshiftForm) ~= "function" then return nil end
    local form = GetShapeshiftForm()
    if type(form) == "number" then return form end
end

function tool:IsEnabled()
    return addon.settings and addon.settings.profile.enableAttackTimer == true
end

-- Explicit, short capture only. Labels are internal constants; payloads contain
-- intervals and remaining times, never spell text, unit identities or GUIDs.
function tool:TraceTiming(label)
    local trace = self.trace
    local now = GetTime()
    if not trace or now > trace.expires then return end
    if #trace.rows == 32 then table.remove(trace.rows, 1) end
    local state = self.state
    trace.rows[#trace.rows + 1] = string.format(
        "+%.3f %s main=%s ranged=%s speed=%.3f", now - trace.started, label,
        state.deadlines.main and string.format("%.3f", state.deadlines.main - now) or "unset",
        state.deadlines.ranged and string.format("%.3f", state.deadlines.ranged - now) or "unset",
        state.speeds.ranged or 0)
end

function tool:StartDiagnostics()
    if not self:IsEnabled() then print("RXP Attack Timer is disabled."); return end
    local now = GetTime()
    self.trace = {started = now, expires = now + 20, rows = {}}
    self:TraceTiming("capture start")
    print("RXP Attack Timer: capturing 20 seconds; fire Auto Shots now.")
    addon.scheduler:After(TRACE_OWNER, "report", 20, function()
        self:PrintDiagnostics()
        self.trace = nil
    end)
end

function tool:RefreshStats()
    self.weapons = self.weapons or {}
    self.missingLinks = self.missingLinks or {}
    for _, slot in ipairs({16, 17, 18}) do
        local link = GetInventoryItemLink("player", slot)
        local key = slot == 16 and "main" or slot == 17 and "off" or "ranged"
        -- A still-equipped item can have an uncached link. Texture presence
        -- distinguishes that from an empty slot without guessing a replacement.
        if not link and GetInventoryItemTexture and GetInventoryItemTexture("player", slot) then
            local now = GetTime()
            self.missingLinks[key] = self.missingLinks[key] or now
            if now - self.missingLinks[key] < 1 then
                link = self.weapons[key]
                addon.scheduler:After(CACHE_OWNER, "refresh", 0.2, function()
                    if self:IsEnabled() then self:RefreshStats(); self:Render() end
                end)
            end
        else
            self.missingLinks[key] = nil
        end
        if self.weapons[key] ~= link then
            self.state.deadlines[key] = nil
            self.state.speeds[key] = nil
            self.state.estimatedHands = nil
            if self.invalidSpeeds then self.invalidSpeeds[key] = nil end
            if key == "ranged" then
                self.state.lastShotAt, self.state.shotSignal = nil, nil
            end
            self:TraceTiming("weapon changed " .. key)
        end
        self.weapons[key] = link
    end
    local main, off = UnitAttackSpeed("player")
    local ranged, rmin, rmax = UnitRangedDamage("player")
    local mmin, mmax, omin, omax = UnitDamage("player")
    if not self.weapons.off then off = nil end
    if not self.weapons.ranged then ranged = nil end
    self.invalidSpeeds = self.invalidSpeeds or {}
    local function StableSpeed(key, value, equipped)
        local valid = type(value) == "number" and value > 0 and value < math.huge
        if valid or not equipped then self.invalidSpeeds[key] = nil; return value end
        local now = GetTime()
        self.invalidSpeeds[key] = self.invalidSpeeds[key] or now
        if now - self.invalidSpeeds[key] < 1 and self.state.speeds[key] then
            addon.scheduler:After(CACHE_OWNER, "refresh", 0.2, function()
                if self:IsEnabled() then self:RefreshStats(); self:Render() end
            end)
            return self.state.speeds[key]
        end
    end
    main = StableSpeed("main", main, true)
    off = StableSpeed("off", off, self.weapons.off ~= nil and self.state.speeds.off ~= nil)
    ranged = StableSpeed("ranged", ranged, self.weapons.ranged ~= nil)
    local changed = self.state.speeds.main ~= main or self.state.speeds.off ~= off
        or self.state.speeds.ranged ~= ranged
    model:SetSpeeds(self.state, main, off, ranged, GetTime())
    if changed then self:TraceTiming("speed update") end
    self.damage = {main = {mmin, mmax}, off = {omin, omax}, ranged = {rmin, rmax}}
end

local function IsAutoShot(spellID, spellName)
    -- Stock 3.3.5 reports unit, localized name, rank and cast counter, not
    -- necessarily a fifth spell-ID argument. Never treat the counter as an ID.
    if type(spellID) == "number" then return spellID == 75 end
    local name = GetSpellInfo(75)
    return type(name) == "string" and name ~= "" and spellName == name
end

function tool:ObserveShot(now, coupled, source)
    -- A single release may arrive through both unit and combat-log events.
    -- Keep the first timestamp; do not extend its deadline on the second event.
    source = source or "unit"
    local pending = self.state.shotSignal
    local window = math.min(1, (self.state.speeds.ranged or 1) * 0.75)
    if pending and pending.source ~= source and now >= pending.time and now - pending.time < window then
        self.state.shotSignal = nil
        self:TraceTiming("duplicate shot ignored")
        return
    end
    self.state.shotSignal = {source = source, time = now}
    self.state.lastShotAt = now
    counts.shot = counts.shot + 1
    self.repeating = true
    model:Shot(self.state, now, coupled)
    self:TraceTiming("shot applied")
end

function tool:OnCombatLog(...)
    counts.combat = counts.combat + 1
    local _, kind, source = ...
    local payload = 9
    -- Stock 3.3.5 uses the eight-field header. Some modified clients expose
    -- the later hideCaster/raid-flags header; never interpret either as a GUID.
    if type(source) == "boolean" then
        source = select(4, ...)
        payload = 12
    end
    local destination = select(payload - (payload == 9 and 3 or 4), ...)
    local coupled = addon.settings.profile.attackTimerCoupled ~= false
    if coupled and destination == UnitGUID("player") and kind == "SWING_MISSED"
        and select(payload, ...) == "PARRY" then
        model:Parry(self.state, GetTime())
        self:TraceTiming("incoming parry")
        return true
    end
    if not source or source ~= UnitGUID("player") then return end
    counts.player = counts.player + 1
    local now = GetTime()
    if kind == "SWING_DAMAGE" or kind == "SWING_MISSED" then
        counts.swing = counts.swing + 1
        model:Swing(self.state, now, coupled)
        self:TraceTiming("melee swing")
        return true
    elseif kind == "SPELL_CAST_SUCCESS" then
        if select(payload, ...) == 75 then
            self:TraceTiming("log shot success")
            self:ObserveShot(now, coupled, "log")
            return true
        end
    elseif kind == "SPELL_DAMAGE" or kind == "SPELL_MISSED" then
        local spellID, name = select(payload, ...)
        local replacement = false
        for _, id in ipairs(NEXT_SWING) do
            local expected = GetSpellInfo(id)
            if spellID == id or (type(expected) == "string" and expected ~= "" and name == expected) then
                replacement = true; break
            end
        end
        if replacement then
            -- On-next-swing abilities can report success when queued. Only the
            -- actual strike (including a miss) proves the weapon was used.
            local stamp = select(1, ...)
            local previous = self.state.replacement
            if previous and previous.id == spellID and previous.stamp == stamp then return end
            self.state.replacement = {id = spellID, stamp = stamp}
            counts.swing = counts.swing + 1
            model:Swing(self.state, now, coupled, "main")
            self:TraceTiming("next-swing strike")
            return true
        end
    elseif kind == "RANGE_DAMAGE" or kind == "RANGE_MISSED" then
        if select(payload, ...) == 75 then self:TraceTiming("shot impact (not reset)") end
    end
    -- Projectile impacts and extra-attack grants do not prove a new release.
end

function tool:PrintDiagnostics()
    print(string.format("RXP Attack Timer: enabled=%s combat=%d player=%d swings=%d shots=%d spells=%d draws=%d",
        tostring(self:IsEnabled()), counts.combat, counts.player, counts.swing,
        counts.shot, counts.spell, counts.draw))
    for _, key in ipairs({"main", "off", "ranged"}) do
        print(key, "speed", self.state.speeds[key] or 0,
            "remaining", model:Remaining(self.state, key, GetTime()) or 0)
    end
    if self.trace then
        for _, row in ipairs(self.trace.rows) do print(row) end
    end
end

function tool:OnEvent(event, ...)
    if not self:IsEnabled() then return end
    local now = GetTime()
    local coupled = addon.settings.profile.attackTimerCoupled ~= false
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not self:OnCombatLog(...) then return end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, spellName, _, _, spellID = ...
        if unit ~= "player" then return end
        counts.spell = counts.spell + 1
        if IsAutoShot(spellID, spellName) then
            self:TraceTiming("unit shot success")
            self:ObserveShot(now, coupled)
        else
            self:TraceTiming("other unit spell ignored")
            return
        end
        -- Queuing/toggling an ability is not evidence of a weapon-timer reset.
    elseif event == "START_AUTOREPEAT_SPELL" then
        self.repeating = true
        self:TraceTiming("autorepeat start")
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        self.repeating = false
        self:TraceTiming("autorepeat stop")
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Armor changes and repeated slot notifications do not restart weapons.
        self:RefreshStats()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        -- This is also a refresh notification, not proof of a transformation.
        -- Stock clients can emit it immediately after a Hunter's Auto Shot.
        local form = CurrentForm()
        if form ~= nil then
            if self.form ~= nil and form ~= self.form then
                self.state = model:New()
                self:TraceTiming("form changed")
            end
            self.form = form
        end
        self:RefreshStats()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD" then
        self.state = model:New()
        self.form = CurrentForm()
        self:TraceTiming(event)
        self:RefreshStats()
    else
        local unit = ...
        if unit and unit ~= "player" then return end
        self:RefreshStats()
    end
    self:Render()
end

function tool:Render()
    if not self.frame or not self.frame:IsShown() then return end
    counts.draw = counts.draw + 1
    local profile = addon.settings.profile
    local lines = {}
    for _, row in ipairs({{"main", "Main hand"}, {"off", "Off hand"}, {"ranged", "Ranged"}}) do
        local key, label = row[1], row[2]
        local speed = self.state.speeds[key]
        if speed then
            local parts = {L(label)}
            if profile.attackTimerShowTimers ~= false then
                local remaining = model:Remaining(self.state, key, GetTime())
                parts[#parts + 1] = string.format("%.1fs", remaining or 0)
            end
            if profile.attackTimerShowDamage ~= false then
                local damage = self.damage[key]
                if type(damage[1]) == "number" and type(damage[2]) == "number" then
                    parts[#parts + 1] = string.format("%d–%d", math.floor(damage[1]), math.ceil(damage[2])) .. " " .. L("Damage")
                end
            end
            if profile.attackTimerShowSpeed ~= false then
                parts[#parts + 1] = string.format("%.2fs", speed)
            end
            lines[#lines + 1] = table.concat(parts, "  |  ")
        end
    end
    if profile.attackTimerShowHelp ~= false then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L("Estimated basic-attack timers, not guaranteed attack times. Damage is before target mitigation. Zero means idle or unobserved; a countdown starts on an observed attack.")
        if self.state.estimatedHands then
            lines[#lines + 1] = L("Dual-wield hand assignment is estimated; equal-speed weapons and extra attacks can make it inaccurate.")
        end
        if not self.repeating then lines[#lines + 1] = L("Ranged autoattack inactive or unobserved.") end
    end
    local text = table.concat(lines, "\n\n")
    if text ~= self.lastText then
        addon.toolWindows:SetText(self.frame, text)
        self.lastText = text
    end
end

function tool:Toggle()
    if not self:IsEnabled() then return end
    if not self.frame then
        self.frame = addon.toolWindows:Create({name = "RXPAttackTimerWindow",
            title = L("Attack Timer"), width = 490, height = 260,
            minWidth = 190, minHeight = 100})
        addon.toolWindows:AddScrollingText(self.frame, {bottom = 24})
        self.frame:HookScript("OnShow", function()
            self:Render()
            addon.scheduler:Ticker(OWNER, "display", 0.1, function() self:Render() end)
        end)
        self.frame:HookScript("OnHide", function() addon.scheduler:CancelOwner(OWNER) end)
    end
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function tool:ApplySettings()
    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    end
    self.eventFrame:UnregisterAllEvents()
    if not self.state or not self.enabled or self.coupled ~= addon.settings.profile.attackTimerCoupled then
        self.state = model:New()
        self.form = CurrentForm()
        self:TraceTiming("settings reset")
        self.repeating = nil
    end
    self.enabled = self:IsEnabled()
    self.coupled = addon.settings.profile.attackTimerCoupled
    if self:IsEnabled() then
        self:RefreshStats()
        for _, event in ipairs(EVENTS) do self.eventFrame:RegisterEvent(event) end
        self:Render()
    else
        self:Shutdown()
    end
end

function tool:Shutdown()
    self.enabled = false
    addon.scheduler:CancelOwner(OWNER)
    addon.scheduler:CancelOwner(TRACE_OWNER)
    addon.scheduler:CancelOwner(CACHE_OWNER)
    self.trace = nil
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    if self.frame then self.frame:Hide() end
    self.state = model:New()
end
