local _, MHT = ...
local Placement = MHT.Placement
local State = Placement.States
local copy = MHT.Util.Copy

-- Building from the pile: the player clicks each copy and it moves to its place in the plan.
-- The build can pause, and keeps what it needs to finish an interrupted item.

local RETRY_FROM_PILE = "Press Resume, then click any matching copy in the pile."
local RESUME_SAME = "Press Resume and click the same item."

function Placement:Build(skipping)
    if not self:Ready() and not self:Paused() then return nil, "Prepare items or use an existing pile first." end
    if not self.api:Active() then return nil, "Open the housing editor first." end
    local interrupted = self.interrupted
    if interrupted and interrupted.pending then return nil, "Waiting for WoW to confirm this item." end
    if interrupted and interrupted.saveFailed then
        local selected = self.api:Selected()
        if not selected or selected.decorGUID ~= interrupted.guid then
            return nil, "Select the same item, then press Resume to save where it stopped."
        end
        self:SaveInterrupted("Saving the item where it stopped...")
        return true
    end
    if interrupted and not interrupted.motion then
        return nil, "This item has no moves left to finish. Skip it or end the build."
    end
    -- After a skip or an interruption, the item to click may still be selected.
    if not skipping and not interrupted and not self.retryFromPile and self.api:IsSelected() then
        return nil, "Finish editing the selected item first."
    end
    self.stage, self.pauseRequested = "building", false
    self.saved = self.api:SaveSettings()
    self.api:UsePlacementSettings()
    self:BeginSelectionPhase()
    return true
end

function Placement:BeginSelectionPhase()
    self.cursor = nil
    self.hoverGUID = nil
    self.lastRejectedGUID = nil
    self:SetState("expert", "Switching to Advanced mode...")
    self.api:Switch("ExpertDecor")
end

