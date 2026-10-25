local addonName, addon = ...

local fmt = string.format
-- Private 3.3.5 timer facade: runtime validation rejects direct _G.C_Timer
-- consumers outside Compat/TimerFacade335.lua.
local C_Timer = addon.timer or _G.C_Timer

local themes = {}
addon.themes = themes

-- FontString:SetFont silently fails for missing custom font files on several
-- 3.3.5 clients. A later SetText then raises "Font not set", obscuring the
-- original problem and preventing guide restoration. Keep a stock-font escape
-- hatch that can also be used when initialization is recovering from an
-- unrelated module error.
function addon.SetFontSafely(fontString, fontPath, size, flags)
    if not fontString then return false end

    size = tonumber(size) or 10
    flags = type(flags) == "string" and flags or ""
    local candidates, seen = {}, {}
    local function AddCandidate(path)
        if type(path) == "string" and path ~= "" and not seen[path] then
            seen[path] = true
            candidates[#candidates + 1] = path
        end
    end

    AddCandidate(fontPath)
    AddCandidate(addon.font)
    AddCandidate(_G.STANDARD_TEXT_FONT)
    if _G.GameFontNormal and _G.GameFontNormal.GetFont then
        AddCandidate(_G.GameFontNormal:GetFont())
    end
    AddCandidate("Fonts\\FRIZQT__.TTF")

    for _, candidate in ipairs(candidates) do
        local ok = pcall(fontString.SetFont, fontString, candidate, size, flags)
        local fontOK, applied = pcall(fontString.GetFont, fontString)
        local expected = candidate:gsub("/", "\\"):lower()
        local actual = type(applied) == "string" and
                           applied:gsub("/", "\\"):lower()
        -- An invalid SetFont can leave the previously-applied font in place.
        -- Verify the resulting path rather than mistaking that stale value for
        -- a successful custom-font load.
        if ok and fontOK and actual == expected then
            addon.font = candidate
            if addon.ApplyFontShadow then addon.ApplyFontShadow(fontString) end
            return true
        end
    end

    if fontString.SetFontObject and _G.GameFontNormal then
        local ok = pcall(fontString.SetFontObject, fontString,
                         _G.GameFontNormal)
        if ok then
            local fontOK, applied = pcall(fontString.GetFont, fontString)
            if fontOK and type(applied) == "string" and applied ~= "" then
                addon.font = applied
                if addon.ApplyFontShadow then
                    addon.ApplyFontShadow(fontString)
                end
                return true
            end
        end
    end
    return false
end

-- 3.3.5a FontStrings expose SetShadowColor and SetShadowOffset directly (both
-- were removed from later clients). Track every string we style so the option
-- can be toggled live without a reload, and so theme changes can restore a
-- zero offset without clobbering unrelated addons.
local shadowFontStrings = setmetatable({}, {__mode = "k"})
local shadowedFontStrings = setmetatable({}, {__mode = "k"})
addon.shadowFontStrings = shadowFontStrings

-- Three states: true forces a 1,-1 black shadow, false removes it, nil leaves
-- the client's font-object shadow untouched (the historical behaviour, since
-- upstream never changed shadows). Transparent opts in with fontShadow = true;
-- the Look and Feel toggle writes an explicit true/false to the profile and
-- overrides whichever theme is active.
--
-- SetShadowColor / SetShadowOffset are 3.3.5a FontString methods (removed from
-- later clients), so no modern-only API is used here.
function addon.GetFontShadowMode()
    local profile = addon.settings and addon.settings.profile
    if profile and profile.fontShadow ~= nil then
        return profile.fontShadow == true
    end
    local theme = addon.activeTheme
    if theme and theme.fontShadow ~= nil then
        return theme.fontShadow == true
    end
    return nil
end

function addon.IsFontShadowEnabled()
    return addon.GetFontShadowMode() == true
end

