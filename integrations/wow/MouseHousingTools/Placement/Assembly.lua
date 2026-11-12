local _, MHT = ...
local Placement = MHT.Placement
local State = Placement.States
local copy = MHT.Util.Copy

-- Building from the pile: the player clicks each copy and it moves to its place in the plan.
-- Each plan item keeps its own state, so the build can pause and finish an interrupted item.

local RETRY_FROM_PILE = "Press Resume, then click any matching copy in the pile."
local RESUME_SAME = "Press Resume and click the same item."
local SAVE_AGAIN = " Select the same item and press Resume to save it again."

local ITEM_FIELDS = {
    waiting = {},
    moving = { "guid", "checkpoint" },
    saving = { "guid", "checkpoint", "onSaved", "onFailed" },
    saved = { "guid" },
    skipped = { "guid" },
    stopped = { "guid", "checkpoint" },
    unsaved = { "guid", "checkpoint", "onSaved", "reason" },
    undone = {},
}
local DONE = { saved = true, skipped = true }

local PROMPTS = {
    saving = "Waiting for WoW to confirm this item.",
    stopped = "The move stopped partway. " .. RESUME_SAME,
    undone = "WoW undid the move. " .. RETRY_FROM_PILE,
}
local UNSAVED = {
    failed = "WoW could not save this item.",
    error = "The item could not be saved.",
    reload = "The game reloaded while saving this item.",
}

-- Every change goes through here, so an item only ever carries its own state's fields.
local function setItem(item, state, fields)
    local allowed = ITEM_FIELDS[state] or error("Unknown item state: " .. tostring(state))
    for key in pairs(item) do item[key] = nil end
    item.state = state
    for _, key in ipairs(allowed) do item[key] = fields and fields[key] end
end

local function prompt(item)
    if item.state == "unsaved" then return (UNSAVED[item.reason] or UNSAVED.error) .. SAVE_AGAIN end
    return PROMPTS[item.state] or "Paused. Press Resume to continue."
end

function Placement:ResetItems(count)
    self.items = {}
    for i = 1, count do
        self.items[i] = {}
        setItem(self.items[i], "waiting")
    end
end

function Placement:Current()
    for i, item in ipairs(self.items) do
        if not DONE[item.state] then return item, i end
    end
end

