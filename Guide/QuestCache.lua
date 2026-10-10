local _, addon = ...

local questCache = addon.questCache or {}
addon.questCache = questCache

function questCache:GetName(id)
    id = tonumber(id)
    if not id or not addon.GetQuestName then return nil end
    return addon.GetQuestName(id)
end

function questCache:GetObjectives(id, step, useCache)
    id = tonumber(id)
    if not id or not addon.GetQuestObjectives then return nil end
    return addon.GetQuestObjectives(id, step, useCache)
end

function questCache:GetNpcName(id)
    id = tonumber(id)
    if not id or not addon.GetNpcName then return nil end
    return addon.GetNpcName(id)
end

function questCache:GetItemName(id)
    id = tonumber(id)
    if not id or not addon.GetItemName then return nil end
    return addon.GetItemName(id)
end

function questCache:InvalidateTransient()
    if addon.ClearQuestCache then addon.ClearQuestCache() end
end

-- 3.3.5 offers quests by localized title only, and no stock API returns the
-- title of a quest that is not in the log yet, so non-English clients could
-- only auto-accept quests whose title had been cached from an earlier pickup.
-- A quest hyperlink on a hidden tooltip makes the client query the server,
-- which answers in the client's locale. Cache that title where quest-accept
-- automation and the gossip quest-ID index already look.
local TITLE_QUERY_OWNER = "quest-title-query"
local TITLE_QUERY_DELAY = 0.5
local TITLE_QUERY_ATTEMPTS = 6
local TITLE_QUERY_MAX_PENDING = 8
local titleTooltip
local pendingTitles, pendingTitleCount, failedTitles = {}, 0, {}

local function NeedsLocalizedTitles()
    local locale = GetLocale()
    return addon.gameVersion == 30300 and locale ~= "enUS" and locale ~= "enGB"
end

local function ReadServerQuestTitle(id)
    if not titleTooltip then
        titleTooltip = CreateFrame("GameTooltip", "RXPQuestTitleTooltip", nil,
                                   "GameTooltipTemplate")
    end
    titleTooltip:SetOwner(_G.WorldFrame, "ANCHOR_NONE")
    titleTooltip:ClearLines()
    local ok = pcall(titleTooltip.SetHyperlink, titleTooltip,
                     string.format("quest:%d:%d", id, UnitLevel("player") or 0))
    local line = _G.RXPQuestTitleTooltipTextLeft1
    local text = ok and line and line:GetText()
    titleTooltip:Hide()
    if type(text) ~= "string" or text == "" or text == _G.RETRIEVING_ITEM_INFO or
        text == _G.RETRIEVING_DATA then
        return
    end
    return text
end

local function StoreServerQuestTitle(id, title)
    if type(RXPCData) ~= "table" then return end
    RXPCData.questNameCache = type(RXPCData.questNameCache) == "table" and
                                  RXPCData.questNameCache or {}
    RXPCData.questNameCache[id] = title
    if type(RXPData) == "table" and type(RXPData.questNames) == "table" then
        RXPData.questNames[id] = title
    end
end

local function FinishTitleQuery(id)
    if pendingTitles[id] then
        pendingTitles[id] = nil
        pendingTitleCount = pendingTitleCount - 1
    end
end

function questCache:RequestLocalizedTitle(id)
    id = tonumber(id)
    if not id or id <= 0 or pendingTitles[id] or failedTitles[id] or
        pendingTitleCount >= TITLE_QUERY_MAX_PENDING or
        not NeedsLocalizedTitles() or type(RXPCData) ~= "table" then
        return
    end
    local cache = RXPCData.questNameCache
    if type(cache) == "table" and cache[id] then return end

    pendingTitles[id] = 0
    pendingTitleCount = pendingTitleCount + 1
    local function Attempt()
        local title = ReadServerQuestTitle(id)
        if title then
            FinishTitleQuery(id)
            StoreServerQuestTitle(id, title)
            -- Let an already open quest giver re-evaluate with the new title.
            addon.questAutoAccept = true
        elseif pendingTitles[id] < TITLE_QUERY_ATTEMPTS then
            pendingTitles[id] = pendingTitles[id] + 1
            addon.scheduler:After(TITLE_QUERY_OWNER, "title-" .. id,
                                  TITLE_QUERY_DELAY, Attempt)
        else
            FinishTitleQuery(id)
            failedTitles[id] = true
        end
    end
    Attempt()
end

function questCache:InvalidateNames()
    if type(RXPCData) == "table" then RXPCData.questNameCache = {} end
    if type(RXPData) == "table" then
        RXPData.questNames = {locale = GetLocale()}
    end
end

addon.services:Register("quest-cache", questCache, "questCache")

