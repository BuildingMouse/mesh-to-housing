local _, MHT = ...
local CalibrationPanel = {}
CalibrationPanel.__index = CalibrationPanel
MHT.CalibrationPanel = CalibrationPanel

function CalibrationPanel.New(parent, api, capture, settings, start, notify)
    settings.kind, settings.axis = settings.kind or "pivot", settings.axis or "z"
    settings.workflow, settings.measurements = settings.workflow or "double", settings.measurements or {}
    local self = setmetatable({ settings = settings, values = {}, notify = notify }, CalibrationPanel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    UI.Text(self.frame, "Calibrate a rectangular block", 18, 105, 740, "GameFontNormalLarge")
    self.pivot = UI.Button(self.frame, "Rotation pivot", 18, 140, 130, function() settings.kind = "pivot"; self:Refresh() end)
    self.size = UI.Button(self.frame, "Item size", 156, 140, 110, function() settings.kind = "size"; self:Refresh() end)
    self.axes = {}
    for i, coordinate in ipairs({ "x", "y", "z" }) do
        local axis = coordinate
        self.axes[axis] = UI.Button(self.frame, axis:upper(), 310 + (i - 1) * 60, 140, 50,
            function() settings.axis = axis; self:Refresh() end)
    end
    self.workflow = UI.Check(self.frame, "Move the first copy aside before placing the second", 18, 180,
        settings.workflow == "aside", function(checked) settings.workflow = checked and "aside" or "double"; self:Refresh() end)
    self.guide = UI.Text(self.frame, "", 18, 220, 740)
    self.item = UI.Text(self.frame, "No item measured yet.", 18, 285, 740)
    for i, axis in ipairs({ "x", "y", "z" }) do
        UI.Text(self.frame, axis:upper(), 18, 322 + (i - 1) * 34, 30)
        self.values[axis] = UI.Text(self.frame, "", 55, 322 + (i - 1) * 34, 700)
    end
    self.detail = UI.Text(self.frame, "", 18, 435, 740)
    self.startButton = UI.Button(self.frame, "Start", 18, 505, 95, start)
    self.nextButton = UI.Button(self.frame, "Start measurement", 121, 505, 170, function() self:Advance() end)
    self.stopButton = UI.Button(self.frame, "End", 299, 505, 95, function() self:Abort() end)
    self.controller = MHT.Calibration.New(api, capture, settings.measurements, function(message)
        self.message = message
        self:Refresh()
        notify(message)
    end)
    self:Refresh()
    return self
end

function CalibrationPanel:Busy()
    return self.controller:Busy()
end

function CalibrationPanel:Start(profile)
    local s = self.settings
    local ok, started, reason = pcall(self.controller.Start, self.controller, s.kind, s.axis, s.workflow, profile)
    if not ok then self:Abort(tostring(started)) elseif not started then self.notify(reason) end
end

function CalibrationPanel:Advance()
    local ok, advanced, reason = pcall(self.controller.Advance, self.controller)
    if not ok then self:Abort(tostring(advanced)) elseif not advanced then self.notify(reason) end
end

function CalibrationPanel:Abort(message)
    self.controller:Abort(message)
end

function CalibrationPanel:Update(elapsed)
    self.controller:Update(elapsed)
    if self:Busy() then self:Refresh() end
end

function CalibrationPanel:OnEvent(event, ...)
    self.controller:OnEvent(event, ...)
end

function CalibrationPanel:SetBlocked(blocked)
    self.blocked = blocked
    self:Refresh()
end

function CalibrationPanel:Refresh()
    local c, s = self.controller, self.settings
    local busy = c and c:Busy() or false
    local locked = self.blocked or busy
    self.pivot:SetEnabled(not locked and s.kind ~= "pivot")
    self.size:SetEnabled(not locked and s.kind ~= "size")
    self.workflow:SetEnabled(not locked)
    for axis, button in pairs(self.axes) do button:SetEnabled(not locked and s.axis ~= axis) end
    self.startButton:SetEnabled(not locked)
    self.stopButton:SetEnabled(busy)
    local state = c and c.state
    self.nextButton:SetEnabled(busy and c.api:Mode() == Enum.HouseEditorMode.ExpertDecor
        and (state == "moveaside" or state == "align" or state == "measuring"))
    self.nextButton:SetText(state == "moveaside" and "Moved aside"
        or state == "measuring" and (s.kind == "pivot" and "Aligned" or "Faces touch") or "Start measurement")
    self.guide:SetText(busy and self.message or s.kind == "pivot"
        and "Start prefers two different stored colors. Align the copies, then rotate one 180° and move it back over the other. Use a block that looks the same after a half turn."
        or "Start prefers two different stored colors. Align the copies, then move one along the chosen axis until the faces just touch. This measures that dimension.")
    local source = c and c.source
    self.item:SetText(source and ((source.name or "Item") .. " (" .. tostring(source.decorID) .. ")") or "No item measured yet.")
    local result = source and s.measurements[source.decorID] and s.measurements[source.decorID][s.kind][s.axis]
    if state == "measuring" then
        result = MHT.Calibration.Measure(s.kind, s.axis, c.capture.recorder:Snapshot(), c.profile)
    end
    for _, axis in ipairs({ "x", "y", "z" }) do
        local text = "—"
        if result and result.ticks[axis] then
            text = string.format("%+.1f ticks    %+.3f s    (about %+.3f movement units)",
                result.ticks[axis], result.seconds[axis], result.units[axis])
        elseif s.kind == "pivot" and s.axis == axis then
            text = "Not measurable by rotating around this axis."
        end
        self.values[axis]:SetText(text)
    end
    local detail = s.kind == "pivot"
        and "Pivot = the point the item turns around, measured from its center. Offset = -½ of your correction."
        or "Size = the distance moved from exact overlap until the matching faces touch."
    detail = detail .. " Ticks count active frames; units use the current movement speed estimate. Saved pivots override presets for this item and rotation axis. Rotation uses the Transform test speed and first cycled axis."
    if state == "returnsource" then
        local x, y = GetCursorPosition()
        detail = string.format("Return to the original cursor spot: X %+.0f, Y %+.0f pixels remaining. Keep the camera still.",
            c.cursor.x - x, c.cursor.y - y)
    end
    self.detail:SetText(detail)
end
