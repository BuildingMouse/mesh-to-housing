local _, MHT = ...
local Placement = {}
Placement.__index = Placement
MHT.Placement = Placement

-- Cooldown starts after the game confirms placement.
local BATCH_COPY_DELAY = 0.2

Placement.DEFAULT_WORKFLOW = "batch"

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
    return self.state ~= "idle"
end

function Placement:SetState(state, message)
    self.state = state
    self.age = 0
    if message then
        self.notify(message, self.completed, self.plan and #self.plan.items or 0)
    end
end

function Placement:Start(plan, profile, workflow)
    if self:Busy() then return end
    if not self.api:Available() then
        return nil, "Placement needs Retail housing catalog variants (12.0.5+)."
    end
    if not self.api:Active() then
        return nil, "Open the housing editor first."
    end
    if self.api:IsSelected() then
        return nil, "Finish editing the selected item first."
    end

    workflow = workflow or Placement.DEFAULT_WORKFLOW
    if workflow ~= "repeat" and workflow ~= "batch" then
        return nil, "Unknown placement workflow."
    end

    self.plan = plan
    self.profile = profile
    self.workflow = workflow
    self.isTest = false

    self.copiesCreated = 0

    self.completed = 0

    self.source = nil
    self.cursor = nil
    self.hoverGUID = nil
    self.hoverX = nil
    self.hoverY = nil
    self.still = 0

    self.activeGUID = nil
    self.activeIndex = nil
    self.createdGUID = nil
    self.finished = {}
    self.lastRejectedGUID = nil

    self.saved = self.api:SaveSettings()

    self:SetState(
        "arming",
        workflow == "batch"
            and "Hover over the source and keep the mouse still. All copies will be created first."
            or "Hover over the source and keep the mouse still. Each copy will be placed, then moved."
    )
    return true
end

function Placement:StartTest(item, profile)
    if self:Busy() then return end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        return nil, "Open Advanced mode first."
    end
    if self.api:IsSelected() then
        return nil, "Deselect the item, press Start, then click it to test."
    end
    self.plan = { items = { item } }
    self.profile = profile
    self.isTest = true
    self.completed = 0
    self.finished = {}
    self.saved, self.source, self.cursor = nil, nil, nil
    self.activeGUID, self.activeIndex = nil, nil
    self.lastRejectedGUID = nil
    self:SetState("testselect", "Test armed. Click one item in Advanced mode.")
    return true
end

function Placement:Abort(message)
    if not self:Busy() then
        if message then
            self.notify(message, self.completed, self.plan and #self.plan.items or 0)
        end
        return
    end

    self.motion:Stop()

    local selected = self.api:Available() and self.api:Selected()
    local ownEditing = false

    if (self.state == "copy" or self.state == "placing") and self.api:Available()
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

    pcall(self.api.RestoreSettings, self.api, self.saved)

    self.saved = nil
    self.cursor = nil
    self.activeGUID = nil
    self.activeIndex = nil
    self.createdGUID = nil

    self:SetState("idle", message or "Aborted. Finished items remain placed.")
end

function Placement:CursorStill()
    if not self.cursor then return true end

    local x, y = GetCursorPosition()
    if math.abs(x - self.cursor.x) + math.abs(y - self.cursor.y) > 8 then
        self:Abort("Mouse moved while copies were being created. Placement stopped.")
        return false
    end

    return true
end

function Placement:BeginCopy()
    local copyIndex = self.copiesCreated + 1

    self:SetState(
        "copy",
        string.format("Creating copy %d / %d. Keep the mouse still...", copyIndex, #self.plan.items)
    )
    self.createdGUID = nil

    -- Keep using the captured source when copies overlap it.
    self.api:BeginCopy(self.source, #self.plan.items - self.copiesCreated)
end

function Placement:BeginBasic()
    self:SetState("basic", "Preparing copies. Keep the mouse still...")
    self.api:Switch("BasicDecor")
end

function Placement:ReturnToSource()
    self.cursor = nil
    self.hoverGUID, self.hoverX, self.hoverY, self.still = nil, nil, nil, 0
    self:SetState("returnsource", "Returning to Basic mode. Hover over the original source for the next copy.")
    self.api:Switch("BasicDecor")
end

function Placement:BeginSelectionPhase()
    self.cursor = nil
    self.hoverGUID = nil
    self.lastRejectedGUID = nil

    self:SetState(
        "expert",
        self.workflow == "batch" and string.format(
            "%d copies created. Switching to Advanced mode; click the stacked copies one at a time.",
            self.copiesCreated
        ) or "Copy placed. Switching to Advanced mode; click the new copy to move it."
    )
    self.api:Switch("ExpertDecor")
end

function Placement:HandleSelectedCopy(selected)
    local guid = selected.decorGUID
    if not guid then return end

    local reason
    if self.isTest and selected.isLocked then
        reason = "That item is locked. Click an unlocked item."
    elseif not self.isTest and guid == self.source.decorGUID then
        reason = "That is the source. Click a copy instead."
    elseif not self.isTest and selected.decorID and selected.decorID ~= self.source.decorID then
        reason = "That is a different decor item. Click a copy."
    elseif self.finished[guid] then
        reason = "That copy is finished. Click another copy."
    elseif not self.isTest and self.workflow == "repeat" and self.createdGUID and guid ~= self.createdGUID then
        reason = "Click the copy just created for this target."
    end
    if reason then
        if self.lastRejectedGUID ~= guid then
            self.lastRejectedGUID = guid
            self.notify(reason, self.completed, #self.plan.items)
        end
        return
    end

    self.lastRejectedGUID = nil
    self.activeGUID = guid

    self.activeIndex = self.completed + 1

    self:SetState(
        "moving",
        string.format(
            "Moving selected copy to target %d / %d...",
            self.activeIndex,
            #self.plan.items
        )
    )

    local function done()
        self:SetState("committing", "Saving the selected copy...")
        self.api:Commit()
    end
    local function onPhase(label)
        self:SetState("moving", label .. (self.isTest and " (test)..." or " selected copy..."))
    end
    local target = self.plan.items[self.activeIndex]
    if self.isTest then
        self.motion:Apply(target, self.profile, guid, done, true, onPhase)
    else
        self.motion:MoveIntoPlace(target, {
            from = self.plan.source,
            pivot = MHT.ItemProfiles.Pivot(self.source.decorID),
            motionProfile = self.profile,
        }, guid, done, onPhase)
    end
end

function Placement:Update(elapsed)
    if not self:Busy() then return end

    if not self.api:Active() then
        self:Abort("Housing editor closed; placement stopped.")
        return
    end

    self.age = self.age + elapsed

    if self.state == "arming" or self.state == "source" then
        local hovered = self.api:Hovered()
        local x, y = GetCursorPosition()

        if not hovered or hovered.isLocked or not hovered.decorGUID
            or (self.state == "source" and hovered.decorGUID ~= self.source.decorGUID) then
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
        if self.still < 1.2 then return end

        if self.state == "arming" then
            local stock, reason = self.api:CheckStock(hovered, #self.plan.items)
            if not stock then self:Abort(reason); return end
            self.source = hovered
            self.notify(string.format("%s: %d matching copies; %d needed.",
                stock.name, stock.count, #self.plan.items), 0, #self.plan.items)
            self.api:UsePlacementSettings()
        end
        self.cursor = { x = x, y = y }
        self:BeginBasic()
        return
    end

    if self.cursor and not self:CursorStill() then return end

    if self.state == "basic" then
        if self.api:Mode() == Enum.HouseEditorMode.BasicDecor then
            self:BeginCopy()
        end

    elseif self.state == "returnsource" then
        if self.api:Mode() == Enum.HouseEditorMode.BasicDecor then
            self:SetState("source", "Hover over the original source and hold still for the next copy.")
        end

    elseif self.state == "nextcopy" then
        if self.age >= BATCH_COPY_DELAY
            and self.api:Mode() == Enum.HouseEditorMode.BasicDecor
            and not self.api:HasPendingCopy() then
            self:BeginCopy()
        end

    elseif self.state == "copy" then
        if self.api:HasPendingCopy() then
            local pending = self.api:PendingInfo()

            if pending and (not pending.decorID or pending.decorID == self.source.decorID) then
                self:SetState("placing", "Placing a copy at the start point...")
                self.api:PlaceCopy()
            end
        end

    elseif self.state == "expert" then
        if self.api:Mode() == Enum.HouseEditorMode.ExpertDecor then
            self:SetState(
                "select",
                self.workflow == "batch"
                    and "Mouse movement is allowed now. Click one stacked copy; after it moves, click the next."
                    or "Click the new copy to move it. Then hover over the original source to repeat."
            )
        end

    elseif self.state == "select" or self.state == "testselect" then
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

    if self.state ~= "select" and self.state ~= "testselect" and self.state ~= "source" and self.state ~= "moving" and self.age > 10 then
        self:Abort("The game did not confirm the last action. Placement stopped.")
    end
end

function Placement:OnEvent(event, ...)
    if not self:Busy() then return end

    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
        self:Abort("Placement interrupted.")
        return
    end

    if event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" or event == "HOUSING_DECOR_PLACE_FAILURE" then
        self:Abort("The game rejected the placement or mode change (" .. tostring((...)) .. ").")
        return
    end

    if event ~= "HOUSING_DECOR_PLACE_SUCCESS" then return end

    local guid, _, isNew, isPreview = ...
    if isPreview then return end

    if self.state == "placing" and isNew then
        self.copiesCreated = self.copiesCreated + 1
        self.createdGUID = guid

        if self.workflow == "repeat" then
            self:BeginSelectionPhase()
        elseif self.copiesCreated < #self.plan.items then
            self:SetState(
                "nextcopy",
                string.format(
                    "Created copy %d / %d. Waiting %.2fs before the next copy...",
                    self.copiesCreated,
                    #self.plan.items,
                    BATCH_COPY_DELAY
                )
            )
        else
            self:BeginSelectionPhase()
        end
        return
    end

    if self.state == "committing" and not isNew then
        if guid and guid ~= self.activeGUID then return end
        local committedGUID = self.activeGUID

        self.finished[committedGUID] = true
        self.completed = self.completed + 1
        self.activeGUID = nil
        self.activeIndex = nil

        if self.completed == #self.plan.items then
            self:Abort(
                self.isTest and "Test finished. Movement and rotation saved."
                    or "Done. All " .. self.completed .. " copies were moved and rotated; source item kept."
            )
        elseif self.workflow == "repeat" then
            self:ReturnToSource()
        else
            self:SetState(
                "select",
                string.format(
                    "%d / %d finished. Click another stacked copy.",
                    self.completed,
                    #self.plan.items
                )
            )
        end
    end
end
