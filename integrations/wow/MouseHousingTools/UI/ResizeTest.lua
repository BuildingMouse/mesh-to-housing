local _, MHT = ...
local Panel = {}
Panel.__index = Panel
MHT.ResizeTestPanel = Panel

function Panel.New(parent, controller, settings, copySettings, start, finish, notify)
    local self = setmetatable({ controller = controller, settings = settings, copySettings = copySettings }, Panel)
    settings.percent = settings.percent or 100
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    UI.Text(self.frame, "Resized corner test", 18, 120, 260, "GameFontNormalLarge")
    self.size = UI.Number(self.frame, "Item size (20–200%)", 18, 165, settings.percent,
        function(value) settings.percent = value; self:Preview() end)
    self.workflow = UI.Check(self.frame, "Move first copy aside", 18, 225, copySettings.workflow == "aside",
        function(checked) copySettings.workflow = checked and "aside" or "double" end)
    UI.Text(self.frame,
        "Start with two fresh copies at 100%. Confirm they overlap, then select each copy. Both resize to the chosen size and meet at opposite corners. Saved dimensions and a saved resize pivot are required.",
        18, 280, 260)
    UI.Text(self.frame, "This checks scaled size and relative placement. Use the 50% calibration test to check the resize pivot.", 302, 510, 490)
    self.next = UI.Button(self.frame, "Copies overlap", 18, 445, 245, function()
        local ok, advanced, reason = pcall(controller.Advance, controller)
        if not ok then controller:Abort(tostring(advanced)) elseif not advanced and reason then notify(reason) end
    end)
    self.start = UI.Button(self.frame, "Start test", 18, 525, 95, start)
    self.finish = UI.Button(self.frame, "End", 121, 525, 95, finish)
    self.progress = UI.Text(self.frame, "", 227, 532, 70)
    self.preview = MHT.Preview.New(self.frame)
    self:Preview()
    self:Refresh(false)
    return self
end

function Panel:Preview()
    local percent = self.settings.percent
    local plan
    if type(percent) == "number" and percent >= 20 and percent <= 200 then
        local scale, height = percent / 100, 0.25
        local lift = height * math.max(1, scale)
        plan = { dimensions = { 2, 2, height }, items = {
            { x = 0, y = 0, z = lift, yaw = 0, scale = scale },
            { x = 2 * scale, y = 2 * scale, z = lift + height * scale, yaw = 0, scale = scale },
        } }
    end
    self.preview:SetPlan(plan, "resize_test")
end

function Panel:Refresh(blocked)
    local c = self.controller
    local own = c:Busy() and c.mode == "corners"
    self.size:SetEnabled(not blocked)
    self.workflow:SetChecked(self.copySettings.workflow == "aside")
    self.workflow:SetEnabled(not blocked)
    self.start:SetEnabled(not blocked)
    self.finish:SetEnabled(own)
    self.next:SetEnabled(own and c.api:Mode() == Enum.HouseEditorMode.ExpertDecor
        and (c.state == "align" or c.state == "moveaside"))
    self.next:SetText(c.state == "moveaside" and "Moved aside" or "Copies overlap")
    self.progress:SetText(c.mode == "corners" and string.format("%d / 2", c.completed or 0) or "")
end
