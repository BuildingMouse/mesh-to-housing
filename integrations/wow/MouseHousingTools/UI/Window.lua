local _, MHT = ...
local Window = {}
Window.__index = Window
MHT.Window = Window

-- The main window.

local MOTION_DEFAULTS = { rotate = MHT.Motion.StandardProfile.rotate, firstRotationAxis = 1 }
local MODES = { { "shapes", "Shapes" }, { "sketch", "3D Sketch" }, { "sculpt", "3D Sculpt" } }

local function centerOffset(frame)
    local x, y = frame:GetCenter()
    local px, py = (frame:GetParent() or UIParent):GetCenter()
    if x and y then return x - (px or 0), y - (py or 0) end
end

function Window.New(settings, uiState)
    local models = uiState.models or {}
    uiState.models = models
    models.percent, models.itemPercent = models.percent or 100, models.itemPercent or 100
    if not MHT.ModelLibrary.Get(models.id) then models.id = MHT.ModelLibrary.Entries[1].id end
    if models.source ~= "import" then models.source = "library" end
    uiState.calibration = uiState.calibration or {}
    uiState.calibration.measurements = uiState.calibration.measurements or {}
    uiState.transformTest = uiState.transformTest or {}
    local motion = uiState.transformTest
    for key, value in pairs(MOTION_DEFAULTS) do
        if motion[key] == nil then motion[key] = value end
    end

    local self = setmetatable({ settings = settings, uiState = uiState, modelSettings = uiState.models,
        motionSettings = motion, measurements = uiState.calibration.measurements, mode = "shapes" }, Window)
    self.placement = MHT.Placement.New(MHT.Housing, function(message, completed, total)
        self:OnPlacementMessage(message, completed, total)
    end, self.measurements)
    self:CreateFrame()
    self.settingsPanel = MHT.SettingsPanel.New(self, self.frame)
    self:CreatePreview()
    self.footer = MHT.Footer.New(self, self.frame)
    self.developer = MHT.DeveloperWindow.New(self)
    self.chrome = MHT.EditorChrome.New()
    self:SelectMode("shapes")
    self.frame:Hide()
    return self
end

function Window:CreateFrame()
    local UI = MHT.UI
    local frame = UI.Surface(UIParent, 1000, 724, "window")
    self.frame = frame
    frame:SetPoint("CENTER", UIParent, "CENTER", self.uiState.windowX or 0, self.uiState.windowY or 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        self:SavePosition()
    end)
    frame:SetScript("OnHide", function() self:SavePosition() end)
    -- Escape closes the window.
    _G.MouseHousingToolsWindow = frame
    table.insert(UISpecialFrames, "MouseHousingToolsWindow")

    MHT.Theme.Logo(frame, 18, 4, 54)
    local title = UI.Text(frame, "Mouse Housing Tools", 84, 20, 540, "GameFontNormalLarge")
    title:SetTextColor(unpack(MHT.Theme.Colors.gold))
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", 18, -60)
    tabs:SetSize(964, 38)
    self.tabs = {}
    for i, tab in ipairs(MODES) do
        local mode = tab[1]
        self.tabs[mode] = UI.Button(tabs, tab[2], (i - 1) * 138, 0, 132, function() self:SelectMode(mode) end, "tab", 34)
    end
    UI.Rule(tabs, 38, 964)
    self.close = UI.CloseButton(frame, 954, 17, 28, function() frame:Hide() end)
    if MHT.DEV_MODE then
        self.developerButton = UI.Button(frame, "Developer tools", 800, 16, 132,
            function() self.developer:Open("test") end, nil, 30)
    end
end

function Window:CreatePreview()
    local UI = MHT.UI
    local panel = UI.Surface(self.frame, 588, 512, "deep")
    panel:SetPoint("TOPLEFT", 394, -104)
    UI.Heading(panel, "Preview", 14, 14, 270)
    self.preview = MHT.Preview.New(panel)
    self.preview.frame:SetPoint("TOPLEFT", 14, -44)
    self.preview.frame:SetSize(560, 454)
    MHT.Theme.Skin(self.preview.frame, nil)
end

function Window:ItemDimensions(decorID)
    return MHT.ItemProfiles.Dimensions(decorID, self.measurements)
end

function Window:Busy()
    return self.placement:Busy() or self.developer:Busy()
end

function Window:SelectMode(mode)
    if self:Busy() then return end
    self.mode = mode
    self.settingsPanel:ScrollToTop()
    self:Refresh()
end

