return function(root)
    local v=assert(loadfile(root.."/tests/hardcore-label-loading.lua"))()(root)
    local function guide(first)
        return {key="label-fixture",group="RestedXP Hardcore Guides (H)",name="Fixture",hardcore=true,
            steps={first,{elements={{tag="complete",first="788"}}},{elements={{tag="turnin",first="788"}}}}}
    end
    v.verify(guide({optional=true,completewith="missing",elements={{tag="use",first="1"}}}),1,"optional-equipment")
    v.verify(guide({completewith="missing",elements={{tag="hs",first=""}}}),1,"hearth-wait")
    v.verify(guide({optional=true,completewith="missing",elements={{tag="cast",first="2580"}}}),1,"optional-tracking")
    local g=guide({optional=true,completewith="missing",elements={{tag="use",first="1"}}})
    g.steps={g.steps[1]}
    v.verify(g,1,"optional-equipment")
    for _,bad in ipairs({
        {completewith="missing",elements={{tag="use",first="1"}}},
        {optional=true,completewith="missing",elements={{tag="complete",first="788"}}},
        {optional=true,completewith="missing",elements={{tag="turnin",first="788"}}},
    }) do
        assert(not pcall(v.verify,guide(bad),1,"optional-equipment"),"Unsafe fallback received approval")
    end
    assert(v.count()==4)
    local emergency=guide({completewith="Stolensupplies",elements={{sourceLine=
        "+|cRXP_WARN_Bind your|r |T133728:0|t[Faintly Glowing Skull] |cRXP_WARN_and|r |T134712:0|t[Really Sticky Glue]|cRXP_WARN_. Save them for emergency situations|r"}}})
    emergency.name="06-13 Tauren"
    emergency.steps[2].elements={{tag="complete",first="837"},{tag="complete",first="837"}}
    v.verify(emergency,1,"manual-emergency-binding")
    local recruit=guide({sticky=true,completewith="EnterST",dungeon="ST",elements={{
        tag="subzone",first="1417",sourceLine=".subzone 1417 >> Now you should be looking for a group to Sunken Temple"}}})
    recruit.name="54-56 Un'Goro Crater"
    recruit.steps[2].elements={{tag="fly",first="Ratchet"}}
    v.verify(recruit,1,"sunken-temple-recruitment")
    emergency.steps[1].elements[1].sourceLine="+Do a required action"
    assert(not pcall(v.verify,emergency,1,"manual-emergency-binding"),"Generic manual fallback approved")
    recruit.steps[2].elements={{tag="turnin",first="788"}}
    assert(not pcall(v.verify,recruit,1,"sunken-temple-recruitment"),"Recruitment borrowed a quest destination")
    recruit.steps[2].elements={{tag="fly",first="Ratchet"}}
    recruit.steps[1].dungeon="DM"
    assert(not pcall(v.verify,recruit,1,"sunken-temple-recruitment"),"Recruitment borrowed another dungeon")
    local graph=assert(loadfile(root.."/tests/hardcore-label-graph.lua"))()
    local cycle=guide({label="a",requires="b",elements={}})
    cycle.steps[2].label,cycle.steps[2].requires="b","a"
    assert(not pcall(graph,cycle,"classic","Orc/WARRIOR"),"Cyclic dependencies passed publication checks")
    cycle.steps[2].requires=nil
    graph(cycle,"classic","Orc/WARRIOR") -- Forward, acyclic dependency is valid.
    local foreign=guide({completewith="RTB",elements={}})
    foreign.name="11-13 Loch Modan (Dwarf/Gnome)"
    assert(not pcall(graph,foreign,"classic","Dwarf/WARRIOR"),"Missing branch-local destination borrowed foreign evidence")
    print("Production label fallbacks passed: optional retirement, blocking hearth, terminal next and unsafe-action rejection.")
end