function addon.ApplyFontShadow(fontString)
    if not fontString or not fontString.SetShadowOffset then return end
    -- OUTLINE/THICKOUTLINE strings already have an outline for contrast; adding
    -- a drop shadow on top only muddies small glyphs, so they are left alone.
    if fontString.GetFont then
        local _, _, flags = fontString:GetFont()
        if type(flags) == "string" and flags:find("OUTLINE") then return end
    end
    -- Register unconditionally: the toggle must reach strings created while the
    -- feature had no opinion (every non-Transparent theme).
    shadowFontStrings[fontString] = true
    local mode = addon.GetFontShadowMode()
    if mode == nil then return end
    if mode then
        if fontString.SetShadowColor then
            fontString:SetShadowColor(0, 0, 0, 1)
        end
        fontString:SetShadowOffset(1, -1)
        shadowedFontStrings[fontString] = true
    else
        fontString:SetShadowOffset(0, 0)
        shadowedFontStrings[fontString] = nil
    end
end

function addon.RefreshFontShadow()
    local enabled = addon.GetFontShadowMode() == true
    for fontString in pairs(shadowFontStrings) do
        if fontString.SetShadowOffset then
            if enabled then
                if fontString.SetShadowColor then
                    pcall(fontString.SetShadowColor, fontString, 0, 0, 0, 1)
                end
                pcall(fontString.SetShadowOffset, fontString, 1, -1)
                shadowedFontStrings[fontString] = true
            elseif shadowedFontStrings[fontString] then
                -- Switching away from a shadowed theme must undo only the
                -- shadow this addon added, not a stock font object's own.
                pcall(fontString.SetShadowOffset, fontString, 0, 0)
                shadowedFontStrings[fontString] = nil
            end
        end
    end
end

-- Dialogs (settings, tools, reports) keep a readable shell even when the HUD
-- itself is fully transparent.
function addon.GetWindowBackground()
    local theme = addon.activeTheme or {}
    return theme.windowBackground or theme.background or
               {0.035, 0.04, 0.075, 0.97}
end

function addon.GetThemeBorderAlpha()
    local theme = addon.activeTheme
    local alpha = theme and theme.borderAlpha
    if alpha == nil then return 0.85 end
    return alpha
end

-- Feature windows normally use their own translucency (0.4, 0.82, ...). A
-- transparent theme has to override that, otherwise those panels still show a
-- dark slab over the world.
function addon.GetSurfaceAlpha(default)
    local theme = addon.activeTheme
    if theme and theme.transparent then return 0 end
    return default
end

function addon.IsThemeTransparent()
    local theme = addon.activeTheme
    return not not (theme and theme.transparent)
end

-- The active theme's fill colour, with a safe fallback. Feature frames read
-- this instead of addon.colors, which is only assigned by the render pass and
-- can be missing while a lazily-created window paints itself.
function addon.GetThemedBackground()
    local theme = addon.activeTheme
    if theme and theme.background then return theme.background end
    local colors = addon.colors
    if colors and colors.background then return colors.background end
    return {0.035, 0.04, 0.075, 1}
end

-- 3.3.5a's SetBackdrop resets the backdrop colour to opaque white, and the
-- theme fills are WHITE8X8 textures. Setting the two separately therefore
-- paints a solid white slab whenever the colour call is skipped, delayed, or
-- applied to a frame that is not the one just changed. Always pair them.
-- A transparent theme goes one step further and installs no WHITE8X8 fill at
-- all, so no code path can ever paint white over the world.
function addon.SetThemedBackdrop(frame, backdrop, color, alpha)
    if not (frame and frame.SetBackdrop) then return end
    local c = color or addon.GetThemedBackground()
    local a = alpha or c[4] or 1
    local theme = addon.activeTheme
    if theme and theme.transparent and not color and a == 0 then
        if frame.ClearBackdrop then frame:ClearBackdrop() end
        return
    end
    frame:SetBackdrop(backdrop or (addon.RXPFrame and
                                       addon.RXPFrame.backdrop.edge))
    frame:SetBackdropColor(c[1] or 0, c[2] or 0, c[3] or 0, a)