function Placement:Completed()
    local _, index = self:Current()
    return (index or #self.items + 1) - 1
end

function Placement:CountItems(state)
    local count = 0
    for _, item in ipairs(self.items) do
        if item.state == state then count = count + 1 end
    end
    return count
end

function Placement:IsFinishedCopy(guid)
    for _, item in ipairs(self.items) do
        if item.guid == guid and DONE[item.state] then return true end
    end
    return false
end

function Placement:SettleSave(item, outcome, reason)
    setItem(item, outcome, { guid = item.guid, checkpoint = item.checkpoint, onSaved = item.onSaved, reason = reason })
end

function Placement:SendSave(item, message)
    self:PauseNow(message)
    if not pcall(self.api.Commit, self.api) then
        self:SettleSave(item, item.onFailed, "error")
        self:PauseNow()
    end
end

function Placement:Build(skipping)
    if not self:Ready() and not self:Paused() then return nil, "Prepare items or use an existing pile first." end
    if not self.api:Active() then return nil, "Open the housing editor first." end
    local item = self:Current()
    if item.state == "saving" then return nil, PROMPTS.saving end
    if item.state == "unsaved" then
        local selected = self.api:Selected()
        if not selected or selected.decorGUID ~= item.guid then return nil, prompt(item) end
        setItem(item, "saving", { guid = item.guid, checkpoint = item.checkpoint, onSaved = item.onSaved,
            onFailed = "unsaved" })
        self:SendSave(item, "Saving the item...")
        return true
    end
    -- After a skip or an interruption, the item to click may still be selected.
    if not skipping and item.state == "waiting" and self.api:IsSelected() then
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
    local item, index = self:Current()
    if item.state == "stopped" then return "Click the same item again to finish its move." end
    if item.state == "undone" then return "Click any matching copy in the pile." end
    if index == 1 then
        return string.format("Click the copies in the pile one at a time (1 / %d). Keep the camera still.",
            #self.items)
    end
    return string.format("Click the next copy in the pile (%d / %d).", index, #self.items)
end

function Placement:CompleteMessage()
    local skipped = self:CountItems("skipped")
    if skipped == 0 then return "Build complete. All " .. #self.items .. " items were placed." end
    return string.format("Build complete. %d of %d items placed, %d skipped.",
        self:CountItems("saved"), #self.items, skipped)
end

function Placement:RejectReason(selected)
    if selected.isLocked then return "Someone else is editing that item. Click another copy." end
    if not self.source then
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
    if self:IsFinishedCopy(guid) then return "That copy is finished. Click another copy." end
    local item = self:Current()
    if item.state == "stopped" and guid ~= item.guid then return "Click the same item that was interrupted." end
end

function Placement:HandleSelectedCopy(selected)
    local guid = selected.decorGUID
    if not guid then return end

    local reason = self:RejectReason(selected)
    if reason then
        if self.lastRejectedGUID ~= guid then
            self.lastRejectedGUID = guid
            self.notify(reason, self:Completed(), #self.items)
        end
        return
    end

    self.lastRejectedGUID = nil
    self.activeGUID = guid
    local item, index = self:Current()
    local checkpoint = item.state == "stopped" and item.checkpoint or nil
    setItem(item, "moving", { guid = guid, checkpoint = checkpoint })

    local target = self.plan.items[index]
    self:SetState("moving", string.format("Moving selected copy to target %d / %d...", index, #self.items))

    local function done()
        setItem(item, "saving", { guid = guid, checkpoint = checkpoint, onSaved = "saved", onFailed = "unsaved" })
        self:SetState("committing", self.pauseRequested and "Pausing after this item..." or "Saving the selected copy...")
        self.api:Commit()
    end
    local function onPhase(label)
        self:SetState("moving", self.pauseRequested and "Pausing after this item..."
            or label .. " selected copy..." .. (target.label and (" " .. target.label) or ""))
    end
    if checkpoint then
        self.motion:Resume(checkpoint, guid, done, onPhase)
    else
        self.motion:MoveTo(target, MHT.ItemProfiles.Calibration(self.source.decorID), guid, done, onPhase)
    end
end

function Placement:CopyMoved(guid, isNew)
    if isNew or guid and guid ~= self.activeGUID then return end
    local item = self:Current()
    self:SettleSave(item, item.onSaved)
    self.activeGUID = nil

    if not self:Current() then
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
        self.notify("Pausing after this item...", self:Completed(), #self.items)
    else
        self:PauseNow()
    end
    return true
end

function Placement:PauseNow(message)
    self.motion:Stop()
    if self.saved then pcall(self.api.RestoreSettings, self.api, self.saved) end
    self.saved, self.cursor, self.activeGUID, self.pauseRequested = nil, nil, nil, false
    local item = self:Current()
    self:SetState("paused", message or item and prompt(item))
end

function Placement:CanSkip()
    local item = self:Current()
    return self:Paused() and item ~= nil
        and (item.state == "stopped" or item.state == "unsaved" or item.state == "undone")
end

function Placement:Skip()
    if not self:CanSkip() then return nil, "Only an interrupted item can be skipped." end
    local item = self:Current()
    setItem(item, "skipped", { guid = item.guid })
    if not self:Current() then
        self:End(self:CompleteMessage())
        return true
    end
    return self:Build(true)
end

-- Interruptions

function Placement:Interrupt(message)
    message = (message or "Placement interrupted.") .. " "
    local item = self:Current()
    local moving = self.state == "moving"
    local selected = self.api:Available() and self.api:Selected()
    local ownEdit = moving and selected and selected.decorGUID == self.activeGUID
        and self.api:Active() and self.api:Mode() == Enum.HouseEditorMode.ExpertDecor
    local checkpoint = moving and self.motion:Checkpoint()
    self.state = "paused"
    self.motion:Stop()
    if ownEdit then
        setItem(item, "saving", { guid = item.guid, checkpoint = checkpoint, onSaved = "stopped", onFailed = "unsaved" })
        self:SendSave(item, message .. RESUME_SAME)
    elseif moving then
        setItem(item, "stopped", { guid = item.guid, checkpoint = checkpoint })
        self:PauseNow(message .. RESUME_SAME)
    else
        self:PauseNow(message .. "Press Resume to continue.")
    end
end

-- If placement was undone and the item is back in the pile, 
-- we don't require to select the exact same item again.
function Placement:RetryPlacement(reason)
    local item = self:Current()
    local fallback = item.checkpoint and "stopped" or "undone"
    if self.state == "committing" then
        setItem(item, "saving", { guid = item.guid, checkpoint = item.checkpoint, onSaved = item.onSaved,
            onFailed = fallback })
        self.state = "paused"
        self:PauseNow(reason .. PROMPTS.saving)
        return
    end
    local guid = self.activeGUID
    setItem(item, fallback, { guid = item.guid, checkpoint = item.checkpoint })
    self.motion:Stop()
    local selected = self.api:Available() and self.api:Selected()
    if guid and selected and selected.decorGUID == guid and self.api:Active()
        and self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then
        pcall(self.api.Cancel, self.api)
    end
    self:PauseNow(reason .. (fallback == "stopped" and RESUME_SAME or RETRY_FROM_PILE))
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
    local message = self:FailureText(event, result) .. SAVE_AGAIN
    local item = self:Current()
    self:SettleSave(item, item.onFailed, "failed")
    self.state = "paused"
    self:PauseNow(message)
end

function Placement:PausedSaveConfirmed(guid, isNew)
    local item = self:Current()
    if isNew or not item or item.state ~= "saving" or guid and guid ~= item.guid then return end
    self:SettleSave(item, item.onSaved)
    if not self:Current() then
        self:End(self:CompleteMessage())
        return
    end
    self:PauseNow()
end

function Placement:PausedSaveFailed(event)
    local item = self:Current()
    if event ~= "HOUSING_DECOR_PLACE_FAILURE" or not item or item.state ~= "saving" then return end
    self:SettleSave(item, item.onFailed, "failed")
    self:PauseNow()
end

-- Reloading

function Placement:SaveBuild()
    if self.stage ~= "building" then return nil end
    return { plan = copy(self.plan), items = copy(self.items), fromPile = self.fromPile,
        source = self.source and { decorGUID = self.source.decorGUID, decorID = self.source.decorID } }
end

function Placement:RestoreBuild(saved)
    if self:Busy() or self:HasSession() or type(saved) ~= "table" then return nil end
    local plan, items = saved.plan, saved.items
    if type(plan) ~= "table" or type(plan.items) ~= "table" or type(items) ~= "table"
        or #items ~= #plan.items or not saved.fromPile and type(saved.source) ~= "table" then
        return nil
    end
    for _, item in ipairs(items) do
        if type(item) ~= "table" or not ITEM_FIELDS[item.state] then return nil end
    end
    self.plan, self.items = copy(plan), copy(items)
    local item = self:Current()
    if not item then return nil end
    self.stage, self.fromPile, self.source = "building", saved.fromPile, copy(saved.source)
    self.pauseRequested, self.activeGUID, self.lastRejectedGUID, self.modeRequest = false, nil, nil, nil
    if item.state == "moving" then
        setItem(item, item.checkpoint and "stopped" or "undone", { guid = item.guid, checkpoint = item.checkpoint })
    elseif item.state == "saving" then
        setItem(item, "unsaved", { guid = item.guid, checkpoint = item.checkpoint, onSaved = item.onSaved,
            reason = "reload" })
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

State.paused = { saved = Placement.PausedSaveConfirmed, failed = Placement.PausedSaveFailed }
