-- Historical previews and published files are alternative inputs. Reject
-- directories containing both so tests cannot silently inspect an old preview.
return function(directory,family,exists)
    local published={classic="Hardcore-Classic.lua",tbc="Hardcore-TBC.lua",curated="Hardcore-Curated.lua"}
    assert(published[family],"Unknown Hardcore family")
    exists=exists or function(path)
        local f=io.open(path,"rb"); if f then f:close(); return true end
        return false
    end
    local preview=directory.."/"..(family=="curated" and "Hardcore335.preview.lua" or "Hardcore-"..family..".preview.lua")
    local final=directory.."/"..published[family]
    local old,new=not not exists(preview),not not exists(final)
    assert(old~=new,"Expected exactly one preview or published input for "..family)
    return old and preview or final
end