end

-- Themed feature windows are created lazily and re-shown across theme changes,
-- so repaint them when they appear. UpdateVisuals only re-applies colours; it
-- never calls Show/Hide, so this cannot recurse through the OnShow handler.
--
-- The repaint runs a second time on the following frame: 3.3.5a can apply a
-- just-set backdrop colour only on the next draw after a frame becomes
-- visible, which is why these windows used to come up white until the user
-- toggled a setting or resized them.
function addon.EnsureVisualsOnShow(frame)
    if not (frame and frame.HookScript) or frame.rxpVisualsOnShow then return end
    frame.rxpVisualsOnShow = true
    frame:HookScript("OnShow", function(this)
        if this.rxpVisualsRefresh then return end
        this.rxpVisualsRefresh = true
        if this.UpdateVisuals then pcall(this.UpdateVisuals, this) end
        this.rxpVisualsRefresh = nil

        local function Repaint()
            if not (this.UpdateVisuals and this:IsShown()) then return end
            if this.rxpVisualsRefresh then return end
            this.rxpVisualsRefresh = true
            pcall(this.UpdateVisuals, this)
            this.rxpVisualsRefresh = nil
        end
        if addon.scheduler and addon.scheduler.After then
            addon.scheduler:After(this, "themeRepaint", 0, Repaint)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, Repaint)
        end
    end)
end

-- 3.3.5a can hold a just-applied backdrop colour until the frame's next draw,
-- so a themed frame that was hidden (or only just created) during the main
-- pass keeps its default white fill. Re-running UpdateVisuals on the following
-- frame settles it regardless of which code path originally painted it.
function addon.RepaintThemedFrames()
    local function Repaint()
        for _, frame in pairs(addon.enabledFrames or {}) do
            if frame.UpdateVisuals and frame:IsShown() then
                pcall(frame.UpdateVisuals, frame)
            end
        end
        if addon.toolWindows and addon.toolWindows.RefreshVisuals then
            pcall(addon.toolWindows.RefreshVisuals, addon.toolWindows)
        end
    end
    if addon.scheduler and addon.scheduler.After then
        addon.scheduler:After(addon, "themeRepaintAll", 0, Repaint)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, Repaint)
    end
end

themes['RXP Blue'] = {
    background = {12 / 255, 12 / 255, 27 / 255, 1},
    bottomFrameBG = {18 / 255, 18 / 255, 40 / 255, 1},
    bottomFrameHighlight = {54 / 255, 62 / 255, 109 / 255, 1},
    mapPins = {206 / 210, 123 / 210, 1, 1},
    tooltip = "|cFFCE7BFF", -- AARRGGBB
    texturePath = "Interface/AddOns/" .. addonName .. "/Textures/",
    font = _G.GameFontNormal:GetFont(),
    textColor = {1, 1, 1},
    applicable = function() return not RXPCData.GA end,
    author = "RestedXP",
    bgTextures = {edge = "Interface/BUTTONS/WHITE8X8", bottom = "Interface/BUTTONS/WHITE8X8"},
    edges = {
        edge = "Interface/AddOns/" .. addonName .. "/Textures/rxp-borders",
        guideName = "Interface/AddOns/" .. addonName .. "/Textures/rxp-borders"
    }
}

themes['Default'] = themes['RXP Blue']

-- Built-in themes must provide all properties
themes['RXP Red'] = {
    background = {19 / 255, 0 / 255, 0 / 255, 1},
    bottomFrameBG = {31 / 255, 0 / 255, 0 / 255, 1},
    bottomFrameHighlight = {81 / 255, 0 / 255, 0 / 255, 1},
    mapPins = {0.9, 0.1, 0.1, 1},
    tooltip = "|cFF0000C1", -- AARRGGBB
    texturePath = "Interface/AddOns/" .. addonName .. "/Textures/Hardcore/",
    font = _G.GameFontNormal:GetFont(),
    textColor = {1, 1, 1},
    -- applicable = function() return addon.settings.profile.hardcore end,
    -- applicable = true,
    applicable = function() return not RXPCData.GA end,
    author = "RestedXP",
    bgTextures = {edge = "Interface/BUTTONS/WHITE8X8", bottom = "Interface/BUTTONS/WHITE8X8"},
    edges = {
        edge = "Interface/AddOns/" .. addonName .. "/Textures/Hardcore/rxp-borders",
        guideName = "Interface/AddOns/" .. addonName .. "/Textures/Hardcore/rxp-borders"
    }
}

