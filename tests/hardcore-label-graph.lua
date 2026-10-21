-- Runs on production-parsed branches, before missing-label normalization.
-- Labels in another race/class branch or family are never considered here.
return function(guide,family,profile)
    local repaired={}
    local labels={}
    for i,step in ipairs(guide.steps) do
        if step.label then
            if step.label:match("335$") then assert(not labels[step.label],"Ambiguous new branch-local anchor") end
            labels[step.label]=i
        end
    end
    if (family=="tbc" or family=="curated") and guide.name=="42-43 Stranglethorn Vale part 2" then
        for _,step in ipairs(guide.steps) do
            for _,e in ipairs(step.elements) do
                if e.tag=="subzone" and tostring(e.first)=="378" then
                    assert(step.optional and not step.completewith and step.dungeonskip=="RFD",
                        "Camp Taurajo arrival became a cross-chapter sticky or lost its dungeon gate")
                end
            end
        end
    end
    local visited,active={},{}
    local function visit(index)
        assert(not active[index],"Cyclic #requires dependencies in "..guide.key)
        if visited[index] then return end
        active[index]=true
        local target=labels[guide.steps[index].requires]
        if target then visit(target) end
        active[index]=nil;visited[index]=true
    end
    for i in ipairs(guide.steps) do visit(i) end
    local checks={
        {"classic","19-20 Redridge","ExitSW"},
        {"classic","59-60 Winterspring/Silithus part 2","Grindto60"},
        {"curated","59-60 Winterspring/Silithus part 2","Grindto60"},
        {"classic","23-25 Hillsbrad","FlytoUC"},
        {"classic","31-34 Hillsbrad/Arathi","AcceptAgony","accept","509"},
        {"classic","06-13 Tauren","Bloodhoofturnins1"},
        {"classic","06-13 Tauren","Entersilverpine","zone","Silverpine Forest"},
        {"classic","06-13 Tauren","ReagentPouch335","complete","1525"},
        {"classic","06-13 Tauren","Stones","complete","771"},
        {"classic","15-19 The Barrens","PlainstriderBeaks335","complete","844"},
        {"curated","15-19 The Barrens","PlainstriderBeaks335","complete","844"},
        {"classic","58-59 Felwood/Winterspring","COTF","accept","4421"},
        {"classic","43-45 Tanaris/Dustwallow","TanarisFieldSampling335","complete","654"},
        {"tbc","20-21 Darkshore","DeeprunDM","subzone","2257"},
        {"tbc","20-21 Darkshore","MoonbrookAssembly335","subzone","20"},
        {"tbc","20-21 Darkshore","DeadminesMageExit335","cast","3561"},
        {"tbc","20-21 Darkshore","RedridgeRendevous","turnin","2281"},
        {"tbc","30-31 Wetlands","StormwindVendor335","bronzetube"},
        {"tbc","52-53 Azshara","ForestSongDeparture335","fly","Forest Song"},
        {"tbc","06-10 Eversong Woods","UndercityOrb335","zone","Undercity"},
        {"tbc","06-12 Mulgore","Stones","complete","771"},
        {"tbc","06-12 Mulgore","BloodhoofReturn335","subzone","222"},
        {"tbc","06-12 Mulgore","BloodhoofCleanup335","turnin","766"},
        {"tbc","10-12 Eversong Woods","AmaniTurnins"},
        {"tbc","14-16 The Barrens","PorttoSilvermoon","zone","Silvermoon City"},
        {"tbc","29-31 Thousand Needles","FlyOrg2","fly","Orgrimmar"},
        {"curated","29-31 Thousand Needles","FlyOrg2","fly","Orgrimmar"},
        {"curated","43-45 Dustwallow Marsh part 2","DrazZilbReward335","turnin","1172"},
        {"classic","01-06 Shadowglen","htraining","train","1978"},
        {"classic","01-06 Orc/Troll","Rwag2","train","1757"},
        {"classic","11-13 Loch Modan (Dwarf/Gnome)","RTB","turnin","6392"},
        {"classic","01-06 Tauren","CallofEarth","turnin","1520"},
        {"classic","19-20 Redridge","FlyR","fly","Redridge"},
        {"classic","47-49 Tanaris","DWMpickups2","accept","1170"},
        {"tbc","50-51 Searing Gorge","SearingAccept","accept","7722"},
        {"classic","06-13 Orc/Troll","Scarletrings","complete","374"},
        {"classic","06-13 Undead","Scarletrings","complete","374"},
        {"classic","30-32 Duskwood","FlytoSouthshoreA","fly","Wetlands"},
        {"classic","30-32 Duskwood","Finished","hs"},
        {"classic","38-39 Swamp of Sorrows","ReclaimersDesolace","turnin","1457"},
        {"classic","11-13 Darkshore (Night Elf)","start","hs"},
        {"tbc","01-06 Mulgore","CallofEarth","turnin","1520"},
        {"tbc","35-37 STV","BBend","turnin","189"},
        {"tbc","38-38 Swamp of Sorrows","NethergardeFlight335","fp","Nethergarde"},
        {"tbc","42-43 Stranglethorn Vale part 2","BloodSailPart1","turnin","209"},
        {"curated","42-43 Stranglethorn Vale part 2","BloodSailPart1","turnin","209"},
        {"tbc","45-46 Feralas","OrgrimmarStops335","turnin","3002"},
        {"curated","45-46 Feralas","OrgrimmarStops335","turnin","3002"},
    }
    if profile=="Scourge/WARLOCK" then
        checks[#checks+1]={family,"10-12 Eversong Woods","FalconPMTrain2","train","6222"}
    end
    if guide.name=="38-39 Dustwallow Marsh" or guide.name=="39-41 Hillsbrad/Alterac/Arathi part 2" then
        for _,step in ipairs(guide.steps) do
            for _,e in ipairs(step.elements) do
                if e.tag=="complete" and tostring(e.first)=="1113" then
                    assert(step.completewith==(profile:match("^Scourge/") and "Bosses" or "Compendium"),
                        "Hearts of Zeal borrowed the unavailable Undead Compendium quest")
                    assert(labels[step.completewith],"Scarlet Monastery cleanup lost its destination")
                end
            end
        end
    end
    for _,case in ipairs(checks) do
        if family==case[1] and guide.name==case[2] then
            for i,step in ipairs(guide.steps) do
                if step.completewith==case[3] then
                    local target=assert(labels[case[3]],"Reviewed destination missing: "..case[3])
                    assert(target>i,"Reviewed forward anchor points backward: "..case[3])
                    local found=case[4]==nil
                    for _,e in ipairs(guide.steps[target].elements) do
                        if e.tag==case[4] and (not case[5] or tostring(e.first)==case[5]) then found=true end
                    end
                    assert(found,"Reviewed destination lost its action: "..case[3])
                    repaired[#repaired+1]=i
                end
            end
        end
    end
    if guide.name=="01-06 Undead" or guide.name=="01-06 Tirisfal Glades" then
        local class=profile:match("/([^/]+)$")
        for _,step in ipairs(guide.steps) do
            for _,e in ipairs(step.elements) do
                if e.tag=="goto" and e.sourceLine and e.sourceLine:find("32.22,65.64,8",1,true) then
                    assert(step.completewith==(class=="WARRIOR" and "Training1" or "Vendor"),
                        "Building approach borrowed another class's trainer")
                end
            end
        end
    end
    return repaired
end
