local _, MHT = ...
local Placement = MHT.Placement
local State = Placement.States

-- Making the pile: copies of the source placed from one cursor spot. Copies either
-- stack where the source is, or, when a new copy covers the cursor, move aside one by one.

-- Cooldown starts after the game confirms placement.
local COPY_DELAY = 0.2
local THROTTLED_COPY_DELAY = 1
local MAX_COPY_RETRIES = 3
local SOURCE_HOLD = 1.2
local CURSOR_TOLERANCE = 2
-- WoW can report the old hover for a while after a copy lands.
local PILE_DETECT_FRAMES = 30
-- After a moved copy is saved, WoW can briefly show it at its old spot again when the mode changes.
local ASIDE_SWITCH_FRAMES = 10
-- The cursor ray can still hit the moved copy for a few frames.
local ASIDE_SETTLE_FRAMES = 10
local ASIDE_CLEAR_FRAMES = 30
local MAX_ASIDE_STEPS = 10

function Placement:ResetPreparation()
    self.copiesCreated = 0
    self.copyDelay, self.copyRetries, self.retryDelay = COPY_DELAY, 0, nil
    self.cursor, self.cursorAway, self.returnHold = nil, false, nil
    self.hoverGUID, self.hoverX, self.hoverY, self.still = nil, nil, nil, 0
    self.pile, self.detectFrames = nil, 0
    self.asideGUID, self.asideSteps, self.asideTotal, self.inPile = nil, 0, nil, {}
end

-- Copying