themes['RXP Gold'] = {
    background = {32 / 255, 18 / 255, 0 / 255, 1},
    bottomFrameBG = {48 / 255, 27 / 255, 0 / 255, 1},
    bottomFrameHighlight = {125 / 255, 71 / 255, 0 / 255, 1},
    mapPins = {0.95, 0.15, 0.15, 1},
    tooltip = "|cFF0000C1", -- AARRGGBB
    texturePath = "Interface/AddOns/" .. addonName .. "/Textures/GoldAssistant/",
    font = _G.GameFontNormal:GetFont(),
    textColor = {1, 1, 1},
    applicable = function() return RXPCData.GA == true end,
    -- applicable = true,
    author = "RestedXP"
}

local classColor = _G.RAID_CLASS_COLORS[select(2, UnitClass("player"))]
themes['DarkMode'] = {
    background = {14 / 255, 14 / 255, 14 / 255, 255 / 255},
    bottomFrameBG = {19 / 255, 19 / 255, 19 / 255, 255 / 255},
    bottomFrameHighlight = {classColor.r, classColor.g, classColor.b, 128 / 255},
    mapPins = {classColor.r, classColor.g, classColor.b, 1},
    tooltip = "|c" .. classColor.colorStr,
    texturePath = "Interface/AddOns/" .. addonName .. "/Textures/DarkMode/",
    font = _G.GameFontNormal:GetFont(),
    textColor = {1, 1, 1},
    applicable = function() return not RXPCData.GA end,
    -- applicable = true,
    author = "Bypass"
}

themes['RXP Green'] = {
    background = {6 / 255, 23 / 255, 12 / 255, 1},
    bottomFrameBG = {9 / 255, 34 / 255, 17 / 255, 1},
    bottomFrameHighlight = {4 / 255, 113 / 255, 65 / 255, 1},
    mapPins = {0 / 255, 203 / 255, 66 / 255, 1},
    tooltip = "|cFFCE7BFF", -- AARRGGBB
    texturePath = "Interface/AddOns/" .. addonName .. "/Textures/Green/",
    font = _G.GameFontNormal:GetFont(),
    textColor = {1, 1, 1},
    applicable = function() return not RXPCData.GA end,
    author = "RestedXP",
    bgTextures = {edge = "Interface/BUTTONS/WHITE8X8", bottom = "Interface/BUTTONS/WHITE8X8"},
    edges = {
        edge = "Interface/AddOns/" .. addonName .. "/Textures/Green/rxp-borders",
        guideName = "Interface/AddOns/" .. addonName .. "/Textures/Green/rxp-borders"
    }
}

-- Fully see-through HUD. Font colours, highlights and progress accents are
-- unchanged; only the filled background and its border texture are dropped.
-- Map pins keep a solid colour so they stay visible on the world map, and the
-- 1,-1 font shadow (3.3.5a FontString API) keeps step text legible over
-- terrain. Interactive controls keep a faint plate so they stay clickable
-- targets, and dialogs use windowBackground so settings stay readable.
themes['Transparent'] = {
    background = {0, 0, 0, 0},
    bottomFrameBG = {0, 0, 0, 0},
    bottomFrameHighlight = {0.55, 0.72, 1, 0.16},
    windowBackground = {10 / 255, 12 / 255, 24 / 255, 0.97},
    -- Dialogs are opaque shells; their buttons and list rows keep a faint plate
    -- so they still read as controls. Guide rows re-apply the transparent HUD
    -- background right after skinning, so this never becomes a step-list slab.
    cardBackground = {0.10, 0.11, 0.19, 0.55},
    mapPins = {206 / 210, 123 / 210, 1, 1},
    tooltip = "|cFFCE7BFF", -- AARRGGBB
    texturePath = "Interface/AddOns/" .. addonName .. "/Textures/",
    font = _G.GameFontNormal:GetFont(),
    textColor = {1, 1, 1},
    accent = {0.10, 0.82, 1},
    applicable = function() return not RXPCData.GA end,
    author = "Vren",
    transparent = true,
    hideEdges = true,
    fontShadow = true,
    borderAlpha = 0.35,
    bgTextures = {
        edge = "Interface/BUTTONS/WHITE8X8",
        bottom = "Interface/BUTTONS/WHITE8X8"
    }
}

