-- lua5.1 tests/hardcore-registration.lua ROOT UPSTREAM [CURATED]
-- Real registration queue, metadata and parser. Client directive bodies are
-- inert here; changed directives have separate production-handler tests.
local root, directory, curated = assert(arg[1]), assert(arg[2]), arg[3]
local inputPath=assert(loadfile(root.."/tests/hardcore-input-path.lua"))()
local newLoader = assert(loadfile(root .. "/tests/guide-loading.lua"))()(root,true)
local function read(path)
    local f=assert(io.open(path,"rb")); local text=f:read("*a"):gsub("\r\n","\n"); f:close(); return text
end
local families, blocks = {"classic","tbc"}, {}
if curated then families[#families+1]="curated" end
for _,family in ipairs(families) do
    blocks[family]={}
    local path=inputPath(family=="curated" and curated or directory,family)
    for body in read(path):gmatch("RXPGuides%.RegisterGuide%(%[%[(.-)%]%]%)") do
        blocks[family][#blocks[family]+1]=body
    end
end
local fixtureChunk=assert(loadfile(root.."/tests/hardcore-candidate-content.lua"))
setfenv(fixtureChunk,setmetatable({arg={root,directory,directory,"--fixtures"}},{__index=_G}))
local profiles=fixtureChunk().profiles
local core=read(root.."/Core/Addon.lua")
local predicateStart=assert(core:find("function addon.stepLogic.PhaseCheck",1,true))
local predicateEnd=assert(core:find("addon.facade:ExposeGlobal",predicateStart,true))
local predicates=core:sub(predicateStart,predicateEnd-1)
local ui=read(root.."/UI/GuideWindow.lua")
local activeStart=assert(ui:find("local function IsGuideActive(",1,true))
local activeEnd=assert(ui:find("addon.IsGuideActive = IsGuideActive",activeStart,true))
local active=ui:sub(activeStart,activeEnd+#"addon.IsGuideActive = IsGuideActive"-1)
local fetchStart=assert(ui:find("function addon:FetchGuide(",1,true))
local fetchEnd=assert(ui:find("function addon:LoadGuideTable(",fetchStart,true))
local prepareStart=assert(ui:find("function addon:PrepareGuideLoad335(",1,true))
local prepareEnd=assert(ui:find("function addon:LoadGuide(",prepareStart,true))
local fetch=ui:sub(fetchStart,fetchEnd-1)..ui:sub(prepareStart,prepareEnd-1)
local menuSource=assert(ui:match("function RXPFrame:GenerateMenuTable.-\nend"))
local selectSource=assert(ui:match("function addon:LoadGuideTable.-\nend"))
local registered, combinations, cached=0,0,0
local identities={}
for _,p in ipairs(profiles) do
    for class in (p[3]..",DEATHKNIGHT"):gmatch("[^,]+") do
        local a,env=newLoader(class,p[2],nil,p[1],1)
        a.stepLogic={}
        a.settings.profile={hardcore=true,phase=6,season=0,xprate=1,dungeons={},enableXpStepSkipping=true}
        a.player.season=0
        local level=1
        env.UnitLevel=function() return level end
        env.addon=a
        setfenv(assert(loadstring(predicates)),env)()
        setfenv(assert(loadstring(active)),env)()
        -- Opposite insertion orders must not merge identical chapter names.
        local order=class=="WARRIOR" and {"tbc","classic","curated"} or {"curated","classic","tbc"}
        for _,family in ipairs(order) do
            for _,body in ipairs(blocks[family] or {}) do a.RegisterGuide(body) end
        end
        local checkpoint={step=7}
        env.RXPCData.guideProgress.saved=checkpoint
        env.RXPCData.currentStep=7
        a.LoadEmbeddedGuides()
        local keys,seen={},{}
        for _,guide in pairs(a.guides) do
            assert(not keys[guide.key],"Family identity collided")
            keys[guide.key]=true
            assert(guide.group:find(p[1]=="Alliance" and "(A)" or "(H)",1,true),"Foreign faction registered")
            assert(guide.hardcore and not guide.softcore)
            local family=guide.group:find(" Classic ",1,true) and "classic" or
                (guide.group:find(" TBC ",1,true) and "tbc" or "curated")
            local row=table.concat({family,assert(guide.sourceName),guide.group,guide.subgroup or "",
                guide.name,guide.key},"\t")
            assert(not identities[guide.key] or identities[guide.key]==row,"Runtime identity differs between profiles")
            identities[guide.key]=row
            seen[family]=true
            assert(class~="DEATHKNIGHT","Death Knight starter registered")
            assert(not (family=="classic" and (p[2]=="Draenei" or p[2]=="BloodElf")),
                "Classic family registered for expansion race")
            local low,high=guide.name:match("^(%d+)%-(%d+)")
            for _,lv in ipairs({1,tonumber(low) or 1,tonumber(high) or 60}) do
                level=lv
                for _,rate in ipairs({1,1.2,1.5,2}) do
                    a.settings.profile.xprate=rate
                    -- Call the full production eligibility predicate, not a
                    -- season/rate-only imitation. Do not infer gameplay.
                    local result=a.IsGuideActive(guide)
                    -- The selected collection has no guide-level XP/maxlevel,
                    -- fresh-account or season-2 restrictions. All its chapters
                    -- must remain manually selectable, even below their range.
                    assert(not guide.xprate and not guide.maxlevel and
                        not guide.fresh and not guide.veteran and not guide.season,
                        "New eligibility policy requires explicit fixture expectations")
                    assert(result==true,"Eligible Hardcore chapter disappeared: "..guide.key)
                    guide.maxlevel=tostring(lv-1)
                    assert(not a.IsGuideActive(guide),"Production maxlevel gate was ignored")
                    guide.maxlevel=nil
                    combinations=combinations+1
                end
            end
            registered=registered+1
        end
        if class~="DEATHKNIGHT" then
            assert(seen.tbc and (not curated or seen.curated),"Eligible family disappeared")
            assert(not not seen.classic == (p[2]~="Draenei" and p[2]~="BloodElf"))
        else assert(next(a.guides)==nil) end
        assert(env.RXPCData.currentStep==7 and env.RXPCData.guideProgress.saved==checkpoint,
            "Registration mutated current progress")
        a.LoadEmbeddedGuides()
        for _,guide in pairs(a.guides) do assert(keys[guide.key],"Repeated registration changed identities") end
        if class==p[3]:match("^[^,]+") then
            -- Exercise the actual regular guide/minimap menu with Hardcore
            -- OFF; a picker-only test cannot prove the requested placement.
            local confirmation,loads=nil,0
            env.RXPFrame,env.L=a.RXPFrame,function(text) return text end
            env.fmt=string.format
            setfenv(assert(loadstring(assert(core:match("function addon.GetGuideTable.-\nend")))),env)()
            env.GAMEOPTIONS_MENU,env.CLOSE="Options","Close"
            env.IsGuideActive=a.IsGuideActive
            a.farmGuides=0
            a.GroupOverride=function(group) return group end
            a.GetGuideName=function(guide) return guide.name end
            a.services={Register=function() end}
            a.comms={ConfirmChoice=function(_,_,_,callback) confirmation=callback end,
                PopupNotification=function() end}
            local mode=assert(loadfile(root.."/Guide/Hardcore.lua"))
            setfenv(mode,env)("RXPGuides",a)
            a.LoadGuide=function(_,guide)
                if not a.hardcoreGuides:BeforeLoad(guide) then return end
                loads=loads+1
            end
            setfenv(assert(loadstring(selectSource.."\n"..menuSource)),env)()
            a.settings.profile.hardcore=false
            local menu=a.RXPFrame:GenerateMenuTable()
            local found={}
            local function visit(list,collection)
                for _,item in ipairs(list) do
                    local parent=collection
                    if item.text=="Validated & Fixed Guides" or item.text=="Original Upstream Guides" then parent=item.text end
                    if item.arg1 and item.arg1:find("RestedXP Hardcore",1,true) then
                        local guide=a.GetGuideTable(item.arg1,item.arg2)
                        assert(guide and a.IsGuideActive(guide) and item.func==a.LoadGuideTable)
                        local family=a.hardcoreGuides:GetFamily(guide)
                        local expected=guide.group:find("Original Guides - ",1,true) and "Original Upstream Guides" or "Validated & Fixed Guides"
                        assert(parent==expected,"Hardcore guide placed in the wrong regular collection")
                        if not found[family.id] then
                            item.func({},item.arg1,item.arg2)
                            assert(confirmation and not a.settings.profile.hardcore and loads==0,
                                "Regular menu selection bypassed mode confirmation")
                            -- Do not invoke the confirmation: closing it must be inert.
                            confirmation=nil
                        end
                        found[family.id]=true
                    end
                    if item.menuList then visit(item.menuList,parent) end
                end
            end
            visit(menu)
            assert(found.tbc and (not curated or found.curated),"Regular menu omitted an eligible family with mode off")
            assert(not not found.classic == (p[2]~="Draenei" and p[2]~="BloodElf"))
            assert(loads==0 and env.RXPCData.currentStep==7 and env.RXPCData.guideProgress.saved==checkpoint)
            a.settings.profile.hardcore=true
        end
        -- Reuse actual persisted metadata in a fresh loader, then exercise the
        -- production lazy-fetch/preflight path. A mock with pre-parsed steps
        -- cannot detect group/subgroup key changes during parsing.
        if class==p[3]:match("^[^,]+") then
            local b,e=newLoader(class,p[2],env.RXPCData,p[1],1)
            b.settings.profile=a.settings.profile
            b.stepLogic={}
            e.addon,e.fmt=b,string.format
            e.UnitFactionGroup=function() return p[1] end
            b.ScheduleTask=function() end
            b.comms={PrettyDebug=function() error("Cached fetch failed") end}
            setfenv(assert(loadstring(predicates)),e)()
            setfenv(assert(loadstring(active)),e)()
            setfenv(assert(loadstring(fetch)),e)()
            for _,family in ipairs(order) do
                for _,body in ipairs(blocks[family] or {}) do b.RegisterGuide(body) end
            end
            b.LoadEmbeddedGuides()
            local pending={}
            for _,g in pairs(b.guides) do pending[#pending+1]=g end
            for _,g in ipairs(pending) do
                assert(not g.steps,"Fixture failed to exercise metadata-only loading")
                local key=g.key
                local result=b:PrepareGuideLoad335(g)
                assert(result and result.steps and result.key==key,
                    "Cached canonical identity rejected by load preflight: "..key)
                cached=cached+1
            end
            assert(e.RXPCData.currentStep==7 and e.RXPCData.guideProgress.saved==checkpoint,
                "Preparing cached guides changed current progression")
        end
    end
end
if arg[4] then
    assert(arg[4]:match("^build/[%w%._/%-]+%.tsv$") and not arg[4]:find("..",1,true),
        "Identity export must be a build artifact")
    local rows={}
    for _,row in pairs(identities) do rows[#rows+1]=row end
    table.sort(rows)
    assert(#rows==(curated and 258 or 169),"Incomplete runtime identity export")
    local out=assert(io.open(arg[4],"wb"))
    out:write("family\tsourceName\tgroup\tsubgroup\tname\tkey\n",table.concat(rows,"\n"),"\n")
    out:close()
end
print("Hardcore real registration passed: "..registered.." guides across class/race fixtures; "..
    combinations.." full eligibility evaluations; "..cached.." real cached fetches; family isolation and expansion-race/DK exclusions.")
