local _, MHT = ...
local Placement = {}
Placement.__index = Placement
MHT.Placement = Placement

-- One build session; Preparation.lua and Assembly.lua register their states here.
Placement.States = {}

local NO_STATE = {}
-- WoW undoes an unfinished edit when any of these change.
local CONTEXT_EVENTS = { HOUSE_EDITOR_MODE_CHANGED = true, HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED = true,
    HOUSING_DECOR_PRECISION_SUBMODE_CHANGED = true }

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
    return string.format("Build ended. %d of %d items placed.", placement:CountItems("saved"), #placement.items)
end

function Placement.New(api, notify)
    return setmetatable({
        api = api,
        motion = MHT.Motion.New(api),
        notify = notify,
        state = "idle",
        items = {},
    }, Placement)
end

function Placement:Busy()
    return self.state ~= "idle" and self.state ~= "ready" and self.state ~= "paused"
end

-- A build session runs from Prepare until the build ends.
function Placement:HasSession()
    return self.stage ~= nil
end

function Placement:Ready()
    return self.state == "ready"
end

function Placement:Paused()
    return self.state == "paused"
end

function Placement:StateInfo()
    return Placement.States[self.state] or NO_STATE
end

function Placement:SetState(state, message)
    self.state = state
    self.age = 0
    if message then
        self.status = message
        self.notify(message, self:Completed(), self.plan and #self.plan.items or 0)
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
    self:ResetItems(#plan.items)
    self.pauseRequested = false
    self.source, self.itemTimesFor = nil, nil
    self.modeRequest = nil
    self.activeGUID, self.lastRejectedGUID = nil, nil
    self:ResetPreparation()

    self.saved = self.api:SaveSettings()

    if self.fromPile then
        self.api:UsePlacementSettings()
        self:BeginSelectionPhase()
    else
        self:SetState("arming", "Hover the item to copy and hold the cursor still.")
    end
    return true
end

function Placement.Estimate(plan, fromPile)
    local seconds = 0
    for _, item in ipairs(Placement.ItemSeconds(plan, plan.requires or MHT.ItemProfiles.DEFAULT_DECOR_ID)) do
        seconds = seconds + item
    end
    if not fromPile then seconds = seconds + Placement.PrepareSeconds(#plan.items) end
    return seconds
end

function Placement:RemainingSeconds()
    if self.stage == "preparing" then return self:PrepareRemaining() + self:BuildRemaining() end
    return self:BuildRemaining()
end

function Placement:Progress()
    if self.stage == "preparing" then return self:PileCount() / #self.items end
    return self:BuildProgress()
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

-- Something went wrong: a running build pauses and keeps its progress; anything else ends.
function Placement:Abort(message)
    if self.stage ~= "building" then
        self:End(message)
    elseif self:Busy() then
        self:Interrupt(message)
    elseif message then
        self.notify(message, self:Completed(), #self.plan.items)
    end
end

function Placement:End(message)
    if not self:Busy() and not self:HasSession() then
        if message then
            self.notify(message, self:Completed(), self.plan and #self.plan.items or 0)
        end
        return
    end

    self.motion:Stop()

    local available = self.api:Available()
    local selected = available and self.api:Selected()
    local ownEditing = self:StateInfo().copying and available
        and self.api:Mode() == Enum.HouseEditorMode.BasicDecor and self.api:HasPendingCopy()
        or self.activeGUID and selected and selected.decorGUID == self.activeGUID

    self.state = "idle"
    if ownEditing then pcall(self.api.Cancel, self.api) end
    if self.saved then pcall(self.api.RestoreSettings, self.api, self.saved) end

    message = message or endMessage(self)
    if self.stage == "preparing" then message = message .. " " .. copiesPlaced(self.copiesCreated) end

    self.saved = nil
    self.cursor = nil
    self.cursorAway, self.returnHold = false, nil
    self.activeGUID = nil
    self.pauseRequested = false
    self.stage = nil

    self:SetState("idle", message)
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

function Placement:Update(elapsed)
    if not self:Busy() then return end

    local watch = self:StateInfo().watch
    if watch and not watch(self) then return end

    if not self.api:Active() then
        self:Abort("Housing editor closed; placement stopped.")
        return
    end

    self.age = self.age + elapsed
    if self.cursor and not self:CursorReady(elapsed) then return end

    local update = self:StateInfo().update
    if update then update(self, elapsed) end

    if self:Busy() and not self:StateInfo().waits and self.age > 10 then
        self:Abort("The game did not confirm the last action. Placement stopped.")
    end
end

function Placement:OnEvent(event, ...)
    if event == "HOUSE_EDITOR_MODE_CHANGED" then self.modeRequest = nil end
    local info = self:StateInfo()
    if CONTEXT_EVENTS[event] and info.watch then
        info.watch(self)
        info = self:StateInfo()
    end

    -- A paused build still hears back about a save it sent.
    if event == "HOUSING_DECOR_PLACE_SUCCESS" then
        local guid, _, isNew, isPreview = ...
        if not isPreview and info.saved then info.saved(self, guid, isNew) end
    elseif event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" or event == "HOUSING_DECOR_PLACE_FAILURE" then
        if info.failed then info.failed(self, event, ...)
        elseif self:Busy() then self:OnFailure(event, ...) end
    elseif (event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD") and self:Busy() then
        self:Abort("Placement interrupted.")
    end
end

function Placement:FailureText(event, result)
    local name = resultName(result)
    if name == "TooManyRequests" then
        return "WoW is limiting housing requests. Wait a few seconds before trying again. ("
            .. name .. ", " .. tostring(result) .. ")"
    end
    local action = event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" and "changing housing mode"
        or self:StateInfo().action or "placing a copy"
    return "WoW rejected " .. action .. ": " .. name .. " (" .. tostring(result) .. ")."
end

function Placement:OnFailure(event, result)
    if event == "HOUSING_DECOR_PLACE_FAILURE" and resultName(result) == "TooManyRequests"
        and self:RetryThrottledCopy() then return end
    self:Abort(self:FailureText(event, result))
end
