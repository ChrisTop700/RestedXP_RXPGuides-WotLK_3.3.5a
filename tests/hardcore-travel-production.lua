-- Real map/subzone directive bodies for the new ordinary-travel checkpoints.
return function(root)
    local factory=assert(loadfile(root.."/tests/quest-automation-audit.lua"))
    setfenv(factory,setmetatable({arg={root,"--fixtures"}},{__index=_G}))
    local fixture=factory()
    for _,localized in ipairs({false,true}) do
        local f=fixture()
        local map,subzone=1453,""
        local theramore=localized and "塞拉摩岛" or "Theramore Isle"
        local tram=localized and "矿道地铁" or "Deeprun Tram"
        f.addon.map={
            GetAreaInfo=function(id)
                assert(id==513 or id==2257)
                return id==513 and theramore or tram
            end,
            GetBestMapForUnit=function() return map end
        }
        f.env.GetSubZoneText=function() return subzone end
        f.env.GetZoneText=function() return localized and "尘泥沼泽" or "Dustwallow Marsh" end
        f:loadDirectives()
        local a=f.addon
        a.mapConversion={}
        a.GetMapId=function(zone)
            return ({Darkshore=1439,["Silverpine Forest"]=1421,["Stormwind City"]=1453,Ironforge=1455})[zone]
        end
        a.SetElementComplete=function(frame) frame.element.completed=true end
        for _,destination in ipairs({{"Darkshore",1439},{"Silverpine Forest",1421},{"Stormwind City",1453},{"Ironforge",1455}}) do
            map=1413
            local element=a.functions.zone(".zone","Ordinary travel",destination[1])
            element.step={active=true}
            local frame={element=element}
            a.functions.zone(frame)
            assert(not element.completed and not element.step.completed,
                "Travel completed before reaching its destination")
            map=nil
            a.functions.zone(frame)
            assert(not element.completed,"Unavailable map completed travel")
            map=destination[2]
            a.functions.zone(frame)
            assert(element.completed and element.step.completed)
        end
        local element=a.functions.subzone(".subzone","Ordinary travel","513")
        element.step={active=true}
        local frame={element=element}
        map,subzone=1445,""
        a.functions.subzone(frame)
        assert(not element.completed,"Entering Dustwallow alone completed Theramore arrival")
        subzone=theramore
        a.functions.subzone(frame)
        assert(element.completed,"Localized Theramore arrival did not complete")
        -- Reproduce the obsolete Monty guard with the production handler:
        -- inside the Tram, subzoneskip 2257 skips the whole quest step.
        subzone=""
        local old=a.functions.subzoneskip(".subzoneskip","","2257")
        old.step={active=true}
        a.functions.subzoneskip({element=old})
        assert(not old.step.completed)
        subzone=tram
        a.functions.subzoneskip({element=old})
        assert(old.step.completed,"Fixture did not reproduce the old Tram skip")
        -- Entry and platform arrival are separate: entering subzone 2257
        -- cannot establish which end of the Tram contains the player.
        local arrival=a.functions.subzone(".subzone","Enter the Tram","2257")
        arrival.step={active=true}
        subzone=""
        a.functions.subzone({element=arrival})
        assert(not arrival.completed)
        subzone=tram
        a.functions.subzone({element=arrival})
        assert(arrival.completed)
        assert(#f.calls==0,"Travel check initiated a quest action")
    end
    local branches=0
    -- The repaired Tauren checkpoint must wait for actual arrival, unless
    -- the unchanged riding/Thunder Bluff predicates explicitly skip it.
    do
        local f=fixture()
        local map,subzone,rank=1413,"",75
        f.addon.map={GetAreaInfo=function(id) assert(id==378); return "Camp Taurajo" end,
            GetBestMapForUnit=function() return map end}
        f.env.GetSubZoneText=function() return subzone end
        f.env.GetZoneText=function() return "The Barrens" end
        f:loadDirectives()
        local a=f.addon
        a.mapConversion={}
        a.GetMapId=function(name) assert(name=="Thunder Bluff"); return 1456 end
        a.GetSkillLevel=function() return rank end
        a.SetElementComplete=function(frame) frame.element.completed=true end
        for _,r in ipairs({false,0,75}) do
            for _,m in ipairs({1413,1456}) do
                for _,arrived in ipairs({false,true}) do
                    rank=r or nil; map=m; subzone=arrived and "Camp Taurajo" or ""
                    local step={active=true,optional=true}
                    local arrival=a.functions.subzone(".subzone","Travel to Camp Taurajo","378")
                    local skill=a.functions.skill(".skill","","riding","<75","1")
                    local zone=a.functions.zoneskip(".zoneskip","","Thunder Bluff")
                    for _,e in ipairs({arrival,skill,zone}) do e.step=step end
                    a.functions.skill({element=skill}); a.functions.zoneskip({element=zone})
                    a.functions.subzone({element=arrival})
                    assert(not not (step.completed or arrival.completed)==(arrived or m==1456 or r==0),
                        "Taurajo travel completed without arrival or an explicit existing skip")
                end
            end
        end
        assert(#f.calls==0,"Travel check performed quest automation")
    end
    for _,mode in ipairs({false,true}) do
        for _,instance in ipairs({"DM","WC","BFD","RFD","ZF","BRD"}) do
            for _,enabled in ipairs({false,true}) do
                for _,negative in ipairs({false,true}) do
                    local f=fixture()
                    f.load("Core/Addon.lua")
                    f:loadDirectives()
                    local a=f.addon
                    a.settings.profile.hardcore=mode
                    a.settings.profile.dungeons={[instance]=enabled}
                    a.player.faction="Alliance"
                    a.currentGuideGroup="Fixture"
                    a.currentGuideName="Dungeon gate fixture"
                    a.error=error
                    a.dungeons={}
                    a.gameVersion=30300
                    a.locale={Get=function(text) return text end}
                    f.load("DB/wotlk/dungeonData_335.lua")
                    assert(a.dungeonStats.Alliance.BRD==nil and a.dungeonStats.Horde.BRD==nil,
                        "BRD must not receive an invented recommendation score")
                    for alias,canonical in pairs({Gnomer="GNOMER",Stockades="STOCKS",
                        Ulda="ULDA",["Blackrock Depths"]="BRD"}) do
                        local name,tag=a.GetDungeonName(alias)
                        assert(name and tag==canonical,"Real dungeon alias did not resolve")
                    end
                    assert(a.GetDungeonName("not a dungeon")==nil,"Unknown dungeon accepted")
                    f.env.RXPCData.guideMetaData={enabledDungeons={Alliance={}},dungeonGuides={}}
                    a.step={}
                    local ok,why=pcall(a.functions.dungeon,".dungeon unknown","","unknown")
                    assert(not ok and tostring(why):find("Invalid dungeon name",1,true),
                        "Production parser did not reject an unknown dungeon")
                    a.functions.dungeon(".dungeon","",(negative and "!" or "")..instance)
                    assert(not not a.stepLogic.DungeonCheck(a.step)==(enabled~=negative),
                        "Dungeon take/skip branch differs from production")
                    assert(a.stepLogic.HardcoreCheck(a.step),"Ordinary travel hidden by mode")
                    a.step.softcore=true
                    assert(a.stepLogic.HardcoreCheck(a.step)==not mode,"Softcore shortcut visible in Hardcore")
                    a.step.softcore=nil
                    a.step.hardcore=true
                    assert(a.stepLogic.HardcoreCheck(a.step)==mode,"Hardcore branch mode was ignored")
                    assert(#f.calls==0)
                    branches=branches+1
                end
            end
        end
    end
    print("Hardcore production travel predicates passed: absent/wrong maps, localized arrival and "..
        branches.." actual dungeon/mode branches.")
end
