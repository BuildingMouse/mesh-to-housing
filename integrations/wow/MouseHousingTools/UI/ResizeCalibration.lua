local _, MHT = ...
local Panel = {}
Panel.__index = Panel
MHT.ResizeCalibrationPanel = Panel

function Panel.New(parent, api, capture, settings, start, notify, test)
    local self = setmetatable({ notify = notify, inputs = {}, values = {} }, Panel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    self.workflow = UI.Check(self.frame, "Move the first copy aside before placing the second", 18, 180,
        settings.workflow == "aside", function(checked) settings.workflow = checked and "aside" or "double" end)
    self.guide = UI.Text(self.frame, "", 18, 220, 740)
    self.item = UI.Text(self.frame, "No resize pivot measured yet.", 18, 285, 740)
    UI.Text(self.frame, "Measured pivot / live movement", 55, 302, 450)
    UI.Text(self.frame, "Trial resize pivot (movement units)", 535, 302, 250)
    for i, axis in ipairs({ "x", "y", "z" }) do
        UI.Text(self.frame, axis:upper(), 18, 322 + (i - 1) * 34, 30)
        self.values[axis] = UI.Text(self.frame, "—", 55, 322 + (i - 1) * 34, 450)
        local edit = CreateFrame("EditBox", nil, self.frame, "InputBoxTemplate")
        edit:SetPoint("TOPLEFT", 560, -316 - (i - 1) * 34)
        edit:SetSize(155, 22)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(20)
        edit:SetScript("OnEnterPressed", function() if self:ReadInputs() then edit:ClearFocus() end end)
        edit:SetScript("OnEditFocusLost", function()
            if not self.controller:Busy() and self.controller.draft == self.displayedDraft then self:ReadInputs() end
        end)
        edit:SetScript("OnEscapePressed", function()
            local draft = self.controller.draft
            edit:SetText(draft and tostring(draft.units[axis]) or "—")
            edit:ClearFocus()
        end)
        self.inputs[axis] = edit
    end
    UI.Text(self.frame,
        "The copy moves up one full-size tile height, then shrinks to 50%. Align its bottom near-left corner with the reference's top near-left corner. The known lift is removed from the measurement. Only Save applies the trial values.",
        18, 430, 740)
    self.start = UI.Button(self.frame, "Measure", 18, 480, 95, start)
    self.next = UI.Button(self.frame, "Copies overlap", 121, 480, 170, function()
        local ok, advanced, reason = pcall(self.controller.Advance, self.controller)
        if not ok then self.controller:Abort(tostring(advanced)) elseif not advanced and reason then notify(reason) end
    end)
    self.stop = UI.Button(self.frame, "End", 299, 480, 95, function() self.controller:Abort() end)
    self.load = UI.Button(self.frame, "Load saved", 18, 515, 120, function()
        local loaded, reason = self.controller:LoadSaved()
        if not loaded then notify(reason) end
    end)
    self.test = UI.Button(self.frame, "Automatic test", 146, 515, 140, test)
    self.save = UI.Button(self.frame, "Save resize pivot", 294, 515, 155, function()
        if not self:ReadInputs() then return end
        local saved, reason = self.controller:Save()
        if not saved then notify(reason) end
    end)
    self.controller = MHT.ResizeCalibration.New(api, capture, settings.measurements, function(message)
        self.message = message
        self:Refresh(self.blocked)
        notify(message)
    end)
    self.settings = settings
    self:Refresh(false)
    return self
end

function Panel:ReadInputs()
    local c = self.controller
    if not c.draft then self.notify("Measure or load a resize pivot first."); return nil end
    for axis, edit in pairs(self.inputs) do
        if edit:GetText() ~= tostring(c.draft.units[axis]) then
            local changed, reason = c:SetValue(axis, tonumber(edit:GetText()))
            if not changed then self.notify(reason); return nil end
        end
    end
    return true
end

function Panel:Start(profile, automatic)
    if self.controller.draft and not self:ReadInputs() then return end
    local ok, started, reason = pcall(self.controller.Start, self.controller,
        automatic and "automatic" or "measure", self.settings.workflow, profile)
    if not ok then self.controller:Abort(tostring(started)) elseif not started then self.notify(reason) end
end

function Panel:Refresh(blocked)
    self.blocked = blocked
    local c = self.controller
    local busy, draft = c:Busy(), c.draft
    local locked = blocked or busy
    self.workflow:SetChecked(self.settings.workflow == "aside")
    self.workflow:SetEnabled(not locked)
    self.start:SetEnabled(not locked)
    self.stop:SetEnabled(busy)
    self.load:SetEnabled(not locked)
    self.test:SetEnabled(not locked and draft ~= nil)
    self.save:SetEnabled(not locked and draft ~= nil)
    self.next:SetEnabled(busy and c.api:Mode() == Enum.HouseEditorMode.ExpertDecor
        and (c.state == "align" or c.state == "moveaside" or c.state == "measuring"))
    self.next:SetText(c.state == "moveaside" and "Moved aside" or c.state == "measuring" and "Aligned" or "Copies overlap")
    self.guide:SetText(self.message or "Measure or load the resize pivot. Saved X, Y and Z sizes are needed; rotation calibration is not required.")
    local shown = not busy and draft or c.source
    self.item:SetText(shown and ((shown.name or "Item") .. " (" .. shown.decorID .. ")") or "No resize pivot measured yet.")
    local movement = c.state == "measuring" and c.capture.recorder:Snapshot()
    for axis, edit in pairs(self.inputs) do
        edit:SetEnabled(not locked and draft ~= nil)
        if self.displayedDraft ~= draft then edit:SetText(draft and tostring(draft.units[axis]) or "—") end
        self.values[axis]:SetText(movement and string.format("%+d ticks    %+.3f s", movement.ticks[axis], movement.seconds[axis])
            or draft and string.format("%+.4f movement units", draft.measurement.units[axis]) or "—")
    end
    self.displayedDraft = draft
end
