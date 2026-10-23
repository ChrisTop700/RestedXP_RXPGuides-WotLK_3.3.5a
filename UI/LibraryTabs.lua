local _, addon = ...
local tabs = {}
addon.libraryTabs = tabs
local L = addon.locale.Get
local names = {"Guides", "Feature Tools", "Settings", "Import"}

-- Only presentation state lives here. In particular, tab selection is never
-- written to a profile or a guide checkpoint.
function tabs:GuidePage(window)
    local page = CreateFrame("Frame", nil, window)
    page:SetPoint("TOPLEFT", 0, -36)
    page:SetPoint("BOTTOMRIGHT", 0, 0)
    return page
end

function tabs:Attach(window, guides)
    self.window, self.pages, self.buttons = window, {Guides = guides}, {}
    self.selected = self.selected or "Guides"
    for i, name in ipairs(names) do
        local button = addon.presentation:Button(window, L(name), 145, function() tabs:Open(name) end)
        button:SetPoint("TOPLEFT", 18 + (i - 1) * 153, -40)
        self.buttons[name] = button
    end
    window:HookScript("OnHide", function()
        tabs:ClearFocus()
        GameTooltip:Hide()
    end)
    window:HookScript("OnShow", function() tabs:RefreshVisible() end)
    window:HookScript("OnSizeChanged", function() tabs:SizeContainers() end)
    -- The library's own OnToolVisuals remains responsible for guide cards.
    local visuals = window.OnToolVisuals
    window.OnToolVisuals = function(...)
        if visuals then visuals(...) end
        for _, button in pairs(tabs.buttons) do addon.presentation:SkinControl(button) end
        if addon.featureToolsUI then addon.featureToolsUI:Refresh() end
    end
    for name, page in pairs(self.pages) do page:SetShown(name == self.selected) end
end

function tabs:ClearFocus()
    if addon.guideHub.frame.search then addon.guideHub.frame.search:ClearFocus() end
    local gui = LibStub("AceGUI-3.0")
    gui:ClearFocus()
end

function tabs:SizeContainers()
    if self.sizing then return end
    self.sizing = true
    for _, page in pairs(self.pages or {}) do
        if page.widget then
            page.widget:SetWidth(math.max(100, page:GetWidth()))
            page.status:SetWidth(math.max(100, page:GetWidth() - 8))
            local statusHeight = page.status:GetText() ~= "" and page.status:GetStringHeight() + 8 or 0
            page.widget:SetHeight(math.max(100, page:GetHeight() - statusHeight))
            page.widget:DoLayout()
        end
    end
    self.sizing = nil
end

-- Native AceConfig callbacks rebuild their own custom container directly.
-- Observe only our root's layout, never hook a library or replace an option
-- setter. Synchronize the independently registered fallback when it is visible.
function tabs:NativeRendered(name)
    if self.rendering or self.sizing then return end
    addon.scheduler:After(self, "fallback-" .. name, 0, function()
        local panel = name == "Import" and addon.settings.gui.import or addon.RXPOptions
        if not (panel and panel.obj and panel.obj.frame:IsVisible()) then return end
        self.rendering = true
        local app = name == "Import" and addon.RXPOptions.name .. "/Import" or addon.title
        local ok, err = pcall(LibStub("AceConfigDialog-3.0").Open, LibStub("AceConfigDialog-3.0"), app, panel.obj)
        self.rendering = nil
        if name == "Import" and addon.settings.textboxHook then addon.settings.textboxHook(panel.obj) end
        if not ok then geterrorhandler()(err) end
    end)
end

function tabs:Page(name)
    if self.pages[name] then return self.pages[name] end
    local page = CreateFrame("Frame", nil, self.window)
    page:Hide()
    page:SetPoint("TOPLEFT", 16, -78)
    page:SetPoint("BOTTOMRIGHT", -16, 18)
    self.pages[name] = page
    if name == "Feature Tools" then
        addon.featureToolsUI:Create(page)
    else
        local widget = LibStub("AceGUI-3.0"):Create("SimpleGroup")
        page.status = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        page.status:SetPoint("BOTTOMLEFT", 4, 0)
        page.status:SetJustifyH("LEFT")
        page.status:SetText("")
        widget.SetStatusText = function(_, text)
            page.status:SetText(text or "")
            tabs:SizeContainers()
        end
        widget:SetLayout("Fill")
        widget.noAutoHeight = true
        widget.frame:SetParent(page)
        -- AceGUI descendants are pooled with other addon interfaces. Never
        -- attach persistent tool-window mouse hooks to those borrowed frames.
        widget.frame.rxpPooledContent = true
        widget.frame:SetFrameStrata(self.window:GetFrameStrata())
        widget.frame:SetFrameLevel(page:GetFrameLevel() + 1)
        widget.frame:ClearAllPoints()
        widget.frame:SetPoint("TOPLEFT")
        local finished = widget.LayoutFinished
        widget.LayoutFinished = function(self, ...)
            if finished then finished(self, ...) end
            if name == "Import" and addon.settings.textboxHook then addon.settings.textboxHook(self) end
            tabs:NativeRendered(name)
        end
        page.widget, page.dirty = widget, true
        page:SetScript("OnSizeChanged", function() tabs:SizeContainers() end)
    end
    return page
end

function tabs:RefreshVisible()
    if not self.window or not self.window:IsShown() then return end
    local page = self.pages[self.selected]
    if not page then return end
    if self.selected == "Guides" then addon.guideHub:Refresh(); return end
    if page.widget and page.dirty and not self.rendering then
        self.rendering = true
        page.dirty = nil
        local app = self.selected == "Import" and addon.RXPOptions.name .. "/Import" or addon.title
        page.widget:SetUserData("basepath", nil)
        self:SizeContainers()
        -- Render the registered tables themselves, including Profiles and
        -- complex editors. AceConfig owns validation, confirmation and writes.
        local ok, err = pcall(LibStub("AceConfigDialog-3.0").Open,
            LibStub("AceConfigDialog-3.0"), app, page.widget)
        self.rendering = nil
        if ok and self.selected == "Import" and addon.settings.textboxHook then
            addon.settings.textboxHook(page.widget)
        end
        if not ok then page.dirty = true; geterrorhandler()(err) end
    elseif self.selected == "Feature Tools" then
        addon.featureToolsUI:Refresh()
    end
end

function tabs:SettingsChanged()
    for _, page in pairs(self.pages or {}) do if page.widget then page.dirty = true end end
    if self.refreshPending then return end
    self.refreshPending = true
    addon.scheduler:After(self, "settings", 0, function()
        self.refreshPending = nil
        if tabs.selected ~= "Guides" then tabs:RefreshVisible() end
    end)
end

function tabs:Open(name, path)
    addon.guideHub:CreateFrame()
    name = self.buttons[name] and name or self.selected or "Guides"
    self:ClearFocus()
    local page = self:Page(name)
    self.selected = name
    for key, child in pairs(self.pages) do child:SetShown(key == name) end
    for key, button in pairs(self.buttons) do
        if key == name then button:Disable() else button:Enable() end
    end
    if name == "Feature Tools" then
        addon.featureToolsUI:SetPath(path)
    elseif name == "Settings" and path then
        local selected = type(path) == "table" and path or {path}
        LibStub("AceConfigDialog-3.0"):SelectGroup(addon.title, unpack(selected))
        page.dirty = true
    end
    local wasShown = self.window:IsShown()
    self.window:Show()
    if wasShown then self:RefreshVisible() end
end