-- Rebuilds the plan from the settings.
function Window:Refresh()
    self.settingsPanel:Refresh()
    local plan, reason = self.settingsPanel:Plan()
    self.plan = plan
    self.preview:SetPlan(plan, self.settingsPanel:Section().points)
    self:UpdateProgress(true)
    self:SetStatus(plan and "Press Start, then hover the item to copy and hold the cursor still." or reason or "")
    self:UpdateControls()
end

function Window:MotionProfile()
    local profile = MHT.Util.Copy(MHT.Motion.StandardProfile)
    for key in pairs(MOTION_DEFAULTS) do profile[key] = self.motionSettings[key] end
    return profile
end

function Window:ValidMotionSettings()
    local s = self.motionSettings
    if not MHT.Util.Finite(s.rotate) or s.rotate <= 0 or s.rotate > 3600 then
        return false, "Rotation speed must be greater than 0 and at most 3600° / second."
    end
    if s.firstRotationAxis ~= 1 and s.firstRotationAxis ~= 2 and s.firstRotationAxis ~= 3 then
        return false, "First cycled axis must be 1 (X), 2 (Y), or 3 (Z)."
    end
    return true
end

function Window:StartPlacement()
    if self:Busy() then return end
    self.settingsPanel:CommitEdits()
    self:Refresh()
    if not self.plan then return end
    local valid, reason = self:ValidMotionSettings()
    if not valid then self:SetStatus(reason); return end
    local placement = self.placement
    local ok, started, reason = pcall(placement.Start, placement, self.plan, self:MotionProfile())
    if not ok then placement:Abort(MHT.Util.ErrorText(started))
    elseif not started then self:SetStatus(reason) end
end

-- Ends whatever runs: a dev tool, or a build.
function Window:EndPlacement(message)
    if self.developer:Stop(message) then return end
    self.placement:Abort(message)
end

function Window:SetStatus(message)
    self.footer:SetStatus(message)
end

function Window:OnPlacementMessage(message, completed, total)
    self:SetStatus(message)
    self.developer:OnPlacementMessage(message, completed, total)
    self:UpdateProgress()
    self:UpdateControls()
end

-- A running build is previewed as fitted to the real item.
function Window:UpdateProgress(reset)
    local placement = self.placement
    local running = not reset and placement:Busy() and placement.plan ~= nil
    local plan = running and placement.plan or self.plan
    local total = plan and #plan.items or 0
    self.footer:SetCount(total == 0 and "Items: —" or running and string.format("%d / %d", placement.completed, total)
        or string.format("%d items", total))
    if running and self.preview.plan ~= placement.plan then
        self.preview:SetPlan(placement.plan, self.settingsPanel:Section().points)
    end
end

function Window:UpdateControls()
    local placement, developer = self.placement, self.developer
    local busy = self:Busy()
    developer:UpdateControls(placement:Busy(), busy)
    self.settingsPanel:UpdateControls(busy)
    for mode, tab in pairs(self.tabs) do
        tab:SetEnabled(not busy)
        tab:SetSelected(self.mode == mode)
    end
    if self.developerButton then self.developerButton:SetEnabled(not busy) end
    self.footer:Update(not busy and self.plan ~= nil, placement:Busy(), busy)
end

function Window:Update(elapsed)
    self.developer:Update(elapsed)
    self.placement:Update(elapsed)
    if self.placement:Busy() then self:UpdateProgress() end
    self.chrome:SetSuppressed(self.placement:Busy())
end

function Window:OnEvent(event, ...)
    self.developer:OnEvent(event, ...)
    self.placement:OnEvent(event, ...)
end

function Window:Toggle()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:ApplySavedPosition(self.frame:GetParent() or UIParent)
        self.frame:Show()
        self.frame:Raise()
    end
end

function Window:SavePosition()
    local x, y = centerOffset(self.frame)
    if x then self.uiState.windowX, self.uiState.windowY = x, y end
end

function Window:ApplySavedPosition(parent)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", parent or UIParent, "CENTER", self.uiState.windowX or 0, self.uiState.windowY or 0)
end

-- In the housing editor, only its child frames stay visible.
function Window:SetHousingParent(parent)
    parent = parent or UIParent
    if self.frame:GetParent() == parent then return end
    self:SavePosition()
    local shown = self.frame:IsShown()
    self.frame:SetParent(parent)
    self:ApplySavedPosition(parent)
    self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    self.frame:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 90)
    self.developer:SetParent(parent)
    self.frame:SetShown(shown)
end
