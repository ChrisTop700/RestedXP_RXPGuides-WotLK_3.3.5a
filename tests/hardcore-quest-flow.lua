-- Called by the production-parser route matrix, not by a second guide parser.
-- Static action ordering is not quest availability or gameplay certification.
return function(reportPath,root,evidencePath)
    local validateGraph=root and assert(loadfile(root.."/tests/hardcore-label-graph.lua"))()
    local evidence=evidencePath and assert(loadfile(root.."/tests/hardcore-label-evidence.lua"))()(root,evidencePath)
    local destinations=root and assert(loadfile(root.."/tests/hardcore-label-destinations.lua"))()(root)
    local findings, counts = {}, {classic=0,tbc=0,curated=0}
    local checks,chainCases=0,0
    local function enabled(a,step)
        return a.stepLogic.HardcoreCheck(step) and a.stepLogic.SeasonCheck(step)
            and a.stepLogic.DungeonCheck(step) and a.stepLogic.XpRateCheck(step)
    end
    local function inspect(a,guide,family,profile,source)
        if validateGraph then
            for _,index in ipairs(validateGraph(guide,family,profile)) do destinations.verify(guide,index) end
        end
        local labels={}
        for _,step in ipairs(guide.steps) do
            if step.label then labels[step.label]=true end
        end
        -- These are real-parser results, including per-line class/race
        -- conditions. A universal reward step must not acquire a dependency
        -- on a class-only objective filtered out of that player's guide.
        local race,class=profile:match("^([^/]+)/(.+)$")
        if (family=="tbc" or family=="curated") and guide.key:match("|51%-52 Blasted Lands$") then
            local reward
            for _,step in ipairs(guide.steps) do
                for _,e in ipairs(step.elements) do
                    if e.tag=="turnin" and tonumber(e.first)==2581 then reward=step end
                end
            end
            assert(reward,"Blasted Lands reward was removed")
            assert(reward.requires==(class=="WARRIOR" and "Helboars" or nil),
                "Helboar dependency must be Warrior-only")
        end
        if family=="tbc" and class=="ROGUE" and
            guide.key:match("|24%-27 Redridge/Duskwood$") then
            local reward
            for _,step in ipairs(guide.steps) do
                if step.label=="KlavenEnd" then reward=step end
            end
            assert(reward,"Klaven's Tower reward anchor was removed")
            assert(reward.requires==(race~="Dwarf" and "AntiVenomEnd2" or nil),
                "Anti-Venom dependency must follow the non-Dwarf branch")
        end
        if family=="classic" and class=="DRUID" and
            guide.key:match("|15%-18 Darkshore$") then
            assert(labels.earthroot,"Final Earthroot pickup has no dependency anchor")
        end
        -- Mode/dungeon-hidden labels still exist in the production parsed
        -- table. Never require a label to be currently active.
        for index,step in ipairs(guide.steps) do
            local applicable=a.stepLogic.HardcoreCheck(step) and
                a.stepLogic.SeasonCheck(step) and a.stepLogic.PhaseCheck(step)
            for _,field in ipairs({"requires","completewith"}) do
                local ref=step[field]
                if applicable and type(ref)=="string" and ref~="next" and ref~="previous"
                    and not tonumber(ref) and not labels[ref] then
                    local key=family.."\t"..guide.key.."\t"..field.."\t"..ref
                    local finding=findings[key]
                    if not finding then
                        finding={profiles={},routeProfiles={},optionalOnly=true}
                        findings[key]=finding
                        counts[family]=counts[family]+1
                    end
                    finding.profiles[profile]=true
                    if not step.optional then finding.optionalOnly=false end
                    local approved,hash
                    if evidence then approved,hash=evidence.check(guide,index,family,profile,field,ref,source) end
                    if approved then finding.evidenceHash=hash else finding.unresolved=true end
                end
            end
        end
        -- Unknown quest/item/player state is deliberately not inferred here.
        -- These tests cover the unconditional production mode/dungeon layer.
        local previous=a.settings.profile.dungeons
        for _,tag in ipairs({"DM","WC","BFD","RFD","ZF","BRD","RFC","ST","SFK"}) do
            for _,selected in ipairs({false,true}) do
                a.settings.profile.dungeons={[tag]=selected}
                for _,step in ipairs(guide.steps) do
                    if step.dungeon==tag and not selected then
                        assert(not enabled(a,step),"Disabled dungeon action remained eligible")
                    elseif step.dungeonskip==tag and selected then
                        assert(not enabled(a,step),"Negative dungeon alternative remained eligible")
                    end
                    if step.softcore then
                        assert(not enabled(a,step),"Softcore shortcut remained eligible in Hardcore")
                    end
                end
            end
        end
        a.settings.profile.dungeons=previous
        checks=checks+1
    end
    local function route(family,guides,profile)
        local visited={}
        for _,guide in ipairs(guides) do visited[guide.key]=true end
        for key,finding in pairs(findings) do
            local f,g=key:match("^([^\t]+)\t([^\t]+)")
            if f==family and visited[g] and finding.profiles[profile] then finding.routeProfiles[profile]=true end
        end
    end
    local function chains(a,resolvePath,family,race,class,faction)
        -- One representative per faction; the outer route matrix separately
        -- covers all class/race/rate paths. Each family owns its own state.
        if class~="WARRIOR" or
            (faction=="Alliance" and race~="Human") or
            (faction=="Horde" and race~="Orc") then return end
        local specs=faction=="Alliance" and {
            {tag="DM",ids={167,168,2040}},
            {tag="BFD",ids={1200}},
            {tag="RFD",ids={3525}},
            {tag="ZF",ids={3042}},
            {tag="BRD",ids=family~="tbc" and {4126} or {}},
        } or {
            {tag="WC",ids={1486,1487}},
            {tag="BFD",ids={6561}},
            {tag="RFD",ids={3525}},
            {tag="ZF",ids={3042}},
            {tag="BRD",ids=family=="classic" and {4134} or {}},
        }
        local previous=a.settings.profile.dungeons
        for _,spec in ipairs(specs) do
            for _,selected in ipairs({false,true}) do
                a.settings.profile.dungeons={[spec.tag]=selected}
                local observations={}
                local ordinal=0
                -- Resolve the actual racial route with this selection. Sorting
                -- every registered chapter could borrow a reward from an
                -- alternative chapter the character will never visit.
                for _,guide in ipairs(resolvePath()) do
                    for _,step in ipairs(guide.steps) do
                        if enabled(a,step) then
                            for _,element in ipairs(step.elements) do
                                ordinal=ordinal+1
                                local id=tonumber(element.first)
                                if id and (element.tag=="accept" or element.tag=="complete" or element.tag=="turnin") then
                                    local record=observations[id] or {}
                                    observations[id]=record
                                    record[element.tag]=record[element.tag] or ordinal
                                    if element.tag=="turnin" then
                                        local guarded=false
                                        for _,gate in ipairs(step.elements) do
                                            if (gate.tag=="isQuestComplete" or gate.tag=="isOnQuest") and
                                                tonumber(gate.first)==id then guarded=true end
                                        end
                                        record.unguardedReward=record.unguardedReward or not guarded
                                    end
                                end
                            end
                        end
                    end
                end
                for _,id in ipairs(spec.ids) do
                    local r=observations[id]
                    -- Deviate Hides also has an authored !WC outside-cave
                    -- alternative. It must keep its reward when WC is off.
                    if selected or (id==1486 and r) then
                        assert(r and r.accept and r.complete and r.turnin,
                            family.." "..spec.tag..": missing pickup/objective/reward for "..id)
                        assert(r.accept<r.complete and r.complete<r.turnin,
                            family.." "..spec.tag..": source-order mismatch for "..id)
                    else
                        -- An explicit carried/completed-quest reward remains
                        -- legitimate after deselecting the dungeon. It may not
                        -- create a new pickup or objective for this route.
                        assert(not r or (not r.accept and not r.complete and
                            r.turnin and not r.unguardedReward),
                            "Disabled "..spec.tag.." still requires quest "..id.." in "..family)
                    end
                end
                chainCases=chainCases+1
            end
        end
        a.settings.profile.dungeons=previous
    end
    local function finish()
        local verified=evidence and evidence.finish() or 0
        local keys={}
        for key in pairs(findings) do keys[#keys+1]=key end
        table.sort(keys)
        if reportPath then
            -- Test artifacts only; never allow this test to overwrite sources.
            assert(reportPath:match("^build/[%w%._/%-]+%.tsv$") and
                not reportPath:find("..",1,true),"Report must be a relative build/*.tsv path")
            local f=assert(io.open(reportPath,"wb"))
            f:write("family\tcanonicalGuide\tfield\tlabel\tclassification\tprofiles\tevidenceHash\tautomaticRouteProfiles\tmanualSelectionOnlyProfiles\n")
            for _,key in ipairs(keys) do
                local finding=findings[key]
                local profiles={}
                for p in pairs(finding.profiles) do profiles[#profiles+1]=p end
                table.sort(profiles)
                local automatic,manual={},{}
                for _,p in ipairs(profiles) do
                    local list=finding.routeProfiles[p] and automatic or manual
                    list[#list+1]=p
                end
                local classification=not finding.unresolved and "verified-harmless" or
                    (finding.optionalOnly and "optional-reference-review" or "required-reference-review")
                f:write(key,"\t",classification,"\t",table.concat(profiles,";"),"\t",finding.evidenceHash or "",
                    "\t",table.concat(automatic,";"),"\t",table.concat(manual,";"),"\n")
            end
            f:close()
        end
        print("Hardcore scoped gate/quest checks: "..checks.." parsed views; "..chainCases..
            " selected/unselected racial-path chain cases; raw missing references: Classic="..
            counts.classic..", TBC="..counts.tbc..", curated="..counts.curated..". No gameplay certification.")
        local unresolved=0
        for _,finding in pairs(findings) do if finding.unresolved then unresolved=unresolved+1 end end
        print("Label evidence: "..verified.." production-loading checks; "..unresolved.." unresolved references remain.")
        if destinations then print("Repaired destination loading/progression checks: "..destinations.count()) end
        return unresolved
    end
    return {inspect=inspect,chains=chains,finish=finish,route=route,
        selected=function(source,family,profile)
            assert(evidence,"Focused label checks require bound evidence")
            return evidence.selected(source,family,profile)
        end}
end
