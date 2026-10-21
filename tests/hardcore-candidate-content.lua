-- lua5.1 tests/hardcore-candidate-content.lua ROOT BEFORE AFTER
-- Narrow compatibility evidence across the actual class/race predicates.
-- Does not claim quest availability, travel safety or complete gameplay.
local root, beforeRoot, afterRoot = assert(arg[1]), assert(arg[2]), assert(arg[3])
local inputPath=assert(loadfile(root.."/tests/hardcore-input-path.lua"))()
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n"); file:close()
    return text
end
local function chapters(path)
    local result = {}
    for body in read(path):gmatch("RXPGuides%.RegisterGuide%(%[%[(.-)%]%]%)") do
        local key = assert(body:match("\n#group ([^\n]+)")) .. "|" ..
            assert(body:match("\n#name ([^\n]+)"))
        assert(not result[key], "Duplicate chapter")
        result[key] = body
    end
    return result
end
local source = read(root .. "/Guide/Loader.lua")
local first = assert(source:find("local function applies(", 1, true))
local last = assert(source:find("addon.applies = applies", first, true))
local production = source:sub(first, last + #"addon.applies = applies" - 1)
local function filter(body, race, class, faction)
    local addon = {game="WOTLK", player={race=race, class=class, faction=faction, season=0}}
    local env = setmetatable({addon=addon, race=race, class=class, aCache={},
        strupper=string.upper, UnitLevel=function() return 1 end,
        UnitSex=function() return 2 end}, {__index=_G})
    local chunk = assert(loadstring(production)); setfenv(chunk,env); chunk()
    local active, lines = false, {}
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local raw = line:match("^(.-)%-%-") or line
        local condition = raw:match("<<%s*(.-)%s*$")
        if raw:match("^%s*step[%s<]*$") or raw:match("^%s*step%s*<<") then
            active = not condition or addon.applies(condition)
            if active then lines[#lines+1] = "step" end
        elseif active and (not condition or addon.applies(condition)) then
            local text = raw:gsub("%s*<<.*$", ""):match("^%s*(.-)%s*$")
            if text ~= "" then lines[#lines+1] = text end
        end
    end
    return table.concat(lines,"\n")
end
local function actions(text)
    local result = {}
    local wanted = {accept=true,turnin=true,complete=true,collect=true,use=true,buy=true,abandon=true}
    for line in text:gmatch("[^\n]+") do
        local tag = line:match("^%.(%a+)")
        if wanted[tag] and not line:match("^%.complete 8346,") then result[#result+1]=line end
    end
    return table.concat(result,"\n")
end
local profiles = {
    {"Alliance","Human","WARRIOR,PALADIN,ROGUE,PRIEST,MAGE,WARLOCK"},
    {"Alliance","Dwarf","WARRIOR,PALADIN,HUNTER,ROGUE,PRIEST"},
    {"Alliance","Gnome","WARRIOR,ROGUE,MAGE,WARLOCK"},
    {"Alliance","NightElf","WARRIOR,HUNTER,ROGUE,PRIEST,DRUID"},
    {"Alliance","Draenei","WARRIOR,PALADIN,HUNTER,PRIEST,MAGE,SHAMAN"},
    {"Horde","Orc","WARRIOR,HUNTER,ROGUE,SHAMAN,WARLOCK"},
    {"Horde","Troll","WARRIOR,HUNTER,ROGUE,PRIEST,MAGE,SHAMAN"},
    {"Horde","Tauren","WARRIOR,HUNTER,SHAMAN,DRUID"},
    {"Horde","Scourge","WARRIOR,ROGUE,PRIEST,MAGE,WARLOCK"},
    {"Horde","BloodElf","PALADIN,HUNTER,ROGUE,PRIEST,MAGE,WARLOCK"},
}
if arg[4] == "--fixtures" then
    return {chapters=chapters, filter=filter, profiles=profiles,inputPath=inputPath}
end
local checked, racials = 0, 0
for _, family in ipairs({"classic","tbc"}) do
    local before = chapters(inputPath(beforeRoot,family))
    local after = chapters(inputPath(afterRoot,family))
    for key, old in pairs(before) do
        local new = assert(after[key], "Chapter removed: " .. key)
        local faction = key:find(" Guides (A)|",1,true) and "Alliance" or "Horde"
        for _, p in ipairs(profiles) do
            if p[1] == faction and (family == "tbc" or (p[2] ~= "Draenei" and p[2] ~= "BloodElf")) then
                for class in p[3]:gmatch("[^,]+") do
                    local a, b = filter(old,p[2],class,faction), filter(new,p[2],class,faction)
                    assert(actions(a) == actions(b), key .. ": quest/reward changes for " .. p[2] .. " " .. class)
                    local racial = key:match("|1%-6 Eversong Woods$")
                    if not racial and class ~= "HUNTER" and class ~= "WARLOCK" then
                        assert(a == b, "Pet repair changed an unrelated class: " .. key .. " " .. class)
                    end
                    if racial and p[2] == "BloodElf" then
                        local _, count = b:gsub("%.complete 8346,1", "")
                        assert(count == 1, "Racial objective missing/duplicated for " .. class)
                        local pickup = assert(b:find(".accept 8346",1,true))
                        local objective = assert(b:find(".complete 8346,1",1,true))
                        local turnin = assert(b:find(".turnin 8346",1,true))
                        assert(pickup < objective and objective < turnin)
                        assert(b:find("living Mana Wyrm",1,true))
                        racials = racials + 1
                    end
                    checked = checked + 1
                end
            end
        end
        after[key] = nil
    end
    assert(next(after) == nil, "Unexpected new chapter")
end
assert(racials == 6)
print("Targeted content preservation passed: " .. checked ..
    " faction/class chapter views; six racial objectives; unrelated classes and quest rewards preserved.")
