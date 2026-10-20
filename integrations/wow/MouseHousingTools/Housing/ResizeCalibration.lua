local _, MHT = ...
local Base = MHT.Calibration
local Resize = setmetatable({}, { __index = Base })
Resize.__index = Resize
MHT.ResizeCalibration = Resize

local coordinates = { "x", "y", "z" }
local speeds = { x = "right", y = "forward", z = "up" }

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Resize.New(api, capture, measurements, notify)
    return setmetatable(Base.New(api, capture, measurements, notify), Resize)
end

function Resize.StackTarget(dimensions, scale)
    return { x = -(1 - scale) * dimensions[1] / 2,
        y = -(1 - scale) * dimensions[2] / 2, z = (1 + scale) * dimensions[3] / 2 }
end

function Resize.Measure(dimensions, correction, profile, lift)
    local target, units = Resize.StackTarget(dimensions, 0.5), {}
    for _, axis in ipairs(coordinates) do
        -- Center after scaling: lift + (1 - scale) * pivot + manual correction.
        units[axis] = (target[axis] - (axis == "z" and lift or 0)
            - correction.seconds[axis] * profile[speeds[axis]]) / 0.5
    end
    return { units = units, correction = copy(correction), dimensions = copy(dimensions),
        measuredScale = 0.5, lift = lift, reference = "placed-copy" }
end

function Resize:ValidateDraft()
    if not self.draft then return nil, "Measure or load a resize pivot first." end
    for _, axis in ipairs(coordinates) do
        if not finite(self.draft.units[axis]) then return nil, "Enter a finite resize pivot for " .. axis:upper() .. "." end
    end
    return true
end

function Resize:LoadSaved()
    if self:Busy() then return end
    local source = self.api:Selected() or self.api:Hovered() or self.source
    local item = source and self.measurements[source.decorID]
    local record = item and item.resizePivot
    if not record then return nil, "Select an item with a saved resize pivot first." end
    local draft = { decorID = source.decorID, name = source.name or item.name,
        units = copy(record.units), measurement = copy(record) }
    for _, axis in ipairs(coordinates) do
        if not draft.units or not finite(draft.units[axis]) then return nil, "The saved resize pivot is incomplete." end
    end
    self.source, self.draft = source, draft
    self:SetState("review", "Resize pivot loaded. Edit the trial values, test, then Save resize pivot.")
    return true
end

function Resize:SetValue(axis, value)
    if self:Busy() then return nil, "Wait for the test to finish before editing." end
    if not self.draft then return nil, "Measure or load a resize pivot first." end
    if not speeds[axis] or not finite(value) then return nil, "Enter a finite resize pivot value." end
    self.draft.units[axis] = value
    return true
end

function Resize:Save()
    if self:Busy() then return nil, "Finish the test before saving." end
    local valid, reason = self:ValidateDraft()
    if not valid then return nil, reason end
    local draft = self.draft
    local item = self.measurements[draft.decorID] or {}
    self.measurements[draft.decorID] = item
    local record = copy(draft.measurement)
    for _, axis in ipairs(coordinates) do
        if record.units[axis] ~= draft.units[axis] then record.edited = true end
    end
    record.units = copy(draft.units)
    item.name, item.resizePivot = draft.name or item.name, record
    draft.measurement = copy(record)
    self:SetState("review", "Resize pivot saved. Placement now uses it for this item.")
    return true
end

function Resize:Start(mode, workflow, profile, scale)
    if self:Busy() then return end
    if mode ~= "measure" and mode ~= "automatic" and mode ~= "corners" then return nil, "Choose a resize test." end
    scale = mode == "corners" and scale or 0.5
    if not finite(scale) or scale < 0.2 or scale > 2 then return nil, "Item size must be between 20% and 200%." end
    local rate = scale > 1 and profile.grow or profile.shrink
    if scale ~= 1 and (not finite(rate) or rate <= 0) then return nil, "Resize speed must be greater than zero." end
    if mode == "automatic" then
        local valid, reason = self:ValidateDraft()
        if not valid then return nil, reason end
    end
    local trial = mode == "automatic" and copy(self.draft) or nil
    local started, reason = Base.Start(self, "resize", nil, workflow, profile)
    if not started then return nil, reason end
    self.kind, self.mode, self.scale, self.trial = "resize", mode, scale, trial
    self.automatic = mode == "automatic"
    self.completed, self.referenceGUID = 0, nil
    self:SetState("arming", "Hover the source at 100% size in its calibrated pose. Keep still for two fresh copies.")
    return true
end

function Resize:PrepareSource(source)
    local dimensions, reason = MHT.ItemProfiles.Dimensions(source.decorID, self.measurements)
    if not dimensions then return nil, reason end
    self.dimensions = dimensions
    self.lift = dimensions[3] * (self.mode == "corners" and math.max(1, self.scale) or 1)
    if self.mode == "corners" then
        local measured
        self.pivot, measured = MHT.ItemProfiles.ResizePivot(source.decorID, self.measurements)
        if not measured then return nil, "Save a resize pivot for this item before the corner test." end
    end
    return true
