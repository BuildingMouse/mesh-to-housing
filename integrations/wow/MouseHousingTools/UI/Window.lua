local _, MHT = ...
local Window = {}
Window.__index = Window
MHT.Window = Window

local function parentCenter(parent)
    local x, y = parent:GetCenter()
    return x or 0, y or 0
end

function Window.New(settings, uiState)
    uiState = uiState or {}
    if MHT.Layout.Solids[settings.shape] then settings.shape = "stairs" end

    local self = setmetatable({ settings = settings, uiState = uiState,
                               controls = {}, inputs = {} }, Window)
    local UI = MHT.UI
    local frame = UI.Panel(UIParent, 810, 610)
    self.frame = frame

    frame:SetPoint("CENTER", UIParent, "CENTER", uiState.windowX or 0, uiState.windowY or 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function() if not self:Busy() then frame:StartMoving() end end)

    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        self:SavePosition()
    end)

    UI.Text(frame, "MouseHousingTools", 18, 15, 500, "GameFontNormalLarge")
    UI.Button(frame, "X", 758, 10, 34, function() frame:Hide() end)

    self.shapesTab = UI.Button(frame, "Shapes", 18, 46, 120, function() self:Mode("shapes") end)
    self.objectsTab = UI.Button(frame, "3D Objects", 146, 46, 120, function() self:Mode("objects") end)
    self.testTab = UI.Button(frame, "Tests", 274, 46, 130, function() self:Mode("test") end)
    self.captureTab = UI.Button(frame, "Movement capture", 412, 46, 145, function() self:Mode("capture") end)
    self.calibrationTab = UI.Button(frame, "Calibrate", 565, 46, 120, function() self:Mode("calibration") end)
    self.cornersTab = UI.Button(frame, "Corner test", 693, 46, 100, function() self:Mode("corners") end)

    self.objects = CreateFrame("Frame", nil, frame)
    self.objects:SetAllPoints(frame)
    UI.Text(self.objects, "3D Objects", 300, 240, 250, "GameFontNormalLarge")
    UI.Text(self.objects, "Coming soon", 300, 275, 250)
    self.objects:Hide()

    self.content = CreateFrame("Frame", nil, frame)
    self.content:SetAllPoints(frame)

    self.stairs = UI.Button(self.content, "Stairs", 18, 82, 120, function() settings.shape = "stairs"; self:Refresh() end)
    self.circle = UI.Button(self.content, "Circle", 146, 82, 120, function() settings.shape = "circle"; self:Refresh() end)
    local fields = {
        { "count", "Items" }, { "rotation", "Item rotation (deg)" },
        { "slope", "Stair slope (deg)" }, { "spacing", "Straight step spacing" },
        { "turns", "Stair turns (0 = straight)" }, { "radius", "Curve / circle radius" },
        { "width", "Item width" }, { "depth", "Item depth" },
        { "thickness", "Item thickness" }, { "clearance", "Source clearance" },
    }

    for i, field in ipairs(fields) do
        local control = UI.Number(self.content, field[2], 18 + ((i - 1) % 2) * 133,
            120 + math.floor((i - 1) / 2) * 54, settings[field[1]], function(value)
                settings[field[1]] = value
                self:Refresh()
            end)
        self.controls[#self.controls + 1] = control
        self.inputs[field[1]] = control
    end

    self.scaleLabel = UI.Text(self.content, "", 18, 397, 250)
    self.scale = CreateFrame("Slider", nil, self.content, "BackdropTemplate")
    self.scale:SetPoint("TOPLEFT", 20, -425)
    self.scale:SetSize(238, 15)
    self.scale:SetOrientation("HORIZONTAL")
    self.scale:SetMinMaxValues(0.2, 2)
    self.scale:SetValueStep(0.01)
    self.scale:SetObeyStepOnDrag(true)
    self.scale:SetThumbTexture("Interface/Buttons/UI-SliderBar-Button-Horizontal")
    self.scale:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    self.scale:SetBackdropColor(0.2, 0.24, 0.3, 1)
    self.scale:SetValue(settings.scale)
    self.scale:SetScript("OnValueChanged", function(_, value)
        settings.scale = math.floor(value * 100 + 0.5) / 100
        self:Refresh()
    end)
    self.controls[#self.controls + 1] = self.scale

    UI.Text(
        self.content,
        "Movement uses fixed timing: 1 coordinate unit = 1 second. Scaling uses about 5 seconds for 100% to 200%. Curved stair spacing follows radius, turns, and item count.",
        18, 450, 260
    )

    self.preview = MHT.Preview.New(self.content)
    self.summary = UI.Text(self.content, "", 302, 510, 490)
    self.status = UI.Text(frame, "", 18, 563, 774)

    self.testsFrame = CreateFrame("Frame", nil, frame)
    self.testsFrame:SetAllPoints(frame)
    self.testCase, self.testChoices = "transform", {}
    self.testChoices.transform = UI.Button(self.testsFrame, "Transform", 18, 82, 120,
        function() self:TestCase("transform") end)
    for i, case in ipairs(MHT.TestFiguresPanel.Cases) do
        local id = case.id
        self.testChoices[id] = UI.Button(self.testsFrame, case.name, 146 + (i - 1) * 145, 82, 137,
            function() self:TestCase(id) end)
    end
    self.testChoices.resize = UI.Button(self.testsFrame, "Resize", 581, 82, 137,
        function() self:TestCase("resize") end)
    self.testContent = CreateFrame("Frame", nil, self.testsFrame)
    self.testContent:SetAllPoints(self.testsFrame)
    self.figures = MHT.TestFiguresPanel.New(self.testsFrame,
        function() self:StartFigureTest() end, function() self:EndPlacement() end)
    uiState.transformTest = uiState.transformTest or {}
    self.testSettings = uiState.transformTest
    -- Replace the old unmeasured 90 deg/sec default once; retain custom speeds.
    if not uiState.rotationSpeedVersion then
        if self.testSettings.rotate == 90 then self.testSettings.rotate = MHT.Motion.StandardProfile.rotate end
        uiState.rotationSpeedVersion = 1
    end
    local testFields = {
        { "x", "Shift X", 0 }, { "y", "Shift Y", 0 }, { "z", "Shift Z", 0 },
        { "rx", "Rotate X (deg)", 0 }, { "ry", "Rotate Y (deg)", 0 }, { "rz", "Rotate Z (deg)", 45 },
        { "rotate", "Rotation deg / sec", MHT.Motion.StandardProfile.rotate },
        { "firstRotationAxis", "First cycled axis (1-3)", 1 },
    }
    self.testInputs = {}
    for i, field in ipairs(testFields) do
        if self.testSettings[field[1]] == nil then self.testSettings[field[1]] = field[3] end
        local control = UI.Number(self.testContent, field[2], 18 + ((i - 1) % 3) * 260,
            120 + math.floor((i - 1) / 3) * 60, self.testSettings[field[1]], function(value)
                self.testSettings[field[1]] = value
            end)
        self.testInputs[#self.testInputs + 1] = control
    end
    UI.Text(self.testContent,
        "Deselect the item, press Start, then click it in Advanced mode. This raw API test shifts the pivot and adds rotation on X, Y, Z one at a time. No pivot compensation; size stays unchanged. End cancels the test.",
        18, 330, 740)
    UI.Text(self.testContent,
        "Use an item with all three rings. Test one nonzero angle at a time. Timing is an estimate; adjust deg / sec. First cycled axis: 1 = X, 2 = Y, 3 = Z. These rotation settings also apply to shapes.",
        18, 390, 740)

    uiState.calibration = uiState.calibration or {}
    uiState.calibration.measurements = uiState.calibration.measurements or {}
    self.placement = MHT.Placement.New(MHT.Housing, function(message, completed, total)
        self:SetStatus(message, completed, total)
        self.progress:SetText(total > 0 and string.format("%d / %d", completed, total) or "")
        self.figures.progress:SetText(total > 0 and string.format("%d / %d", completed, total) or "")
        self:Lock(self.placement:Busy())
    end, uiState.calibration.measurements)
    self.capture = MHT.CapturePanel.New(frame, MHT.Housing, function() self:StartCapture() end, function(message)
        if not self.calibration or not self.calibration:Busy() then self:SetStatus(message) end
        self:Lock(self.placement:Busy())
    end)
    self.calibration = MHT.CalibrationPanel.New(frame, MHT.Housing, self.capture, uiState.calibration,
        function() self:StartCalibration() end, function(message)
        self:SetStatus(message)
        self:Lock(self.placement:Busy())
    end, function() self:StartCalibrationTest() end)
    uiState.resizeTest = uiState.resizeTest or {}
    self.resizeTest = MHT.ResizeTestPanel.New(self.testsFrame, self.calibration.resizePanel.controller,
        uiState.resizeTest, uiState.calibration, function() self:StartResizeTest() end,
        function() self:EndPlacement() end, function(message) self:SetStatus(message) end)
    self.corners = MHT.CornerTestPanel.New(frame, MHT.Housing, uiState.calibration.measurements,
        function(id) self:StartCornerTest(id) end, function(message, completed, total)
        self:SetStatus(message, completed, total)
        self:Lock(self.placement:Busy())
    end)

    self.start = UI.Button(self.content, "Start", 18, 525, 95, function() self:StartPlacement() end)
    self.abort = UI.Button(self.content, "Abort", 121, 525, 95, function() self:EndPlacement() end)
    self.progress = UI.Text(self.content, "", 227, 532, 70)
    self.testStart = UI.Button(self.testContent, "Start", 18, 490, 95, function() self:StartTest() end)
    self.testAbort = UI.Button(self.testContent, "End", 121, 490, 95, function() self:EndPlacement() end)

    frame:SetScript("OnHide", function() self:SavePosition() end)

    self:Refresh()
    self:Lock(false)
    self:Mode("shapes")
    frame:Hide()
    return self
end

function Window:Busy()
    return self.placement:Busy() or self.capture:Busy() or self.calibration:Busy() or self.corners:Busy()
end

function Window:Update(elapsed)
    self.capture:Update(elapsed)
    self.placement:Update(elapsed)
    self.calibration:Update(elapsed)
    if self.calibration.resizePanel.controller:Busy() then self.resizeTest:Refresh(true) end
    self.corners:Update(elapsed)
end

function Window:OnEvent(event, ...)
    self.capture:OnEvent(event, ...)
    self.placement:OnEvent(event, ...)
    self.calibration:OnEvent(event, ...)
    self.corners:OnEvent(event, ...)
end

function Window:SavePosition()
    local parent = self.frame:GetParent() or UIParent
    local x, y = self.frame:GetCenter()
    local px, py = parentCenter(parent)
    if x and y then
        self.uiState.windowX = x - px
        self.uiState.windowY = y - py
    end
end

function Window:ApplySavedPosition(parent)
    parent = parent or UIParent
    self.frame:ClearAllPoints()
    self.frame:SetPoint(
        "CENTER",
        parent,
        "CENTER",
        self.uiState.windowX or 0,
        self.uiState.windowY or 0
    )
end

function Window:SetHousingParent(parent)
    parent = parent or UIParent

    if self.frame:GetParent() == parent then return end

    self:SavePosition()
    local wasShown = self.frame:IsShown()

    self.frame:SetParent(parent)
    self:ApplySavedPosition(parent)
    self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    self.frame:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 90)
    self.capture:SetHousingParent(parent)

    self.frame:SetShown(wasShown)
end

function Window:SetStatus(message, completed, total)
    self.status:SetText(message)
    if self.onStatus then self.onStatus(message, completed, total) end
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

function Window:StartPlacement()
    if self:Busy() then return end
    if self.mode == "test" then
        if self.testCase == "transform" then self:StartTest()
        elseif self.testCase == "resize" then self:StartResizeTest()
        else self:StartFigureTest() end
        return
    end
    if self.mode == "capture" then self:StartCapture(); return end
    if self.mode == "calibration" then self:StartCalibration(); return end
    if self.mode == "corners" then self:StartCornerTest(); return end

    self:Mode("shapes")
    self:Refresh()
    if not self.plan then return end
    if not self:ValidRotationSettings() then return end

    local ok, started, reason = pcall(
        self.placement.Start,
        self.placement,
        self.plan,
        self:MotionProfile(),
        self.settings.placementWorkflow
    )

    if not ok then
        self.placement:Abort(tostring(started))
    elseif not started then
        self:SetStatus(reason)
    end
end

function Window:MotionProfile()
    local profile = {}
    for key, value in pairs(MHT.Motion.StandardProfile) do profile[key] = value end
    profile.rotate = self.testSettings.rotate
    profile.firstRotationAxis = self.testSettings.firstRotationAxis
    return profile
end

function Window:StartTest()
    if self:Busy() then return end
    local s = self.testSettings
    for _, key in ipairs({ "x", "y", "z", "rx", "ry", "rz" }) do
        if type(s[key]) ~= "number" or s[key] ~= s[key] or math.abs(s[key]) > 360 then
            self:SetStatus("Test offsets and angles must be between -360 and 360.")
            return
        end
    end
    if not self:ValidRotationSettings() then return end
    local ok, started, reason = pcall(self.placement.StartTest, self.placement,
        { x = s.x, y = s.y, z = s.z, rotation = { x = s.rx, y = s.ry, z = s.rz } },
        self:MotionProfile())
    if not ok then
        self.placement:Abort(tostring(started))
    elseif not started then
        self:SetStatus(reason)
    end
end

function Window:StartCapture()
    if self:Busy() then return end
    local ok, started, reason = pcall(self.capture.Start, self.capture)
    if not ok then
        self.capture:Stop(tostring(started))
    elseif not started then
        self:SetStatus(reason)
    end
end

function Window:TestCase(id)
    if self:Busy() then return end
    if id ~= "transform" and id ~= "resize" and not self.figures:Select(id) then return end
    if id == "resize" then self.resizeTest:Preview() end
    self.testCase = id
    self:Mode("test")
    self:Lock(false)
end

function Window:StartFigureTest()
    if self:Busy() or not self:ValidRotationSettings() then return end
    local ok, started, reason = pcall(self.placement.Start, self.placement,
        self.figures.plan, self:MotionProfile(), self.settings.placementWorkflow)
    if not ok then self.placement:Abort(tostring(started))
    elseif not started then self:SetStatus(reason) end
end

function Window:StartCalibration()
    local kind = self.calibration.settings.kind
    if self:Busy() or ((kind == "pivot" or kind == "axes") and not self:ValidRotationSettings()) then return end
    self.calibration:Start(self:MotionProfile())
end

function Window:StartResizeTest()
    if self:Busy() then return end
    local percent = self.uiState.resizeTest.percent
    if type(percent) ~= "number" or percent ~= percent or percent < 20 or percent > 200 then
        self:SetStatus("Item size must be between 20% and 200%."); return
    end
    local c = self.calibration.resizePanel.controller
    local ok, started, reason = pcall(c.Start, c, "corners", self.calibration.settings.workflow,
        self:MotionProfile(), percent / 100)
    if not ok then c:Abort(tostring(started)) elseif not started then self:SetStatus(reason) end
end

function Window:StartCalibrationTest()
    if self:Busy() or (self.calibration.settings.kind == "pivot" and not self:ValidRotationSettings()) then return end
    self.calibration:StartTest(self:MotionProfile())
end

function Window:StartCornerTest(id)
    if self:Busy() or not self:ValidRotationSettings() then return end
    self.corners:Start(id, self:MotionProfile())
end

function Window:ValidRotationSettings()
    local s = self.testSettings
    if type(s.rotate) ~= "number" or s.rotate ~= s.rotate or s.rotate <= 0 or s.rotate > 3600 then
        self:SetStatus("Rotation speed must be greater than 0 and at most 3600 degrees / second.")
        return false
    end
    if s.firstRotationAxis ~= 1 and s.firstRotationAxis ~= 2 and s.firstRotationAxis ~= 3 then
        self:SetStatus("First cycled axis must be 1 (X), 2 (Y), or 3 (Z).")
        return false
    end
    return true
end

function Window:EndPlacement(message)
    if self.corners:Busy() then
        self.corners:Abort(message)
    elseif self.calibration:Busy() then
        self.calibration:Abort(message)
    elseif self.capture:Busy() or self.capture.bindingsInstalled then
        self.capture:Stop(message)
    else
        self.placement:Abort(message)
    end
end

function Window:Mode(mode)
    if self:Busy() then return end
    self.mode = mode
    self.content:SetShown(mode == "shapes")
    self.objects:SetShown(mode == "objects")
    self.testsFrame:SetShown(mode == "test")
    self.testContent:SetShown(mode == "test" and self.testCase == "transform")
    self.figures.frame:SetShown(mode == "test" and self.testCase ~= "transform" and self.testCase ~= "resize")
    self.resizeTest.frame:SetShown(mode == "test" and self.testCase == "resize")
    self.capture.frame:SetShown(mode == "capture")
    self.calibration.frame:SetShown(mode == "calibration")
    self.corners.frame:SetShown(mode == "corners")
    self.shapesTab:SetEnabled(mode ~= "shapes")
    self.objectsTab:SetEnabled(mode ~= "objects")
    self.testTab:SetEnabled(mode ~= "test")
    self.captureTab:SetEnabled(mode ~= "capture")
    self.calibrationTab:SetEnabled(mode ~= "calibration")
    self.cornersTab:SetEnabled(mode ~= "corners")
    if mode == "corners" then
        self.corners:Refresh(true)
        self:SetStatus("Run a named test, click the tile, then corners 1, 2, 3, 4. Restore the starting layout between cases.")
    end
    if mode == "test" then self:SetStatus(self.testCase == "transform"
        and "Set shift and rotation, then Start and click an item in Advanced mode."
        or "Start the test, then hover a calibrated tile at 100% size. Keep still while copies are created.") end
    if mode == "capture" then self:SetStatus("Select an item in Advanced mode, then Start to capture movement keys.") end
    if mode == "calibration" then self:SetStatus(self.calibration.settings.kind == "axes"
        and "Choose an axis. In Advanced mode, select a placed copy and Start, or Start then click it."
        or "Choose a test and axis. Deselect the item, then Start and hover the source.") end
end

function Window:Lock(busy)
    local calibrating = self.calibration and self.calibration:Busy()
    local corners = self.corners and self.corners:Busy()
    self.capture:SetBlocked(busy or calibrating or corners)
    if self.calibration then self.calibration:SetBlocked(busy or corners or (self.capture:Busy() and not calibrating)) end
    if self.corners then self.corners:SetBlocked(busy or calibrating or self.capture:Busy()) end
    busy = busy or calibrating
    busy = busy or self.capture:Busy()
    busy = busy or corners
    for _, control in ipairs(self.controls) do control:SetEnabled(not busy) end

    local stairs = self.settings.shape == "stairs"
    self.inputs.slope:SetEnabled(not busy and stairs)
    self.inputs.turns:SetEnabled(not busy and stairs)
    self.inputs.spacing:SetEnabled(not busy and stairs and self.settings.turns == 0)
    self.inputs.radius:SetEnabled(not busy and (not stairs or self.settings.turns ~= 0))
    self.stairs:SetEnabled(not busy and self.settings.shape ~= "stairs")
    self.circle:SetEnabled(not busy and self.settings.shape ~= "circle")
    self.objectsTab:SetEnabled(not busy)
    self.shapesTab:SetEnabled(not busy and self.mode ~= "shapes")
    self.testTab:SetEnabled(not busy and self.mode ~= "test")
    for id, button in pairs(self.testChoices) do button:SetEnabled(not busy and self.testCase ~= id) end
    self.figures:SetBlocked(busy)
    self.resizeTest:Refresh(busy)
    self.captureTab:SetEnabled(not busy and self.mode ~= "capture")
    self.calibrationTab:SetEnabled(not busy and self.mode ~= "calibration")
    self.cornersTab:SetEnabled(not busy and self.mode ~= "corners")
    for _, control in ipairs(self.testInputs) do control:SetEnabled(not busy) end
    self.testStart:SetEnabled(not busy)
    self.testAbort:SetEnabled(busy)
    self.start:SetEnabled(not busy and self.plan ~= nil)
    self.abort:SetEnabled(busy)
end

function Window:Refresh()
    self.scaleLabel:SetText(string.format("Item size: %d%%", math.floor(self.settings.scale * 100 + 0.5)))

    local plan, reason = MHT.Layout.Build(self.settings)
    self.plan = plan
    self.preview:SetPlan(plan, self.settings.shape)

    if plan then
        local batch = (self.settings.placementWorkflow or MHT.Placement.DEFAULT_WORKFLOW) == "batch"
        local source = self.settings.shape == "stairs" and "Gold block" or "Gold dot"
        self.summary:SetText(string.format(
            "%d new items. %s = source/start; blue = shape.\n%s",
            #plan.items, source,
            batch and "Create the full stack first; then click copies in Advanced mode."
                or "Place one copy, click it to move, then return to the source and repeat."
        ))
        self:SetStatus(batch
            and "Hover the source and press Ctrl+S. Keep the mouse still while copies are created; then click them one at a time."
            or "Hover the source and press Ctrl+S. Keep still until the copy is placed; click it to move, then hover the original source again.")
    else
        self.summary:SetText("")
        self:SetStatus(reason)
    end

    self:Lock(self.placement:Busy())
end
