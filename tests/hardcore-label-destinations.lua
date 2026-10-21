-- Exercise repaired destinations through real loading and completion, without
-- replaying protected actions. Client-state predicates have separate tests.
return function(root)
    local f=assert(loadfile(root.."/tests/hardcore-load-contract.lua"))()(root,true)
    local count=0
    local function verify(guide,index)
        local g=f.load(guide)
        local step=g.steps[index]
        local target=assert(g.labels[step.completewith],"Repaired label normalized to a fallback")
        assert(target>index,"Repaired destination must be forward in this branch")
        local a,d=f.addon,f.data
        step.active,step.completed=true,nil
        for _,e in ipairs(step.elements) do
            e.completed,e.skip=nil,nil
            if e.tag=="hs" or e.tag=="hsbatching" then e.hearthPending=true end
        end
        f.env.activeSteps={step}
        d.stepSkip={}
        local advances=0
        a.guideState.QueueAdvance=function() advances=advances+1 end
        a.lastStepUpdate=0
        for _,position in ipairs({index,target}) do
            d.currentStep=position
            a.UpdateStepCompletion()
            assert(not step.completed and not d.stepSkip[index] and advances==0,
                "Repaired reference retired before its destination was passed: "..g.key.." "..step.completewith)
        end
        if step.waitForHearth then
            assert(not step.sticky,"Repaired hearth became an optional sticky")
        else
            assert(step.sticky,"Repaired grouping stopped being sticky")
            d.currentStep=target+1
            if g.steps[target].sticky then d.stepSkip[target]=true end
            a.UpdateStepCompletion()
            assert(d.stepSkip[index] and not step.active and advances==0,
                "Repaired reference failed to retire at its destination")
        end
        for n,s in ipairs(g.steps) do
            if n~=index then assert(s.completed==guide.steps[n].completed,"Reference completed another step") end
        end
        count=count+1
    end
    return {verify=verify,count=function() return count end}
end
