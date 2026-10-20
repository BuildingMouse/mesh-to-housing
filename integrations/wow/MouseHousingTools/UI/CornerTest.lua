local _, MHT = ...
local Panel = {}
Panel.__index = Panel
MHT.CornerTestPanel = Panel

function Panel.New(parent, api, measurements, start, notify)
    local self = setmetatable({ chosen = "test_x", buttons = {}, rows = {}, notify = notify }, Panel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    UI.Text(self.frame, "Corner rotation tests", 18, 105, 740, "GameFontNormalLarge")
    UI.Text(self.frame,
        "Place the tile at 100% size in its calibrated starting pose. Put the four markers at its corners, roughly halfway up its thickness. Finish editing, run a named test, then click the tile. After it turns, click corners 1 → 2 → 3 → 4. Markers only move.",
        18, 140, 760)
    self.layout = UI.Text(self.frame, "", 18, 195, 760)
    for i, case in ipairs(MHT.CornerTest.Cases) do
        local id = case.id
        self.buttons[id] = UI.Button(self.frame, id, 18 + (i - 1) % 3 * 260,
            235 + math.floor((i - 1) / 3) * 35, 245, function() start(id) end)
    end
    self.details = UI.Text(self.frame, "", 18, 350, 760)
    UI.Text(self.frame, "Marker", 18, 385, 100)
    UI.Text(self.frame, "Predicted corner (X, Y, Z)", 150, 385, 280)
    UI.Text(self.frame, "Move from its starting corner (X, Y, Z)", 440, 385, 340)
    for i, corner in ipairs(MHT.CornerTest.Corners) do
        local y = 410 + (i - 1) * 25
        UI.Text(self.frame, corner.name, 18, y, 120)
        self.rows[i] = { expected = UI.Text(self.frame, "—", 150, y, 280),
            shift = UI.Text(self.frame, "—", 440, y, 340) }
    end
    self.run = UI.Button(self.frame, "Run test_x", 18, 520, 170, function() start(self.chosen) end)
    self.stop = UI.Button(self.frame, "End", 196, 520, 100, function() self.controller:Abort() end)
    UI.Text(self.frame, "Results stay in game for screenshots. Restore the starting layout before each case. Calibration values stay unchanged.", 315, 515, 465)
    self.controller = MHT.CornerTest.New(api, measurements, function(message, completed, total)
        self.message = message
        notify(message, completed, total)
    end)
    return self
end

function Panel:Start(id, profile)
    self.chosen = id or self.chosen
    local ok, started, reason = pcall(self.controller.Start, self.controller, self.chosen, profile)
    if not ok then self.controller:Abort(tostring(started))
    elseif not started and reason then self.notify(reason) end
    self:Refresh()
end

function Panel:Busy() return self.controller:Busy() end
function Panel:Abort(message) self.controller:Abort(message) end
function Panel:OnEvent(event, ...) self.controller:OnEvent(event, ...) end

function Panel:Update(elapsed)
    self.controller:Update(elapsed)
    if self:Busy() then self:Refresh() end
end

function Panel:SetBlocked(blocked)
    self.blocked = blocked
    self:Refresh()
end

function Panel:Refresh(refreshBindings)
    local c, busy = self.controller, self:Busy()
    if refreshBindings or self.bindingState ~= c.state then
        self.bindings = c.api.MovementBindings and c.api:MovementBindings() or {}
        self.bindingState = c.state
    end
    self.layout:SetText(MHT.RotationAxes.WithBindings(
        "Starting view: far / Forward: 2 — 3; near / Back: 1 — 4.\nRaw angles: X +35°, Y +25°, Z +40°. Pairs and triples run in X → Y → Z order.", self.bindings))
    for _, button in pairs(self.buttons) do button:SetEnabled(not self.blocked and not busy) end
    self.run:SetText("Run " .. self.chosen)
    self.run:SetEnabled(not self.blocked and not busy)
    self.stop:SetEnabled(busy)
    local detail = c.case and (c.case.id .. ": " .. c.case.label) or "Choose a named test. All predictions use the tile's saved dimensions, axes and pivots."
    if c.calibration then
        local d = c.calibration.dimensions
        detail = detail .. string.format("\nItem %d; size %.4f × %.4f × %.4f; rotation %.2f°/s; first cycled axis %d.",
            c.calibration.decorID, d[1], d[2], d[3], c.profile.rotate, c.profile.firstRotationAxis)
    end
    self.details:SetText(detail)
    for i, row in ipairs(self.rows) do
        local prediction = c.predictions and c.predictions[i]
        local function coordinates(point)
            return point and string.format("%+.4f, %+.4f, %+.4f", point.x, point.y, point.z) or "—"
        end
        row.expected:SetText(coordinates(prediction and prediction.expected))
        row.shift:SetText(coordinates(prediction and prediction.shift))
    end
end
