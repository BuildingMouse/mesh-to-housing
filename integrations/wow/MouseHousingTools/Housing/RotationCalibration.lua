local _, MHT = ...
local Calibration = {}
Calibration.__index = Calibration
MHT.RotationCalibration = Calibration

function Calibration.New(api, measurements, notify)
    return setmetatable({ api = api, measurements = measurements, notify = notify,
        motion = MHT.Motion.New(api), state = "idle" }, Calibration)
end

function Calibration:Busy()
    return self.state == "armed" or self.state == "rotating" or self.state == "observe"
end

function Calibration:SetState(state, message)
    self.state = state
    self.notify(message)
end

function Calibration:Load(source)
    if not source or not source.decorID then return nil, "Select or hover the item first." end
    local item = self.measurements[source.decorID]
    self.draft = { decorID = source.decorID, name = source.name or item and item.name,
        axes = MHT.RotationAxes.Copy(item and item.rotationAxes) }
    return true
end

function Calibration:LoadSaved()
    if self:Busy() then return end
    local loaded, reason = self:Load(self.api:Selected() or self.api:Hovered() or self.source)
    if not loaded then return nil, reason end
    self:SetState("review", next(self.draft.axes)
        and "Saved axis answers loaded. Test an axis to replace its answer; Save axes applies the results."
        or "No saved axis answers for this item. Test X, Y and Z, then Save axes.")
    return true
end

function Calibration:Start(axis, profile)
    if self:Busy() then return end
    if axis ~= "x" and axis ~= "y" and axis ~= "z" then return nil, "Choose X, Y or Z." end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        return nil, "Open Advanced mode first."
    end
    local selected = self.api:Selected()
    if selected and (selected.isLocked or not selected.decorGUID or not selected.decorID) then
        return nil, "Choose an editable, placed copy."
    end
    self.axis, self.profile, self.guid = axis, profile, nil
    self:SetState("armed", "Click a flat, placed copy in your usual starting pose. The test adds +90° on " .. axis:upper() .. "; no rotation reset.")
    if selected then self:Begin(selected) end
    return true
end

function Calibration:Begin(selected)
    if selected.isLocked or not selected.decorGUID or not selected.decorID then
        self:Abort("Choose an editable, placed copy."); return
    end
    self.source, self.guid = selected, selected.decorGUID
    if not self.draft or self.draft.decorID ~= selected.decorID then self:Load(selected) end
    local rotation = { x = 0, y = 0, z = 0 }
    rotation[self.axis] = 90
    self:SetState("rotating", "Adding +90° on " .. self.axis:upper() .. " from the copy's placed pose. Watch its original top surface.")
    self.motion:Apply({ x = 0, y = 0, z = 0, rotation = rotation }, self.profile, self.guid, function()
        self:SetState("observe", "Choose where the original top surface faces. If it stayed up, follow the original forward edge.")
    end, true)
end

function Calibration:Update(elapsed)
    if not self:Busy() then return end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        self:Abort("Axis test stopped because Advanced mode closed."); return
    end
    local selected = self.api:Selected()
    if self.state == "armed" then
        if not selected then return end
        self:Begin(selected)
    elseif not selected or selected.decorGUID ~= self.guid then
        self:Abort("Selection changed. The unfinished axis answer was not recorded."); return
    elseif self.state == "rotating" then
        self.motion:Update(elapsed)
    end
end

function Calibration:Choose(choiceIndex)
    if self.state ~= "observe" then return nil, "Wait for the quarter turn to finish before answering." end
    local selected, choice = self.api:Selected(), MHT.RotationAxes.Choices[choiceIndex]
    if not selected or selected.decorGUID ~= self.guid then self:Abort("Selection changed; answer not recorded."); return end
    if not choice then return nil, "Choose an observed direction." end
    -- Cancel restores the last placed pose, including the copy's orientation.
    self.api:Cancel()
    self.draft.axes[self.axis] = { axis = choice.axis, sign = choice.sign, angle = 90,
        rotationSpeed = self.profile.rotate, firstRotationAxis = self.profile.firstRotationAxis, reference = "placed-copy" }
    self.guid = nil
    self:SetState("review", self.axis:upper() .. ": " .. choice.text .. ". Item restored. Test the next axis, then Save axes.")
    return true
end

function Calibration:Save()
    if self:Busy() then return nil, "Finish the axis test before saving." end
    local valid, reason = MHT.RotationAxes.Validate(self.draft and self.draft.axes)
    if not valid then return nil, reason end
    local item = self.measurements[self.draft.decorID] or {}
    self.measurements[self.draft.decorID] = item
    item.name = self.draft.name or item.name
    item.rotationAxes = MHT.RotationAxes.Copy(self.draft.axes)
    self:SetState("review", "Rotation axes saved for this item. Shape placement now uses these answers.")
    return true
end

function Calibration:Abort(message)
    self.motion:Stop()
    local selected = self.api:Selected()
    if self.guid and selected and selected.decorGUID == self.guid then pcall(self.api.Cancel, self.api) end
    self.guid = nil
    self:SetState("idle", message or "Axis test stopped. The test item was restored; saved calibration is unchanged.")
end

function Calibration:OnEvent(event)
    if not self:Busy() then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD"
        or event == "HOUSING_DECOR_PLACE_FAILURE" then self:Abort("Axis test interrupted; answer not recorded.") end
end
