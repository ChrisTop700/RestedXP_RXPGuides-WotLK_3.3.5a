local _, addon = ...

-- Pure state model: never persist combat identities or infer a dual-wield hand.
local model = {}
addon.attackTiming = model

function model:New()
    return {speeds = {}, deadlines = {}}
end

function model:SetSpeeds(state, main, off, ranged)
    local values = {main = main, off = off, ranged = ranged}
    for _, key in ipairs({"main", "off", "ranged"}) do
        local value = tonumber(values[key])
        if not value or value <= 0 then value = nil end
        if state.speeds[key] ~= value then state.deadlines[key] = nil end
        state.speeds[key] = value
    end
end

function model:Reset(state, key, now)
    state.deadlines[key] = state.speeds[key] and now + state.speeds[key] or nil
end

function model:Shot(state, now, coupled)
    self:Reset(state, "ranged", now)
    if coupled then
        self:Reset(state, "main", now)
        self:Reset(state, "off", now)
    end
end

function model:Swing(state, now, coupled)
    if state.speeds.off then
        state.deadlines.main, state.deadlines.off = nil, nil
    else
        self:Reset(state, "main", now)
    end
    if coupled then self:Reset(state, "ranged", now) end
end

function model:Remaining(state, key, now)
    local deadline = state.deadlines[key]
    if deadline then return math.max(0, deadline - now) end
end
