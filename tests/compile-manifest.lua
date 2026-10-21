-- Syntax-only fallback for local Lua 5.1 runners without a separate luac.
assert(_VERSION == "Lua 5.1", "Manifest syntax validation requires Lua 5.1")
local count = 0
for path in io.lines(assert(arg[1], "Missing manifest file list")) do
    path = path:gsub("\r$", "")
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    if source:sub(1, 3) == "\239\187\191" then source = source:sub(4) end
    assert(loadstring(source, "@" .. path))
    count = count + 1
end
assert(count > 0, "Empty manifest syntax inventory")
print("Lua 5.1 manifest syntax passed: " .. count .. " files.")
