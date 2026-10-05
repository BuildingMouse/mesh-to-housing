local _, MHT = ...
local Calibration = {}
Calibration.__index = Calibration
MHT.Calibration = Calibration

function Calibration.New(parent, profile, placement)
    local self = setmetatable({ profile = profile, placement = placement,
                               motion = MHT.Motion.New(MHT.Housing) }, Calibration)
    local UI = MHT.UI
    self.frame = UI.Panel(parent, 580, 435)
    self.frame:SetPoint("CENTER")
    self.frame:SetFrameStrata("DIALOG")
    self.frame:EnableMouse(true)
    UI.Text(self.frame, "Placement calibration", 18, 16, 520, "GameFontNormalLarge")
    UI.Text(self.frame, "Select a spare floor item in advanced mode. Each probe holds a control for 0.5 seconds. Measure the change, enter twice that value as the per-second rate, then Restore. Keep the same camera and precision settings during a run.", 18, 48, 535)
    self.edits, self.buttons = {}, {}
    local fields = {
        { "right", "Right (units/s)", "Right" }, { "forward", "Forward (units/s)", "Forward" },
        { "up", "Up (units/s)", "Up" }, { "grow", "Grow (scale/s)", "ScaleUp" },
        { "shrink", "Shrink (scale/s)", "ScaleDown" },
    }
    for i, field in ipairs(fields) do
        local x = 18 + ((i - 1) % 3) * 182
        local y = 118 + math.floor((i - 1) / 3) * 85
        self.edits[#self.edits + 1] = UI.Number(self.frame, field[2], x, y, profile[field[1]] or 0, function(value)
            profile[field[1]], profile.confirmed = value, false
            self.confirm:SetChecked(false)
        end)
        self.buttons[#self.buttons + 1] = UI.Button(self.frame, "Probe", x, y + 44, 108, function() self:Probe(field[3]) end)
    end
    UI.Text(self.frame, "Units are relative: one unit can be one known item width. Scale 1 means 100%; a change from 1 to 1.2 over 0.5s is 0.4 scale/s. Probe resets scale to 1. Timing is approximate; calibrate near your intended size.", 18, 294, 535)
    self.confirm = UI.Check(self.frame, "I measured these rates for this setup", 18, 349, profile.confirmed, function(value)
        profile.confirmed = value
    end)
    UI.Button(self.frame, "Restore item", 304, 349, 115, function() self:Restore() end)
    UI.Button(self.frame, "Close", 433, 349, 115, function() self:Restore(); self.frame:Hide() end)
    self.status = UI.Text(self.frame, "Rates are saved locally. No probe changes are committed.", 18, 393, 535)
    self.frame:SetScript("OnUpdate", function(_, elapsed)
        if not self.motion.queue then return end
        if not MHT.Housing:Active() then self:Restore(); return end
        local ok, reason = pcall(self.motion.Update, self.motion, elapsed)
        if not ok then self:Restore(); self.status:SetText(tostring(reason)) end
    end)
    self.frame:SetScript("OnHide", function() self:Restore() end)
    self.frame:Hide()
    return self
end

function Calibration:Restore()
    self.motion:Stop()
    local selected = MHT.Housing:Available() and MHT.Housing:Selected()
    if self.guid and selected and selected.decorGUID == self.guid then pcall(MHT.Housing.Cancel, MHT.Housing) end
    self.guid = nil
end

function Calibration:Probe(control)
    if self.placement:Busy() or self.guid then
        self.status:SetText("Restore the previous probe or abort placement first."); return
    end
    if not MHT.Housing:Active() or MHT.Housing:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        self.status:SetText("Open advanced mode and select a spare item first."); return
    end
    local selected = MHT.Housing:Selected()
    if not selected then self.status:SetText("Select a spare item first."); return end
    self.guid = selected.decorGUID
    self.status:SetText("Probing " .. control .. " for 0.5 seconds...")
    self.motion:Probe(control, self.guid, function()
        self.status:SetText("Measure the change, update the rate, then Restore item.")
    end)
end
