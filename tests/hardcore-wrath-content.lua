-- lua5.1 tests/hardcore-wrath-content.lua ROOT GUIDE_DIRECTORY
-- Cold-cache titles use the production title extractor, not display-only
-- comparison. Structural repair assertions supplement the full route matrix.
local root,directory=assert(arg[1]),assert(arg[2])
local function read(path)
    local f=assert(io.open(path,"rb")); local text=f:read("*a"):gsub("\r\n","\n"); f:close(); return text
end
local factory=assert(loadfile(root.."/tests/quest-automation-audit.lua"))
setfenv(factory,setmetatable({arg={root,"--fixtures"}},{__index=_G}))
local f=factory()()
local names
f.addon.guideLocalization={RegisterEnglishNames=function(_,data) names=data.quests end}
f.load("DB/wotlk/guideEnglishNames_335.lua")
assert(names and names[1218]=="Marsh Frog Legs","Committed quest-name fixture was not merged")
local titles,frogs,jaina=0,0,0
for _,family in ipairs({"Classic","TBC","Curated"}) do
    local source=read(directory.."/Hardcore-"..family..".lua")
    assert(not source:find("Maatparm",1,true),"Modern renamed NPC survived")
    assert(not source:match("%.isOnQuest%s+5867%f[%D]"),"Item ID used as a quest gate")
    assert(not source:match("%.turnin%s+64038%f[%D]"),"Unavailable Dark Portal reward survived")
    assert(not source:match("%.zoneskip%s+209,1"),"SFK still uses the unsupported map predicate")
    assert(not source:match("%.zoneskip%s+30[45]%f[%D]"),"SM still uses unsupported map predicates")
    for body in source:gmatch("RXPGuides%.RegisterGuide%(%[%[(.-)%]%]%)") do
        local title=assert(body:match("#name ([^\n]+)"))
        for line in body:gmatch("[^\n]+") do
            local id,text=line:match("^%s*%.accept%s+(%d+).- ?>>%s*(.*)")
            id=tonumber(id)
            if id and names[id] then
                text=text:gsub("%s*<<.*$",""):gsub("%s*%-%-.*$","")
                local actual=f.addon.GetGuideAcceptTitle({text=text,questId=id})
                assert(actual==names[id],family.."/"..title..": cold-cache title differs for "..id.."/"..tostring(actual))
                titles=titles+1
            end
            local payload=line:match("^%s*%.goto%s+([^<]+)")
            if payload then
                payload=payload:gsub("%s*>>.*$",""):gsub("%s*%-%-.*$","")
                local _,commas=payload:gsub(",","")
                assert(commas<=4,"Excess waypoint arguments remain")
            end
        end
        if family=="Classic" and body:find(".accept 1218 ",1,true) then
            local pickup=assert(body:find(".accept 1218 ",1,true))
            local objective=assert(body:find(".complete 1218,1",pickup,true))
            local reward=assert(body:find(".turnin 1218 ",objective,true))
            assert(body:find(".accept 1206 ",reward,true),"Jarl follow-up moved ahead of required reward")
            assert(body:find("Marsh Frog Legs (10)",objective,true),"Missing ten-leg requirement")
            assert(not body:find(".collect 3713,3,1218",1,true),"Obsolete spice preparation survived")
            frogs=frogs+1
        end
        if family=="TBC" and (title=="38-40 Dustwallow Marsh" or title=="45-45 Tanaris") then
            for _,tag in ipairs({"accept","turnin","abandon","isOnQuest","isQuestTurnedIn"}) do
                assert(not body:match("%."..tag.."%s+1122[23]%f[%D]"),"Unavailable Jaina branch survived")
            end
            assert(body:find("Menethil",1,true) and body:find("Dun Algaz",1,true) and body:find("Deeprun Tram",1,true))
            if title=="38-40 Dustwallow Marsh" then
                local reward=assert(body:find(".turnin 11142",1,true))
                local arrival=assert(body:find(".zone Stormwind City >>Reach Stormwind",reward,true))
                assert(body:find(".turnin 3636",arrival,true) and body:find(".turnin 1448",arrival,true))
                local ironforge=assert(body:find(".zone Ironforge >>Reach Ironforge",arrival,true))
                assert(body:find(".target Dink",ironforge,true) and body:find(".target Ginny Longberry",ironforge,true))
            else
                assert(body:find(".bindlocation 513,1",1,true) and body:find(".cooldown item,6948,>2,1",1,true))
                local arrival=assert(body:find(".zone Ironforge >>Reach Ironforge",1,true))
                assert(body:find(".target Dink",arrival,true),"No-teleport Mage lost training")
            end
            jaina=jaina+1
        end
    end
end
assert(frogs==2 and jaina==2,"Targeted changed-chain inventory differs")
assert(titles>5000,"Cold-cache title coverage unexpectedly decreased")
print("Hardcore Wrath content passed: "..titles.." production cold-cache titles, both frog chains and both ordinary Jaina continuations.")
