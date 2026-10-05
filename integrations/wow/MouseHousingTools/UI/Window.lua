local _, MHT = ...
local Window = {}
Window.__index = Window
MHT.Window = Window

function Window.New(settings, profile)
    local self = setmetatable({ settings = settings, controls = {}, inputs = {} }, Window)
    local UI = MHT.UI
    local frame = UI.Panel(UIParent, 810, 610)
    self.frame = frame
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() if not self.placement:Busy() then frame:StartMoving() end end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    UI.Text(frame, "MouseHousingTools", 18, 15, 500, "GameFontNormalLarge")
    UI.Button(frame, "X", 758, 10, 34, function() self.placement:Abort(); frame:Hide() end)
    self.shapesTab = UI.Button(frame, "Shapes", 18, 46, 120, function() self:Mode("shapes") end)
    self.objectsTab = UI.Button(frame, "3D Objects", 146, 46, 120, function() self:Mode("objects") end)
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
        { "width", "Preview width" }, { "depth", "Preview depth" },
        { "thickness", "Preview thickness" }, { "clearance", "Source clearance" },
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
    UI.Text(self.content, "Dimensions only describe the preview; the real item is scaled uniformly. Curved stair spacing follows radius, turns, and item count. Negative turns reverse the curve.", 18, 450, 260)
    self.preview = MHT.Preview.New(self.content)
    self.summary = UI.Text(self.content, "", 302, 510, 490)
    self.status = UI.Text(self.content, "", 18, 563, 774)
    self.placement = MHT.Placement.New(MHT.Housing, function(message, completed, total)
        self.status:SetText(message)
        self.progress:SetText(total > 0 and string.format("%d / %d", completed, total) or "")
        self:Lock(self.placement:Busy())
    end)
    self.start = UI.Button(self.content, "Start", 18, 525, 95, function()
        self.calibration.frame:Hide()
        self:Refresh()
        if not self.plan then return end
        local ok, started, reason = pcall(self.placement.Start, self.placement, self.plan, profile)
        if not ok then self.placement:Abort(tostring(started))
        elseif not started then self.status:SetText(reason) end
    end)
    self.abort = UI.Button(self.content, "Abort", 121, 525, 95, function() self.placement:Abort() end)
    self.progress = UI.Text(self.content, "", 227, 532, 70)
    self.calibration = MHT.Calibration.New(frame, profile, self.placement)
    self.calibrate = UI.Button(self.content, "Calibration", 670, 525, 122, function() self.calibration.frame:Show() end)
    frame:SetScript("OnHide", function() self.calibration:Restore(); self.placement:Abort() end)
    self:Refresh()
    self:Lock(false)
    self:Mode("shapes")
    frame:Hide()
    return self
end

function Window:Mode(mode)
    if self.placement:Busy() then return end
    self.content:SetShown(mode == "shapes")
    self.objects:SetShown(mode == "objects")
    self.shapesTab:SetEnabled(mode ~= "shapes")
    self.objectsTab:SetEnabled(mode ~= "objects")
end

function Window:Lock(busy)
    for _, control in ipairs(self.controls) do control:SetEnabled(not busy) end
    local stairs = self.settings.shape == "stairs"
    self.inputs.slope:SetEnabled(not busy and stairs)
    self.inputs.turns:SetEnabled(not busy and stairs)
    self.inputs.spacing:SetEnabled(not busy and stairs and self.settings.turns == 0)
    self.inputs.radius:SetEnabled(not busy and (not stairs or self.settings.turns ~= 0))
    self.stairs:SetEnabled(not busy and self.settings.shape ~= "stairs")
    self.circle:SetEnabled(not busy and self.settings.shape ~= "circle")
    self.objectsTab:SetEnabled(not busy)
    self.start:SetEnabled(not busy and self.plan ~= nil)
    self.abort:SetEnabled(busy)
    self.calibrate:SetEnabled(not busy)
end

function Window:Refresh()
    self.scaleLabel:SetText(string.format("Item size: %d%%", math.floor(self.settings.scale * 100 + 0.5)))
    local plan, reason = MHT.Layout.Build(self.settings)
    self.plan = plan
    self.preview:SetPlan(plan)
    if plan then
        self.summary:SetText(string.format("%d new items + the source. Gold = source; blue = shape.\nApproximate placement; keep the camera fixed.", #plan.items))
        self.status:SetText("Place a source item in front of the shape. Start, then hover over it without moving the mouse.")
    else
        self.summary:SetText("")
        self.status:SetText(reason)
    end
    if self.calibrate then self:Lock(self.placement:Busy()) end
end
