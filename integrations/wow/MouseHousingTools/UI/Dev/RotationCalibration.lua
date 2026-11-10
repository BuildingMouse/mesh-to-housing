local _, MHT = ...
local Panel = {}
Panel.__index = Panel
MHT.RotationCalibrationPanel = Panel

function Panel.New(parent, api, settings, start, notify)
    local self = setmetatable({ settings = settings, notify = notify, choices = {} }, Panel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    UI.Text(self.frame,
        "Use a flat, placed copy at 100% size in your usual pivot-test pose. Forward/Back mean movement keys; answers show your keybinds. No rotation reset is used.",
        18, 180, 760)
    self.guide = UI.Text(self.frame, "", 18, 240, 760)
    self.item = UI.Text(self.frame, "No item tested yet.", 18, 275, 760)
    for i, choice in ipairs(MHT.RotationAxes.Choices) do
        local index = i
        self.choices[i] = UI.Button(self.frame, choice.text, 18 + (i - 1) % 2 * 385,
            315 + math.floor((i - 1) / 2) * 34, 375, function()
                local chosen, reason = self.controller:Choose(index)
                if not chosen and reason then notify(reason) end
            end)
    end
    self.results = UI.Text(self.frame, "", 18, 423, 760)
    self.start = UI.Button(self.frame, "Start +90° test", 18, 480, 150, function() start() end)
    self.stop = UI.Button(self.frame, "Restore / End", 176, 480, 140, function() self.controller:Abort() end)
    self.load = UI.Button(self.frame, "Load saved", 18, 515, 120, function()
        local loaded, reason = self.controller:LoadSaved()
        if not loaded and reason then notify(reason) end
    end)
    self.save = UI.Button(self.frame, "Save axes", 146, 515, 130, function()
        local saved, reason = self.controller:Save()
        if not saved and reason then notify(reason) end
    end)
    self.hint = UI.Text(self.frame, "", 330, 515, 430)
    self.controller = MHT.RotationCalibration.New(api, settings.measurements, function(message)
        self.message = message
        notify(message)
    end)
    return self
end

function Panel:Refresh(blocked)
    local c = self.controller
    local busy = c:Busy()
    if self.bindingState ~= c.state then
        self.bindings = c.api.MovementBindings and c.api:MovementBindings() or {}
        self.bindingState = c.state
    end
    local function bound(text) return MHT.RotationAxes.WithBindings(text, self.bindings) end
    self.start:SetEnabled(not blocked and not busy)
    self.stop:SetEnabled(busy)
    self.load:SetEnabled(not blocked and not busy)
    self.save:SetEnabled(not blocked and not busy and MHT.RotationAxes.Validate(c.draft and c.draft.axes) == true)
    for i, button in ipairs(self.choices) do
        button:SetEnabled(not blocked and c.state == "observe")
        button:SetText(bound(MHT.RotationAxes.Choices[i].text))
    end
    self.guide:SetText(bound(self.message or "Choose X, Y or Z above. Select a placed copy in Advanced mode and Start. Watch its original top and which edge rises or lowers."))
    self.hint:SetText("Restore / End returns to the placed pose. Only Save axes changes calibration. If a turn is not 90°, check the speed in Transform test.")
    local draft = c.draft
    local valid, reason = MHT.RotationAxes.Validate(draft and draft.axes)
    local item = draft and self.settings.measurements[draft.decorID]
    local saved = item and item.rotationAxes
    local active = valid and MHT.RotationAxes.Validate(saved) == true
    self.item:SetText(draft and ((draft.name or "Item") .. " (" .. draft.decorID .. ")") or "No item tested yet.")
    local lines = {}
    for _, axis in ipairs({ "x", "y", "z" }) do
        lines[#lines + 1] = bound(axis:upper() .. ": " .. MHT.RotationAxes.Describe(draft and draft.axes[axis]))
        if active and (draft.axes[axis].axis ~= saved[axis].axis or draft.axes[axis].sign ~= saved[axis].sign) then active = false end
    end
    lines[#lines + 1] = active and "These saved answers are active for shape placement."
        or valid and "Unsaved answers: press Save axes to use them for shapes." or reason
    self.results:SetText(table.concat(lines, "\n"))
end
