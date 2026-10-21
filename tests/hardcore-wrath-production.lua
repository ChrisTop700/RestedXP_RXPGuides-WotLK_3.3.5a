-- Actual bundled map/flight data and production directive bodies. The legacy
-- client supplies location/node observations; the test does not replace the
-- resolver or assume that parsing a flight means the character has learned it.
return function(root)
    local factory = assert(loadfile(root .. "/tests/quest-automation-audit.lua"))
    setfenv(factory, setmetatable({arg={root,"--fixtures"}}, {__index=_G}))
    local fixture = factory()
    local input=assert(io.open(root.."/tools/data/Hardcore-Locations335.json","rb"))
    local required={}
    for id in input:read("*a"):gmatch('"id"%s*:%s*(%d+)') do required[tonumber(id)]=true end
    input:close()
    assert(next(required),"Missing committed location facts")
    local checks = 0
    for _,locale in ipairs({"enUS","deDE","esES","frFR","koKR","ruRU","zhCN","zhTW"}) do
        local f=fixture()
        f.env.GetLocale=function() return locale end
        f.env.DongleStub=function() return {} end
        f.env.LibStub=nil
        f.env.geterrorhandler=function() return error end
        f.load("Compat/LocationLocales335.lua")
        f.load("libs/HBD335/HereBeDragons-335.lua")
        local a=f.addon
        assert(type(a.map.GetAreaInfo)=="function", "Actual map facade did not initialize")
        f:loadDirectives()
        a.currentGuideName="Hardcore location compatibility"
        a.error=error
        a.SetElementComplete=function(frame) frame.element.completed=true end
        local subzone, zone="", ""
        f.env.GetSubZoneText=function() return subzone end
        f.env.GetZoneText=function() return zone end
        for id,english in pairs(a.LegacyAreaNames335) do
          if required[id] then
            local localized=a.map.GetAreaInfo(id)
            assert(localized==a.LocalizeLegacyLocationName(english), "Conflicting runtime area identity")
            for _,tag in ipairs({"subzone","subzoneskip"}) do
                local e=a.functions[tag]("."..tag,"",tostring(id))
                e.step={active=true}
                subzone,zone="", ""
                a.functions[tag]({element=e})
                assert(not e.completed and not e.step.completed, "Missing observation completed an area predicate: "..locale.."/"..id.."/"..tag.."/"..tostring(localized))
                subzone=localized
                a.functions[tag]({element=e})
                assert(e.completed or e.step.completed, "Localized area did not complete: "..locale.."/"..id)
                checks=checks+1
            end
            local home=a.functions.home(".home","Set your Hearthstone",tostring(id))
            home.step={active=true}
            f.env.GetBindLocation=function() return "not this inn" end
            a.functions.home({element=home},"BAG_UPDATE")
            assert(not home.completed)
            f.env.GetBindLocation=function() return localized end
            a.functions.home({element=home},"BAG_UPDATE")
            assert(home.completed,"Localized home predicate failed")
            for flags=0,1 do
                local gate=a.functions.bindlocation(".bindlocation","",tostring(id),tostring(flags))
                gate.step={active=true}
                a.functions.bindlocation({element=gate})
                assert(not not gate.step.completed==(flags==0),"Localized binding guard changed polarity")
            end
          end
        end
        for _,id in ipairs({209,796}) do
            for _,mapped in ipairs({false,true}) do
                a.map.GetBestMapForUnit=function() return mapped and 310 or nil end
                local e=a.functions.subzone(".subzone","",tostring(id))
                e.step={active=true}
                subzone,zone="",a.map.GetAreaInfo(id)
                a.functions.subzone({element=e})
                assert(e.completed, "Instance arrival wrongly required an unavailable map")
                local old=a.functions.subzone(".subzone","",tostring(id),"2")
                old.step={active=true}
                a.functions.subzone({element=old})
                assert(not not old.completed == not mapped, "Did not reproduce the obsolete map-dependent entry")
            end
        end
    end
    do
        local f=fixture()
        f.load("Compat/Bootstrap.lua")
        f.load("DB/wotlk/db.lua")
        f:loadDirectives()
        local a=f.addon
        a.mapConversion={}
        a.error=error
        a.currentGuideName="Corrected coordinate arguments"
        f.env.LibStub=function() return {
            GetWorldCoordinatesFromZone=function(_,x,y,map) return x,y,map end,
            GetZoneCoordinatesFromWorld=function(_,x,y) return x,y end,
        } end
        f.load("Guide/Directives/Handlers.lua")
        local file=assert(io.open(root.."/UI/Map.lua","rb"))
        local source=file:read("*a");file:close()
        local first=assert(source:find("local function GetMapCoefficients",1,true))
        local marker='addon.mapId["EPLNew"] = addon.mapId["Eastern Plaguelands"]'
        local last=assert(source:find(marker,first,true))+#marker-1
        f.env.addon=a
        setfenv(assert(loadstring(source:sub(first,last))),f.env)()
        for _,v in ipairs({
            {"The Barrens",46.07,79.19,40}, {"Undercity",59.91,11.32,20},
            {"Un'Goro Crater",20.6,60.4,70}, {"Un'Goro Crater",22.2,41.0,70},
            {"Un'Goro Crater",46.0,56.6,70}, {"Burning Steppes",49.6,55.4,60},
            {"Silithus",51.6,16.4,70},
        }) do
            local e=a.functions["goto"](".goto","",v[1],tostring(v[2]),tostring(v[3]),tostring(v[4]),"0")
            assert(e.zone==a.mapId[v[1]] and e.x==v[2] and e.y==v[3] and e.radius==v[4],
                "Corrected coordinates/radius differ in the real parser")
        end
    end
    for faction,nodes in pairs({
        Alliance={ ["Sentinel Hill"]=4,["Lakeshire"]=5,["Astranaar"]=28,["Talonbranch Glade"]=65,
            ["Rut'theran Village"]=27,["Theramore"]=32,["Stormwind"]=2 },
        Horde={ ["Bloodvenom Post"]=48,["The Sepulcher"]=10,["Spinebreaker Ridge"]=141 },
    }) do
        local f=fixture()
        f.env.UnitFactionGroup=function() return faction end
        f.load("Compat/Bootstrap.lua")
        f.load("DB/wotlk/flightData.lua")
        f:loadDirectives()
        local a=f.addon
        a.player.faction=faction
        a.currentGuideName="Hardcore flights"
        a.error=error
        for name,id in pairs(nodes) do
            local actual,ambiguous=a.ResolveLegacyFlightPath(name)
            assert(actual==id and not ambiguous, "Wrong real flight resolution: "..name.."/"..tostring(actual))
            local e=a.functions.fly(".fly","",name)
            assert(e.fpId==id and not e.fpAmbiguous)
            e.step={active=true}
            a.IsAutomationElementReady=function() return true end
            a.settings.profile.enableFPAutomation=true
            f.env.IsShiftKeyDown=function() return false end
            a.TAXIMAP_OPENED=function() end
            a.flightInfo={[1]=id}
            a.comms.PrettyDebug=function() end
            local taken=0
            f.env.NumTaxiNodes=function() return 1 end
            f.env.TaxiNodeName=function() return name end
            f.env.TakeTaxiNode=function() taken=taken+1 end
            f.env.GameTooltip={IsForbidden=function() return false end, Hide=function() end}
            for _,state in ipairs({"NONE","CURRENT","REACHABLE"}) do
                f.env.TaxiNodeGetType=function() return state end
                a.functions.fly({element=e},"TAXIMAP_OPENED")
                assert(taken==(state=="REACHABLE" and 1 or 0), "Unlearned/current flight was taken")
            end
        end
        if faction=="Alliance" then
            local id,ambiguous=a.ResolveLegacyFlightPath("Westfall")
            assert(id==nil and ambiguous,"Wrath Westfall ambiguity was weakened")
        end
    end
    do
        local f=fixture()
        local legs=9
        f.env.GetNumQuestLogEntries=function() return 1 end
        f.env.ExpandQuestHeader=function() end
        f.env.RXPCompatGetQuestLogTitle=function()
            return "Marsh Frog Legs",35,nil,false,false,false,nil,1218
        end
        f.env.GetNumQuestLeaderBoards=function() return 1 end
        f.env.GetQuestLogLeaderBoard=function()
            return "Marsh Frog Legs: "..legs.."/10","item",legs==10
        end
        f.env.GetInventoryItemID=function() end
        f.env.INVSLOT_LAST_EQUIPPED=19
        f:loadDirectives()
        f.env.bit.rshift=function(n,bits) return math.floor(n/2^bits) end
        f.load("Guide/Directives/Handlers.lua")
        f.load("Guide/State.lua")
        local a=f.addon
        a.lastStepUpdate,a.questCompleteItems=f.now,{}
        a.UpdateStepText,a.QueueMessage=function() end,function() end
        a.comms.AnnounceStepEvent=function() end
        a.GetQuestName=function() return "Marsh Frog Legs" end
        f.env.RXPCData.questObjectivesCache={[0]=0}
        f.env.RXPCData.stepSkip,f.env.RXPCData.completedWaypoints={},{}
        f.log[1218]=true
        local e=f:element("complete",1218,"Marsh Frog Legs")
        e.flags,e.obj=0,1
        local frame={element=e,step=f.step}
        a.UpdateQuestCompletionData(frame)
        assert(not e.completed,"Nine frog legs satisfied the ten-leg objective")
        legs=10
        a.UpdateQuestCompletionData(frame)
        assert(e.completed,"Ten live frog legs did not satisfy the Wrath objective")
        assert(#f.calls==0,"Objective evaluation initiated quest automation")
    end
    print("Hardcore Wrath production paths passed: "..checks.." localized area predicates, mapped/unmapped instances, exact learned-flight checks, corrected coordinates and ten-leg objective.")
end
