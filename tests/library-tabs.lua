-- Real settings registration and the bundled AceConfig/AceGUI renderer. Only
-- the client frame/API boundary is mocked; no option tree is copied here.
return function(root, baseObject, style)
    style = style or "modern"
    local env = setmetatable({}, {__index = function(_, key)
        if _G[key] ~= nil then return _G[key] end
        if key:match("^[A-Z][A-Z_0-9]+$") then return key end
    end})
    env._G = env
    local queue, errors, frames = {}, {}, {}
    local function object(name, parent)
        local f = baseObject(name)
        f.parent, f.children = parent, {}
        f.actualWidth, f.actualHeight = f.width, f.height
        function f:GetWidth() return self.actualWidth end
        function f:GetHeight() return self.actualHeight end
        function f:SetWidth(value) self.actualWidth = value end
        function f:SetHeight(value) self.actualHeight = value end
        function f:SetSize(width, height) self:SetWidth(width); self:SetHeight(height) end
        if parent then parent.children[#parent.children + 1] = f end
        function f:GetChildren() return unpack(self.children) end
        function f:GetObjectType() return self.kind or "Frame" end
        function f:GetTexture() return self.texture end
        function f:SetTexture(texture) self.texture = texture end
        function f:GetEffectiveScale() return 1 end
        function f:GetLeft() return 0 end
        function f:GetRight() return self:GetWidth() end
        function f:GetCenter() return 400, 300 end
        function f:GetNumLetters() return #self:GetText() end
        function f:GetTextInsets() return 0, 0, 0, 0 end
        function f:GetFontObject() return env.GameFontNormal end
        function f:GetTextWidth() return self:GetStringWidth() end
        function f:SetFrameLevel(level) self.level = level end
        function f:SetFrameStrata(strata) self.strata = strata end
        function f:GetVerticalScroll() return self.scroll or 0 end
        function f:SetVerticalScroll(n) self.scroll = n end
        function f:GetVerticalScrollRange() return 0 end
        function f:GetMinMaxValues() return self.low or 0, self.high or 100 end
        function f:SetMinMaxValues(low, high) self.low, self.high = low, high end
        function f:IsMouseOver() return false end
        function f:HasFocus() return self.focus end
        function f:SetFocus() self.focus = true; if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end end
        function f:ClearFocus() self.focus = nil; if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
        function f:HighlightText() end
        function f:SetMaxBytes(value) self.maxBytes = value end
        function f:EnableKeyboard() end
        function f:LockHighlight() end
        function f:UnlockHighlight() end
        function f:ClearAllPoints() self.points = {} end
        function f:CreateTexture() local r = object(); r.parent = self; return r end
        function f:CreateFontString() local r = object(); r.parent = self; return r end
        function f:GetHighlightFontObject() return env.GameFontNormal end
        function f:SetAllPoints(other) other = other or self.parent; self:SetSize(other:GetWidth(), other:GetHeight()) end
        local setText = f.SetText
        function f:SetText(text)
            setText(self, text)
            if self.scripts.OnTextSet then self.scripts.OnTextSet(self) end
        end
        if name then env[name] = f end
        frames[#frames + 1] = f
        return f
    end
    env.CreateFrame = function(kind, name, parent, template)
        local f = object(name, parent); f.kind = kind; if kind == "Slider" then f.value = 0 end
        if template == "UIPanelScrollFrameTemplate" and name then
            f.ScrollBar = object(name .. "ScrollBar", f)
            object(name .. "ScrollBarScrollUpButton", f.ScrollBar)
            object(name .. "ScrollBarScrollDownButton", f.ScrollBar)
        end
        if template == "OptionsFrameTabButtonTemplate" then
            object(name .. "Text"); object(name .. "HighlightTexture")
        end
        if template == "OptionsListButtonTemplate" then
            f.toggle = object(name .. "Toggle", f); f.highlight = object(name .. "Highlight", f)
            f.text = object(name .. "Text", f)
        end
        if template == "UIDropDownMenuTemplate" then
            for _, suffix in ipairs({"Left", "Middle", "Right", "Text", "Button"}) do object(name .. suffix, f) end
        end
        return f
    end
    env.UIParent = object("UIParent")
    for _, name in ipairs({"GameFontNormal", "GameFontNormalSmall", "GameFontHighlight", "GameFontHighlightSmall",
        "GameFontHighlightLarge", "GameFontDisable", "GameFontDisableSmall", "GameFontNormalLarge", "ChatFontNormal"}) do env[name] = object(name) end
    env.GameTooltip = object("GameTooltip")
    env.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
    env.loadstring = function(code, name) local chunk, err = loadstring(code, name); if chunk then setfenv(chunk, env) end; return chunk, err end
    env.wipe = function(t) for key in pairs(t) do t[key] = nil end; return t end
    env.CopyTable = function(t) local out = {}; for key, value in pairs(t) do out[key] = type(value) == "table" and env.CopyTable(value) or value end; return out end
    env.tinsert, env.tremove, env.sort, env.format, env.strsplit = table.insert, table.remove, table.sort, string.format,
        function(sep, text) local t = {}; for s in text:gmatch("[^" .. sep .. "]+") do t[#t + 1] = s end; return unpack(t) end
    env.strmatch, env.strlen, env.strsub, env.floor, env.ceil, env.max, env.min = string.match, string.len, string.sub, math.floor, math.ceil, math.max, math.min
    local oldSplit = string.split
    string.split = env.strsplit
    env.GetLocale = function() return "enUS" end
    env.GetCVar = function() return "enUS" end
    env.strlower = string.lower
    local now = 0
    env.GetTime = function() return now end
    env.GetBuildInfo = function() return "3.3.5", "12340", "2010", 30300 end
    env.UnitName = function() return "Fixture" end
    env.GetRealmName = function() return "Fixture" end
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.UnitRace = function() return "Orc", "Orc" end
    env.UnitFactionGroup = function() return "Horde" end
    env.UnitLevel = function() return 1 end
    env.GetMaxPlayerLevel = function() return 80 end
    env.InCombatLockdown = function() return false end
    env.IsLoggedIn = function() return true end
    env.IsAddOnLoaded = function() return false end
    env.GetNumAddOns = function() return 0 end
    env.BNGetInfo = function() end
    env.GetScreenWidth, env.GetScreenHeight = function() return 1024 end, function() return 768 end
    env.PlaySound, env.InterfaceOptions_AddCategory = function() end, function() end
    env.SetDesaturation = function() end
    env.CloseSpecialWindows = function() end
    env.PanelTemplates_TabResize, env.PanelTemplates_SetDisabledTabState = function() end, function() end
    env.PanelTemplates_SelectTab, env.PanelTemplates_DeselectTab = function() end, function() end
    env.ChatEdit_InsertLink = function() end
    env.hooksecurefunc = function(target, key, callback)
        if type(target) == "string" then callback, key, target = key, target, env end
        local original = assert(target[key], key)
        target[key] = function(...) local result = original(...); callback(...); return result end
    end
    env.Enum = {ItemQuality = {Heirloom = 7}}
    env.NORMAL_FONT_COLOR = {r = 1, g = 0.82, b = 0}
    env.RAID_CLASS_COLORS = setmetatable({}, {__index = function() return {r = 0.8, g = 0.6, b = 0.4, colorStr = "ffc09060"} end})
    env.StaticPopupDialogs, env.UISpecialFrames = {}, {}
    local popup
    env.StaticPopup_Show = function(key) popup = key; return object() end
    env.RXPData = {cache = true, guideHub = {filters = {}, favorites = {}}}
    env.RXPCData = {currentStep = 7, guideProgress = {}, recentGuides = {},
        guideMetaData = {enabledDungeons = {Horde = {}}, professions = {}, skills = {}, enableGroupQuests = {}}}
    env.FauxScrollFrame_GetOffset = function(f) return f.offset or 0 end
    env.FauxScrollFrame_SetOffset = function(f, n) f.offset = n end
    env.FauxScrollFrame_Update = function() end
    env.FauxScrollFrame_OnVerticalScroll = function() end
    local addon = {title = "RestedXP Guides", versionText = "fixture", gameVersion = 30300,
        locale = {Get = function(s) return s end}, player = {class = "WARRIOR", race = "Orc", faction = "Horde"},
        font = "font", help = {}, compatibility = {}, colors = {}, enabledFrames = {},
        comms = {SendPing = function() end, OpenBugReport = function() end},
        targeting = {CanCreateMacro = function() return true end},
        classColor = {r = 0.8, g = 0.6, b = 0.4},
        scheduler = {After = function(_, _, key, _, fn) queue[key] = fn end},
        timer = {After = function(_, fn) queue.timer = fn end},
        db = {profile = {guides = {}}}, guideList = {}, guides = {}, settings = {}, RXPFrame = object(),
        GetTexture = function(s) return "Textures/" .. s end,
        GetOrphanedQuests = function() return {} end,
        SetFontSafely = function(f, path, size) f:SetFont(path, size) end,
        IsQuestRewardSettlementActive = function() return false end}
    function addon:NewModule() return self.settings end
    addon.RXPFrame.BottomFrame = object()
    local function load(path)
        local chunk = assert(loadfile(root .. "/" .. path)); setfenv(chunk, env)("RXPGuides", addon)
    end
    load("libs/LibStub/LibStub.lua")
    load("libs/Legacy335/CallbackHandler-1.0/CallbackHandler-1.0.lua")
    load("libs/Legacy335/AceGUI-3.0/AceGUI-3.0.lua")
    local xml = assert(io.open(root .. "/libs/Legacy335/AceGUI-3.0/AceGUI-3.0.xml")); local body = xml:read("*a"); xml:close()
    for path in body:gmatch('<Script file="([^"]+)"') do
        if path ~= "AceGUI-3.0.lua" then load("libs/Legacy335/AceGUI-3.0/" .. path:gsub("\\", "/")) end
    end
    load("libs/Legacy335/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua")
    load("libs/Legacy335/AceConfig-3.0/AceConfigDialog-3.0/AceConfigDialog-3.0.lua")
    load("libs/Legacy335/AceDB-3.0/AceDB-3.0.lua")
    load("libs/Legacy335/AceDBOptions-3.0/AceDBOptions-3.0.lua")
    -- AceConfig's command-line and broker collaborators are not used by the
    -- renderer. Registration still goes through the real registry validator.
    local config = env.LibStub:NewLibrary("AceConfig-3.0", 1)
    function config:RegisterOptionsTable(...) return env.LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable(...) end
    for _, name in ipairs({"LibDBIcon-1.0", "LibDataBroker-1.1"}) do env.LibStub:NewLibrary(name, 1) end
    load("UI/Themes.lua")
    load("UI/Settings.lua")
    addon.settings:InitializeDatabase()
    addon.settings.profile.uiStyle = style
    load("UI/Presentation.lua"); addon.presentation:Initialize()
    load("UI/ToolWindow.lua"); load("UI/SettingsAdapter.lua"); load("UI/FeatureTools.lua")
    load("UI/GuideHub.lua"); load("UI/ModernLibrary.lua"); load("UI/LibraryTabs.lua")
    addon.settings:CreateAceOptionsPanel()
    addon.settings:CreateImportOptionsPanel()
    local forbidden = function() error("presentation invoked gameplay/progression") end
    addon.LoadGuide, addon.ReloadGuide, addon.GoToStep, addon.SetStep, addon.UpdateMap = forbidden, forbidden, forbidden, forbidden, forbidden
    local before = {}
    for key, value in pairs(addon.settings.profile) do if type(value) ~= "table" then before[key] = value end end
    addon.guideHub:Setup()
    addon.libraryTabs:Open("Settings")
    assert(#errors == 0, table.concat(errors, "\n"))
    local function find(widget, key)
        local path = widget.GetUserData and widget:GetUserData("path")
        if path and path[#path] == key then return widget end
        for _, child in ipairs(widget.children or {}) do local found = find(child, key); if found then return found end end
    end
    local function clean(label)
        assert(#errors == 0, label .. ":\n" .. table.concat(errors, "\n"))
    end
    local function groups(option, path)
        for key, child in pairs(option.args or {}) do
            if child.type == "group" and not child.inline then
                local nextPath = {}; for i, value in ipairs(path) do nextPath[i] = value end; nextPath[#nextPath + 1] = key
                addon.libraryTabs:Open("Settings", nextPath)
                clean(table.concat(nextPath, "/"))
                groups(child, nextPath)
            end
        end
    end
    groups(addon.settings.optionTree, {})
    addon.libraryTabs:Open("Import")
    clean("Import")
    local import = assert(find(addon.libraryTabs.pages.Import.widget, "importBox"))
    assert(import.editBox.rxpImportHooked, "registered Import owns its paste hook")
    addon.libraryTabs:Open("Guides")
    addon.libraryTabs:Open("Feature Tools", "routePreflight")
    clean("Feature Tools")
    addon.libraryTabs:Open("Import")
    assert(find(addon.libraryTabs.pages.Import.widget, "importBox") == import, "tab switch retains import widgets")
    assert(env.RXPCData.currentStep == 7, "tabs never change guide progress")
    for key, value in pairs(before) do assert(addon.settings.profile[key] == value, "initialization changed " .. key) end
    -- Registered callbacks are exercised through the native rendered widget.
    -- Discover the actual category containing the control instead of relying
    -- on translated captions or an assumed profile key.
    local function pathTo(option, wanted, path)
        for key, child in pairs(option.args or {}) do
            if key == wanted then return path end
            if child.type == "group" then
                local nextPath = env.CopyTable(path); nextPath[#nextPath + 1] = key
                local found = pathTo(child, wanted, nextPath); if found then return found end
            end
        end
    end
    addon.libraryTabs:Open("Settings", assert(pathTo(addon.settings.optionTree, "enableQuestAutomation", {})))
    clean("Automation deep link")
    local qa = assert(find(addon.libraryTabs.pages.Settings.widget, "enableQuestAutomation"))
    local conflicts = 0
    addon.CheckQuestieAutomationConflict = function() conflicts = conflicts + 1 end
    addon.questAutomation = {ResetTransient = function() conflicts = conflicts + 1 end}
    qa:Fire("OnValueChanged", false)
    assert(addon.settings.profile.enableQuestAutomation == false and conflicts == 1, "native setter executes once")
    clean("Native setter")
    addon.settings.profile.enableQuestAutomation = true
    addon.presentation:SettingsChanged()
    assert(queue.settings); queue.settings(); queue.settings = nil
    qa = assert(find(addon.libraryTabs.pages.Settings.widget, "enableQuestAutomation"))
    assert(qa.checked and conflicts == 1, "external changes refresh without setters")
    local dialog = env.LibStub("AceConfigDialog-3.0")
    dialog:Open(addon.title, addon.RXPOptions.obj)
    addon.RXPOptions.obj.frame:Show()
    local fallbackQA = assert(find(addon.RXPOptions.obj, "enableQuestAutomation"))
    fallbackQA:Fire("OnValueChanged", false)
    assert(conflicts == 2 and queue.settings, "fallback changes schedule the visible hub refresh")
    local refresh = queue.settings; queue.settings = nil; refresh()
    qa = assert(find(addon.libraryTabs.pages.Settings.widget, "enableQuestAutomation"))
    assert(not qa.checked and conflicts == 2, "native fallback and hub agree without replaying setters")
    qa:Fire("OnValueChanged", true)
    assert(conflicts == 3 and queue["fallback-Settings"])
    refresh = queue["fallback-Settings"]; queue["fallback-Settings"] = nil; refresh()
    assert(find(addon.RXPOptions.obj, "enableQuestAutomation").checked and conflicts == 3,
        "hub callback refreshes the visible original panel once")
    clean("Bidirectional native refresh")
    addon.libraryTabs:Open("Import")
    import = assert(find(addon.libraryTabs.pages.Import.widget, "importBox"))
    import.editBox:SetFocus()
    now = 1
    import.editBox.scripts.OnChar(import.editBox, "invalid fixture")
    import.editBox.scripts.OnUpdate(import.editBox)
    local imports = 0
    addon.ImportString = function(text) imports = imports + 1; assert(text == "invalid fixture"); return nil, "Fixture rejection" end
    addon.comms.PrettyPrint = function() end
    import.button:GetScript("OnClick")(import.button)
    assert(imports == 1 and #addon.settings.gui.importStatusHistory > 0, "import validator and status remain live")
    assert(addon.libraryTabs.pages.Import.status:GetText() == "Fixture rejection", "native validation message remains visible")
    clean("Import validation")
    local purge = assert(find(addon.libraryTabs.pages.Import.widget, "purgeAll"))
    local purges = 0
    addon.CreateMetaDataTable = function() purges = purges + 1 end
    purge:Fire("OnClick")
    assert(popup == "ACECONFIGDIALOG30_CONFIRM_DIALOG" and purges == 0)
    env.StaticPopupDialogs[popup].OnCancel()
    assert(purges == 0, "cancelled native confirmation invokes no action")
    purge = assert(find(addon.libraryTabs.pages.Import.widget, "purgeAll"))
    purge:Fire("OnClick"); env.StaticPopupDialogs[popup].OnAccept()
    assert(purges == 1, "confirmed native action executes once")
    clean("Native confirmations")
    import = assert(find(addon.libraryTabs.pages.Import.widget, "importBox"))
    import.editBox:SetFocus(); now = 2
    import.editBox.scripts.OnChar(import.editBox, "pending buffer")
    dialog:Open(addon.RXPOptions.name .. "/Import", addon.settings.gui.import.obj)
    addon.settings.textboxHook(addon.settings.gui.import.obj)
    addon.settings.gui.import.obj:ReleaseChildren()
    assert(import.editBox:GetScript("OnUpdate") and not import.editBox:IsEnabled(),
        "releasing the other import pane cannot consume the active paste")
    addon.libraryTabs.pages.Import.widget:ReleaseChildren()
    assert(import.editBox.maxBytes == 0 and not import.editBox:GetScript("OnUpdate"), "release clears paste restrictions and queued work")
    local borrowed = env.LibStub("AceGUI-3.0"):Create("MultiLineEditBox")
    borrowed.editBox:SetText("unrelated editor")
    if borrowed.editBox:GetScript("OnEditFocusGained") then borrowed.editBox:GetScript("OnEditFocusGained")(borrowed.editBox) end
    if borrowed.editBox:GetScript("OnChar") then borrowed.editBox:GetScript("OnChar")(borrowed.editBox, "x") end
    assert(borrowed.editBox:GetText() == "unrelated editor" and not borrowed.editBox:GetScript("OnUpdate"), "pooled editors do not inherit active import hooks")
    env.LibStub("AceGUI-3.0"):Release(borrowed)
    addon.libraryTabs.pages.Import.dirty = true
    addon.libraryTabs:RefreshVisible()
    clean("Pooled import refresh")
    assert(not addon.libraryTabs.pages.Import.widget.frame.rxpToolLayerHook, "native pooled controls avoid persistent tool hooks")
    -- Tab switching must leave pooled draft controls and independent gameplay
    -- windows alone; Escape targets only the registered hub root.
    local persistent = object(); persistent:Show()
    addon.guideHub.window:Hide()
    assert(persistent:IsShown() and env.RXPCData.currentStep == 7)
    addon.settings.OpenSettings()
    assert(addon.libraryTabs.selected == "Settings" and addon.guideHub.window:IsShown())
    addon.settings.OpenFeatureToolSettings("routePreflight")
    assert(addon.libraryTabs.selected == "Feature Tools")
    addon.guideHub.window:Hide()
    local oldTrim = string.trim
    string.trim = function(s) return s:match("^%s*(.-)%s*$") end
    addon.settings.ChatCommand("")
    string.trim = oldTrim
    assert(addon.libraryTabs.selected == "Feature Tools" and addon.guideHub.window:IsShown(), "bare command restores session tab")
    addon.guideHub:Toggle()
    assert(addon.libraryTabs.selected == "Guides")
    local fallback = 0
    env.InterfaceOptionsFrame_OpenToCategory = function(panel) assert(panel == addon.RXPOptions); fallback = fallback + 1 end
    addon.settings.OpenLegacySettings()
    assert(fallback == 2, "stock Interface Options remains independently reachable")
    clean("Fallback")
    print("Unified library: production options and bundled renderer passed")
    string.split = oldSplit
    if style == "modern" then assert(loadfile(root .. "/tests/library-tabs.lua"))()(root, baseObject, "legacy") end
end
