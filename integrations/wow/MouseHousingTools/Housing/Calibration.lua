local _, MHT = ...
local Calibration = {}
Calibration.__index = Calibration
MHT.Calibration = Calibration

local axes = { x = "right", y = "forward", z = "up" }

-- A half turn shifts the center by twice the pivot offset in the perpendicular plane.
function Calibration.Measure(kind, axis, correction, profile)
    local result = { kind = kind, axis = axis, ticks = {}, seconds = {}, units = {}, correction = correction }
    for coordinate, speed in pairs(axes) do
        if (kind == "pivot" and coordinate ~= axis) or (kind == "size" and coordinate == axis) then
            local ticks, seconds = correction.ticks[coordinate], correction.seconds[coordinate]
            if kind == "pivot" then
                ticks, seconds = -ticks / 2, -seconds / 2
            else
                ticks, seconds = math.abs(ticks), math.abs(seconds)
            end
            result.ticks[coordinate], result.seconds[coordinate] = ticks, seconds
            result.units[coordinate] = seconds * profile[speed]
        end
    end
    return result
end

function Calibration.New(api, capture, measurements, notify)
    return setmetatable({ api = api, capture = capture, measurements = measurements,
        notify = notify, motion = MHT.Motion.New(api), state = "idle" }, Calibration)
end

function Calibration:Busy()
    return self.state ~= "idle" and self.state ~= "done"
end

function Calibration:SetState(state, message)
    self.state, self.age = state, 0
    self.notify(message)
end

function Calibration:Start(kind, axis, workflow, profile)
    if self:Busy() then return end
    assert((kind == "pivot" or kind == "size") and axes[axis]
        and (workflow == "double" or workflow == "aside"), "Choose a calibration test, axis and copy method.")
    if not self.api:Active() then return nil, "Open the housing editor first." end
    if self.api:IsSelected() then return nil, "Finish editing the selected item, then Start and hover the source." end
    self.kind, self.axis, self.workflow, self.profile = kind, axis, workflow, profile
    self.source, self.cursor, self.hoverGUID, self.hoverX, self.hoverY = nil, nil, nil, nil, nil
    self.still, self.created, self.copies, self.testGUID, self.result = 0, 0, {}, nil, nil
    self.asideGUID, self.copyVariants = nil, nil
    self.saved = self.api:SaveSettings()
    self:SetState("arming", "Hover a rectangular block at its default size and orientation; keep the mouse still.")
    return true
end

function Calibration:BeginCopy()
    self:SetState("copy", "Creating calibration copy " .. (self.created + 1) .. " / 2. Keep the mouse still.")
    self.api:BeginCopy(self.source, 2 - self.created, self.copyVariants[self.created + 1])
end

function Calibration:ValidCopy(selected)
    if not selected or selected.isLocked or not selected.decorGUID then return false end
    if selected.decorGUID == self.source.decorGUID or selected.decorID ~= self.source.decorID then return false end
    if #self.copies == self.created then
        for _, guid in ipairs(self.copies) do if guid == selected.decorGUID then return true end end
        return false
    end
    return true
end

function Calibration:BeginCapture()
    local allowed = {}
    for coordinate in pairs(axes) do
        allowed[coordinate] = self.kind == "pivot" and coordinate ~= self.axis or self.kind == "size" and coordinate == self.axis
    end
    self:SetState("measuring", self.kind == "pivot"
        and "Use movement keys, one axis at a time, to align the rotated copy over the untouched copy. Then click Aligned."
        or "Move along " .. self.axis:upper() .. " until the faces just touch without overlap. Then click Faces touch.")
    local started, reason = self.capture:Start({ axes = allowed })
    if not started then error(reason or "Could not start movement capture.") end
end

