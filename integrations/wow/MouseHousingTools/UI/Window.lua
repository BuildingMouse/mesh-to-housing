local _, MHT = ...
local Window = {}
Window.__index = Window
MHT.Window = Window

-- The main window.

local MODES = { { "shapes", "Shapes" }, { "sketch", "3D Sketch" }, { "sculpt", "3D Sculpt" } }
-- Default and smallest sizes. The full and the small window keep their saved state under these prefixes.
local SIZES = {
    window = { width = 1000, height = 724, minWidth = 820, minHeight = 560 },
    compact = { width = 640, height = 500, minWidth = 430, minHeight = 400 },
}

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

    local self = setmetatable({ settings = settings, uiState = uiState, modelSettings = uiState.models,
        mode = "shapes" }, Window)
    self.placement = MHT.Placement.New(MHT.Housing, function(message, completed, total)
        self:OnPlacementMessage(message, completed, total)
    end)
    self:CreateFrame()
    self.developer = MHT.DeveloperWindow.New(self)
    self.settingsPanel = MHT.SettingsPanel.New(self, self.frame)
    self:CreatePreview()
    self.footer = MHT.Footer.New(self, self.frame)
    self.compact = self.uiState.compact == true
    self:Layout()
    self:ApplySavedPosition(UIParent)
    self.chrome = MHT.EditorChrome.New()
    self:SelectMode("shapes")
    self:RestoreBuild()
    self:FitToBuild()
    self.frame:Hide()
    return self
end

function Window:CreateFrame()
    local UI = MHT.UI
    local frame = UI.Surface(UIParent, SIZES.window.width, SIZES.window.height, "window")
    self.frame = frame
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

    self.logo = MHT.Theme.Logo(frame, 18, 4, 54)
    self.title = UI.Text(frame, "Mouse Housing Tools", 84, 20, 540, "GameFontNormalLarge")
    self.title:SetTextColor(unpack(MHT.Theme.Colors.gold))
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", 18, -60)
    tabs:SetPoint("TOPRIGHT", -18, -60)
    tabs:SetHeight(38)
    self.tabs = {}
    for i, tab in ipairs(MODES) do
        local mode = tab[1]
        self.tabs[mode] = UI.Button(tabs, tab[2], (i - 1) * 138, 0, 132, function() self:SelectMode(mode) end, "tab", 34)
    end
    UI.Rule(tabs, 38, 964):SetPoint("TOPRIGHT", 0, -38)
    self.tabFrame = tabs
    self.close = UI.CloseButton(frame, 0, 0, 28, function() frame:Hide() end)
    self.close:ClearAllPoints()
    self.sizeButton = UI.IconButton(frame, "shrink", 0, 0, 28, 14, function() self:ToggleCompact() end)
    self.sizeButton:ClearAllPoints()
    self.sizeButton:SetPoint("TOPRIGHT", self.close, "TOPLEFT", -6, 0)
    UI.Tooltip(self.sizeButton, "Window size", "Switch between the full window and a small preview. Drag the bottom-right corner to resize either one.")
    if MHT.DEV_MODE then
        self.developerButton = UI.Button(frame, "Developer tools", 0, 0, 132,
            function() self.developer:Open("test") end, nil, 30)
        self.developerButton:ClearAllPoints()
        self.developerButton:SetPoint("TOPRIGHT", self.sizeButton, "TOPLEFT", -8, 1)
    end
    self.grip = UI.ResizeGrip(frame, function() self:SaveSize() end)
end

