local _, MHT = ...
local Placement = {}
Placement.__index = Placement
MHT.Placement = Placement

-- One build session; Preparation.lua and Assembly.lua register their states here.
Placement.States = {}

local NO_STATE = {}

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

function Placement:StateInfo()
    return Placement.States[self.state] or NO_STATE
end

function Placement:SetState(state, message)
    self.state = state
    self.age = 0
    if message then
        self.status = message
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
    self.completed = 0
    self.source = nil
    self.modeRequest = nil
    self.activeGUID, self.lastRejectedGUID = nil, nil
    self.finished = {}
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
    -- Any finished mode change, the player's too, lets EnsureMode ask again.
    if event == "HOUSE_EDITOR_MODE_CHANGED" then self.modeRequest = nil end
    if not self:Busy() then return end

    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
        self:Abort("Placement interrupted.")
    elseif event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" or event == "HOUSING_DECOR_PLACE_FAILURE" then
        self:OnFailure(event, ...)
    elseif event == "HOUSING_DECOR_PLACE_SUCCESS" then
        local guid, _, isNew, isPreview = ...
        local saved = self:StateInfo().saved
        if not isPreview and saved then saved(self, guid, isNew) end
    end
end

function Placement:OnFailure(event, result)
    local name = resultName(result)
    local limited = name == "TooManyRequests"
    if event == "HOUSING_DECOR_PLACE_FAILURE" and limited and self:RetryThrottledCopy() then return end
    local action = event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" and "changing housing mode"
        or self:StateInfo().action or "placing a copy"
    self:Abort(limited and ("WoW is limiting housing requests. Wait a few seconds before trying again. ("
        .. name .. ", " .. tostring(result) .. ")")
        or ("WoW rejected " .. action .. ": " .. name .. " (" .. tostring(result) .. ")."))
end
