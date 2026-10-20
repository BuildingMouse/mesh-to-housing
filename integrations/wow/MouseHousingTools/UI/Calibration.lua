local _, MHT = ...
local CalibrationPanel = {}
CalibrationPanel.__index = CalibrationPanel
MHT.CalibrationPanel = CalibrationPanel

function CalibrationPanel.New(parent, api, capture, settings, start, notify, test)
    settings.kind, settings.axis = settings.kind or "pivot", settings.axis or "z"
    settings.workflow, settings.measurements = settings.workflow or "double", settings.measurements or {}
    local self = setmetatable({ settings = settings, values = {}, trialInputs = {}, notify = notify }, CalibrationPanel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    UI.Text(self.frame, "Calibrate a rectangular block", 18, 105, 740, "GameFontNormalLarge")
    self.pivot = UI.Button(self.frame, "Rotation pivot", 18, 140, 130, function() self:Kind("pivot") end)
    self.size = UI.Button(self.frame, "Item size", 156, 140, 110, function() self:Kind("size") end)
    self.rotationAxes = UI.Button(self.frame, "Rotation axes", 274, 140, 145, function() self:Kind("axes") end)
    self.axes = {}
    for i, coordinate in ipairs({ "x", "y", "z" }) do
        local axis = coordinate
        self.axes[axis] = UI.Button(self.frame, axis:upper(), 475 + (i - 1) * 60, 140, 50,
            function() settings.axis = axis; self:Refresh() end)
    end
    local body = CreateFrame("Frame", nil, self.frame)
    body:SetAllPoints(self.frame)
    self.measurementFrame = body
    self.workflow = UI.Check(body, "Move the first copy aside before placing the second", 18, 180,
        settings.workflow == "aside", function(checked) settings.workflow = checked and "aside" or "double"; self:Refresh() end)
    self.guide = UI.Text(body, "", 18, 220, 740)
    self.item = UI.Text(body, "No item measured yet.", 18, 285, 740)
    UI.Text(body, "Measured / saved result", 55, 302, 450)
    self.trialHeading = UI.Text(body, "Trial pivot (movement units)", 555, 302, 220)
    for i, axis in ipairs({ "x", "y", "z" }) do
        UI.Text(body, axis:upper(), 18, 322 + (i - 1) * 34, 30)
        self.values[axis] = UI.Text(body, "", 55, 322 + (i - 1) * 34, 480)
        local edit = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
        edit:SetPoint("TOPLEFT", 560, -316 - (i - 1) * 34)
        edit:SetSize(155, 22)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(20)
        edit:SetScript("OnEnterPressed", function()
            if self:ReadTrialInputs() then edit:ClearFocus() end
        end)
        edit:SetScript("OnEditFocusLost", function()
            local draft = self:GetDraft()
            if self.controller and not self:Busy() and draft and draft == self.displayedDraft then self:ReadTrialInputs() end
        end)
        edit:SetScript("OnEscapePressed", function()
            local draft = self:GetDraft()
            edit:SetText(draft and draft.units[axis] and tostring(draft.units[axis])
                or settings.kind == "size" and "" or "—")
            edit:ClearFocus()
        end)
        self.trialInputs[axis] = edit
    end
    self.detail = UI.Text(body, "", 18, 430, 740)
    self.startButton = UI.Button(body, "Measure", 18, 480, 95, start)
    self.nextButton = UI.Button(body, "Start measurement", 121, 480, 170, function() self:Advance() end)
    self.stopButton = UI.Button(body, "End", 299, 480, 95, function() self:Abort() end)
    self.loadButton = UI.Button(body, "Load saved", 18, 515, 120, function() self:LoadSaved() end)
    self.testButton = UI.Button(body, "Automatic test", 146, 515, 140,
        test or function() self:StartTest(MHT.Motion.StandardProfile) end)
    self.saveButton = UI.Button(body, "Save pivot", 294, 515, 110, function() self:SaveTrial() end)
    self.saveHint = UI.Text(body, "Trial values stay temporary until Save pivot.", 420, 521, 350)
    self.controller = MHT.Calibration.New(api, capture, settings.measurements, function(message)
        self.message = message
        self:Refresh()
        notify(message)
    end)
    self.axisPanel = MHT.RotationCalibrationPanel.New(self.frame, api, settings, start, function(message)
        self:Refresh()
        notify(message)
    end)
    self:Refresh()
    return self
end

function CalibrationPanel:Busy()
    return self.controller:Busy() or self.axisPanel.controller:Busy()
end

function CalibrationPanel:Kind(kind)
    if self:Busy() or self.blocked then return end
    if self:GetDraft() and not self:ReadTrialInputs() then return end
    self.settings.kind = kind
    self:Refresh()
    if kind == "axes" then self.notify("Choose an axis. In Advanced mode, select a placed copy and Start, or Start then click it.") end
end

function CalibrationPanel:Start(profile)
    if self.settings.kind == "axes" then
        local c = self.axisPanel.controller
        local ok, started, reason = pcall(c.Start, c, self.settings.axis, profile)
        if not ok then c:Abort(tostring(started)) elseif not started then self.notify(reason) end
        return
    end
    if self:GetDraft() and not self:ReadTrialInputs() then return end
    local s = self.settings
    local ok, started, reason = pcall(self.controller.Start, self.controller, s.kind, s.axis, s.workflow, profile)
    if not ok then self:Abort(tostring(started)) elseif not started then self.notify(reason) end
end

function CalibrationPanel:Advance()
    local ok, advanced, reason = pcall(self.controller.Advance, self.controller)
    if not ok then self:Abort(tostring(advanced)) elseif not advanced then self.notify(reason) end
end

function CalibrationPanel:GetDraft()
    local c = self.controller
    if not c then return nil end
    if self.settings.kind == "axes" then return nil end
    if self.settings.kind == "size" then return c.sizeDraft end
    return c.draft and c.draft.axis == self.settings.axis and c.draft or nil
end

function CalibrationPanel:ReadTrialInputs()
    local c, draft = self.controller, self:GetDraft()
    local size = self.settings.kind == "size"
    if not draft then
        self.notify(size and "Measure or load an item size first."
            or "Measure or load a saved pivot for this rotation axis first.")
        return nil
    end
    for axis, edit in pairs(self.trialInputs) do
        local text = edit:GetText()
        local empty = size and text == "" and draft.units[axis] == nil
        if not empty and text ~= tostring(draft.units[axis]) then
            local setValue = size and c.SetSizeValue or c.SetPivotValue
            local changed, reason = setValue(c, axis, tonumber(text))
            if not changed then self.notify(reason); return nil end
        end
    end
    return true
end

function CalibrationPanel:LoadSaved()
    local c, s = self.controller, self.settings
    local load = s.kind == "size" and c.LoadSavedSize or c.LoadSaved
    local loaded, reason = load(c, s.axis)
    if not loaded then self.notify(reason) end
end

function CalibrationPanel:StartTest(profile)
    if not self:ReadTrialInputs() then return end
    local c, s = self.controller, self.settings
    local start = s.kind == "size" and c.StartSizeTest or c.StartTest
    local ok, started, reason = pcall(start, c, s.axis, s.workflow, profile)
    if not ok then self:Abort(tostring(started)) elseif not started then self.notify(reason) end
end

function CalibrationPanel:SaveTrial()
    if not self:ReadTrialInputs() then return end
    local c, s = self.controller, self.settings
    local save = s.kind == "size" and c.SaveSize or c.SavePivot
    local saved, reason = save(c, s.axis)
    if not saved then self.notify(reason) end
end

function CalibrationPanel:Abort(message)
    if self.axisPanel.controller:Busy() or self.settings.kind == "axes" then self.axisPanel.controller:Abort(message)
    else self.controller:Abort(message) end
end

function CalibrationPanel:Update(elapsed)
    self.controller:Update(elapsed)
    self.axisPanel.controller:Update(elapsed)
    if self:Busy() then self:Refresh() end
end

function CalibrationPanel:OnEvent(event, ...)
    self.controller:OnEvent(event, ...)
    self.axisPanel.controller:OnEvent(event, ...)
end

function CalibrationPanel:SetBlocked(blocked)
    self.blocked = blocked
    self:Refresh()
end

function CalibrationPanel:Refresh()
    local c, s = self.controller, self.settings
    local busy = self:Busy()
    local locked = self.blocked or busy
    self.pivot:SetEnabled(not locked and s.kind ~= "pivot")
    self.size:SetEnabled(not locked and s.kind ~= "size")
    self.rotationAxes:SetEnabled(not locked and s.kind ~= "axes")
    for axis, button in pairs(self.axes) do button:SetEnabled(not locked and s.axis ~= axis) end
    local axes = s.kind == "axes"
    self.measurementFrame:SetShown(not axes)
    self.axisPanel.frame:SetShown(axes)
    if axes then self.axisPanel:Refresh(self.blocked); return end
    self.workflow:SetEnabled(not locked)
    self.startButton:SetEnabled(not locked)
    self.stopButton:SetEnabled(busy)
    local state = c and c.state
    local size = s.kind == "size"
    local draft = self:GetDraft()
    self.trialHeading:SetText(size and "Trial size (movement units)" or "Trial pivot (movement units)")
    self.saveHint:SetText(size and "Trial values stay temporary until Save size."
        or "Trial values stay temporary until Save pivot.")
    self.saveButton:SetText(size and "Save size" or "Save pivot")
    self.loadButton:SetEnabled(not locked)
    self.testButton:SetEnabled(not locked and draft ~= nil)
    self.saveButton:SetEnabled(not locked and draft ~= nil)
    for axis, edit in pairs(self.trialInputs) do
        edit:SetEnabled(not locked and draft ~= nil)
        if self.displayedDraft ~= draft then
            edit:SetText(draft and draft.units[axis] and tostring(draft.units[axis])
                or size and "" or "—")
        end
    end
    self.displayedDraft = draft
    self.nextButton:SetEnabled(busy and c.api:Mode() == Enum.HouseEditorMode.ExpertDecor
        and (state == "moveaside" or state == "align" or state == "measuring"))
    self.nextButton:SetText(state == "moveaside" and "Moved aside"
        or state == "measuring" and (s.kind == "pivot" and "Aligned" or "Faces touch")
        or c and c.automatic and state == "align" and "Run test" or "Start measurement")
    local showMessage = busy or c and c.kind == s.kind and c.axis == s.axis and (state == "review" or state == "done")
    self.guide:SetText(showMessage and self.message or s.kind == "pivot"
        and "Start prefers two different stored colors. Align the copies, then rotate one 180° and move it back over the other. Use a block that looks the same after a half turn."
        or "Align two copies, then measure one dimension at a time. Only that dimension's movement keys are enabled. The automatic size test moves by all three dimensions so opposite corners meet.")
    local source = c and c.source
    local shown = not busy and draft or source
    self.item:SetText(shown and ((shown.name or "Item") .. " (" .. tostring(shown.decorID) .. ")") or "No item measured yet.")
    local item = source and s.measurements[source.decorID]
    local result = not size and draft and draft.measurement or item and item[s.kind] and item[s.kind][s.axis]
    for _, axis in ipairs({ "x", "y", "z" }) do
        local row = size and (draft and draft.measurements[axis] or item and item.size and item.size[axis]) or result
        if state == "measuring" and (not size or axis == s.axis) then
            row = MHT.Calibration.Measure(s.kind, s.axis, c.capture.recorder:Snapshot(), c.profile)
        end
        local text = "—"
        if row and row.ticks and row.ticks[axis] then
            text = string.format("%+.1f ticks    %+.3f s    (about %+.3f movement units)",
                row.ticks[axis], row.seconds[axis], row.units[axis])
        elseif row and row.units and row.units[axis] then
            text = string.format("%+.4f movement units (edited)", row.units[axis])
        end
        self.values[axis]:SetText(text)
    end
    local detail = s.kind == "pivot"
        and "Pivot = the point the item turns around, measured from its center. Measure first or select an item and Load saved. Edit the trial values, deselect the item, then Automatic test. Save pivot applies the values to shapes."
        or "Measure or load the sizes, then edit X, Y and Z. Deselect the item and start Automatic test. After confirming the starting overlap, the copy moves right, forward and up by its full size. Save size keeps your values."
    if not size then detail = detail .. " Tests use the Transform test rotation settings." end
    if state == "returnsource" then
        local x, y = GetCursorPosition()
        detail = string.format("Return to the original cursor spot: X %+.0f, Y %+.0f pixels remaining. Keep the camera still.",
            c.cursor.x - x, c.cursor.y - y)
    end
    self.detail:SetText(detail)
end