function Placement:SelectMessage()
    if self.interrupted then return "Click the same item again to finish its move." end
    if self.retryFromPile then return "Click any matching copy in the pile." end
    if self.completed == 0 then
        return string.format("Click the copies in the pile one at a time (1 / %d). Keep the camera still.",
            #self.plan.items)
    end
    return string.format("Click the next copy in the pile (%d / %d).", self.completed + 1, #self.plan.items)
end

function Placement:CompleteMessage()
    local skipped = #self.skipped
    if skipped == 0 then return "Build complete. All " .. self.completed .. " items were placed." end
    return string.format("Build complete. %d of %d items placed, %d skipped.",
        self.completed - skipped, #self.plan.items, skipped)
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
    if self.interrupted and guid ~= self.interrupted.guid then return "Click the same item that was interrupted." end
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

    self.lastRejectedGUID, self.retryFromPile = nil, nil
    self.activeGUID = guid

    local index = self.completed + 1
    local target = self.plan.items[index]
    self:SetState("moving", string.format("Moving selected copy to target %d / %d...", index, #self.plan.items))

    local function done()
        self:SetState("committing", self.pauseRequested and "Pausing after this item..." or "Saving the selected copy...")
        self.api:Commit()
    end
    local function onPhase(label)
        self:SetState("moving", self.pauseRequested and "Pausing after this item..."
            or label .. " selected copy..." .. (target.label and (" " .. target.label) or ""))
    end
    if self.interrupted then
        self.motion:Resume(self.interrupted.motion, guid, done, onPhase)
    else
        self.motion:MoveTo(target, MHT.ItemProfiles.Calibration(self.source.decorID), guid, done, onPhase)
    end
end

function Placement:CopyMoved(guid, isNew)
    if isNew or guid and guid ~= self.activeGUID then return end
    self.finished[self.activeGUID] = true
    self.interrupted = nil
    self.completed = self.completed + 1
    self.activeGUID = nil

    if self.completed == #self.plan.items then
        self:End(self:CompleteMessage())
    elseif self.pauseRequested then
        self:PauseNow()
    else
        self:SetState("select", self:SelectMessage())
    end
end

-- Pausing

function Placement:CanPause()
    return self.stage == "building" and self:Busy() and not self.pauseRequested
end

function Placement:Pause()
    if not self:CanPause() then return nil, "Only a running build can be paused." end
    if self.state == "moving" or self.state == "committing" then
        self.pauseRequested = true
        self.notify("Pausing after this item...", self.completed, #self.plan.items)
    else
        self:PauseNow()
    end
    return true
end

function Placement:PauseNow(message)
    self.motion:Stop()
    if self.saved then pcall(self.api.RestoreSettings, self.api, self.saved) end
    self.saved, self.cursor, self.activeGUID, self.pauseRequested = nil, nil, nil, false
    self:SetState("paused", message or self.interrupted and self.interrupted.message
        or self.retryFromPile and RETRY_FROM_PILE or "Paused. Press Resume to continue.")
end

function Placement:CanSkip()
    return self:Paused() and (self.interrupted ~= nil or self.retryFromPile == true)
        and not (self.interrupted and self.interrupted.pending)
end

-- A partly moved item stays where it is and counts as finished, so it isn't clicked again.
function Placement:Skip()
    if not self:CanSkip() then return nil, "Only an interrupted item can be skipped." end
    if self.interrupted then self.finished[self.interrupted.guid] = true end
    self.interrupted, self.retryFromPile = nil, nil
    self.skipped[#self.skipped + 1] = self.completed + 1
    self.completed = self.completed + 1
    if self.completed >= #self.plan.items then
        self:End(self:CompleteMessage())
        return true
    end
    return self:Build(true)
end

-- Interruptions

-- Something stopped the move but the edit is still ours: save it where it is and keep the rest of the move.
function Placement:Interrupt(message, retryOnFailure)
    local committing = self.state == "committing"
    message = message or "Placement interrupted."
    if self.activeGUID then
        if not retryOnFailure then message = message .. " " .. RESUME_SAME end
        self.interrupted = { guid = self.activeGUID, motion = self.motion:Checkpoint(), message = message,
            complete = committing, pending = committing, retryOnFailure = retryOnFailure }
    elseif not retryOnFailure then
        message = message .. " Press Resume to continue."
    end
    local selected = self.api:Available() and self.api:Selected()
    local ownEdit = self.activeGUID and selected and selected.decorGUID == self.activeGUID
    self.state = "paused"
    self.motion:Stop()
    -- Cancelling can keep part of the move, and replaying all of it would then overshoot.
    if ownEdit and not committing and self.api:Active() and self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then
        self:SaveInterrupted(message)
        return
    end
    self:PauseNow(message)
end

function Placement:SaveInterrupted(message)
    local interrupted = self.interrupted
    interrupted.pending, interrupted.saveFailed = true, nil
    self:PauseNow(message)
    if not pcall(self.api.Commit, self.api) then
        interrupted.pending, interrupted.saveFailed = false, true
        self:PauseNow("Could not save where the item stopped. Select the same item and press Resume.")
    end
end

-- WoW undid the unfinished edit. A fresh copy is back in the pile, so any copy can take the target;
-- an item resumed from a saved stop is back at that stop and keeps its remaining moves.
function Placement:RetryPlacement(reason)
    if self.state == "committing" then
        -- The save already sent must settle first.
        self.retryFromPile = true
        self:Interrupt(reason .. RETRY_FROM_PILE, true)
        return
    end
    local guid = self.activeGUID
    local resumed = guid ~= nil and self.interrupted ~= nil and self.interrupted.guid == guid
    if not resumed then self.interrupted, self.retryFromPile = nil, true end
    self.motion:Stop()
    local selected = self.api:Available() and self.api:Selected()
    if guid and selected and selected.decorGUID == guid and self.api:Active()
        and self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then
        pcall(self.api.Cancel, self.api)
    end
    self:PauseNow(reason .. (resumed and RESUME_SAME or RETRY_FROM_PILE))
end

function Placement:CheckBuildContext()
    local reason
    if not self.api:Active() then
        reason = "Editor closed. Open it. "
    elseif self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        reason = "Editor mode changed. "
    else
        local selected = self.api:Selected()
        local preparing = self.motion:PreparingPhase()
        if selected and selected.decorGUID ~= self.activeGUID or not selected and not preparing then
            reason = "Selection changed. "
        elseif not preparing and self.motion.submode and not self.api:InSubmode(self.motion.submode) then
            reason = "Editing mode changed. "
        end
    end
    if not reason then return true end
    self:RetryPlacement(reason)
    return false
end

-- WoW can confirm part of an edit while the item stays selected; the move carries on unless it was undone.
function Placement:EditConfirmed(guid, isNew)
    if not isNew and guid == self.activeGUID then self:CheckBuildContext() end
end

function Placement:MoveSaveFailed(event, result)
    if event ~= "HOUSING_DECOR_PLACE_FAILURE" then
        self:OnFailure(event, result)
        return
    end
    local message = self:FailureText(event, result) .. " Select the same item and press Resume to retry saving."
    self:Interrupt(message)
    local interrupted = self.interrupted
    interrupted.pending, interrupted.saveFailed, interrupted.message = false, true, message
    self:PauseNow()
end

function Placement:InterruptedSaved(guid, isNew)
    local interrupted = self.interrupted
    if isNew or not interrupted or not interrupted.pending or guid and guid ~= interrupted.guid then return end
    interrupted.pending, interrupted.saveFailed = false, nil
    if interrupted.complete then
        self.finished[interrupted.guid], self.completed, self.interrupted = true, self.completed + 1, nil
        if self.completed == #self.plan.items then
            self:End(self:CompleteMessage())
            return
        end
    end
    self:PauseNow()
end

function Placement:InterruptedSaveFailed(event)
    local interrupted = self.interrupted
    if event ~= "HOUSING_DECOR_PLACE_FAILURE" or not interrupted or not interrupted.pending then return end
    if interrupted.retryOnFailure then
        self:RetryPlacement("WoW did not save this item. ")
        return
    end
    interrupted.pending, interrupted.saveFailed = false, true
    interrupted.message = "WoW could not save this item. Select the same item and press Resume to retry saving."
    self:PauseNow()
end

-- Reloading

-- Only confirmed progress is kept.
function Placement:SaveBuild()
    if self.stage ~= "building" then return nil end
    return { plan = copy(self.plan), completed = self.completed, finished = copy(self.finished),
        skipped = copy(self.skipped), fromPile = self.fromPile, interrupted = copy(self.interrupted),
        retryFromPile = self.retryFromPile,
        source = self.source and { decorGUID = self.source.decorGUID, decorID = self.source.decorID } }
end

function Placement:RestoreBuild(saved)
    if self:Busy() or self:HasSession() or type(saved) ~= "table" then return nil end
    local plan = saved.plan
    if type(plan) ~= "table" or type(plan.items) ~= "table" or type(saved.completed) ~= "number"
        or saved.completed >= #plan.items or not saved.fromPile and type(saved.source) ~= "table" then
        return nil
    end
    self.plan, self.stage, self.fromPile, self.source = copy(plan), "building", saved.fromPile, copy(saved.source)
    self.completed, self.finished = saved.completed, copy(saved.finished or {})
    self.skipped = copy(saved.skipped or {})
    self.interrupted, self.retryFromPile, self.pauseRequested = copy(saved.interrupted), saved.retryFromPile, false
    self.activeGUID, self.lastRejectedGUID, self.modeRequest = nil, nil, nil
    if self.interrupted and self.interrupted.pending then
        -- The reload came before WoW answered, so the save may not have happened.
        self.interrupted.pending, self.interrupted.saveFailed = false, true
        self.interrupted.message = "The game reloaded while saving this item. Select it and press Resume to save it again."
    end
    self:PauseNow()
    return true
end

-- States

local function inAdvancedMode(self)
    if self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then return true end
    self:Abort("Editor mode changed; placement stopped.")
end

State.expert = { update = function(self)
    if self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then self:SetState("select", self:SelectMessage()) end
end }

State.select = { waits = true, update = function(self)
    if not inAdvancedMode(self) then return end
    local selected = self.api:Selected()
    if selected then self:HandleSelectedCopy(selected) end
end }

State.moving = { waits = true, watch = Placement.CheckBuildContext, saved = Placement.EditConfirmed,
    update = function(self, elapsed) self.motion:Update(elapsed) end }

State.committing = { action = "saving the moved item", watch = Placement.CheckBuildContext,
    saved = Placement.CopyMoved, failed = Placement.MoveSaveFailed }

State.paused = { saved = Placement.InterruptedSaved, failed = Placement.InterruptedSaveFailed }
