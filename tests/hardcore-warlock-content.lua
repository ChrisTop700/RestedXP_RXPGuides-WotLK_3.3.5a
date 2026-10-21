-- lua5.1 tests/hardcore-warlock-content.lua ROOT BEFORE AFTER
-- Real production class/race predicates, with explicit allowed action changes.
local root, beforeRoot, afterRoot = assert(arg[1]), assert(arg[2]), assert(arg[3])
local chunk = assert(loadfile(root .. "/tests/hardcore-candidate-content.lua"))
setfenv(chunk, setmetatable({arg={root,beforeRoot,afterRoot,"--fixtures"}}, {__index=_G}))
local fixture = chunk()
local removed = {[1485]=true,[1499]=true,[1470]=true,[1598]=true,[1599]=true,[8344]=true}
local books = {[16302]=true,[16316]=true,[16321]=true,[16346]=true,[16351]=true,[16357]=true}
local starters = {
    ["1-6 Orc/Troll"]=788,["1-6 Durotar"]=788,["1-6 Undead"]=364,["1-6 Tirisfal Glades"]=364,
    ["1-6 Northshire"]=33,["1-11 Elwynn Forest"]=33,
    ["1-6 Coldridge Valley"]=179,["1-10 Dun Morogh"]=179,["1-6 Eversong Woods"]=8326,
}
local function actions(text, orc)
    local result = {}
    for line in text:gmatch("[^\n]+") do
        local tag, id = line:match("^%.(%a+)%s+(%d+)")
        id = tonumber(id)
        local quest = tag == "accept" or tag == "turnin" or tag == "complete"
        local item = tag == "collect" or tag == "use" or tag == "buy"
        -- Orc Warlocks now take the already-authored valid792 ->794 route.
        -- The redundant early boar objective is removed with the Imp detour.
        if (quest and not removed[id] and not (orc and
            (id == 792 or id == 794 or (tag == "complete" and (id == 788 or id == 789))))) or
            (item and not books[id]) then
            result[#result+1] = line
        end
    end
    return table.concat(result,"\n")
end
local checked, startersChecked = 0, 0
for _, family in ipairs({"classic","tbc"}) do
    local before = fixture.chapters(fixture.inputPath(beforeRoot,family))
    local after = fixture.chapters(fixture.inputPath(afterRoot,family))
    for key, old in pairs(before) do
        local new = assert(after[key], "Chapter removed: " .. key)
        local faction = key:find(" Guides (A)|",1,true) and "Alliance" or "Horde"
        local name = key:match("|(.+)$")
        for _, p in ipairs(fixture.profiles) do
            if p[1] == faction and (family == "tbc" or (p[2] ~= "Draenei" and p[2] ~= "BloodElf")) then
                for class in p[3]:gmatch("[^,]+") do
                    local a = fixture.filter(old,p[2],class,faction)
                    local b = fixture.filter(new,p[2],class,faction)
                    if class ~= "WARLOCK" then
                        assert(a == b, "Warlock repair changed unrelated class: " .. key .. " " .. class)
                    else
                        local orc = name == "1-6 Durotar" or name == "1-6 Orc/Troll"
                        local aa, bb = actions(a,orc), actions(b,orc)
                        if aa ~= bb then
                            local x,y={},{}
                            for line in aa:gmatch("[^\n]+") do x[#x+1]=line end
                            for line in bb:gmatch("[^\n]+") do y[#y+1]=line end
                            for i=1,math.max(#x,#y) do
                                if x[i] ~= y[i] then
                                    error("Valid actions changed: "..key.." "..p[2].." at "..i..
                                        ": "..tostring(x[i]).." -> "..tostring(y[i]))
                                end
                            end
                        end
                        for id in pairs(books) do
                            assert(not b:match("%.(collect) " .. id .. "%D") and
                                not b:match("%.use " .. id .. "%D"), "Obsolete grimoire action")
                        end
                        if starters[name] then
                            local pickup = assert(b:find(".accept "..starters[name],1,true))
                            local training = assert(b:find(".train 688 >>",1,true))
                            local summon = assert(b:find(".cast 688 >>",1,true))
                            assert(pickup < training and training < summon, "Imp acquisition order: "..key)
                            for id in pairs(removed) do
                                assert(not b:match("%.accept " .. id .. "%D") and
                                    not b:match("%.complete " .. id .. "%D") and
                                    not b:match("%.turnin " .. id .. "%D"), "Unavailable Imp quest")
                            end
                            if orc then
                                local accept = assert(b:find(".accept 792",1,true))
                                local objective = assert(b:find(".complete 792,1",1,true))
                                local reward = assert(b:find(".turnin 792",1,true))
                                local followup = assert(b:find(".accept 794",1,true))
                                assert(accept < objective and objective < reward and reward < followup)
                                assert(b:find(".complete 788,1",1,true), "Boar objective lost")
                                assert(b:find(".complete 789,1",1,true), "Scorpid objective lost")
                            end
                            if name == "1-6 Eversong Woods" then
                                local _, n = b:gsub("%.complete 8346,1","")
                                assert(n == 1, "Racial objective duplicated")
                                assert(b:find("#label RunRamp",1,true) and b:find("#label ArcaneSliver",1,true))
                                assert(b:find(".turnin 8338",1,true) < b:find(".accept 8335",1,true),
                                    "Upstream early sliver circuit was replaced by curated itinerary")
                            end
                            startersChecked = startersChecked + 1
                        end
                    end
                    checked = checked + 1
                end
            end
        end
        after[key] = nil
    end
    assert(next(after) == nil, "Unexpected new chapter")
end
assert(startersChecked > 0)
print("Warlock production-filtered preservation: " .. checked .. " chapter views, " ..
    startersChecked .. " starter views; unrelated classes, valid rewards and acquisition ordering passed.")