function Placement:UpdateArming(elapsed)
    local hovered = self.api:Hovered()
    local x, y = GetCursorPosition()

    if not hovered or hovered.isLocked or not hovered.decorGUID then
        self.hoverGUID = nil
        self.still = 0
        return
    end

    if self.hoverGUID ~= hovered.decorGUID
        or not self.hoverX
        or math.abs(x - self.hoverX) + math.abs(y - self.hoverY) > 2 then
        self.hoverGUID = hovered.decorGUID
        self.hoverX = x
        self.hoverY = y
        self.still = 0
    end

    self.still = self.still + elapsed
    if self.still < SOURCE_HOLD then return end

    local ok, reason = self:UseSource(hovered)
    if ok then ok, reason = self.api:CheckStock(hovered, #self.plan.items) end
    if not ok then self:Abort(reason); return end
    self.api:UsePlacementSettings()
    self.cursor = { x = x, y = y }
    self:SetState("basic", "Preparing copies. Keep the cursor still...")
    self:EnsureMode("BasicDecor")
end

-- A copy goes wherever the cursor points, so copying waits while the cursor is off
-- its spot. Once back, it must hold still there, like the first hover.
function Placement:CursorReady(elapsed)
    local x, y = GetCursorPosition()
    local wasAway, wasHolding = self.cursorAway, self.returnHold ~= nil
    if math.abs(x - self.cursor.x) + math.abs(y - self.cursor.y) > CURSOR_TOLERANCE then
        if self.state == "copy" and self.api:HasPendingCopy() then
            -- The pending copy follows the cursor; cancel it before it lands elsewhere.
            pcall(self.api.Cancel, self.api)
            self.state = "basic"
        end
        self.cursorAway, self.returnHold = true, nil
    elseif self.cursorAway then
        self.returnHold = (self.returnHold or 0) + elapsed
        if self.returnHold >= SOURCE_HOLD then self.cursorAway, self.returnHold = false, nil end
    end

    if wasAway ~= self.cursorAway or wasHolding ~= (self.returnHold ~= nil) then
        self.notify(self.returnHold and "Hold the cursor still to continue."
            or self.cursorAway and "Cursor moved. Put it back where it was to continue."
            or self.status, self:Completed(), #self.plan.items)
    end
    if self.cursorAway and self:StateInfo().cursor then
        self.age = 0
        return false
    end
    return true
end

function Placement:BeginCopy()
    self:SetState("copy", string.format("Creating copy %d / %d. Keep the cursor still...",
        self.copiesCreated + 1, #self.plan.items))
    -- Keep using the captured source when copies overlap it.
    self.api:BeginCopy(self.source, #self.plan.items - self.copiesCreated)
end

function Placement:IsNewCopy(item)
    local guid = item and item.decorGUID
    return guid ~= nil and guid ~= self.source.decorGUID and not self.inPile[guid]
        and (item.decorID == nil or item.decorID == self.source.decorID)
end

function Placement:NextCopy()
    local hovered = self.api:Hovered()
    local newCopy = self:IsNewCopy(hovered)
    if not self.pile then
        self.detectFrames = self.detectFrames + 1
        if not newCopy and self.detectFrames < PILE_DETECT_FRAMES then return end
        if newCopy then
            self.pile = "aside"
        elseif hovered and hovered.decorGUID == self.source.decorGUID then
            self.pile = "source"
        else
            self:Abort("The cursor no longer points at the item being copied.")
            return
        end
    elseif self.pile == "source" and newCopy then
        self:Abort("The cursor now points at a new copy, so the pile would drift.")
        return
    end
    if self.pile == "aside" then
        self:BeginAside("Click the new copy without moving the mouse. It moves aside.")
    elseif self.copiesCreated < #self.plan.items then
        self:BeginCopy()
    else
        self:PileReady()
    end
end

function Placement:PileReady()
    self.cursor = nil
    self.cursorAway, self.returnHold = false, nil
    pcall(self.api.RestoreSettings, self.api, self.saved)
    self.saved = nil
    self.stage = "ready"
    self:SetState("ready", string.format(
        "%d copies ready. Press Build, then click the pile's copies one at a time.", #self.plan.items))
end

function Placement:CopyPlaced(_, isNew)
    if not isNew then return end
    self.copiesCreated = self.copiesCreated + 1
    self.copyRetries, self.retryDelay = 0, nil
    if self.copiesCreated < #self.plan.items or self.pile ~= "source" then
        self:SetState("nextcopy", string.format("Created copy %d / %d. Keep the cursor still...",
            self.copiesCreated, #self.plan.items))
    else
        self:PileReady()
    end
end

-- Returns true while WoW's request limit is being waited out.
function Placement:RetryThrottledCopy()
    if self.state == "throttled" then return true end
    if self.state ~= "copy" and self.state ~= "placing" then return false end
    self.copyRetries = self.copyRetries + 1
    if self.copyRetries > MAX_COPY_RETRIES then return false end
    self.copyDelay, self.retryDelay = THROTTLED_COPY_DELAY, 2 ^ self.copyRetries
    self:SetState("throttled", string.format(
        "WoW's housing request limit reached. Waiting %d seconds before retrying copy %d / %d. Keep the cursor still.",
        self.retryDelay, self.copiesCreated + 1, #self.plan.items))
    return true
end

local function placePending(self, message)
    local pending = self.api:PendingInfo()
    if pending and (not pending.decorID or pending.decorID == self.source.decorID) then
        self:SetState("placing", message)
        self.api:PlaceCopy()
        return true
    end
end

-- Moving copies aside

function Placement:BeginAside(prompt)
    self.asidePrompt = prompt
    self:SetState("asideexpert", "Switching to Advanced mode...")
    self:EnsureMode("ExpertDecor")
end

function Placement:AskAsideClick(reason)
    self.asideClick, self.asideSeen = false, 0
    self:SetState("asideselect", (reason or "") .. self.asidePrompt)
end

function Placement:UpdateAsideSelection(elapsed)
    if not self:EnsureMode("ExpertDecor") then return end
    local selected = self.api:Selected()
    local guid = selected and selected.decorGUID
    -- Only the player's own click counts: WoW sometimes reports a selection by itself, or for one frame.
    local down = IsMouseButtonDown()
    if down then self.asideClick, self.asideSeen = true, 0 end
    if self:IsNewCopy(selected) then
        if not down and self.asideClick then
            self.asideSeen = self.asideSeen + 1
            if self.asideSeen >= 2 then self:MoveCopyAside(guid, elapsed) end
        end
        return
    end
    self.asideSeen = 0
    if guid and self.lastRejectedGUID ~= guid then
        self.lastRejectedGUID = guid
        self.notify((guid == self.source.decorGUID and "That is the original item under the copy. "
            or "That is not the new copy. ") .. "Click the new copy without moving the mouse.",
            self:Completed(), #self.plan.items)
    end
end

-- Until the first copy clears the cursor, it moves one step per click; later copies move the whole way at once.
function Placement:MoveCopyAside(guid, elapsed)
    self.lastRejectedGUID, self.activeGUID, self.asideGUID = nil, guid, guid
    local shift = self.asideTotal or MHT.ItemProfiles.AsideStep(self.source.decorID)
    self:SetState("asidemoving", "Moving the copy aside...")
    self.motion:Shift(shift, guid, function()
        self:SetState("asidecommitting", "Saving the copy...")
        self.api:Commit()
    end)
    self:StepAside(elapsed)
end

function Placement:StepAside(elapsed)
    if self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        -- Leaving Advanced mode cancels the unfinished move.
        self.motion:Stop()
        self.activeGUID = nil
        self:AskAsideClick("The editor mode changed, so the copy moved back. ")
        return
    end
    local selected = self.api:Selected()
    local guid = selected and selected.decorGUID
    if guid ~= self.activeGUID and (guid or not self.motion:PreparingPhase()) then
        -- WoW cancels the move when the copy loses the selection.
        self.motion:Stop()
        self.activeGUID, self.lastRejectedGUID = nil, guid
        self:AskAsideClick(guid and "Another item was selected, so the copy moved back. "
            or "The copy lost its selection and moved back. ")
        return
    end
    self.motion:Update(elapsed)
end

function Placement:CopyAsideSaved(guid, isNew)
    if isNew or guid and guid ~= self.activeGUID then return end
    self.activeGUID = nil
    if not self.asideTotal then self.asideSteps = self.asideSteps + 1 end
    if self.copiesCreated < #self.plan.items then
        self.switchFrames = 0
        self:SetState("asidewait", "Copy moved aside. Keep the cursor still...")
    else
        self:FinishAside()
    end
end

function Placement:FinishAside()
    if not self.asideTotal then
        local step = MHT.ItemProfiles.AsideStep(self.source.decorID)
        self.asideTotal = { x = step.x * self.asideSteps, y = step.y * self.asideSteps, z = step.z * self.asideSteps }
    end
    self.inPile[self.asideGUID] = true
    self.asideGUID = nil
    if self.copiesCreated < #self.plan.items then self:BeginCopy() else self:PileReady() end
end

-- The next copy may only be placed once the cursor points at the original again.
function Placement:UpdateAsideSettle()
    if not self:EnsureMode("BasicDecor") then return end
    self.settleFrames = self.settleFrames + 1
    if self.settleFrames < ASIDE_SETTLE_FRAMES then return end
    local hovered = self.api:Hovered()
    local guid = hovered and hovered.decorGUID
    if guid == self.source.decorGUID then
        self:FinishAside()
    elseif self.settleFrames >= ASIDE_SETTLE_FRAMES + ASIDE_CLEAR_FRAMES then
        -- Hover and selection can report different GUIDs for the same copy, so anything but the source counts as covered.
        if self.asideTotal then
            self:Abort(guid and "A moved copy still covers the cursor spot."
                or "The cursor no longer points at the item being copied.")
        elseif self.asideSteps >= MAX_ASIDE_STEPS then
            self:Abort(string.format("The copy still covers the cursor after %d steps aside.", self.asideSteps))
        else
            self:BeginAside("The copy still covers the cursor. Click it again without moving the mouse.")
        end
    end
end

-- States

State.arming = { waits = true, update = Placement.UpdateArming }

State.basic = { cursor = true, update = function(self)
    if self:EnsureMode("BasicDecor") then self:BeginCopy() end
end }

State.copy = { cursor = true, copying = true, update = function(self)
    if self.api:Mode() ~= Enum.HouseEditorMode.BasicDecor then
        -- Leaving Basic mode drops the pending copy; start it again.
        self.state = "basic"
    elseif self.api:HasPendingCopy() then
        placePending(self, "Placing a copy at the start point...")
    end
end }

State.placing = { copying = true, saved = Placement.CopyPlaced }

State.nextcopy = { cursor = true, update = function(self)
    if self.age >= self.copyDelay and self:EnsureMode("BasicDecor") and not self.api:HasPendingCopy() then
        self:NextCopy()
    end
end }

State.throttled = { cursor = true, copying = true, saved = Placement.CopyPlaced, update = function(self)
    if self.api:Mode() ~= Enum.HouseEditorMode.BasicDecor then
        self:Abort("Editor mode changed while waiting to retry the copy.")
    elseif self.age >= self.retryDelay then
        if not self.api:HasPendingCopy() then
            self:BeginCopy()
        elseif not placePending(self, "Retrying the pending copy after WoW's request limit...") then
            self:Abort("The pending item changed while waiting to retry the copy.")
        end
    end
end }

State.asideexpert = { update = function(self)
    if self:EnsureMode("ExpertDecor") then self:AskAsideClick() end
end }

State.asideselect = { cursor = true, waits = true, update = Placement.UpdateAsideSelection }

State.asidemoving = { waits = true, update = Placement.StepAside }

State.asidecommitting = { action = "saving the copy moved aside", saved = Placement.CopyAsideSaved }

State.asidewait = { update = function(self)
    self.switchFrames = self.switchFrames + 1
    if self.switchFrames >= ASIDE_SWITCH_FRAMES then
        self.settleFrames = 0
        self:SetState("asidesettle")
        self:EnsureMode("BasicDecor")
    end
end }

State.asidesettle = { cursor = true, update = Placement.UpdateAsideSettle }