addon.customThemeBase = CopyTable(themes.Default)
addon.customThemeBase.name = "Custom"
addon.customThemeBase.applicable = true
addon.customThemeBase.author = _G.UnitName("player")
addon.customThemeBase.bgTextures.guideName = "Interface/BUTTONS/WHITE8X8"

addon.guideTextColors = {}

-- TODO move into themes
addon.guideTextColors.default = {
    ["RXP_FRIENDLY_"] = "FF00FF25",
    ["RXP_ENEMY_"] = "FFFF5722",
    ["RXP_LOOT_"] = "FF00BCD4",
    ["RXP_WARN_"] = "FFFCDC00",
    ["RXP_PICK_"] = "FFDB2EEF",
    ["RXP_BUY_"] = "FF0E8312",
    -- Fallback colour for unknown/uncustomised tokens (referenced as
    -- guideTextColors.default["error"] in the colour-replacement code).
    ["error"] = "FFFFFFFF"
}

-- Seed the top-level lookup with the default colours so text/title colour
-- replacement (UI/Map.lua, UI/Settings.lua) works even before/without
-- profile customisation. Profile colours may override these later.
for token, hex in pairs(addon.guideTextColors.default) do
    if addon.guideTextColors[token] == nil then
        addon.guideTextColors[token] = hex
    end
end

local function themeApplies(applicable, isTable)
    if applicable == nil then
        return true
    elseif type(applicable) == "boolean" then
        return applicable
    elseif type(applicable) == "function" then
        return applicable()
    elseif type(applicable) == "table" and not isTable then
        return themeApplies(applicable.applicable, true)
    end
end

local function GetDefaultTheme()

    if addon.currentGuide and addon.currentGuide.theme and themes[addon.currentGuide.theme] then
        return themes[addon.currentGuide.theme]
    elseif RXPCData.GA then
        return themes["RXP Gold"]
    elseif addon.settings.profile.hardcore then
        return themes["RXP Red"]
    else
        return themes["Default"]
    end
end

