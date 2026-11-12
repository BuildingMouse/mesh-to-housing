local _, MHT = ...
local ShapePanel = {}
ShapePanel.__index = ShapePanel
MHT.ShapePanel = ShapePanel

-- Settings for the Shapes tab.

local function tidy(number)
    return tonumber(string.format("%.6g", number))
end

function ShapePanel.New(window, container, parent)
    local self = setmetatable({ window = window, container = container, controls = {}, inputs = {} }, ShapePanel)
    local UI, settings, width = MHT.UI, window.settings, container.width
    local function current() return settings[settings.shape] end
    local function changed() window:Refresh() end
    local function track(control, key)
        self.controls[#self.controls + 1] = control
        if key then self.inputs[key] = control end
        return control
    end
    local function range(parent, key, label, y, minimum, maximum, step, onChange, limits)
        return track(UI.Range(parent, label, 0, y, width, minimum, maximum, step, 0, onChange, limits), key)
    end
    local function group(parent)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetAllPoints(parent)
        return frame
    end
    local function checkbox(parent, label, y, onChange)
        local check = track(UI.Check(parent, label, 0, y, false, onChange))
        check:SetLabelWidth(width - 28)
        return check
    end

    local frame = group(parent)
    self.frame = frame
    UI.Heading(frame, "Shape", 0, 0, width)
    UI.Tooltip(track(UI.ResetButton(frame, width - 24, 0, function() self:Reset() end)), "Reset this shape")
    local shapes = {}
    for _, id in ipairs(MHT.Layout.ShapeOrder) do shapes[#shapes + 1] = { id = id, name = MHT.Layout.Shapes[id].name } end
    self.shapePicker = track(UI.Dropdown(frame, 0, 28, width, shapes, settings.shape, function(id)
        settings.shape = id
        container:ScrollToTop()
        changed()
    end))
    UI.Rule(frame, 74, width)
    UI.Heading(frame, "Items", 0, 88, width)
    UI.Text(frame, "Item count", 0, 120, 200)
    track(UI.NumberBox(frame, width - 72, 112, 72, 0, function(value) current().count = value; changed() end,
        { 2, 200, integer = true }), "count")
    range(frame, "scale", "Item size (%)", 146, 20, 200, 1, function(value) current().scale = value / 100; changed() end)
    UI.Rule(frame, 190, width)

    self.stairFields = group(frame)
    local fields = self.stairFields
    UI.Heading(fields, "Spacing", 0, 204, width)
    range(fields, "spacing", "Forward spacing", 228, 0, 3, 0.01,
        function(value) settings.stairs.spacing = value; changed() end, { 0, 100 })
    local stepX = range(fields, "stepX", "Sideways spacing", 262, -3, 3, 0.01,
        function(value) settings.stairs.stepX = value; changed() end, { -100, 100 })
    UI.Tooltip(stepX.slider, "Straight stair spacing",
        "Forward and sideways spacing apply to straight stairs. Curved stairs follow the spiral radius; your straight-stair spacing stays saved.")
    local stepZ = range(fields, "stepZ", "Up per step", 296, 0, 3, 0.01,
        function(value) settings.stairs.stepZ = value; changed() end, { 0, 100 })
    UI.Tooltip(stepZ.slider, "Rise per step",
        "Vertical distance between steps. The curve, radius, item count and forward spacing never change it.")
    UI.Rule(fields, 340, width)
    self.curve = checkbox(fields, "Curve the stairs", 352, function(checked) settings.stairs.curveEnabled = checked; changed() end)
    self.curveFields = CreateFrame("Frame", nil, fields)
    self.curveFields:SetSize(width, 64)
    self.curveFields:SetPoint("TOPLEFT", 0, -380)
    local curve = track(UI.Range(self.curveFields, "Curve", 0, 0, width, -1080, 1080, 1, 0,
        function(value) settings.stairs.curve = value; changed() end), "curve")
    UI.Tooltip(curve.slider, "Curve angle",
        "Scroll for 1° steps or enter an angle. Negative angles curve left, positive angles right. 360° is one full turn.")
    local radius = track(UI.Range(self.curveFields, "Spiral radius", 0, 34, width, 0.05, 10, 0.01, 0,
        function(value) settings.stairs.radius = value; changed() end, { 0.05, 100 }), "stairRadius")
    UI.Tooltip(radius.slider, "Radius around the vertical axis",
        "Horizontal distance from the spiral's vertical centerline to each step's center. It doesn't change the rise per step.")

    self.circleFields = group(frame)
    fields = self.circleFields
    UI.Heading(fields, "Circle", 0, 204, width)
    range(fields, "circleRadius", "Radius", 228, 0.05, 10, 0.01,
        function(value) settings.circle.radius = value; changed() end, { 0.05, 100 })
    UI.Text(fields, "Orientation", 0, 270, 124)
    local function orientation(value)
        return function() settings.circle.orientation = value; changed() end
    end
    self.horizontal = track(UI.Button(fields, "Horizontal", 136, 262, 93, orientation("horizontal")))
    self.vertical = track(UI.Button(fields, "Vertical", 235, 262, 93, orientation("vertical")))
    UI.Tooltip(self.vertical, "Vertical circle", "Stands the circle and its items upright.")
    UI.Rule(fields, 300, width)
    self.partial = checkbox(fields, "Partial circle", 312, function(checked) settings.circle.partial = checked; changed() end)
    UI.Tooltip(self.partial, "Partial circle",
        "Spread the items over part of a circle. At 360°, they are spaced evenly around a full circle.")
    range(fields, "arc", "Angle", 348, 1, 360, 1, function(value) settings.circle.arc = value; changed() end)

    self.advancedHeader = CreateFrame("Frame", nil, frame)
    self.advancedHeader:SetSize(width, 28)
    UI.Rule(self.advancedHeader, 0, width)
    self.advancedButton = UI.Button(self.advancedHeader, "Advanced settings", 0, 4, width, function()
        self.advancedOpen = not self.advancedOpen
        self:Layout()
        if self.advancedOpen then container:Reveal(self.advancedY + 36 + self.advancedFields:GetHeight()) end
    end, "disclosure", 24)
    local disclosure = self.advancedButton.label
    disclosure:ClearAllPoints()
    disclosure:SetPoint("TOPLEFT", self.advancedButton, "TOPLEFT", 26, 0)
    disclosure:SetPoint("BOTTOMRIGHT", self.advancedButton, "BOTTOMRIGHT", 0, 0)
    disclosure:SetJustifyH("LEFT")
    self.advancedButton.icon = MHT.Theme.Icon(self.advancedButton, "right", 10, -width / 2 + 10, 0)
    self.advancedFields = CreateFrame("Frame", nil, frame)
    self.advancedFields:SetSize(width, 128)
    UI.Heading(self.advancedFields, "Item rotation", 0, 2, width - 32)
    UI.Tooltip(track(UI.ResetButton(self.advancedFields, width - 24, 0, function() self:ResetRotations() end)),
        "Reset rotations")
    for index, field in ipairs({ { "itemPitch", "Pitch" }, { "itemYaw", "Yaw" }, { "itemRoll", "Roll" } }) do
        local key = field[1]
        local edit = range(self.advancedFields, key, field[2], 26 + (index - 1) * 34, -180, 180, 1,
            function(value) current()[key] = value; changed() end, { -math.huge, math.huge })
        UI.Tooltip(edit, field[2], "Any angle, including fractions. Relative to the item's starting orientation and the shape's direction.")
        UI.Tooltip(edit.slider, field[2], "Drag or scroll for 1° steps. Type in the field for exact values.")
    end
    return self
end

function ShapePanel:Plan()
    local window = self.window
    local dimensions, reason = MHT.ItemProfiles.Dimensions(MHT.ItemProfiles.DEFAULT_DECOR_ID)
    if not dimensions then return nil, reason end
    return MHT.Layout.Build(window.settings, dimensions)
end

function ShapePanel:Reset()
    local settings = self.window.settings
    MHT.Layout.Reset(settings, settings.shape)
    self.window:Refresh()
end

function ShapePanel:ResetRotations()
    local values = self.window.settings[self.window.settings.shape]
    values.itemPitch, values.itemYaw, values.itemRoll = 0, 0, 0
    self.window:Refresh()
end

-- The advanced section sits below the shape's own fields, which change height.
function ShapePanel:Layout()
    local settings = self.window.settings
    local advancedY
    if settings.shape == "stairs" then
        advancedY = settings.stairs.curveEnabled and 450 or 384
    else
        advancedY = settings.circle.partial and 384 or 344
    end
    self.advancedY = advancedY
    self.advancedHeader:ClearAllPoints()
    self.advancedHeader:SetPoint("TOPLEFT", 0, -advancedY)
    self.advancedFields:ClearAllPoints()
    self.advancedFields:SetPoint("TOPLEFT", 0, -advancedY - 36)
    self.advancedFields:SetShown(self.advancedOpen == true)
    self.advancedButton.icon:SetShape(self.advancedOpen and "down" or "right")
    self.container:SetContentHeight(advancedY + (self.advancedOpen and 172 or 36))
end

function ShapePanel:Refresh()
    local settings, inputs = self.window.settings, self.inputs
    local stairs, circle, values = settings.stairs, settings.circle, settings[settings.shape]
    self.shapePicker:SetValue(settings.shape)
    self.stairFields:SetShown(settings.shape == "stairs")
    self.circleFields:SetShown(settings.shape == "circle")
    self.curveFields:SetShown(stairs.curveEnabled)
    self.curve:SetChecked(stairs.curveEnabled)
    self.partial:SetChecked(circle.partial)
    inputs.arc.row:SetShown(circle.partial)
    self.horizontal:SetSelected(circle.orientation == "horizontal")
    self.vertical:SetSelected(circle.orientation == "vertical")
    local numbers = {
        count = values.count, scale = values.scale * 100,
        itemPitch = values.itemPitch, itemYaw = values.itemYaw, itemRoll = values.itemRoll,
        spacing = stairs.spacing, stepX = stairs.stepX, stepZ = stairs.stepZ,
        curve = stairs.curve, stairRadius = stairs.radius,
        circleRadius = circle.radius, arc = circle.arc,
    }
    for key, number in pairs(numbers) do inputs[key]:SetNumber(tidy(number)) end
    self:Layout()
end

function ShapePanel:UpdateControls(busy)
    local stairs = self.window.settings.stairs
    self.inputs.spacing:SetEnabled(not busy and not stairs.curveEnabled)
    self.inputs.stepX:SetEnabled(not busy and not stairs.curveEnabled)
    self.advancedButton:SetEnabled(not busy)
end
