local _, addon = ...

-- Pure state model: no persisted combat identities. Dual-wield hand assignment
-- is an explicit estimate, not authoritative client evidence.
local model = {}
addon.attackTiming = model

function model:New()
    return {speeds = {}, deadlines = {}}
end

function model:SetSpeeds(state, main, off, ranged, now)
    local values = {main = main, off = off, ranged = ranged}
    for _, key in ipairs({"main", "off", "ranged"}) do
        local value = tonumber(values[key])
        if not value or value <= 0 then value = nil end
        if state.speeds[key] ~= value then
            local old, deadline = state.speeds[key], state.deadlines[key]
            if now and old and value and deadline then
                state.deadlines[key] = now + math.max(0, deadline - now) * value / old
            else
                state.deadlines[key] = nil
            end
        end
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

function model:Swing(state, now, coupled, knownHand)
    local hand = "main"
    if state.speeds.off then
        -- Stock 3.3.5 does not reliably identify the swinging hand. Seed the
        -- first observed swing as main hand, then prefer the earliest deadline.
        -- Equal-speed weapons, extra attacks and delayed events are ambiguous.
        local main, off = state.deadlines.main, state.deadlines.off
        hand = knownHand or (main and (off or now) < main and "off" or "main")
        self:Reset(state, hand, now)
        state.estimatedHands = not knownHand or state.estimatedHands
        if coupled then
            local other = hand == "main" and "off" or "main"
            if state.deadlines[other] and state.deadlines[other] < now + 0.2 then
                state.deadlines[other] = now + 0.2
            end
        end
    else
        self:Reset(state, "main", now)
        state.estimatedHands = nil
    end
    if coupled then self:Reset(state, "ranged", now) end
end

function model:Parry(state, now)
    local hand = "main"
    if state.speeds.off and state.deadlines.off and state.deadlines.main
        and state.deadlines.off < state.deadlines.main then hand = "off" end
    local speed, deadline = state.speeds[hand], state.deadlines[hand]
    if not speed or not deadline then return end
    local remaining = deadline - now
    if remaining > speed * 0.2 then
        state.deadlines[hand] = now + math.max(speed * 0.2, remaining - speed * 0.4)
    end
end

function model:Remaining(state, key, now)
    local deadline = state.deadlines[key]
    if deadline then return math.max(0, deadline - now) end
end
