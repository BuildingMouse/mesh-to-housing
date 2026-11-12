local _, MHT = ...
local Placement = {}
Placement.__index = Placement
MHT.Placement = Placement

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
local CURSOR_GATES = { basic = true, copy = true, nextcopy = true, throttled = true,
    asideselect = true, asidesettle = true }
local WAITS_FOR_PLAYER = { select = true, moving = true, asideselect = true, asidemoving = true }

local function resultName(result)
    for name, value in pairs(Enum.HousingResult or {}) do
        if value == result then return name end
    end
    return "Unknown housing error"
end

local function copiesPlaced(count)
    return string.format("%d %s placed.", count, count == 1 and "copy was" or "copies were")
end

local function endMessage(placement)
    if placement.stage == "preparing" then return "Preparation stopped." end
    return string.format("Build ended. %d of %d items placed.", placement.completed, #placement.plan.items)
end

function Placement.New(api, notify)
    return setmetatable({
        api = api,
        motion = MHT.Motion.New(api),
        notify = notify,
        state = "idle",
        completed = 0,
    }, Placement)
end

function Placement:Busy()
    return self.state ~= "idle" and self.state ~= "ready"
end

-- A build session runs from Prepare until the build ends.
function Placement:HasSession()
    return self.stage ~= nil
end

function Placement:Ready()
    return self.state == "ready"
end

function Placement:SetState(state, message)
    self.state = state
    self.age = 0
    if message then
        self.notify(message, self.completed, self.plan and #self.plan.items or 0)
    end
end

function Placement:Prepare(plan)
    return self:Start(plan, "preparing")
end

function Placement:BuildFromPile(plan)
    return self:Start(plan, "building")
end

function Placement:Start(plan, stage)
    if self:Busy() or self:HasSession() then return nil, "End the current build first." end
    if not self.api:Available() then
        return nil, "Placement needs Retail housing catalog variants (12.0.5+)."
    end
    if not self.api:Active() then
        return nil, "Open the housing editor first."
    end
    if self.api:IsSelected() then
        return nil, "Finish editing the selected item first."
    end
    if not MHT.Plan.SingleItem(plan) then
        return nil, "This plan uses more than one item; building supports one item for now."
    end

    self.plan = plan
    self.stage = stage
    self.fromPile = stage == "building"

    self.copiesCreated = 0
    self.pile, self.detectFrames = nil, 0
    self.asideGUID, self.asideSteps, self.asideTotal, self.inPile = nil, 0, nil, {}
    self.copyDelay, self.copyRetries, self.retryDelay = COPY_DELAY, 0, nil

    self.completed = 0

    self.source = nil
    self.cursor = nil
    self.cursorAway, self.returnHold = false, nil
    self.modeRequest = nil
    self.hoverGUID = nil
    self.hoverX = nil
    self.hoverY = nil
    self.still = 0

    self.activeGUID = nil
    self.finished = {}
    self.lastRejectedGUID = nil

    self.saved = self.api:SaveSettings()

    if self.fromPile then
        self.api:UsePlacementSettings()
        self:BeginSelectionPhase()
    else
        self:SetState("arming", "Hover the item to copy and hold the cursor still.")
    end
    return true
end

function Placement:Build()
    if not self:Ready() then return nil, "Prepare items or use an existing pile first." end
    if not self.api:Active() then return nil, "Open the housing editor first." end
    if self.api:IsSelected() then return nil, "Finish editing the selected item first." end
    self.stage = "building"
    self.saved = self.api:SaveSettings()
    self.api:UsePlacementSettings()
    self:BeginSelectionPhase()
    return true
end

function Placement:UseSource(item)
    local required = self.plan.requires
    if required and item.decorID ~= required then
        local name = MHT.ItemProfiles.Logged(required).name or ("decor item " .. required)
        return nil, "Use " .. name .. " for this model."
    end
    self.source = item
    return true
end

function Placement:Abort(message)
    if not self:Busy() and not self:HasSession() then
        if message then
            self.notify(message, self.completed, self.plan and #self.plan.items or 0)
        end
        return
    end

    self.motion:Stop()

    local selected = self.api:Available() and self.api:Selected()
    local ownEditing = false

    if (self.state == "copy" or self.state == "placing" or self.state == "throttled") and self.api:Available()
        and self.api:Mode() == Enum.HouseEditorMode.BasicDecor
        and self.api:HasPendingCopy() then
        ownEditing = true
    end

    if self.activeGUID and selected and selected.decorGUID == self.activeGUID then
        ownEditing = true
    end

    self.state = "idle"

    if ownEditing then
        pcall(self.api.Cancel, self.api)
    end

    if self.saved then pcall(self.api.RestoreSettings, self.api, self.saved) end

    message = message or endMessage(self)
    if self.stage == "preparing" then message = message .. " " .. copiesPlaced(self.copiesCreated) end

    self.saved = nil
    self.cursor = nil
    self.cursorAway, self.returnHold = false, nil
    self.activeGUID = nil
    self.stage = nil

    self:SetState("idle", message)
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
            or self.state == "asideselect" and self.asidePrompt
            or "Keep the cursor still while copies are placed.", self.completed, #self.plan.items)
    end
    if self.cursorAway and CURSOR_GATES[self.state] then
        self.age = 0
        return false
    end
    return true
end

-- Switches once and waits; asks again if the player leaves the mode later.
function Placement:EnsureMode(mode)
    if self.api:Mode() == Enum.HouseEditorMode[mode] then
        self.modeRequest = nil
        return true
    end
    if self.modeRequest ~= mode then
        self.modeRequest = mode
        self.api:Switch(mode)
    end
    return false
end

function Placement:BeginCopy()
    local copyIndex = self.copiesCreated + 1

    self:SetState(
        "copy",
        string.format("Creating copy %d / %d. Keep the cursor still...", copyIndex, #self.plan.items)
    )

    -- Keep using the captured source when copies overlap it.
    self.api:BeginCopy(self.source, #self.plan.items - self.copiesCreated)
end

function Placement:BeginBasic()
    self:SetState("basic", "Preparing copies. Keep the cursor still...")
    self:EnsureMode("BasicDecor")
end

function Placement:IsNewCopy(item)
    local guid = item and item.decorGUID
    return guid ~= nil and guid ~= self.source.decorGUID and not self.inPile[guid]
        and (item.decorID == nil or item.decorID == self.source.decorID)
end

-- The first copy shows whether new copies cover the cursor; read in Basic mode, as it was placed.
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
            self.completed, #self.plan.items)
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

function Placement:CopyAsideSaved()
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

function Placement:PileReady()
    self.cursor = nil
    self.cursorAway, self.returnHold = false, nil
    pcall(self.api.RestoreSettings, self.api, self.saved)
    self.saved = nil
    self.stage = "ready"
    self:SetState("ready", string.format(
        "%d copies ready. Press Build, then click the pile's copies one at a time.", #self.plan.items))
end

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

    self:SetState(
        "moving",
        string.format(
            "Moving selected copy to target %d / %d...",
            index,
            #self.plan.items
        )
    )

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

function Placement:Update(elapsed)
    if not self:Busy() then return end

    if not self.api:Active() then
        self:Abort("Housing editor closed; placement stopped.")
        return
    end

    self.age = self.age + elapsed

    if self.state == "arming" then
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
        self:BeginBasic()
        return
    end

    if self.cursor and not self:CursorReady(elapsed) then return end

    if self.state == "basic" then
        if self:EnsureMode("BasicDecor") then
            self:BeginCopy()
        end

    elseif self.state == "nextcopy" then
        if self.age >= self.copyDelay
            and self:EnsureMode("BasicDecor")
            and not self.api:HasPendingCopy() then
            self:NextCopy()
        end

    elseif self.state == "asideexpert" then
        if self:EnsureMode("ExpertDecor") then self:AskAsideClick() end

    elseif self.state == "asideselect" then
        self:UpdateAsideSelection(elapsed)

    elseif self.state == "asidemoving" then
        if self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
            -- Leaving Advanced mode cancels the unfinished move.
            self.motion:Stop()
            self.activeGUID = nil
            self:AskAsideClick("The editor mode changed, so the copy moved back. ")
        else
            self:StepAside(elapsed)
        end

    elseif self.state == "asidewait" then
        self.switchFrames = self.switchFrames + 1
        if self.switchFrames >= ASIDE_SWITCH_FRAMES then
            self.settleFrames = 0
            self:SetState("asidesettle")
            self:EnsureMode("BasicDecor")
        end

    elseif self.state == "asidesettle" then
        self:UpdateAsideSettle()

    elseif self.state == "throttled" then
        if self.api:Mode() ~= Enum.HouseEditorMode.BasicDecor then
            self:Abort("Editor mode changed while waiting to retry the copy.")
        elseif self.age >= self.retryDelay then
            if self.api:HasPendingCopy() then
                local pending = self.api:PendingInfo()
                if pending and (not pending.decorID or pending.decorID == self.source.decorID) then
                    self:SetState("placing", "Retrying the pending copy after WoW's request limit...")
                    self.api:PlaceCopy()
                else
                    self:Abort("The pending item changed while waiting to retry the copy.")
                end
            else
                self:BeginCopy()
            end
        end

    elseif self.state == "copy" then
        if self.api:Mode() ~= Enum.HouseEditorMode.BasicDecor then
            -- Leaving Basic mode drops the pending copy; start it again.
            self.state = "basic"
        elseif self.api:HasPendingCopy() then
            local pending = self.api:PendingInfo()

            if pending and (not pending.decorID or pending.decorID == self.source.decorID) then
                self:SetState("placing", "Placing a copy at the start point...")
                self.api:PlaceCopy()
            end
        end

    elseif self.state == "expert" then
        if self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then
            self:SetState("select", string.format(
                "Click the copies in the pile one at a time (1 / %d). Keep the camera still.", #self.plan.items))
        end

    elseif self.state == "select" then
        if self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
            self:Abort("Editor mode changed; placement stopped.")
            return
        end

        local selected = self.api:Selected()
        if selected then
            self:HandleSelectedCopy(selected)
        end

    elseif self.state == "moving" then
        if self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
            self:Abort("Editor mode changed; placement stopped.")
            return
        end

        self.motion:Update(elapsed)
    end

    if self:Busy() and not WAITS_FOR_PLAYER[self.state] and self.age > 10 then
        self:Abort("The game did not confirm the last action. Placement stopped.")
    end
end

function Placement:OnEvent(event, ...)
    -- Any finished mode change, the player's too, lets EnsureMode ask again.
    if event == "HOUSE_EDITOR_MODE_CHANGED" then self.modeRequest = nil end
    if not self:Busy() then return end

    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
        self:Abort("Placement interrupted.")
        return
    end

    if event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" or event == "HOUSING_DECOR_PLACE_FAILURE" then
        local result = ...
        local name = resultName(result)
        local limited = name == "TooManyRequests"
        if event == "HOUSING_DECOR_PLACE_FAILURE" and limited then
            if self.state == "throttled" then return end
            if self.state == "copy" or self.state == "placing" then
                self.copyRetries = self.copyRetries + 1
                if self.copyRetries <= MAX_COPY_RETRIES then
                    self.copyDelay, self.retryDelay = THROTTLED_COPY_DELAY, 2 ^ self.copyRetries
                    self:SetState("throttled", string.format(
                        "WoW's housing request limit reached. Waiting %d seconds before retrying copy %d / %d. Keep the cursor still.",
                        self.retryDelay, self.copiesCreated + 1, #self.plan.items))
                    return
                end
            end
        end
        local action = event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" and "changing housing mode"
            or self.state == "committing" and "saving the moved item"
            or self.state == "asidecommitting" and "saving the copy moved aside" or "placing a copy"
        self:Abort(limited and ("WoW is limiting housing requests. Wait a few seconds before trying again. ("
            .. name .. ", " .. tostring(result) .. ")")
            or ("WoW rejected " .. action .. ": " .. name .. " (" .. tostring(result) .. ")."))
        return
    end

    if event ~= "HOUSING_DECOR_PLACE_SUCCESS" then return end

    local guid, _, isNew, isPreview = ...
    if isPreview then return end

    if (self.state == "placing" or self.state == "throttled") and isNew then
        self.copiesCreated = self.copiesCreated + 1
        self.copyRetries, self.retryDelay = 0, nil

        if self.copiesCreated < #self.plan.items or self.pile ~= "source" then
            self:SetState(
                "nextcopy",
                string.format(
                    "Created copy %d / %d. Keep the cursor still...",
                    self.copiesCreated,
                    #self.plan.items
                )
            )
        else
            self:PileReady()
        end
        return
    end

    if self.state == "asidecommitting" and not isNew then
        if guid and guid ~= self.activeGUID then return end
        self:CopyAsideSaved()
        return
    end

    if self.state == "committing" and not isNew then
        if guid and guid ~= self.activeGUID then return end
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
end
