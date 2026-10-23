local _, addon = ...
local ui = {}
addon.featureToolsUI = ui
local L, view, adapter = addon.locale.Get, addon.presentation, addon.settingsAdapter

-- Display only: setters continue to receive the original numeric value.
function ui:FormatValue(value, info)
    local multiplier = info and info.isPercent and 100 or 1
    local step = math.abs(tonumber(info and info.step) or 0.01) * multiplier
    local precision = 0
    while precision < 6 and math.abs(step - math.floor(step + 0.5)) > 0.000001 do
        precision = precision + 1
        step = step * 10
    end
    local result = string.format("%." .. precision .. "f", value * multiplier)
    return result .. (multiplier == 100 and "%" or "")
end

local function Text(parent, size)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    addon.SetFontSafely(text, addon.font, size or 12, "")
    text:SetJustifyH("LEFT"); text:SetJustifyV("TOP")
    return text
end
local function Scroll(parent, name, left, right)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", left, -42)
    scroll:SetPoint("BOTTOMRIGHT", right, 60)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(200, 1)
    scroll:SetScrollChild(child)
    return scroll, child
end

function ui:Create(parent)
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    self.frame, self.controls, self.pages = f, {}, {}
    f.status = Text(f, 11)
    f.status:SetPoint("TOPLEFT", 22, -4); f.status:SetPoint("RIGHT", -22, 0)
    f.status:SetHeight(30)
    f.navScroll, f.navChild = Scroll(f, "RXPFeatureToolsNavigation", 18, 0)
    f.navScroll:ClearAllPoints()
    f.navScroll:SetPoint("TOPLEFT", 18, -42)
    f.navScroll:SetPoint("BOTTOMLEFT", 18, 60)
    f.navScroll:SetWidth(180)
    f.scroll, f.child = Scroll(f, "RXPFeatureToolsOptions", 238, -38)
    f.advanced = view:Button(f, L("Advanced Settings..."), 180, function()
        addon.libraryTabs:Open("Settings", ui.path or {"featureToolsSettings"})
    end)
    f.advanced:SetPoint("BOTTOMLEFT", 20, 20)
    f.reload = view:Button(f, L("Reload Now"), 130, function() view:Reload() end)
    f.reload:SetPoint("BOTTOMRIGHT", -24, 20)
    f:SetScript("OnSizeChanged", function() ui:Refresh() end)
    f.OnToolVisuals = function() ui:Refresh() end
    f:HookScript("OnShow", function() ui:Refresh() end)
    return f
end

function ui:Open(path)
    return addon.libraryTabs:Open("Feature Tools", path)
end

