-- Production loader/completion evidence, not a substitute implementation.
return function(root)
    local fixture=assert(loadfile(root.."/tests/hardcore-load-contract.lua"))()(root,true)
    local verified=0
    local function verify(guide,index,kind)
        local old=assert(guide.steps[index])
        local manual=kind=="manual-emergency-binding"
        local recruitment=kind=="sunken-temple-recruitment"
        assert(kind=="optional-equipment" or kind=="optional-tracking" or kind=="hearth-wait" or manual or recruitment,
            "Unsupported harmless-fallback evidence")
        if manual then
            assert(guide.name=="06-13 Tauren" and old.completewith=="Stolensupplies",
                "Emergency reminder evidence is chapter-specific")
            assert(#old.elements==1 and old.elements[1].tag==nil and old.elements[1].sourceLine==
                "+|cRXP_WARN_Bind your|r |T133728:0|t[Faintly Glowing Skull] |cRXP_WARN_and|r |T134712:0|t[Really Sticky Glue]|cRXP_WARN_. Save them for emergency situations|r",
                "Emergency reminder text/actions changed")
            local objectives=0
            for _,e in ipairs(assert(guide.steps[index+1]).elements) do
                if e.tag=="complete" then assert(tostring(e.first)=="837"); objectives=objectives+1 end
            end
            assert(objectives==2,"Emergency reminder no longer precedes Encroachment objectives")
        elseif recruitment then
            assert(guide.name=="54-56 Un'Goro Crater" and old.completewith=="EnterST" and old.dungeon=="ST",
                "Recruitment evidence is chapter/dungeon-specific")
            assert(#old.elements==1 and old.elements[1].tag=="subzone" and
                tostring(old.elements[1].first)=="1417" and old.elements[1].sourceLine==
                ".subzone 1417 >> Now you should be looking for a group to Sunken Temple",
                "Recruitment reminder changed into another action")
            local flight=false
            for _,e in ipairs(assert(guide.steps[index+1]).elements) do
                if e.tag=="fly" then assert(e.first=="Ratchet"); flight=true end
                assert(e.tag~="accept" and e.tag~="complete" and e.tag~="turnin","Recruitment retirement changed")
            end
            assert(flight,"Recruitment reminder lost its Ratchet departure")
        elseif kind=="hearth-wait" then
            local hearth=false
            for _,e in ipairs(old.elements) do
                if e.tag=="hs" or e.tag=="hsbatching" then hearth=true end
            end
            assert(hearth,"Hearth evidence applied to an ordinary step")
        else
            assert(old.optional,"Only explicitly optional reminders qualify")
            local allowed=kind=="optional-equipment" and
                {use=true,itemcount=true,itemStat=true,xp=true} or
                {cast=true,usespell=true,train=true}
            for _,e in ipairs(old.elements) do
                local manualEquip=kind=="optional-equipment" and e.tag==nil and
                    type(e.sourceLine)=="string" and e.sourceLine:find("+|cRXP_WARN_Equip the|r",1,true)==1
                assert(allowed[e.tag] or manualEquip or (e.tag==nil and e.textOnly==true),
                    "Unexpected action in optional reminder: "..tostring(e.tag).." in "..tostring(guide.key)..
                    " step "..index..": "..tostring(e.sourceLine))
            end
        end
        local g=fixture.load(guide)
        local step=g.steps[index]
        local a,env,data=fixture.addon,fixture.env,fixture.data
        assert(step.completewith=="next","Production loader did not normalize missing label")
        assert(#g.steps==#guide.steps,"Loading removed an authored step")
        for n,s in ipairs(g.steps) do
            assert(#s.elements==#guide.steps[n].elements,"Loading changed authored actions")
            for j,e in ipairs(s.elements) do
                assert(e.tag==guide.steps[n].elements[j].tag and
                    e.first==guide.steps[n].elements[j].first,"Loading changed an action identity")
            end
        end
        step.active=true
        step.completed=nil
        for _,e in ipairs(step.elements) do
            e.completed,e.skip=nil,nil
            if kind=="hearth-wait" and (e.tag=="hs" or e.tag=="hsbatching") then e.hearthPending=true end
        end
        env.activeSteps={step}
        data.currentStep=index
        data.stepSkip={}
        local advances=0
        a.guideState.QueueAdvance=function() advances=advances+1 end
        a.lastStepUpdate=0
        a.UpdateStepCompletion()
        assert(not step.completed and not data.stepSkip[index] and advances==0,
            "Fallback completed an unfinished current instruction")
        if kind=="hearth-wait" then
            assert(step.waitForHearth and not step.sticky,"Hearth became an optional sticky reminder")
        elseif index<#g.steps then
            assert(step.sticky,"Optional reminder was made blocking")
            data.currentStep=index+2
            if g.steps[index+1].sticky then data.stepSkip[index+1]=true end
            a.UpdateStepCompletion()
            assert(data.stepSkip[index] and not step.active and advances==0,
                "Optional reminder failed to retire without advancing the route")
        else
            assert(not step.sticky,"Terminal next-reference cannot wait for a nonexistent step")
        end
        for n,s in ipairs(g.steps) do
            if n~=index then
                assert(s.completed==guide.steps[n].completed,"Fallback completed another instruction")
            end
        end
        verified=verified+1
    end
    return {verify=verify,count=function() return verified end}
end