function Calibration:Advance()
    local selected = self.api:Selected()
    if self.state == "moveaside" or self.state == "align" then
        if self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
            return nil, "Return to Advanced mode and select a calibration copy."
        end
    end
    if self.state == "moveaside" then
        if not self:ValidCopy(selected) then return nil, "Click the first calibration copy and move it aside first." end
        self.asideGUID = selected.decorGUID
        self:SetState("committingAside", "Saving the copy moved aside...")
        self.api:Commit()
    elseif self.state == "align" then
        if not self:ValidCopy(selected) then return nil, "Select a calibration copy, not the original source." end
        self.testGUID = selected.decorGUID
        if self.kind == "size" then
            self:BeginCapture()
        else
            self:SetState("rotating", "Rotating the selected copy 180° around " .. self.axis:upper() .. "...")
            local rotation = { x = 0, y = 0, z = 0 }
            rotation[self.axis] = 180
            self.motion:Apply({ x = 0, y = 0, z = 0, rotation = rotation }, self.profile, self.testGUID,
                function() self:BeginCapture() end, true)
        end
    elseif self.state == "measuring" then
        if not self.capture:Busy() or not selected or selected.decorGUID ~= self.testGUID then
            return nil, "The measurement was interrupted. Start again."
        end
        local correction = self.capture.recorder:Snapshot()
        if self.kind == "size" and math.abs(correction.seconds[self.axis]) < 1e-6 then
            return nil, "Move the copy until its face touches the reference before finishing."
        end
        self.result = Calibration.Measure(self.kind, self.axis, correction, self.profile)
        self.result.rotationSpeed, self.result.firstRotationAxis = self.profile.rotate, self.profile.firstRotationAxis
        self:SetState("committing", "Saving the aligned test copy...")
        self.capture:Stop()
        self.api:Commit()
    end
    return true
end

function Calibration:Update(elapsed)
    if not self:Busy() then return end
    if not self.api:Active() then self:Abort("Housing editor closed; calibration stopped."); return end
    self.age = self.age + elapsed
    local mode = self.api:Mode()
    if self.state == "arming" or self.state == "returnsource" then
        local hovered = self.api:Hovered()
        local x, y = GetCursorPosition()
        local valid = hovered and not hovered.isLocked and hovered.decorGUID
        if self.state == "returnsource" then
            valid = valid and hovered.decorGUID == self.source.decorGUID
                and math.abs(x - self.cursor.x) + math.abs(y - self.cursor.y) <= 2
        end
        if not valid then self.still, self.hoverGUID = 0, nil; return end
        if self.hoverGUID ~= hovered.decorGUID or not self.hoverX
            or math.abs(x - self.hoverX) + math.abs(y - self.hoverY) > 2 then
            self.still = 0
            self.hoverGUID, self.hoverX, self.hoverY = hovered.decorGUID, x, y
        end
        self.still = self.still + elapsed
        if self.still < 1.2 then return end
        if self.state == "arming" then
            local variants, reason = self.api:CalibrationCopies(hovered)
            if not variants then self:Abort(reason); return end
            self.copyVariants = variants
            self.source, self.cursor = hovered, { x = x, y = y }
            self.api:UsePlacementSettings()
        end
        self:SetState("basic", "Preparing calibration copies. Keep the mouse still.")
        self.api:Switch("BasicDecor")
        return
    end

    if self.state == "basic" or self.state == "copy" or self.state == "placing" or self.state == "nextcopy" then
        local x, y = GetCursorPosition()
        if math.abs(x - self.cursor.x) + math.abs(y - self.cursor.y) > 8 then
            self:Abort("Mouse moved during placement. Start again."); return
        end
    end
    if self.state == "basic" and self.api:Mode() == Enum.HouseEditorMode.BasicDecor then
        self:BeginCopy()
    elseif self.state == "copy" and self.api:HasPendingCopy() then
        local pending = self.api:PendingInfo()
        if pending and (not pending.decorID or pending.decorID == self.source.decorID) then
            self:SetState("placing", "Placing a calibration copy...")
            self.api:PlaceCopy()
        end
    elseif self.state == "nextcopy" and self.age >= 0.2 and self.api:Mode() == Enum.HouseEditorMode.BasicDecor
        and not self.api:HasPendingCopy() then
        self:BeginCopy()
    elseif self.state == "expertAside" and mode == Enum.HouseEditorMode.ExpertDecor then
        self:SetState("moveaside", "Click the first copy, move it aside with keybinds, then click Moved aside. Do not rotate or resize it.")
    elseif self.state == "expert" and mode == Enum.HouseEditorMode.ExpertDecor then
        self:SetState("align", "Select one of the two copies and check they overlap exactly at the same size and orientation. Move it to match if needed, then Start measurement.")
    elseif self.state == "measuring" and not self.capture:Busy() then
        self:Abort((self.capture.stopReason or "Movement capture stopped.") .. " Calibration was not saved.")
    end
    if (self.state == "align" or self.state == "moveaside" or self.state == "rotating" or self.state == "measuring")
        and mode ~= Enum.HouseEditorMode.ExpertDecor then
        self:Abort("Editor mode changed; calibration stopped.")
        return
    end
    if self.state == "rotating" then self.motion:Update(elapsed) end
    if self.age > 10 and (self.state == "basic" or self.state == "copy" or self.state == "placing" or self.state == "nextcopy"
        or self.state == "expert" or self.state == "expertAside" or self.state == "committing"
        or self.state == "committingAside") then
        self:Abort("The game did not confirm the calibration step.")
    end
