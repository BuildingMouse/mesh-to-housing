local _, MHT = ...
local Test = {}
Test.__index = Test
MHT.TransformTest = Test

-- Applies a raw shift and rotation to one clicked item, without pivot compensation.

function Test.New(api, notify)
    return setmetatable({ api = api, notify = notify, motion = MHT.Motion.New(api), state = "idle" }, Test)
end

function Test:Busy()
    return self.state ~= "idle"
end

function Test:SetState(state, message)
    self.state, self.age = state, 0
    self.notify(message)
end

function Test:Start(edit, profile)
    if self:Busy() then return end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        return nil, "Open Advanced mode first."
    end
    if self.api:IsSelected() then
        return nil, "Deselect the item, press Start, then click it to test."
    end
    self.edit, self.profile, self.activeGUID = edit, profile, nil
    self:SetState("select", "Test armed. Click one item in Advanced mode.")
    return true
end

function Test:Begin(guid)
    self.activeGUID = guid
    self:SetState("moving", "Moving (test)...")
    self.motion:Apply(self.edit, self.profile, guid, function()
        self:SetState("committing", "Saving the test edit...")
        self.api:Commit()
    end, function(label) self:SetState("moving", label .. " (test)...") end)
end

function Test:Update(elapsed)
    if not self:Busy() then return end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        self:Abort("Editor mode changed; test stopped.")
        return
    end
    self.age = self.age + elapsed
    if self.state == "select" then
        local selected = self.api:Selected()
        if selected and selected.decorGUID and not selected.isLocked then self:Begin(selected.decorGUID) end
    elseif self.state == "moving" then
        self.motion:Update(elapsed)
    elseif self.state == "committing" and self.age > 10 then
        self:Abort("The game did not confirm the test edit.")
    end
end

function Test:OnEvent(event, ...)
    if not self:Busy() then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD"
        or event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" or event == "HOUSING_DECOR_PLACE_FAILURE" then
        self:Abort("Test interrupted.")
        return
    end
    if event ~= "HOUSING_DECOR_PLACE_SUCCESS" or self.state ~= "committing" then return end
    local guid, _, isNew, isPreview = ...
    if isNew or isPreview or (guid and guid ~= self.activeGUID) then return end
    self.activeGUID = nil
    self:SetState("idle", "Test finished. Movement and rotation saved.")
end

function Test:Abort(message)
    if not self:Busy() then return end
    self.motion:Stop()
    local selected = self.api:Selected()
    if self.activeGUID and selected and selected.decorGUID == self.activeGUID then pcall(self.api.Cancel, self.api) end
    self.activeGUID = nil
    self:SetState("idle", message or "Test stopped.")
end