function ui:SetPath(path)
    if not path and self.path then return end
    self.path = {"featureToolsSettings"}
    if type(path) == "string" and path ~= "" then
        self.path[2] = path
    elseif type(path) == "table" then
        for _, key in ipairs(path) do self.path[#self.path + 1] = key end
    else self.path[2] = "routePreflight" end
    if not adapter:Resolve(self.path) then self.path = {"featureToolsSettings", "routePreflight"} end
    if #self.path == 2 and self.path[2] == "speedrunning" then self.path[3] = "overview" end
    self:Refresh()
end

function ui:Control(index, kind)
    local pool = self.controls[kind]
    if not pool then pool = {}; self.controls[kind] = pool end
    local row = pool[index]
    if row then return row end
    row = CreateFrame("Frame", nil, self.frame.child)
    row.label = Text(row)
    row.label:SetPoint("TOPLEFT", 0, 0); row.label:SetPoint("RIGHT", 0, 0)
    if kind == "toggle" then
        row.widget = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.widget:SetSize(26, 26); row.widget:SetPoint("TOPLEFT", 0, 0)
        row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT", 32, -4); row.label:SetPoint("RIGHT", 0, 0)
        row.widget:SetScript("OnClick", function(button)
            adapter:Commit(row.path, button:GetChecked() and true or false)
        end)
    elseif kind == "range" then
        row.widget = CreateFrame("Slider", nil, row)
        row.widget:SetOrientation("HORIZONTAL")
        row.widget:SetPoint("TOPLEFT", 0, -27); row.widget:SetPoint("RIGHT", -15, 0); row.widget:SetHeight(16)
        if view:IsModern() then view:Skin(row.widget, true)
        else row.widget:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"}); row.widget:SetBackdropColor(0.2, 0.2, 0.2, 1) end
        row.widget:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        row.value = Text(row, 11); row.value:SetPoint("TOPRIGHT", 0, -48)
        row.widget:SetScript("OnValueChanged", function(_, value)
            row.previewValue = value
            if row.value then row.value:SetText(ui:FormatValue(value, row.rangeInfo)) end
            -- A drag commits once on release. Programmatic initialization and
            -- clamping must never change a feature preference.
        end)
        row.widget:SetScript("OnMouseDown", function()
            row.dragPath, row.dragProfile, row.dragRevision = row.path, addon.settings.profile, view.settingsRevision
        end)
        row.widget:SetScript("OnMouseUp", function()
            if not ui.rendering and row.dragPath == row.path and row.dragProfile == addon.settings.profile and
                row.dragRevision == view.settingsRevision then adapter:Commit(row.path, row.widget:GetValue()) end
            row.dragPath, row.dragProfile, row.dragRevision = nil, nil, nil
        end)
    elseif kind == "execute" or kind == "select" then
        row.widget = view:Button(row, "", 220, function()
            if kind == "execute" then adapter:Commit(row.path); return end
            local info = adapter:Describe(row.path)
            if not info or info.disabled then return end
            local path, revision, profile = row.path, view.settingsRevision, addon.settings.profile
            local items = {}
            for key, name in pairs(info.values or {}) do items[#items + 1] = {key = key, name = name} end
            table.sort(items, function(a, b) return tostring(a.name) < tostring(b.name) end)
            local menu = {}
            for _, item in ipairs(items) do
                local key = item.key
                menu[#menu + 1] = {text = item.name, checked = adapter:Value(row.path, "get") == key,
                    func = function()
                        if row.path == path and view.settingsRevision == revision and addon.settings.profile == profile then
                            adapter:Commit(path, key)
                        end
                    end}
            end
            ui.menu = ui.menu or CreateFrame("Frame", "RXPFeatureToolsMenu", UIParent, "UIDropDownMenuTemplate")
            EasyMenu(menu, ui.menu, row.widget, 0, 0, "MENU")
        end)
        row.widget:SetPoint("TOPLEFT", 0, kind == "select" and -25 or 0)
    end
    row:EnableMouse(true)
    row:SetScript("OnEnter", function()
        local info = adapter:Describe(row.path)
        if info and info.desc and info.desc ~= "" then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:AddLine(info.desc, 0.85, 0.87, 0.95, true); GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if row.widget then
        row.widget:HookScript("OnEnter", row:GetScript("OnEnter"))
        row.widget:HookScript("OnLeave", row:GetScript("OnLeave"))
    end
    pool[index] = row
    self.layersDirty = true
    return row
end

function ui:Refresh()
    local f = self.frame
    if not f or not f:IsVisible() or self.rendering then return end
    self.rendering = true
    local ok, message = pcall(self.RenderPage, self)
    self.rendering = nil
    if not ok then
        f.status:SetText(L("This page could not be displayed. Advanced Settings remain available."))
        if geterrorhandler then geterrorhandler()(message) end
    end
end

function ui:RenderPage()
    local f = self.frame
    f.status:SetText(view:IsPending() and L("Interface change pending. Reload when convenient; current controls remain live.") or
        L("Enable a tool separately from opening its window. Changes apply immediately."))
    f.reload:SetShown(view:IsPending())
    local pages = adapter:Children({"featureToolsSettings"})
    local entries = {}
    for _, page in ipairs(pages) do
        if page.info.type == "group" then
            entries[#entries + 1] = page
            for _, child in ipairs(adapter:Children(page.path)) do
                if child.info.type == "group" then child.nested = true; entries[#entries + 1] = child end
            end
        end
    end
    for i, page in ipairs(entries) do
        local button = self.pages[i]
        if not button then button = view:Button(f.navChild, "", 176); self.pages[i] = button; self.layersDirty = true end
        button:Show(); button:ClearAllPoints(); button:SetPoint("TOPLEFT", 0, -(i - 1) * 36)
        button:SetText((page.nested and "  " or "") .. (page.info.name or ""))
        local path = page.path
        local selected = self.path and table.concat(path, "/") == table.concat(self.path, "/")
        if view:IsModern() then
            view:Skin(button, true)
            local _, _, accent = view:Palette()
            button:SetBackdropBorderColor(selected and accent[1] or 0.3, selected and accent[2] or 0.34, selected and accent[3] or 0.46, 1)
        else
            button:SetNormalFontObject(selected and GameFontHighlightSmall or GameFontNormalSmall)
        end
        button:SetScript("OnClick", function()
            self.path = path
            if #path == 2 and path[2] == "speedrunning" then
                self.path = {"featureToolsSettings", "speedrunning", "overview"}
            end
            f.scroll:SetVerticalScroll(0); self:Refresh()
        end)
    end
    for i = #entries + 1, #self.pages do self.pages[i]:Hide() end
    f.navChild:SetSize(176, math.max(1, #entries * 36))
    f.child:SetWidth(math.max(280, f.scroll:GetWidth() - 8))
    for _, pool in pairs(self.controls) do for _, row in ipairs(pool) do row:Hide() end end
    local used, y = {}, 0
    for _, item in ipairs(adapter:PageControls(self.path or {"featureToolsSettings", "routePreflight"})) do
        local info = item.info
        local kind = info.supported and info.type or "description"
        if info.type ~= "group" then
            used[kind] = (used[kind] or 0) + 1
            local row = self:Control(used[kind], kind)
            row.path = item.path
            row:SetWidth(f.child:GetWidth()); row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", kind == "toggle" and 32 or 0, kind == "toggle" and -4 or 0)
            row.label:SetWidth(math.max(40, f.child:GetWidth() - (kind == "toggle" and 32 or 0)))
            row.label:SetHeight(0)
            if row.label.SetWordWrap then row.label:SetWordWrap(true) end
            addon.SetFontSafely(row.label, addon.font, math.max(12, tonumber(addon.settings.profile.guideFontSize) or 12), "")
            row.label:SetText(info.supported and (info.name or "") or L("Additional controls are available in Advanced Settings."))
            local height = math.max(26, row.label:GetStringHeight() + 10)
            if kind == "header" then
                local _, _, accent = view:Palette()
                if view:IsModern() then row.label:SetTextColor(unpack(accent)) else row.label:SetTextColor(1, 0.82, 0) end
            end
            if row.widget then
                if info.disabled then row.widget:Disable() else row.widget:Enable() end
                if kind == "toggle" then row.widget:SetChecked(adapter:Value(item.path, "get"))
                elseif kind == "range" then
                    row.rangeInfo = info
                    row.widget:ClearAllPoints()
                    row.widget:SetPoint("TOPLEFT", 0, -height)
                    row.widget:SetPoint("RIGHT", -15, 0)
                    row.value:SetPoint("TOPRIGHT", 0, -height - 21)
                    row.widget:SetMinMaxValues(info.min, info.max)
                    row.widget:SetValueStep(info.step or 1)
                    row.widget:SetValue(adapter:Value(item.path, "get") or info.min)
                    -- Reused sliders may retain the same number while their
                    -- display format changes; SetValue need not fire an event.
                    row.value:SetText(self:FormatValue(row.widget:GetValue(), info))
                    height = height + 42
                elseif kind == "select" then
                    row.widget:SetPoint("TOPLEFT", 0, -height)
                    row.widget:SetText((info.values or {})[adapter:Value(item.path, "get")] or L("Select")); height = height + 32
                else row.widget:SetText(info.name or ""); row.label:SetText("") end
            end
            row:SetAlpha(info.disabled and 0.55 or 1)
            row:SetHeight(height); row:Show(); y = y + height + 8
        end
    end
    f.child:SetHeight(math.max(1, y))
    -- Reparenting is intentionally avoided; newly pooled controls just join
    -- their owning window's existing frame-level band.
    if self.layersDirty then
        self.layersDirty = nil
        addon.toolWindows:RefreshLayering()
    end
end
