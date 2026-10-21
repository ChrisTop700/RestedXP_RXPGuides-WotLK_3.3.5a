-- lua5.1 tests/hardcore-travel-content.lua ROOT BEFORE AFTER
-- Production class/race filtering; exact preservation of non-travel actions.
local root,beforeRoot,afterRoot=assert(arg[1]),assert(arg[2]),assert(arg[3])
local ferries=arg[4]=="--ferries"
local chunk=assert(loadfile(root.."/tests/hardcore-candidate-content.lua"))
setfenv(chunk,setmetatable({arg={root,beforeRoot,afterRoot,"--fixtures"}},{__index=_G}))
local fixture=chunk()
local function withoutIncubus(text)
    local result,at={},1
    while at<=#text do
        local boundary=text:find("\nstep\n",at,true)
        local part=text:sub(at,boundary and boundary-1 or #text)
        local valid=part:find(".accept 1738",1,true) or part:find(".turnin 1716",1,true)
            or part:find(".turnin 1739",1,true)
        local exclusive=part:match("%.isOnQuest 6560[23]") or
            part:match("%.isQuestTurnedIn 65602") or part:match("%.collect 19030[78]") or
            part:match("%.complete 65602")
        if valid or not exclusive then
            part=part:gsub("%.isOnQuest 1739,65603",".isOnQuest 1739")
            part=part.."\n"
            -- Keep matching explicit rather than accepting arbitrary quest IDs.
            part=part:gsub("%.accept 6560[23][^\n]*\n",""):gsub("%.turnin 6560[23][^\n]*\n","")
            result[#result+1]=part
        end
        if not boundary then break end
        at=boundary+1
    end
    return table.concat(result,"\n")
end
local function actions(text,key)
    if ferries then text=withoutIncubus(text) end
    local result={}
    local wanted={accept=true,acceptmultiple=true,turnin=true,turninmultiple=true,
        complete=true,collect=true,use=true,buy=true,abandon=true,train=true,
        cast=true,vendor=true,fly=true,fp=true,home=true,hs=true}
    for line in text:gmatch("[^\n]+") do
        local replacedFlight=ferries and key:match("|20%-21 Darkshore$") and
            (line==".fly Stormwind>> Fly to Stormwind" or line==".fly Ironforge >> Fly to Ironforge")
        if not replacedFlight and (wanted[line:match("^%.(%a+)")] or line:match("^#label ") or
            line:match("^#completewith ") or line:match("^%.dungeon ") or
            line:match("^%.isOnQuest ")) then result[#result+1]=line end
    end
    return table.concat(result,"\n")
end
local views,changed=0,0
for _,family in ipairs({"classic","tbc"}) do
    local before=fixture.chapters(fixture.inputPath(beforeRoot,family))
    local after=fixture.chapters(fixture.inputPath(afterRoot,family))
    for key,old in pairs(before) do
        local new=assert(after[key],"Chapter removed: "..key)
        if ferries and key:match("|6%-12 Mulgore$") then
            -- Explicit syntax repair: the old text was not a valid dungeon
            -- name at all. Compare its intended conditional gate separately.
            local count
            old,count=old:gsub("%.dungeon RFC !Hunter !Druid",".dungeon RFC << !Hunter !Druid")
            assert(count==12,"Mulgore malformed-gate inventory changed")
        end
        if ferries and (key:match("|6%-12 Mulgore$") or key:match("|6%-13 Tauren$")) then
            -- The destination already exists; only its missing reference
            -- anchor is restored. All authored actions keep their order.
            new=new:gsub("[ \t]*#label TravelToTiragarde\n","")
        end
        if ferries and family=="classic" and key:match("|15%-18 Darkshore$") then
            new=new:gsub("[ \t]*#label earthroot\n","")
        end
        local faction=key:find(" Guides (A)|",1,true) and "Alliance" or "Horde"
        for _,p in ipairs(fixture.profiles) do
            if p[1]==faction and (family=="tbc" or (p[2]~="Draenei" and p[2]~="BloodElf")) then
                for class in p[3]:gmatch("[^,]+") do
                    local a=fixture.filter(old,p[2],class,faction)
                    local b=fixture.filter(new,p[2],class,faction)
                    assert(actions(a,key)==actions(b,key),"Travel edit changed actions or anchors: "..key.." "..class)
                    views=views+1
                    if a~=b then changed=changed+1 end
                end
            end
        end
        after[key]=nil
    end
    assert(not next(after),"Unexpected chapter added")
end
assert(changed>0,"Fixture did not exercise new travel instructions")
print("Travel production-filtered preservation passed: "..views.." chapter views; "..changed..
    " changed views; quest, item, training, flights, hearth, labels and dungeon gates retained.")