function addon:LoadActiveTheme()
    local applicableTheme = addon.settings.profile.activeTheme
    local newTheme
    if applicableTheme == "Default" then
        newTheme = GetDefaultTheme()
    else
        newTheme = themes[applicableTheme]
    end

    -- Reset theme to default if selected goes away

    if not (newTheme and themeApplies(newTheme)) then newTheme = GetDefaultTheme() end

    addon.activeTheme = newTheme

    local RXPFrame = addon.RXPFrame

    -- Rebuild every backdrop from scratch for the incoming theme. Rebuilding
    -- (rather than only applying the new theme's keys) also undoes a previous
    -- transparent theme, which drops the border art globally.
    if RXPFrame and RXPFrame.backdrop then
        for name, frame in pairs(RXPFrame.backdrop) do
            frame.bgFile = (newTheme.bgTextures and
                               newTheme.bgTextures[name]) or
                               RXPFrame.defaultBackground[name]
            frame.edgeFile = nil
        end
    end

    if RXPFrame and RXPFrame.backdrop then
        RXPFrame.backdrop.edge.edgeFile = addon.GetTexture("rxp-borders") or
                                              RXPFrame.defaultEdges.edge
        RXPFrame.backdrop.guideName.edgeFile = addon.GetTexture("rxp-borders") or
                                                   RXPFrame.defaultEdges.guideName
    end

    if newTheme.edges and RXPFrame and RXPFrame.backdrop then
        for name, texture in pairs(newTheme.edges) do
            local frame = RXPFrame.backdrop[name]
            if frame then frame.edgeFile = texture end
        end
    end

    -- Transparent themes drop the border art everywhere, keeping every colour,
    -- highlight, and progress accent intact. SetBackdrop rejects a table with
    -- neither a bgFile nor an edgeFile, so guideName temporarily borrows the
    -- plain white fill; its backdrop colour alpha is zero, so nothing is drawn.
    if newTheme.hideEdges and RXPFrame and RXPFrame.backdrop then
        for _, frame in pairs(RXPFrame.backdrop) do
            frame.bgFile = "Interface\\BUTTONS\\WHITE8X8"
            frame.edgeFile = nil
        end
    end

    -- TOOD fix legacy calls
    addon.colors = addon.activeTheme

    addon.font = addon.activeTheme.font

    -- Validate custom/imported font paths at theme activation time. This keeps
    -- every subsequently-created step, tracker, targeting, and talent string
    -- on the same known-good fallback instead of protecting only the title.
    local guideText = RXPFrame and RXPFrame.GuideName and
                          RXPFrame.GuideName.text
    if guideText then
        local _, currentSize, currentFlags = guideText:GetFont()
        addon.SetFontSafely(guideText, addon.font, currentSize or 11,
                            currentFlags or "")
    elseif type(addon.font) ~= "string" or addon.font == "" then
        addon.font = themes.Default.font or _G.STANDARD_TEXT_FONT or
                         "Fonts\\FRIZQT__.TTF"
    end

    addon.RefreshFontShadow()

    return addon.activeTheme
end

function addon:GetThemeOptions()
    local themeOptions = {}

    for k, t in pairs(themes) do
        if themeApplies(t.applicable) then
            if k == 'Custom' then
                themeOptions[k] = 'Custom'
            elseif k == "Default" then
                themeOptions[""] = "Default"
            else
                themeOptions[k] = fmt("%s by %s", k, t.author)
            end
        end
    end

    return themeOptions
end

function addon:RegisterTheme(theme)
    if not theme then return end

    if not theme['name'] or not theme['author'] then
        self.comms.PrettyPrint("Theme missing name or author")
        return
    end

    for k, _ in pairs(themes.Default) do
        if not theme[k] and k ~= 'name' and k ~= 'author' then
            self.comms.PrettyDebug("%s theme missing %s using default", theme.name, k)

            theme[k] = themes.Default[k]
        end
    end

    if not themeApplies(theme.applicable) then
        self.comms.PrettyPrint("%s does not apply to current mode, importing anyway", theme.name)
    end

    themes[theme.name] = theme
end

function addon.GetTexture(name)
    -- Avoid nil concatenation
    if not name or not (addon.activeTheme and addon.activeTheme.texturePath) then return end

    -- Exclude banner from hiding custom theme colors
    if addon.activeTheme.name == "Custom" and name == 'rxp-banner' then return end

    -- Validate for non-built-in textures?
    -- https://www.wowinterface.com/forums/showpost.php?p=337605&postcount=8
    -- 3.3.5a's texture loader is unreliable with forward slashes for custom
    -- addon files, so normalise to backslashes (Blizzard paths accept both).
    local path = fmt("%s%s", addon.activeTheme.texturePath, name)
    return (path:gsub("/", "\\"))
end

function addon:ImportCustomThemes()
    -- Register empty custom theme
    self:RegisterTheme(addon.settings.profile.customTheme)

    if not _G.RXPGuides_Themes then return end

    -- TODO use loop to strip array?
    for _, theme in pairs(_G.RXPGuides_Themes) do self:RegisterTheme(theme) end

    wipe(_G.RXPGuides_Themes)
end
