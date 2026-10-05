local _, MHT = ...
local Placement = {}
Placement.__index = Placement
MHT.Placement = Placement

function Placement.New(api, notify)
    return setmetatable({ api = api, motion = MHT.Motion.New(api), notify = notify,
                          state = "idle", completed = 0 }, Placement)
end

function Placement:Busy()
    return self.state ~= "idle"
end

function Placement:SetState(state, message)
    self.state, self.age = state, 0
    if message then self.notify(message, self.completed, self.plan and #self.plan.items or 0) end
end

function Placement:Start(plan, profile)
    if self:Busy() then return end
    if not self.api:Active() then return nil, "Open the housing editor first." end
    if self.api:IsSelected() then return nil, "Finish editing the selected item first." end
    local valid, reason = MHT.Motion.Validate(profile)
    if not valid then return nil, reason end
    self.plan, self.profile = plan, profile
    self.completed, self.index = 0, 1
    self.source, self.pendingGUID, self.cursor = nil, nil, nil
    self.hoverGUID, self.still = nil, 0
    self.saved = self.api:SaveSettings()
    self:SetState("arming", "Place a source item in front. Hover over it, then keep the mouse and camera still.")
    return true
end

function Placement:Abort(message)
    if not self:Busy() then
        if message then self.notify(message, self.completed, self.plan and #self.plan.items or 0) end
        return
    end
    self.motion:Stop()
    local selected = self.api:Available() and self.api:Selected()
    local pending = self.api:Available() and self.api:PendingInfo()
    local ownPending = self.pendingGUID and ((self.api:Mode() == Enum.HouseEditorMode.BasicDecor
        and self.api:HasPendingCopy() and pending and pending.decorGUID == self.pendingGUID)
        or (selected and selected.decorGUID == self.pendingGUID))
    self.state = "idle"
    if ownPending then pcall(self.api.Cancel, self.api) end
    pcall(self.api.RestoreSettings, self.api, self.saved)
    self.saved, self.pendingGUID, self.cursor = nil, nil, nil
    self:SetState("idle", message or "Aborted. Finished items remain placed.")
end

function Placement:BeginCopy()
    local hovered = self.api:Hovered()
    if not hovered or hovered.decorGUID ~= self.source.decorGUID then
        self:SetState("source", "Hover over the original source again. Keep the mouse still.")
        return
    end
    self.pendingGUID = nil
    self:SetState("copy", "Preparing item " .. self.index .. "...")
    self.api:BeginCopy(self.source, #self.plan.items - self.completed)
end

function Placement:BeginBasic()
    self:SetState("basic", "Returning to the source item...")
    self.api:Switch("BasicDecor")
end

function Placement:Update(elapsed)
    if not self:Busy() then return end
    if not self.api:Active() then self:Abort("Housing editor closed; placement stopped."); return end
    self.age = self.age + elapsed
    if self.state == "arming" or self.state == "source" then
        local hovered = self.api:Hovered()
        local x, y = GetCursorPosition()
        if not hovered or hovered.isLocked then self.hoverGUID, self.still = nil, 0; return end
        if self.state == "source" and hovered.decorGUID ~= self.source.decorGUID then return end
        if self.hoverGUID ~= hovered.decorGUID or not self.hoverX
            or math.abs(x - self.hoverX) + math.abs(y - self.hoverY) > 2 then
            self.hoverGUID, self.hoverX, self.hoverY, self.still = hovered.decorGUID, x, y, 0
        end
        self.still = (self.still or 0) + elapsed
        if self.still < 1.2 then return end
        if self.state == "arming" then
            local stock, reason = self.api:CheckStock(hovered, #self.plan.items)
            if not stock then self:Abort(reason); return end
            self.source = hovered
            self.notify(string.format("%s: %d matching copies; %d needed.", stock.name, stock.count, #self.plan.items), 0, #self.plan.items)
            self.api:UsePlacementSettings()
        end
        self.cursor = { x, y }
        self:BeginBasic()
        return
    end
    if self.cursor then
        local x, y = GetCursorPosition()
        if math.abs(x - self.cursor[1]) + math.abs(y - self.cursor[2]) > 8 then
            self:Abort("Mouse moved. Placement stopped; keep the source under the cursor next time.")
            return
        end
    end
    if self.state == "basic" then
        if self.api:Mode() == Enum.HouseEditorMode.BasicDecor then self:BeginCopy() end
    elseif self.state == "copy" then
        if self.api:HasPendingCopy() then
            local pending = self.api:PendingInfo()
            if pending and pending.decorID == self.source.decorID and pending.decorGUID ~= self.source.decorGUID then
                self.pendingGUID = pending.decorGUID
                self:SetState("placing", "Placing the copy at the starting point...")
                self.api:PlaceCopy(self.plan.items[self.index].yaw)
            end
        end
    elseif self.state == "expert" then
        if self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then
            self:SetState("select", "Click the new copy to select it. Keep the mouse still.")
        end
    elseif self.state == "select" then
        if self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
            self:Abort("Editor mode changed; placement stopped."); return
        end
        local selected = self.api:Selected()
        if selected then
            if selected.decorGUID ~= self.pendingGUID then
                self:Abort("A different item was selected. No adjustments were made to it."); return
            end
            self:SetState("moving", "Adjusting item " .. self.index .. "...")
            self.motion:Place(self.plan.items[self.index], self.profile, self.pendingGUID, function()
                self:SetState("committing", "Saving item " .. self.index .. "...")
                self.api:Commit()
            end)
        end
    elseif self.state == "moving" then
        if self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
            self:Abort("Editor mode changed; placement stopped."); return
        end
        self.motion:Update(elapsed)
    end
    if self.state ~= "select" and self.state ~= "moving" and self.age > 10 then
        self:Abort("The game did not confirm the last action. Placement stopped.")
    end
end

function Placement:OnEvent(event, ...)
    if not self:Busy() then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
        self:Abort("Placement interrupted.")
    elseif event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" or event == "HOUSING_DECOR_PLACE_FAILURE" then
        self:Abort("The game rejected the placement or mode change (" .. tostring((...)) .. ").")
    elseif event == "HOUSING_DECOR_PLACE_SUCCESS" then
        local guid, _, isNew, isPreview = ...
        if isPreview or guid ~= self.pendingGUID then return end
        if self.state == "placing" and isNew then
            self:SetState("expert", "Switching to advanced mode...")
            self.api:Switch("ExpertDecor")
        elseif self.state == "committing" and not isNew then
            self.completed = self.completed + 1
            self.pendingGUID = nil
            if self.completed == #self.plan.items then
                self:Abort("Done. " .. self.completed .. " items placed; source item kept.")
            else
                self.index = self.index + 1
                self:BeginBasic()
            end
        end
    end
end
