local _, MHT = ...
local Placement = MHT.Placement
local State = Placement.States

-- Building from the pile: the player clicks each copy and it moves to its place in the plan.

function Placement:BeginSelectionPhase()
    self.cursor = nil
    self.hoverGUID = nil
    self.lastRejectedGUID = nil
    self:SetState("expert", "Switching to Advanced mode...")
    self.api:Switch("ExpertDecor")
end

function Placement:RejectReason(selected)
    if selected.isLocked then return "Someone else is editing that item. Click another copy." end
    if not self.source then
        -- An existing pile has no source to keep: the first copy clicked sets the item.
        local ok, reason = self:UseSource(selected)
        if not ok then return reason end
    end
    local guid = selected.decorGUID
    if guid == self.source.decorGUID and not self.fromPile then
        return "That is the source. Click a copy instead."
    end
    if selected.decorID and selected.decorID ~= self.source.decorID then
        return "That is a different decor item. Click a copy."
    end
    if self.finished[guid] then return "That copy is finished. Click another copy." end
end

function Placement:HandleSelectedCopy(selected)
    local guid = selected.decorGUID
    if not guid then return end

    local reason = self:RejectReason(selected)
    if reason then
        if self.lastRejectedGUID ~= guid then
            self.lastRejectedGUID = guid
            self.notify(reason, self.completed, #self.plan.items)
        end
        return
    end

    self.lastRejectedGUID = nil
    self.activeGUID = guid

    local index = self.completed + 1
    local target = self.plan.items[index]
    self:SetState("moving", string.format("Moving selected copy to target %d / %d...", index, #self.plan.items))

    local function done()
        self:SetState("committing", "Saving the selected copy...")
        self.api:Commit()
    end
    local function onPhase(label)
        self:SetState("moving", label .. " selected copy..." .. (target.label and (" " .. target.label) or ""))
    end
    local item = MHT.ItemProfiles.Calibration(self.source.decorID)
    self.motion:MoveTo(target, item, guid, done, onPhase)
end

function Placement:CopyMoved(guid, isNew)
    if isNew or guid and guid ~= self.activeGUID then return end
    self.finished[self.activeGUID] = true
    self.completed = self.completed + 1
    self.activeGUID = nil

    if self.completed == #self.plan.items then
        self:Abort("Build complete. All " .. self.completed .. " items were placed.")
    else
        self:SetState("select", string.format(
            "Click the next copy in the pile (%d / %d).", self.completed + 1, #self.plan.items))
    end
end

local function inAdvancedMode(self)
    if self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then return true end
    self:Abort("Editor mode changed; placement stopped.")
end

State.expert = { update = function(self)
    if self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then
        self:SetState("select", string.format(
            "Click the copies in the pile one at a time (1 / %d). Keep the camera still.", #self.plan.items))
    end
end }

State.select = { waits = true, update = function(self)
    if not inAdvancedMode(self) then return end
    local selected = self.api:Selected()
    if selected then self:HandleSelectedCopy(selected) end
end }

State.moving = { waits = true, update = function(self, elapsed)
    if inAdvancedMode(self) then self.motion:Update(elapsed) end
end }

State.committing = { action = "saving the moved item", saved = Placement.CopyMoved }
