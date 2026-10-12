local _, addon = ...

local tool = {}
addon.attackTimer = tool
local model = addon.attackTiming
local L = addon.locale.Get
local OWNER = "attack-timer"
local EVENTS = {"COMBAT_LOG_EVENT_UNFILTERED", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_ATTACK_SPEED", "UNIT_DAMAGE", "UNIT_RANGEDDAMAGE", "UNIT_STATS",
    "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "PLAYER_EQUIPMENT_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
    "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_REGEN_ENABLED"}

function tool:IsEnabled()
    return addon.settings and addon.settings.profile.enableAttackTimer == true
end

function tool:RefreshStats()
    local main, off = UnitAttackSpeed("player")
    local ranged, rmin, rmax = UnitRangedDamage("player")
    local mmin, mmax, omin, omax = UnitDamage("player")
    if not GetInventoryItemLink("player", 18) then ranged = nil end
    model:SetSpeeds(self.state, main, off, ranged)
    self.damage = {main = {mmin, mmax}, off = {omin, omax}, ranged = {rmin, rmax}}
end

function tool:OnEvent(event, ...)
    if not self:IsEnabled() then return end
    local now = GetTime()
    local coupled = addon.settings.profile.attackTimerCoupled ~= false
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Stock 3.3.5 layout: timestamp, event, source GUID/name/flags, destination...
        local _, kind, source = ...
        if source ~= UnitGUID("player") then return end
        if kind == "SWING_DAMAGE" or kind == "SWING_MISSED" then
            model:Swing(self.state, now, coupled)
        elseif kind == "SPELL_EXTRA_ATTACKS" then
            self.state.deadlines = {}
        end
        -- RANGE_DAMAGE is impact time, not launch time. Never synchronize to it.
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, _, _, spellID = ...
        if unit ~= "player" then return end
        if spellID == 75 then
            model:Shot(self.state, now, coupled)
        elseif spellID == 5019 then
            -- Wand shoot has different timing/casting rules: display stats only.
            self.state.deadlines = {}
        else
            -- Abilities are deliberately outside this basic-attack model.
            -- They may alter timers, so discard predictions rather than lie.
            self.state.deadlines = {}
        end
    elseif event == "START_AUTOREPEAT_SPELL" then
        self.repeating = true
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        self.repeating = false
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD"
        or event == "PLAYER_REGEN_ENABLED" then
        self.state = model:New()
        self:RefreshStats()
    else
        local unit = ...
        if unit and unit ~= "player" then return end
        self:RefreshStats()
    end
end

function tool:Render()
    if not self.frame or not self.frame:IsShown() then return end
    local profile = addon.settings.profile
    local lines = {}
    for _, row in ipairs({{"main", "Main hand"}, {"off", "Off hand"}, {"ranged", "Ranged"}}) do
        local key, label = row[1], row[2]
        local speed = self.state.speeds[key]
        if speed then
            local parts = {L(label)}
            if profile.attackTimerShowTimers ~= false then
                local remaining = model:Remaining(self.state, key, GetTime())
                parts[#parts + 1] = remaining and
                    (remaining > 0 and string.format("~%.1fs", remaining) or L("Timer ready"))
                    or L("Timing unknown")
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
    lines[#lines + 1] = ""
    lines[#lines + 1] = L("Estimated basic-attack timers, not guaranteed attack times. Damage is before target mitigation. Abilities invalidate timing; dual-wield swings and wands may remain unknown.")
    if not self.repeating then lines[#lines + 1] = L("Ranged autoattack inactive or unobserved.") end
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
            minWidth = 300, minHeight = 200})
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
    self.state = model:New()
    self.repeating = nil
    if self:IsEnabled() then
        self:RefreshStats()
        for _, event in ipairs(EVENTS) do self.eventFrame:RegisterEvent(event) end
        self:Render()
    else
        self:Shutdown()
    end
end

function tool:Shutdown()
    addon.scheduler:CancelOwner(OWNER)
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
    if self.frame then self.frame:Hide() end
    self.state = model:New()
end
