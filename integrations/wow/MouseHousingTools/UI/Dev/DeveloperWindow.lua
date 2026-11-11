local _, MHT = ...
local DeveloperWindow = {}
DeveloperWindow.__index = DeveloperWindow
MHT.DeveloperWindow = DeveloperWindow

-- Calibration and test tools, shown with MHT.DEV_MODE.

local TAB_STATUS = {
    capture = "Select an item in Advanced mode, then Start to capture movement keys.",
    corners = "Run a named test, click the tile, then corners 1, 2, 3, 4. Restore the starting layout between cases.",
}

function DeveloperWindow.New(window)
    local self = setmetatable({ window = window, tab = "test", testCase = "transform", testChoices = {} },
        DeveloperWindow)
    local UI, uiState = MHT.UI, window.uiState
    local frame = UI.Surface(UIParent, 810, 650, "window")
    frame:SetPoint("CENTER", UIParent, "CENTER", uiState.devX or 0, uiState.devY or 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(window.frame:GetFrameLevel() + 20)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(true)
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); self:SavePosition() end)
    frame:SetScript("OnHide", function() self:SavePosition() end)
    self.frame = frame
    UI.Text(frame, "Developer tools", 18, 15, 500, "GameFontNormalLarge")
    self.close = UI.CloseButton(frame, 764, 10, 28, function() frame:Hide() end)
    self.tabs = {
        test = UI.Button(frame, "Tests", 18, 46, 120, function() self:Open("test") end),
        capture = UI.Button(frame, "Movement capture", 146, 46, 145, function() self:Open("capture") end),
        calibration = UI.Button(frame, "Calibrate", 299, 46, 120, function() self:Open("calibration") end),
        corners = UI.Button(frame, "Corner test", 427, 46, 120, function() self:Open("corners") end),
    }
    UI.Rule(frame, 560, 810)
    self.status = UI.Muted(frame, "", 18, 576, 774)

    self.testsFrame = CreateFrame("Frame", nil, frame)
    self.testsFrame:SetAllPoints(frame)
    self.testChoices.transform = UI.Button(self.testsFrame, "Transform", 18, 82, 120,
        function() self:SelectTest("transform") end)
    for i, case in ipairs(MHT.TestFiguresPanel.Cases) do
        local id = case.id
        self.testChoices[id] = UI.Button(self.testsFrame, case.name, 146 + (i - 1) * 145, 82, 137,
            function() self:SelectTest(id) end)
    end
    self.testChoices.resize = UI.Button(self.testsFrame, "Resize", 581, 82, 137,
        function() self:SelectTest("resize") end)

    local function finish() window:EndPlacement() end
    self.transformTest = MHT.TransformTestPanel.New(self.testsFrame, window.motionSettings,
        function() self:StartTransformTest() end, finish)
    uiState.figureTests = uiState.figureTests or {}
    self.figures = MHT.TestFiguresPanel.New(self.testsFrame,
        function() self:StartFigureTest() end, finish, uiState.figureTests)
    self.capture = MHT.CapturePanel.New(frame, MHT.Housing, function() self:StartCapture() end, function(message)
        if not self.calibration or not self.calibration:Busy() then self:SetStatus(message) end
        window:UpdateControls()
    end)
    self.calibration = MHT.CalibrationPanel.New(frame, MHT.Housing, self.capture, uiState.calibration,
        function() self:StartCalibration() end, function(message)
            self:SetStatus(message)
            window:UpdateControls()
        end, function() self:StartCalibrationTest() end)
    uiState.resizeTest = uiState.resizeTest or {}
    self.resizeTest = MHT.ResizeTestPanel.New(self.testsFrame, self.calibration.resizePanel.controller,
        uiState.resizeTest, uiState.calibration, function() self:StartResizeTest() end,
        finish, function(message) self:SetStatus(message) end)
    self.corners = MHT.CornerTestPanel.New(frame, MHT.Housing, uiState.calibration.measurements,
        function(id) self:StartCornerTest(id) end, function(message)
            self:SetStatus(message)
            window:UpdateControls()
        end)
    self:ShowTab()
    frame:Hide()
    return self
end

function DeveloperWindow:Busy()
    return self.capture:Busy() or self.calibration:Busy() or self.corners:Busy()
end

function DeveloperWindow:Open(tab)
    if self.window:Busy() then return end
    self.tab = tab
    self.frame:Show()
    self.frame:Raise()
    self:ShowTab()
    self:SetStatus(self:TabStatus())
    self.window:UpdateControls()
end

function DeveloperWindow:ShowTab()
    local tab, case = self.tab, self.testCase
    self.testsFrame:SetShown(tab == "test")
    self.transformTest.frame:SetShown(tab == "test" and case == "transform")
    self.figures.frame:SetShown(tab == "test" and case ~= "transform" and case ~= "resize")
    self.resizeTest.frame:SetShown(tab == "test" and case == "resize")
    self.capture.frame:SetShown(tab == "capture")
    self.calibration.frame:SetShown(tab == "calibration")
    self.corners.frame:SetShown(tab == "corners")
    if tab == "corners" then self.corners:Refresh(true) end
end

function DeveloperWindow:TabStatus()
    if self.tab == "test" then
        return self.testCase == "transform" and "Set shift and rotation, then Start and click an item in Advanced mode."
            or "Start the test, then hover a calibrated tile at 100% size. Keep still while copies are created."
    elseif self.tab == "calibration" then
        return self.calibration.settings.kind == "axes"
            and "Choose an axis. In Advanced mode, select a placed copy and Start, or Start then click it."
            or "Choose a test and axis. Deselect the item, then Start and hover the source."
    end
    return TAB_STATUS[self.tab]
