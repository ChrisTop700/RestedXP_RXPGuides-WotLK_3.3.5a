-- Offline evidence consumer. The PowerShell entry point verifies SHA-256 and
-- the exact policy/profile inventory first. This visitor also checks content
-- at use time and executes the production loader for EVERY affected step.
return function(root,path)
    local cases,seen={},{}
    local header="family\tcanonicalGuide\tfield\tlabel\tkind\tsourceHash\tsourceAdler\tprofiles\treason"
    local file=assert(io.open(path,"rb"))
    local text=file:read("*a"):gsub("\r\n","\n"); file:close()
    local first=true
    for line in text:gmatch("[^\n]+") do
        if first then assert(line==header,"Invalid label evidence schema"); first=false
        else
            local fields={}
            for value in (line.."\t"):gmatch("([^\t]*)\t") do fields[#fields+1]=value end
            assert(#fields==9,"Malformed label evidence")
            local family,guide,field,label,kind,sha,adler,profiles,reason=unpack(fields)
            assert(family=="classic" or family=="tbc" or family=="curated","Foreign evidence family")
            assert(field=="completewith" and label~="" and guide~="" and reason~="","Incomplete evidence")
            assert(kind=="optional-equipment" or kind=="optional-tracking" or kind=="hearth-wait" or
                kind=="manual-emergency-binding" or kind=="sunken-temple-recruitment","Unknown evidence kind")
            assert(#sha==64 and sha:match("^[0-9a-f]+$") and tonumber(adler),"Invalid evidence hash")
            local key=table.concat({family,guide,field,label},"\t")
            assert(not cases[key],"Duplicate evidence identity")
            local allowed={}
            local previous
            for profile in profiles:gmatch("[^;]+") do
                assert(profile:match("^%a+/%u+$") and not allowed[profile] and
                    (not previous or previous<profile),"Invalid evidence profile inventory")
                allowed[profile]=true; previous=profile
            end
            assert(previous,"Empty profile inventory")
            cases[key]={kind=kind,adler=tonumber(adler),profiles=allowed,sha=sha,reason=reason}
        end
    end
    assert(not first,"Empty evidence")
    local verifier=assert(loadfile(root.."/tests/hardcore-label-loading.lua"))()(root)
    local hashes={}
    local function canonical(source)
        return source:gsub("\r\n","\n"):match("^%s*(.-)%s*$").."\n"
    end
    local function check(guide,index,family,profile,field,label,source)
        local key=table.concat({family,guide.key,field,label},"\t")
        local case=cases[key]
        if not case then return false end
        assert(case.profiles[profile],"Unexpected profile in reviewed label case: "..profile)
        assert(type(source)=="string","Label evidence requires exact source content")
        if not hashes[source] then
            local a,b=1,0
            local body=canonical(source)
            for n=1,#body do a=(a+body:byte(n))%65521; b=(b+a)%65521 end
            hashes[source]=b*65536+a
        end
        assert(hashes[source]==case.adler,"Stale label evidence: chapter content changed")
        verifier.verify(guide,index,case.kind)
        seen[key]=seen[key] or {}; seen[key][profile]=true
        return true,case.sha
    end
    local function finish()
        for key,case in pairs(cases) do
            for profile in pairs(case.profiles) do
                assert(seen[key] and seen[key][profile],"Missing reviewed label scenario: "..key.." "..profile)
            end
        end
        return verifier.count()
    end
    local function selected(source,family,profile)
        local name=assert(source:match("#name ([^\n]+)")):gsub("^(%d)-(%d%d?)",function(low,high)
            return string.format("%02d-%02d",tonumber(low),tonumber(high))
        end)
        for key,case in pairs(cases) do
            local f,g=key:match("^([^\t]+)\t([^\t]+)")
            if f==family and g:sub(-#name-1)=="|"..name and case.profiles[profile] then return true end
        end
        return false
    end
    return {check=check,finish=finish,selected=selected}
end
