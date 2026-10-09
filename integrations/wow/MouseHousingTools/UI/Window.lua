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

    frame:SetScript("OnDragStart", function() if not self.placement:Busy() then frame:StartMoving() end end)

    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        self:SavePosition()
    end)

    UI.Text(frame, "MouseHousingTools", 18, 15, 500, "GameFontNormalLarge")
    UI.Button(frame, "X", 758, 10, 34, function() frame:Hide() end)

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

    UI.Text(
        self.content,
        "Movement uses fixed timing: 1 coordinate unit = 1 second. Scaling uses about 5 seconds for 100% to 200%. Curved stair spacing follows radius, turns, and item count.",
        18, 450, 260
    )

    self.preview = MHT.Preview.New(self.content)
    self.summary = UI.Text(self.content, "", 302, 510, 490)
    self.status = UI.Text(self.content, "", 18, 563, 774)

    self.placement = MHT.Placement.New(MHT.Housing, function(message, completed, total)
        self:SetStatus(message, completed, total)
        self.progress:SetText(total > 0 and string.format("%d / %d", completed, total) or "")
        self:Lock(self.placement:Busy())
    end)

    self.start = UI.Button(self.content, "Start", 18, 525, 95, function() self:StartPlacement() end)
    self.abort = UI.Button(self.content, "Abort", 121, 525, 95, function() self:EndPlacement() end)
    self.progress = UI.Text(self.content, "", 227, 532, 70)

    frame:SetScript("OnHide", function() self:SavePosition() end)

    self:Refresh()
    self:Lock(false)
    self:Mode("shapes")
    frame:Hide()
    return self
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
    if self.placement:Busy() then return end

    self:Mode("shapes")
    self:Refresh()
    if not self.plan then return end

    local ok, started, reason = pcall(
        self.placement.Start,
        self.placement,
        self.plan,
        MHT.Motion.StandardProfile,
        self.settings.placementWorkflow
    )

    if not ok then
        self.placement:Abort(tostring(started))
    elseif not started then
        self:SetStatus(reason)
    end
end

function Window:EndPlacement()
    self.placement:Abort()
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