end

function Calibration:OnEvent(event, ...)
    if not self:Busy() then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD"
        or event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" or event == "HOUSING_DECOR_PLACE_FAILURE" then
        self:Abort("Calibration interrupted; measurement was not saved.")
        return
    end
    if event ~= "HOUSING_DECOR_PLACE_SUCCESS" then return end
    local guid, _, isNew, isPreview = ...
    if isPreview then return end
    if self.state == "placing" and isNew then
        self.created = self.created + 1
        if guid then self.copies[#self.copies + 1] = guid end
        if self.created == 1 and self.workflow == "aside" then
            self:SetState("expertAside", "Switching to Advanced mode so you can move the first copy aside.")
            self.api:Switch("ExpertDecor")
        elseif self.created == 1 then
            self:SetState("nextcopy", "First copy placed. Keep the mouse still for the second.")
        else
            self.api:RestoreSettings(self.saved)
            self.saved = nil
            self:SetState("expert", "Copies created. Switching to Advanced mode to check their alignment.")
            self.api:Switch("ExpertDecor")
        end
    elseif self.state == "committingAside" and not isNew and (not guid or guid == self.asideGUID) then
        self.still, self.hoverGUID = 0, nil
        self:SetState("returnsource", "Return the mouse to the exact original source spot and hover it until the second copy is placed.")
        self.api:Switch("BasicDecor")
    elseif self.state == "committing" and not isNew and (not guid or guid == self.testGUID) then
        local item = self.measurements[self.source.decorID] or { pivot = {}, size = {} }
        self.measurements[self.source.decorID] = item
        item.name, item[self.kind][self.axis] = self.source.name, self.result
        self:SetState("done", self.kind == "pivot"
            and "Pivot saved. Placement now uses it for this item and rotation axis."
            or "Size measurement saved for this item.")
    end
end

function Calibration:Abort(message)
    local wasBusy = self:Busy()
    self.motion:Stop()
    if self.capture:Busy() or self.capture.bindingsInstalled then self.capture:Stop() end
    local selected = self.api:Selected()
    local pending = (self.state == "copy" or self.state == "placing") and self.api:HasPendingCopy()
    self.state = "idle"
    if pending or (wasBusy and selected and (selected.decorGUID == self.testGUID or selected.decorGUID == self.asideGUID)) then
        pcall(self.api.Cancel, self.api)
    end
    pcall(self.api.RestoreSettings, self.api, self.saved)
    self.saved, self.result = nil, nil
    self:SetState("idle", message or "Calibration stopped. Already placed copies remain.")
end