end

function DeveloperWindow:SelectTest(id)
    if self.window:Busy() then return end
    if id ~= "transform" and id ~= "resize" and not self.figures:Select(id) then return end
    if id == "resize" then self.resizeTest:Preview() end
    self.testCase = id
    self:Open("test")
end

function DeveloperWindow:UpdateControls(placementBusy, busy)
    local capturing, calibrating, cornering = self.capture:Busy(), self.calibration:Busy(), self.corners:Busy()
    self.capture:SetBlocked(placementBusy or calibrating or cornering)
    self.calibration:SetBlocked(placementBusy or cornering or (capturing and not calibrating))
    self.corners:SetBlocked(placementBusy or calibrating or capturing)
    for tab, button in pairs(self.tabs) do
        button:SetEnabled(not busy)
        button:SetSelected(self.tab == tab)
    end
    for id, button in pairs(self.testChoices) do
        button:SetEnabled(not busy)
        button:SetSelected(self.testCase == id)
    end
    self.transformTest:SetBlocked(busy)
    self.figures:SetBlocked(busy)
    self.resizeTest:Refresh(busy)
end

function DeveloperWindow:Update(elapsed)
    self.capture:Update(elapsed)
    self.calibration:Update(elapsed)
    if self.calibration.resizePanel.controller:Busy() then self.resizeTest:Refresh(true) end
    self.corners:Update(elapsed)
end

function DeveloperWindow:OnEvent(event, ...)
    self.capture:OnEvent(event, ...)
    self.calibration:OnEvent(event, ...)
    self.corners:OnEvent(event, ...)
end

function DeveloperWindow:SetStatus(message)
    self.status:SetText(message)
end

-- Dev tests build through the main window's placement too.
function DeveloperWindow:OnPlacementMessage(message, completed, total)
    self:SetStatus(message)
    self.figures.progress:SetText(total > 0 and string.format("%d / %d", completed, total) or "")
end

function DeveloperWindow:Stop(message)
    if self.corners:Busy() then
        self.corners:Abort(message)
    elseif self.calibration:Busy() then
        self.calibration:Abort(message)
    elseif self.capture:Busy() or self.capture.bindingsInstalled then
        self.capture:Stop(message)
    else
        return false
    end
    return true
end

function DeveloperWindow:Run(action, onError, ...)
    local ok, started, reason = pcall(action, ...)
    if not ok then onError(MHT.Util.ErrorText(started))
    elseif not started and reason then self:SetStatus(reason) end
end

function DeveloperWindow:CanStart(needsMotion)
    if self.window:Busy() then return false end
    if needsMotion then
        local valid, reason = self.window:ValidMotionSettings()
        if not valid then self:SetStatus(reason); return false end
    end
    return true
end

function DeveloperWindow:StartTransformTest()
    if not self:CanStart(true) then return end
    local window, s = self.window, self.window.motionSettings
    for _, key in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
        if not MHT.Util.Finite(s[key]) or math.abs(s[key]) > 360 then
            self:SetStatus("Test offsets and angles must be between -360 and 360.")
            return
        end
    end
    local placement = window.placement
    self:Run(placement.StartTest, function(reason) placement:Abort(reason) end, placement,
        { x = s.x, y = s.y, z = s.z, turns = { x = s.rx, y = s.ry, z = s.rz } }, window:MotionProfile())
end

function DeveloperWindow:StartFigureTest()
    if not self:CanStart(true) then return end
    local plan, reason = self.figures:Prepare()
    if not plan then self:SetStatus(reason); return end
    local window = self.window
    local placement = window.placement
    self:Run(placement.Start, function(message) placement:Abort(message) end, placement, plan, window:MotionProfile())
end

function DeveloperWindow:StartCapture()
    if not self:CanStart(false) then return end
    local capture = self.capture
    self:Run(capture.Start, function(reason) capture:Stop(reason) end, capture)
end

function DeveloperWindow:StartCalibration()
    local kind = self.calibration.settings.kind
    if not self:CanStart(kind == "pivot" or kind == "axes") then return end
    self.calibration:Start(self.window:MotionProfile())
end

function DeveloperWindow:StartCalibrationTest()
    if not self:CanStart(self.calibration.settings.kind == "pivot") then return end
    self.calibration:StartTest(self.window:MotionProfile())
end

function DeveloperWindow:StartResizeTest()
    if not self:CanStart(false) then return end
    local window = self.window
    local percent = window.uiState.resizeTest.percent
    if not MHT.Util.Finite(percent) or percent < 20 or percent > 200 then
        self:SetStatus("Item size must be between 20% and 200%.")
        return
    end
    local controller = self.calibration.resizePanel.controller
    self:Run(controller.Start, function(reason) controller:Abort(reason) end, controller,
        "corners", self.calibration.settings.workflow, window:MotionProfile(), percent / 100)
end

function DeveloperWindow:StartCornerTest(id)
    if not self:CanStart(true) then return end
    self.corners:Start(id, self.window:MotionProfile())
end

function DeveloperWindow:SavePosition()
    local x, y = self.frame:GetCenter()
    local px, py = (self.frame:GetParent() or UIParent):GetCenter()
    if x and y then self.window.uiState.devX, self.window.uiState.devY = x - (px or 0), y - (py or 0) end
end

function DeveloperWindow:SetParent(parent)
    self:SavePosition()
    local shown = self.frame:IsShown()
    self.frame:SetParent(parent)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", parent, "CENTER", self.window.uiState.devX or 0, self.window.uiState.devY or 0)
    self.frame:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 110)
    self.frame:SetShown(shown)
    self.capture:SetHousingParent(parent)
end
