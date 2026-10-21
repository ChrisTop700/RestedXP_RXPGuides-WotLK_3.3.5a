return function(root)
    local body="fixture\n"
    local a,b=1,0
    for n=1,#body do a=(a+body:byte(n))%65521; b=(b+a)%65521 end
    local hash=b*65536+a
    local header="family\tcanonicalGuide\tfield\tlabel\tkind\tsourceHash\tsourceAdler\tprofiles\treason\n"
    local function row(profile,kind)
        return table.concat({"classic","fixture","completewith","missing",kind or "optional-equipment",
            string.rep("a",64),tostring(hash),profile or "Orc/WARRIOR","Explicit optional equipment reminder."},"\t").."\n"
    end
    local function make(text)
        local chunk=assert(loadfile(root.."/tests/hardcore-label-evidence.lua"))
        local env=setmetatable({io={open=function(path)
            assert(path=="fixture")
            return {read=function() return text or header..row() end,close=function() end}
        end}},{__index=_G})
        setfenv(chunk,env)
        return chunk()(root,"fixture")
    end
    local function guide(tag)
        return {key="fixture",group="RestedXP Hardcore Guides (H)",name="Fixture",hardcore=true,
            steps={{optional=true,completewith="missing",elements={{tag=tag or "use",first="1"}}},
                {elements={{tag="complete",first="788"}}},{elements={{tag="turnin",first="788"}}}}}
    end
    local e=make()
    assert(e.check(guide(),1,"classic","Orc/WARRIOR","completewith","missing",body))
    assert(e.finish()==1)
    local function rejects(fn) assert(not pcall(fn),"Invalid label evidence was accepted") end
    rejects(function() make(header..row()..row()) end)
    rejects(function() make(header..row("Orc/WARRIOR;Orc/WARRIOR")) end)
    rejects(function() make(header..row(nil,"blanket")) end)
    rejects(function() local v=make(); v.check(guide(),1,"classic","Human/WARRIOR","completewith","missing",body) end)
    rejects(function() local v=make(); v.check(guide(),1,"classic","Orc/WARRIOR","completewith","missing",body.."changed") end)
    rejects(function() local v=make(); v.check(guide("turnin"),1,"classic","Orc/WARRIOR","completewith","missing",body) end)
    rejects(function() make().finish() end)
    local other=make()
    assert(not other.check(guide(),1,"tbc","Orc/WARRIOR","completewith","missing",body),"Borrowed another family's evidence")
    assert(not other.check(guide(),1,"classic","Orc/WARRIOR","completewith","another",body),"Borrowed another label's evidence")
    rejects(other.finish)
    local input=assert(loadfile(root.."/tests/hardcore-input-path.lua"))()
    assert(input("fixture","classic",function(p) return p:find("preview",1,true)~=nil end)=="fixture/Hardcore-classic.preview.lua")
    assert(input("fixture","curated",function(p) return p=="fixture/Hardcore-Curated.lua" end)=="fixture/Hardcore-Curated.lua")
    rejects(function() input("fixture","tbc",function() return true end) end)
    rejects(function() input("fixture","tbc",function() return false end) end)
    print("Label evidence rejects changed content, unexpected/missing profiles, duplicate identities, unsafe actions and cross-family borrowing.")
end
