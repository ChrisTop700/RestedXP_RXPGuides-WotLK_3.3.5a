-- Optional offline candidate test:
-- lua5.1 tests/hardcore-upstream-loading.lua . <upstream directory> [curated directory]
-- Uses the production parser, full guide eligibility and .next resolver.
-- Directive bodies are inert; this establishes route structure, not gameplay.
local root, candidate = assert(arg[1]), assert(arg[2])
local curated = arg[3]
local inputPath=assert(loadfile(root.."/tests/hardcore-input-path.lua"))()
local flow=arg[4]=="--quest-flow" and
    assert(loadfile(root.."/tests/hardcore-quest-flow.lua"))()(arg[5],root,arg[7])
local families = {"classic", "tbc"}
if curated then families[#families + 1] = "curated" end
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
local function slice(text, first, last)
    local start = assert(text:find(first, 1, true))
    return text:sub(start, assert(text:find(last, start + #first, true)) - 1)
end
local predicates = slice(read(root .. "/Core/Addon.lua"),
    "function addon.stepLogic.PhaseCheck", "addon.facade:ExposeGlobal")
local active = slice(read(root .. "/UI/GuideWindow.lua"),
    "local function IsGuideActive(", "function RXPFrame:GenerateMenuTable(")
local resolver = slice(read(root .. "/Guide/Directives/Handlers.lua"),
    "local legacyCoverageNotified = {}", "function addon.functions.train(")
local dungeonParser = slice(read(root .. "/Guide/Directives/Handlers.lua"),
    "function addon.functions.dungeon(", "addon.professions = {}")
local deathParser = slice(read(root .. "/Guide/Directives/Handlers.lua"),
    "function addon.functions.deathskip(", "function addon.functions.addquestitem(")
local blocks = {}
-- Never let the inert directive fixtures invent support for an unknown tag.
local registry = read(root .. "/tests/runtime-surface.json")
local supported = {}
for _, field in ipairs({"directives", "directiveAliases"}) do
    local list = assert(registry:match('"' .. field .. '"%s*:%s*%[(.-)%]'),
        "Missing runtime directive surface")
    for name in list:gmatch('"([^"]+)"') do supported[name] = true end
end
for _, family in ipairs(families) do
    blocks[family] = {}
    local path=inputPath(family=="curated" and curated or candidate,family)
    local compiled,syntaxError=loadfile(path)
    assert(compiled,syntaxError) -- Compile the whole generated Lua5.1 file too.
    for text in read(path):gmatch(
        "RXPGuides%.RegisterGuide%(%[%[(.-)%]%]%)") do
        for line in text:gmatch("[^\n]+") do
            local tag = line:match("^%s*%.([%a][%w_]*)")
            assert(not tag or supported[tag], "Unsupported guide directive: ." .. (tag or ""))
        end
        blocks[family][#blocks[family] + 1] = text
    end
end
local profiles = {
    {"Alliance","Human","WARRIOR,PALADIN,ROGUE,PRIEST,MAGE,WARLOCK","1-6 Northshire","1-11 Elwynn Forest"},
    {"Alliance","Dwarf","WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST","1-6 Coldridge Valley","1-10 Dun Morogh"},
    {"Alliance","Gnome","WARRIOR,ROGUE,MAGE,WARLOCK","1-6 Coldridge Valley","1-10 Dun Morogh"},
    {"Alliance","NightElf","WARRIOR,HUNTER,ROGUE,PRIEST,DRUID","1-6 Shadowglen","1-11 Teldrassil"},
    {"Alliance","Draenei","WARRIOR,PALADIN,HUNTER,PRIEST,MAGE,SHAMAN",false,"1-12 Azuremyst Isle"},
    {"Horde","Orc","WARRIOR,HUNTER,ROGUE,SHAMAN,WARLOCK","1-6 Orc/Troll","1-6 Durotar"},
    {"Horde","Troll","WARRIOR,HUNTER,ROGUE,PRIEST,MAGE,SHAMAN","1-6 Orc/Troll","1-6 Durotar"},
    {"Horde","Tauren","WARRIOR,HUNTER,SHAMAN,DRUID","1-6 Tauren","1-6 Mulgore"},
    {"Horde","Scourge","WARRIOR,ROGUE,PRIEST,MAGE,WARLOCK","1-6 Undead","1-6 Tirisfal Glades"},
    {"Horde","BloodElf","PALADIN,HUNTER,ROGUE,PRIEST,MAGE,WARLOCK",false,"1-6 Eversong Woods"},
}
local focused=arg[6]=="--focused-chains"
local labelCases=arg[6]=="--label-cases"
assert(not labelCases or (flow and arg[7]),"Label cases require bound evidence")
if focused then
    assert(flow,"Focused chains require the quest-flow visitor")
    profiles={
        {"Alliance","Human","WARRIOR","1-6 Northshire","1-11 Elwynn Forest"},
        {"Horde","Orc","WARRIOR","1-6 Orc/Troll","1-6 Durotar"},
    }
end
local paths, parsed = 0, 0
for _, profile in ipairs(profiles) do
    for class in profile[3]:gmatch("[^,]+") do
        local env = setmetatable({}, {__index = _G})
        env._G = env
        env.strlower, env.strupper, env.tinsert, env.tremove = string.lower, string.upper, table.insert, table.remove
        local level=1
        env.UnitLevel, env.UnitSex = function() return level end, function() return 2 end
        env.bit = {band = function(value) return value % 4294967296 end}
        env.LibStub = function() return {} end
        env.RXPGuides = {}
        env.RXPCData={guideMetaData={enabledDungeons={Alliance={},Horde={}},dungeonGuides={}}}
        local addon = {
            player = {class=class, race=profile[2], faction=profile[1], season=0},
            game="WOTLK", gameVersion=30300, RXPGuides={}, separators={}, guideCache={}, db={},
            locale={Get=function(s) return s end}, services={Register=function() end},
            settings={profile={hardcore=true, season=0, phase=6, enableXpStepSkipping=true,
                dungeons={}}, ReplaceColors=function(s) return s end},
            RXPFrame={GenerateMenuTable=function() end}, error=error, stepLogic={},
            comms={PrettyPrint=function() end}, dungeons={}, icons={deathskip=""},
        }
        env.addon = addon
        addon.functions = setmetatable({}, {__index=function(functions, tag)
            local handler = function(_, text, first)
                if tag == "deathskip" then addon.step.softcore = true end
                return {text=text, first=first, tag=tag}
            end
            rawset(functions,tag,handler)
            return handler
        end})
        local function load(path) local fn=assert(loadfile(root .. "/" .. path)); setfenv(fn,env)("RXPGuides",addon) end
        load("DB/wotlk/dungeonData_335.lua")
        env.L=addon.locale.Get
        setfenv(assert(loadstring(dungeonParser)),env)()
        setfenv(assert(loadstring(deathParser)),env)()
        load("Guide/Loader.lua")
        load("Guide/Hardcore.lua")
        local fn=assert(loadstring(predicates)); setfenv(fn,env)()
        fn=assert(loadstring(active)); setfenv(fn,env)()
        -- The resolver's reputation branch is not used in level-60 routes.
        addon.stepLogic.AldorScryerCheck=function() error("Unexpected reputation route") end
        fn=assert(loadstring(resolver)); setfenv(fn,env)()
        for _, family in ipairs(families) do
            addon.settings.profile.xprate=1
            local startName = family == "classic" and profile[4] or profile[5]
            if family == "classic" and not profile[4] then startName = nil end
            if startName then
                local routes = {}
                local group = (family == "curated" and "RestedXP Hardcore Guides" or
                    ("Original Guides - RestedXP Hardcore " ..
                    (family == "classic" and "Classic" or "TBC") .. " Guides")) ..
                    " (" .. (profile[1] == "Alliance" and "A" or "H") .. ")"
                for _, text in ipairs(blocks[family]) do
                    if not labelCases or flow.selected(text,family,profile[2].."/"..class) then
                    level=tonumber(text:match("#name (%d+)%-")) or 1
                    local guide, excluded = addon.ParseGuide(text)
                    if not excluded then
                        assert(guide.group == group and guide.hardcore and not guide.softcore, "Wrong family/faction")
                        assert(not routes[guide.name], "Duplicate canonical name")
                        routes[guide.name] = guide
                        if flow then flow.inspect(addon,guide,family,profile[2].."/"..class,text) end
                        parsed = parsed + 1
                    end
                    end
                end
                addon.GetGuideTable=function(g,n) if g == group then return routes[n] end end
                local function walk()
                    local current = assert(routes[startName:gsub("^(%d)-(%d%d?)", addon.affix)], "Missing racial start")
                    local seen,ordered = {},{}
                    while true do
                        assert(not seen[current.name], "Route loop: " .. current.name)
                        seen[current.name] = true
                        ordered[#ordered+1]=current
                        level=tonumber(current.name:match("^(%d+)%-")) or 1
                        assert(addon.IsGuideActive(current), "Ineligible chapter: " .. current.name)
                        level=tonumber(current.name:match("^%d+%-(%d+)")) or level
                        assert(addon.IsGuideActive(current), "Ineligible chapter boundary: " .. current.name)
                        local nextGroup, nextName = addon.functions.next(false, current)
                        if not current.next then
                            assert(tonumber(current.name:match("^%d+%-(%d+)")) == 60, "Premature endpoint")
                            break
                        end
                        assert(nextGroup == group and nextName and routes[nextName],
                            profile[2] .. " " .. class .. " @" .. addon.settings.profile.xprate .. ": broken handoff " .. current.name)
                        current = routes[nextName]
                    end
                    return ordered
                end
                for _, rate in ipairs(labelCases and {} or {1,1.2,1.5,2}) do
                    addon.settings.profile.xprate = rate
                    local ordered=walk()
                    if flow then flow.route(family,ordered,profile[2].."/"..class) end
                    paths = paths + 1
                    if flow and rate==1 then
                        flow.chains(addon,walk,family,profile[2],class,profile[1])
                    end
                end
            end
        end
    end
end
assert(paths == (labelCases and 0 or (focused and (curated and 24 or 16) or (curated and 576 or 368))), "Missing class/race/rate profiles")
if flow then
    local unresolved=flow.finish()
    if arg[6]=="--require-clean-labels" then
        assert(unresolved==0,"Unresolved branch-local label references block publication")
    end
end
if labelCases then
    print("Focused evidence checks only: "..parsed.." parsed chapters. Full route/publication checks remain required.")
else
    print("Hardcore candidate structure passed: " .. paths .. " production-resolved paths to 60 at chapter entry/exit levels; " .. parsed .. " parsed faction/class chapters. No gameplay certification.")
end