-- The small window keeps only the preview and the footer.
function Window:Layout()
    local compact, frame, state, footer = self.compact, self.frame, self.uiState, self.footer
    local prefix = self:StatePrefix()
    local size = SIZES[prefix]
    frame:SetResizeBounds(size.minWidth, size.minHeight)
    frame:SetSize(math.max(size.minWidth, state[prefix .. "Width"] or size.width),
        math.max(size.minHeight, state[prefix .. "Height"] or size.height))
    local logo = compact and 28 or 54
    self.logo:SetSize(logo, logo)
    self.logo:SetPoint("TOPLEFT", compact and 12 or 18, compact and -8 or -4)
    MHT.Theme.Font(self.title, compact and "heading" or "title")
    self.title:SetPoint("TOPLEFT", compact and 48 or 84, compact and -14 or -20)
    self.close:SetPoint("TOPRIGHT", compact and -10 or -18, compact and -8 or -17)
    self.sizeButton.icon:SetShape(compact and "expand" or "shrink")
    self.tabFrame:SetShown(not compact)
    self.settingsPanel.frame:SetShown(not compact)
    if self.developerButton then self.developerButton:SetShown(not compact) end

    -- The settings column keeps its width, and the preview and the footer take the rest.
    local margin, gap = compact and 12 or 18, compact and 8 or 12
    local panel = self.previewPanel
    panel:ClearAllPoints()
    footer.frame:ClearAllPoints()
    footer:SetCompact(compact)
    footer.frame:SetPoint("BOTTOMLEFT", margin, margin)
    footer.frame:SetPoint("BOTTOMRIGHT", -margin, margin)
    panel:SetPoint("TOPLEFT", compact and 12 or 394, compact and -44 or -104)
    panel:SetPoint("BOTTOMRIGHT", footer.frame, "TOPRIGHT", 0, gap)
    self.settingsPanel.frame:SetPoint("BOTTOMLEFT", footer.frame, "TOPLEFT", 0, gap)
    self.previewHeading:SetShown(not compact)
    self.roomPicker:SetShown(not compact)
    self.preview:SetRoom(compact and "none" or self.uiState.previewRoom)
    self.preview.frame:SetPoint("TOPLEFT", 14, compact and -14 or -44)
    self.preview.frame:SetPoint("BOTTOMRIGHT", -14, compact and 14 or 58)
    self.resetView:ClearAllPoints()
    if compact then
        self.resetView:SetPoint("TOPRIGHT", -20, -20)
    else
        self.resetView:SetPoint("BOTTOMRIGHT", -14, 16)
    end
end

function Window:SetCompact(compact)
    if self.compact == compact then return end
    self:SavePosition()
    self.compact = compact
    self.uiState.compact = compact or nil
    self:Layout()
    self:ApplySavedPosition(self.frame:GetParent())
end

function Window:ToggleCompact()
    self:SetCompact(not self.compact)
end

-- A build only needs the preview, so the window shrinks once when a build starts.
-- When the build ends, finished or ended by the player, the full window comes back.
function Window:FitToBuild()
    local state = self.uiState
    local running = self.placement:Busy() or self.placement:HasSession()
    if running and not state.sizedForBuild then
        state.sizedForBuild = true
        self:SetCompact(true)
    elseif not running and state.sizedForBuild then
        state.sizedForBuild = nil
        self:SetCompact(false)
    end
end

