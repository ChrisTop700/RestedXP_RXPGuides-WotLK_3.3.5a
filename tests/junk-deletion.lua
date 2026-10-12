return function(root)
    local file = assert(io.open(root .. "/Features/InventoryManager.lua", "rb"))
    local source = file:read("*a"); file:close()
    local first = assert(source:find("local function ReadJunkCandidate", 1, true))
    local last = assert(source:find("inventoryManager.itemsToOpen =", first, true))
    local function scenario(items)
        local state = {items = items, free = 0, enabled = true, deleted = {}, logs = {}, picks = 0}
        local manager = {bagUpdated = true, IsBagAutomationEnabled = function() return state.enabled end}
        local env = setmetatable({inventoryManager = manager,
            BACKPACK_CONTAINER = 0, NUM_BAG_FRAMES = 0,
            bit = {band = function(n) return n % 4 end},
            GetContainerNumFreeSlots = function() return state.free, state.family or 0 end,
            GetContainerNumSlots = function() return #state.items end,
            GetContainerItemID = function(_, slot) local i = state.items[slot]; return i and i.id end,
            GetContainerItemLink = function(_, slot) local i = state.items[slot]; return i and i.link end,
            GetContainerItemInfo = function(_, slot)
                local i = state.items[slot]; if not i then return end
                if state.tableAPI then return {stackCount = i.count, isLocked = i.locked} end
                return "texture", i.count, i.locked
            end,
            GetItemInfo = function(link)
                for _, i in pairs(state.items) do
                    if i.link == link then
                        return i.cached ~= false and "name" or nil, link, 0, nil, nil, nil, nil, i.max, nil, nil, i.price
                    end
                end
            end,
            GetProjectileSubclass = function() return nil end,
            IsJunk = function(id)
                if state.classify then return state.classify(id) end
                for _, i in pairs(state.items) do if i.id == id then return i.junk end end
            end,
            UnitIsDead = function() return state.dead end,
            InCombatLockdown = function() return state.combat end,
            GetCursorInfo = function()
                local i = state.cursor; if i then return "item", i.id, i.link end
            end,
            PickupContainerItem = function(_, slot)
                state.picks = state.picks + 1
                if state.pickupFails then return end
                state.cursor = state.wrongCursor or state.items[slot]
                state.cursorSlot = slot
            end,
            ClearCursor = function() state.cursor = nil end,
            DeleteCursorItem = function()
                if state.deleteFails then return end
                table.insert(state.deleted, state.cursor)
                state.items[state.cursorSlot] = nil
                state.cursor = nil
            end,
            addon = {guideTextColors = {RXP_WARN_ = "x"}, comms = {
                PrettyPrint = function(...) table.insert(state.logs, {...}) end}},
            L = function(s) return s end,
        }, {__index = _G})
        local chunk = assert(loadstring(source:sub(first, last - 1) ..
            " return FindJunk, DeleteItems, DeleteCheapestItem"))
        local find, delete, manual = setfenv(chunk, env)()
        return state, manager, find, delete, manual
    end
    local function item(id, count, price, max)
        return {id = id, link = "item:" .. id, count = count, price = price, max = max or 20, junk = true}
    end
    local s, m, find, delete, manual = scenario({item(1, 1, 10), item(2, 1, 50, 1)})
    find(); assert(m.deleteSlot == 1)
    delete(); assert(s.deleted[1].id == 1 and s.logs[1][3] == "item:1" and s.logs[1][4] == 1)

    s, m, find, delete = scenario({item(1, 20, 10), item(2, 1, 50, 1)})
    find(); assert(m.deleteSlot == 2) -- total stack cost, not unit price
    s.items[2] = item(3, 1, 500); s.items[2].junk = false
    delete(); assert(s.deleted[1].id == 1) -- never delete a stale replacement

    s, m, find, delete = scenario({item(1, 1, 10), item(2, 1, 50)})
    find(); s.free = 1; delete(); assert(#s.deleted == 0)
    s.free = nil; find(); assert(m.deleteBag == nil)

    s, m, find, delete = scenario({item(1, 1, nil), item(2, 1, 2)})
    find(); assert(m.deleteSlot == 2)
    s.items[1].price = 0; find(); assert(m.deleteSlot == 1) -- known zero is valid
    s.items[1].locked = true; find(); assert(m.deleteSlot == 2)
    s.items[1].locked = 0; s.tableAPI = true; find(); assert(m.deleteSlot == 1)
    s.items[1].cached = false; find(); assert(m.deleteSlot == 2)
    s.items[2].junk = false; find(); assert(m.deleteBag == nil)

    s, m, find, delete, manual = scenario({item(1, 1, 0)})
    s.family = 1; find(); assert(m.deleteBag == nil) -- cannot solve full bags by emptying a quiver
    manual(); assert(#s.deleted == 1)
    s, m, find = scenario({item(1, 1, 10), item(2, 2, 5)})
    find(); assert(m.deleteSlot == 1) -- stable bag/slot ordering for equal stack costs

    for _, flag in ipairs({"combat", "dead", "pickupFails", "deleteFails"}) do
        s, m, find, delete = scenario({item(1, 1, 10)})
        find(); s[flag] = true; delete()
        assert(#s.deleted == 0 and #s.logs == 0, flag)
    end
    s, m, find, delete = scenario({item(1, 1, 10)})
    find(); s.cursor = item(9, 1, 1); delete()
    assert(s.cursor.id == 9 and s.picks == 0)
    s.cursor = nil; s.wrongCursor = item(9, 1, 1); delete()
    assert(#s.deleted == 0 and s.cursor == nil)

    s, m, find, delete = scenario({item(1, 1, 10)})
    find(); s.enabled = false; delete(); assert(#s.deleted == 0)
    s, m, find, delete, manual = scenario({item(1, 1, 10)})
    s.free = 1; s.enabled = false; manual(nil, true); assert(#s.deleted == 0)
    manual(); assert(#s.deleted == 1) -- explicit keybinding still works with space

    s, m, find, delete = scenario({item(1, 1, 10)})
    find()
    local reads = 0
    s.classify = function() reads = reads + 1; return reads == 1 end
    delete(); assert(#s.deleted == 0) -- protection changed during revalidation
    print("Junk deletion regressions passed: stack value, cache, locks, revalidation, cursor and input guards.")
end
