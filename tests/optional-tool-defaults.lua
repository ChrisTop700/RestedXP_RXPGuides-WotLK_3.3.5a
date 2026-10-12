return function(root)
    local function read(path)
        local f = assert(io.open(root .. "/" .. path, "rb"))
        local text = f:read("*a"); f:close(); return text
    end
    local settings = read("UI/Settings.lua")
    for _, key in ipairs({"enableSpeedrunSuite", "enablePetAssistant", "enableStepDoctor",
        "enableSuppliesChecklist", "enablePersonalBestArchives"}) do
        assert(settings:find(key .. " = false", 1, true), key .. " must default off")
    end
    local frames, messages, pending = 0, {}, {}
    local env = setmetatable({RXPData = {}, RXPCData = {},
        CreateFrame = function()
            frames = frames + 1
            return {RegisterEvent = function(self, e) self[e] = true end,
                UnregisterAllEvents = function(self)
                    for key, value in pairs(self) do if value == true then self[key] = nil end end
                end, SetScript = function() end}
        end}, {__index = _G})
    env._G = env
    local addon = {locale = {Get = function(s) return s end}, settings = {profile = {}},
        player = {class = "HUNTER"}, toolWindows = {},
        scheduler = {After = function(_, owner, key) pending[key] = true end,
            CancelOwner = function() pending = {} end},
        RegisterMessage = function(_, event, callback) messages[event] = callback end}
    for _, file in ipairs({"Diagnostics", "Supplies", "RunArchive", "PetAssistant", "SpeedrunCore"}) do
        setfenv(assert(loadfile(root .. "/Features/" .. file .. ".lua")), env)("test", addon)
    end
    for _, module in ipairs({addon.diagnostics, addon.supplies, addon.runArchive,
        addon.petAssistant, addon.speedrun}) do module:Setup() end
    assert(frames == 0 and next(messages) == nil and next(env.RXPData) == nil)
    addon.diagnostics:Record("ignored", {})
    addon.petAssistant:ScheduleRefresh()
    addon.runArchive:Snapshot()
    assert(not addon.diagnostics.records and next(pending) == nil)
    assert(not addon.runArchive:GetCurrent(true))
    assert(not addon.speedrun:EnsureLiveSetup())

    addon.settings.profile.enableStepDoctor = true
    addon.diagnostics:Setup()
    local frame = addon.diagnostics.eventFrame
    assert(frame.QUEST_LOG_UPDATE)
    addon.settings.profile.enableStepDoctor = false
    addon.diagnostics:Shutdown()
    assert(not frame.QUEST_LOG_UPDATE)
    addon.settings.profile.enableStepDoctor = true
    addon.diagnostics:Setup()
    assert(addon.diagnostics.eventFrame == frame and frame.QUEST_LOG_UPDATE)

    addon.settings.profile.enablePetAssistant = true
    addon.petAssistant:Setup()
    local petFrame = addon.petAssistant.eventFrame
    addon.petAssistant:ScheduleRefresh()
    assert(pending["pet-refresh"])
    addon.settings.profile.enablePetAssistant = false
    addon.petAssistant:Shutdown()
    assert(not petFrame.BAG_UPDATE and next(pending) == nil)
    addon.settings.profile.enablePetAssistant = true
    addon.petAssistant:Setup()
    assert(addon.petAssistant.eventFrame == petFrame)
    addon.supplies.CreateFrame = function(self)
        self.frame = self.frame or {Hide = function() end}
    end
    addon.settings.profile.enableSuppliesChecklist = true
    addon.supplies:Setup()
    local supplyFrame = addon.supplies.eventFrame
    assert(supplyFrame.MERCHANT_SHOW)
    addon.settings.profile.enableSuppliesChecklist = false
    addon.supplies:Shutdown()
    assert(not supplyFrame.MERCHANT_SHOW)
    addon.supplies:ExecutePurchase({}) -- no purchases can escape a disabled checklist
    addon.settings.profile.enableSuppliesChecklist = true
    addon.supplies:Setup()
    assert(addon.supplies.eventFrame == supplyFrame)
    assert(not addon.runArchive:IsEnabled())
    addon.settings.profile.enableSpeedrunSuite = true
    assert(addon.runArchive:IsEnabled()) -- explicit suite opt-in retains PB dependency
    print("Optional tool default and lifecycle regressions passed.")
end