end

function Resize:SetState(state, message)
    if state == "align" then
        message = "Select a copy and check the two copies overlap at 100% size. Then confirm to begin resizing."
    end
    Base.SetState(self, state, message)
end

function Resize:BeginResize()
    self:SetState("resizing", "Moving the selected copy up before resizing it...")
    self.motion:Apply({ x = 0, y = 0, z = self.lift }, self.profile, self.testGUID, function()
        self:SetState("resizing", string.format("Resizing the copy to %.0f%%...", self.scale * 100))
        self.motion:Apply({ x = 0, y = 0, z = 0, scale = self.scale }, self.profile, self.testGUID, function()
            if self.mode == "measure" then
                self:SetState("measuring", "Use movement keys to stack the smaller tile on the reference: bottom near-left corner to top near-left corner. Then click Aligned.")
                local started, reason = self.capture:Start()
                if not started then error(reason or "Could not start movement capture.") end
            elseif self.mode == "automatic" then
                local target, shift = Resize.StackTarget(self.dimensions, self.scale), {}
                for _, axis in ipairs(coordinates) do
                    shift[axis] = target[axis] - (axis == "z" and self.lift or 0)
                        - (1 - self.scale) * self.trial.units[axis]
                end
                self:SetState("fitting", "Stacking the half-size tile using the trial resize pivot...")
                self:MoveTestCopy(shift)
            else
                local shift = {}
                for i, axis in ipairs(coordinates) do
                    shift[axis] = (self.completed == 1 and self.dimensions[i] * self.scale or 0)
                        - (1 - self.scale) * self.pivot[axis]
                end
                self:SetState("fitting", "Correcting for resizing and moving the tile into place...")
                self.motion:Apply(shift, self.profile, self.testGUID, function()
                    self:SetState(self.completed == 0 and "committingReference" or "committingTest", "Saving the resized test copy...")
                    self.api:Commit()
                end, true)
            end
        end, true)
    end, true)
end

function Resize:Advance()
    if self.state == "align" then
        if self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then return nil, "Return to Advanced mode first." end
        local selected = self.api:Selected()
        if not self:ValidCopy(selected) then return nil, "Select a calibration copy, not the source." end
        self.testGUID = selected.decorGUID
        self:BeginResize()
        return true
    elseif self.state == "measuring" then
        local selected = self.api:Selected()
        if not self.capture:Busy() or not selected or selected.decorGUID ~= self.testGUID then
            return nil, "Measurement interrupted. Start again."
        end
        self.result = Resize.Measure(self.dimensions, self.capture.recorder:Snapshot(), self.profile, self.lift)
        self:SetState("committing", "Saving the aligned test copy. The resize pivot is still a trial.")
        self.capture:Stop()
        self.api:Commit()
        return true
    end
    return Base.Advance(self)
end

function Resize:Update(elapsed)
    if self.state == "resizing" or self.state == "selectSecond" or self.state == "committingReference" then
        if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
            self:Abort("Advanced mode closed; resize test stopped."); return
        end
        self.age = self.age + elapsed
        if self.state == "resizing" then self.motion:Update(elapsed)
        elseif self.state == "selectSecond" then
            local selected = self.api:Selected()
            if self:ValidCopy(selected) and selected.decorGUID ~= self.referenceGUID then
                self.testGUID = selected.decorGUID
                self:BeginResize()
            end
        elseif self.age > 10 then self:Abort("The game did not confirm the resized reference copy.") end
        return
    end
    Base.Update(self, elapsed)
end

function Resize:OnEvent(event, ...)
    if not self:Busy() then return end
    if event == "HOUSING_DECOR_PLACE_SUCCESS" then
        local guid, _, isNew, isPreview = ...
        if not isNew and not isPreview and (not guid or guid == self.testGUID) then
            if self.state == "committing" then
                self.draft = { decorID = self.source.decorID, name = self.source.name,
                    units = copy(self.result.units), measurement = copy(self.result) }
                self:SetState("review", "Resize pivot measured. Edit or test the trial values, then Save resize pivot.")
                return
            elseif self.state == "committingReference" then
                self.referenceGUID, self.completed = self.testGUID, 1
                self:SetState("selectSecond", "First copy resized. Click the other copy; it will resize and meet the first corner to corner.")
                return
            elseif self.state == "committingTest" then
                if self.mode == "corners" then self.completed = 2 end
                self:SetState("review", self.mode == "corners"
                    and "Finished. Both copies are resized and their opposite corners should touch."
                    or "Finished. Check the near-left stack, adjust the trial values and test again. Only Save resize pivot applies them.")
                return
            end
        end
    end
    Base.OnEvent(self, event, ...)
end