function Window:CreatePreview()
    local UI = MHT.UI
    local panel = UI.Surface(self.frame, 588, 512, "deep")
    self.previewPanel = panel
    self.previewHeading = UI.Heading(panel, "Preview", 14, 14, 270)
    self.preview = MHT.Preview.New(panel)
    MHT.Theme.Skin(self.preview.frame, nil)

    local rooms = {}
    for _, room in ipairs(MHT.Rooms.Entries) do rooms[#rooms + 1] = { id = room.id, name = "Room: " .. room.name } end
    rooms[#rooms + 1] = { id = "none", name = "Room: None" }
    local roomID = self.uiState.previewRoom
    if roomID ~= "none" and not MHT.Rooms.Get(roomID) then roomID = MHT.Rooms.DEFAULT_ID end
    self.uiState.previewRoom = roomID
    local picker = UI.Dropdown(panel, 14, 470, 166, rooms, roomID, function(id)
        self.uiState.previewRoom = id
        self.preview:SetRoom(id)
    end)
    self.roomPicker = picker
    picker:ClearAllPoints()
    picker:SetPoint("BOTTOMLEFT", 14, 12)
    picker.menu:ClearAllPoints()
    picker.menu:SetPoint("BOTTOMLEFT", picker, "TOPLEFT", 0, 2)
    UI.Tooltip(picker, "Preview room",
        "Small is twice as wide as Tiny, Medium three times and Large four times. All rooms are as high as Tiny.")
    self.preview:SetRoom(roomID)
    local reset = UI.ResetButton(panel, 0, 0, function() self.preview:ResetView() end)
    -- The small window puts the button over the preview's corner.
    reset:SetFrameLevel(self.preview.frame:GetFrameLevel() + 2)
    self.resetView = reset
    UI.Tooltip(reset, "Reset view", "Drag to turn the preview, right-drag to move it, and scroll to zoom.")
end

-- A build paused before a /reload comes back paused.
function Window:RestoreBuild()
    local saved = self.uiState.buildProgress
    if not saved then return end
    if self.tabs[saved.mode] then self:SelectMode(saved.mode) end
    if not self.placement:RestoreBuild(saved.placement) then self.uiState.buildProgress = nil end
end

function Window:SaveBuildProgress()
    local placement = self.placement
    self.uiState.buildProgress = placement.stage == "building"
        and { placement = placement:SaveBuild(), mode = self.mode } or nil
end

function Window:Busy()
    return self.placement:Busy() or self.developer:Busy()
end

-- Settings stay fixed from Prepare until the build ends.
function Window:Locked()
    return self:Busy() or self.placement:HasSession()
end

function Window:SelectMode(mode)
    if self:Locked() then return end
    self.mode = mode
    self.settingsPanel:ScrollToTop()
    self:Refresh()
end

-- Rebuilds the plan from the settings.
function Window:Refresh()
    self.settingsPanel:Refresh()
    local plan, reason = self.settingsPanel:Plan()
    self.plan = plan
    self.preview:SetPlan(plan, self.settingsPanel:Section().points, self:PreviewView())
    self:UpdateProgress(true)
    self:SetStatus(plan and self:StartHint(#plan.items) or reason or "")
    self:UpdateControls()
end

function Window:PreviewView()
    if self.mode ~= "shapes" then return self.mode end
    local shape = self.settings.shape
    if shape == "circle" and self.settings.circle.orientation == "vertical" then return "vertical" end
    local stairs = self.settings.stairs
    if shape == "stairs" and stairs.curveEnabled and stairs.curve ~= 0 then
        return stairs.curve > 0 and "curveRight" or "curveLeft"
    end
    return shape
end

function Window:StartHint(count)
    if self.useExistingPile then
        return string.format("Stack %d copies of the item in one spot, then press Build and click them one at a time.", count)
    end
    return "Press Prepare items, then hover the item to copy and hold the cursor still."
end

function Window:UseExistingPile(checked)
    if self:Locked() then return end
    self.useExistingPile = checked
    self:Refresh()
end

-- Prepares the pile, builds from it once it is ready, and pauses or resumes the build.
function Window:StartPlacement()
    local placement = self.placement
    if placement:CanPause() then placement:Pause(); return end
    if self:Busy() then return end
    local ok, started, reason
    if placement:Ready() or placement:Paused() then
        ok, started, reason = pcall(placement.Build, placement)
    else
        self.settingsPanel:CommitEdits()
        self:Refresh()
        if not self.plan then return end
        local start = self.useExistingPile and placement.BuildFromPile or placement.Prepare
        ok, started, reason = pcall(start, placement, self.plan)
    end
    if not ok then placement:Abort(MHT.Util.ErrorText(started))
    elseif not started then self:SetStatus(reason) end
end

-- Ends whatever runs: a dev tool, or a build.
function Window:EndPlacement(message)
    if self.developer:Stop(message) then return end
    self.placement:End(message)
end

-- A build pauses on an error; anything else ends.
function Window:OnError(message)
    if self.developer:Stop(message) then return end
    self.placement:Abort(message)
end

function Window:SkipItem()
    local ok, skipped, reason = pcall(self.placement.Skip, self.placement)
    if not ok then self.placement:Abort(MHT.Util.ErrorText(skipped))
    elseif not skipped then self:SetStatus(reason) end
end

function Window:SetStatus(message)
    self.footer:SetStatus(message)
end

function Window:OnPlacementMessage(message, completed, total)
    self:SaveBuildProgress()
    self:FitToBuild()
    self:SetStatus(message)
    self.developer:OnPlacementMessage(message, completed, total)
    self:UpdateProgress()
    self:UpdateControls()
end

function Window:UpdateProgress(reset)
    local placement, footer = self.placement, self.footer
    local running = not reset and (placement:Busy() or placement:HasSession()) and placement.plan ~= nil
    local plan = running and placement.plan or self.plan
    local total = plan and #plan.items or 0
    footer:SetCount(self:CountText(total, running))
    if running then
        footer:SetTime(placement:RemainingSeconds())
        footer:SetProgress(not placement:Ready() and placement:Progress() or nil)
        self.preview:SetItemLooks(self:ItemLooks())
    else
        self.preview:SetItemLooks({})
        footer:SetTime(plan and MHT.Placement.Estimate(plan, self.useExistingPile))
        footer:SetProgress(nil)
    end
end

-- The current item stays highlighted between moves, so the preview always shows what comes next.
function Window:ItemLooks()
    local placement, looks = self.placement, {}
    if placement.stage ~= "building" then return looks end
    local _, current = placement:Current()
    for index, item in ipairs(placement.items) do
        looks[index] = index == current and "placing" or item.state == "saved" and "built" or "waiting"
    end
    return looks
end

function Window:CountText(total, running)
    local placement = self.placement
    if total == 0 then return "Items: —" end
    if not running then return string.format("%d items", total) end
    if placement.stage == "preparing" then return string.format("Preparing %d / %d", placement.copiesCreated, total) end
    if placement:Ready() then return string.format("%d copies ready", total) end
    return string.format("%d / %d", placement:Completed(), total)
end

function Window:UpdateControls()
    local placement, developer = self.placement, self.developer
    local busy, locked = self:Busy(), self:Locked()
    developer:UpdateControls(placement:Busy() or placement:HasSession(), locked)
    self.settingsPanel:UpdateControls(locked)
    for mode, tab in pairs(self.tabs) do
        tab:SetEnabled(not locked)
        tab:SetSelected(self.mode == mode)
    end
    if self.developerButton then self.developerButton:SetEnabled(not locked) end
    local canStart = placement:CanPause()
        or not busy and (placement:Ready() or placement:Paused() or not locked and self.plan ~= nil)
    self.footer:Update(placement, canStart, locked, self.useExistingPile)
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

function Window:StatePrefix()
    return self.compact and "compact" or "window"
end

function Window:SavePosition()
    local x, y = centerOffset(self.frame)
    local prefix = self:StatePrefix()
    if x then self.uiState[prefix .. "X"], self.uiState[prefix .. "Y"] = x, y end
end

function Window:ApplySavedPosition(parent)
    local state, prefix = self.uiState, self:StatePrefix()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", parent or UIParent, "CENTER",
        state[prefix .. "X"] or state.windowX or 0, state[prefix .. "Y"] or state.windowY or 0)
end

function Window:SaveSize()
    local prefix = self:StatePrefix()
    self.uiState[prefix .. "Width"], self.uiState[prefix .. "Height"] = self.frame:GetSize()
    self:SavePosition()
    self:ApplySavedPosition(self.frame:GetParent())
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
