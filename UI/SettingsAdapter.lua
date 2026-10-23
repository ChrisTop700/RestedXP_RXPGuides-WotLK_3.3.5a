local _, addon = ...
local adapter = {}
addon.settingsAdapter = adapter
local inherited = {get = true, set = true, func = true, hidden = true,
    disabled = true, validate = true, confirm = true}
local literalStrings = {name = true, desc = true, icon = true, usage = true, width = true, fontSize = true}
local types = {toggle = true, range = true, select = true, execute = true, header = true, description = true}
local related = {
    routePreflight = {{"guideRoutingSettings", "enableRoutePreflight"},
        {"guideRoutingSettings", "preflightLookahead"}, {"guideRoutingSettings", "enableItemReservations"},
        {"guideRoutingSettings", "reservationLookahead"}, {"guideRoutingSettings", "enableXPShortfallPredictor"}},
    xpEstimator = {{"guideRoutingSettings", "enableMobXPEstimator"},
        {"guideRoutingSettings", "adaptiveMobXP"}, {"guideRoutingSettings", "showXPRemaining"}},
    petAssistant = {{"guideRoutingSettings", "enablePetAssistant"}},
    performance = {{"advancedSettings", "enableAdaptivePerformance"},
        {"advancedSettings", "adaptivePerformanceFPSThreshold"}},
}
local allowedRelated = {}
for _, paths in pairs(related) do
    for _, path in ipairs(paths) do allowedRelated[table.concat(path, "/")] = true end
end

-- Settings owns the only option tree. The view carries paths, never copies of
-- callbacks or a profile table. No private metadata is added to Ace options.
function adapter:Resolve(path)
    if type(path) ~= "table" or (path[1] ~= "featureToolsSettings" and
        not allowedRelated[table.concat(path, "/")]) then return end
    local root = addon.settings.optionTree
    if not root then return end
    local option, chain, handler = root, {root}, root.handler
    for _, key in ipairs(path) do
        if type(option.args) ~= "table" then return end
        option = option.args[key]
        if type(option) ~= "table" then return end
        chain[#chain + 1] = option
        handler = option.handler or handler
    end
    local info = {options = root, appName = addon.title, [0] = addon.title,
        arg = option.arg, handler = handler, option = option, type = option.type,
        uiType = "dialog", uiName = "RXPFeatureTools"}
    for i, key in ipairs(path) do info[i] = key end
    return option, info, chain
end

function adapter:Value(path, member, ...)
    local option, info, chain = self:Resolve(path)
    if not option then return end
    local value = option[member]
    if inherited[member] then
        value = nil
        for _, ancestor in ipairs(chain) do
            if ancestor[member] ~= nil then value = ancestor[member] end
        end
    end
    if type(value) == "function" then return value(info, ...) end
    if type(value) == "string" and not literalStrings[member] and member ~= "type" then
        assert(info.handler and type(info.handler[value]) == "function", "Invalid settings handler")
        return info.handler[value](info.handler, info, ...)
    end
    return value
end

function adapter:Describe(path)
    local option = self:Resolve(path)
    if not option then return end
    return {type = option.type, supported = types[option.type] == true,
        name = self:Value(path, "name"), desc = self:Value(path, "desc"),
        hidden = self:Value(path, "hidden"), disabled = self:Value(path, "disabled"),
        order = self:Value(path, "order") or 100, min = option.min, max = option.max,
        step = option.step, isPercent = option.isPercent,
        values = option.type == "select" and self:Value(path, "values") or nil}
end

function adapter:Children(path)
    local option = self:Resolve(path)
    local list = {}
    for key in pairs(option and option.args or {}) do
        local child = {}
        for i, part in ipairs(path) do child[i] = part end
        child[#child + 1] = key
        local info = self:Describe(child)
        if info and not info.hidden then list[#list + 1] = {path = child, info = info} end
    end
    table.sort(list, function(a, b)
        if a.info.order ~= b.info.order then return a.info.order < b.info.order end
        return table.concat(a.path, "/") < table.concat(b.path, "/")
    end)
    return list
end

function adapter:PageControls(path)
    local list = self:Children(path)
    if #path == 2 then
        for _, extra in ipairs(related[path[2]] or {}) do
            local info = self:Describe(extra)
            if info and not info.hidden then list[#list + 1] = {path = extra, info = info} end
        end
    end
    table.sort(list, function(a, b)
        if a.info.order ~= b.info.order then return a.info.order < b.info.order end
        return table.concat(a.path, "/") < table.concat(b.path, "/")
    end)
    return list
end

function adapter:Commit(path, value, approved)
    local info = self:Describe(path)
    if not info or info.hidden or info.disabled or not info.supported then return false end
    if info.type == "range" then
        if type(value) ~= "number" or value ~= value then return false end
        value = math.max(info.min, math.min(info.max, value))
        if info.step and info.step > 0 then
            value = info.min + math.floor((value - info.min) / info.step + 0.5) * info.step
            value = math.max(info.min, math.min(info.max, value))
        end
    elseif info.type == "toggle" then
        if type(value) ~= "boolean" then return false end
    elseif info.type == "select" then
        if type(info.values) ~= "table" or info.values[value] == nil then return false end
    elseif info.type ~= "execute" then return false end
    local valid = self:Value(path, "validate", value)
    if valid == false or type(valid) == "string" then
        if type(valid) == "string" then addon.comms.PrettyPrint(valid) end
        return false
    end
    local confirm = self:Value(path, "confirm", value)
    if confirm and not approved then
        local profile, tree, option = addon.settings.profile, addon.settings.optionTree, self:Resolve(path)
        local revision = addon.presentation.settingsRevision
        addon.comms:ConfirmChoice("RXP_MODERN_OPTION", type(confirm) == "string" and confirm or info.name, function()
            if profile == addon.settings.profile and tree == addon.settings.optionTree and self:Resolve(path) == option and
                revision == addon.presentation.settingsRevision then
                self:Commit(path, value, true)
            end
        end)
        return false
    end
    self:Value(path, info.type == "execute" and "func" or "set", value)
    addon.presentation:SettingsChanged()
    return true
end
