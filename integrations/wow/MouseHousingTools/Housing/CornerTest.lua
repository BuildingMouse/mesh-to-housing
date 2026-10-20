local _, MHT = ...
local Test = {}
Test.__index = Test
MHT.CornerTest = Test

Test.Cases = {
    { id = "test_x", label = "X +35°", rotation = { x = 35, y = 0, z = 0 } },
    { id = "test_y", label = "Y +25°", rotation = { x = 0, y = 25, z = 0 } },
    { id = "test_z", label = "Z +40°", rotation = { x = 0, y = 0, z = 40 } },
    { id = "test_xy", label = "X +35° → Y +25°", rotation = { x = 35, y = 25, z = 0 } },
    { id = "test_xz", label = "X +35° → Z +40°", rotation = { x = 35, y = 0, z = 40 } },
    { id = "test_yz", label = "Y +25° → Z +40°", rotation = { x = 0, y = 25, z = 40 } },
    { id = "test_xyz", label = "X +35° → Y +25° → Z +40°", rotation = { x = 35, y = 25, z = 40 } },
    { id = "test_xyz_negative", label = "X -35° → Y +25° → Z -40°", rotation = { x = -35, y = 25, z = -40 } },
}

Test.Corners = {
    { name = "Corner 1", location = "near-left", x = -1, y = -1 },
    { name = "Corner 2", location = "far-left", x = -1, y = 1 },
    { name = "Corner 3", location = "far-right", x = 1, y = 1 },
    { name = "Corner 4", location = "near-right", x = 1, y = -1 },
}

function Test.New(api, measurements, notify)
    return setmetatable({ api = api, measurements = measurements, notify = notify,
        motion = MHT.Motion.New(api), state = "idle", completed = 0 }, Test)
end

function Test:Busy()
    return self.state ~= "idle" and self.state ~= "done"
end

function Test:SetState(state, message)
    self.state, self.age = state, 0
    self.notify(message, self.completed, 4)
end

function Test:Start(id, profile)
    if self:Busy() then return nil, "Finish the current corner test first." end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        return nil, "Open Advanced mode first."
    end
    if self.api:IsSelected() then return nil, "Finish editing the selected item, then run a test and click the tile." end
    local chosen
    for _, case in ipairs(Test.Cases) do if case.id == id then chosen = case end end
    if not chosen then return nil, "Choose a named corner test." end
    self.case = { id = chosen.id, label = chosen.label, rotation = {} }
    for axis, value in pairs(chosen.rotation) do self.case.rotation[axis] = value end
    self.profile = {}
    for key, value in pairs(profile) do self.profile[key] = value end
    self.activeGUID, self.tileGUID, self.lastRejectedGUID = nil, nil, nil
    self.predictions, self.calibration = nil, nil
    self.finished, self.completed = {}, 0
    self:SetState("selecttile", chosen.id .. ": click the tile in its calibrated starting pose at 100% size.")
    return true
end

function Test:Reject(selected, message)
    local guid = selected and selected.decorGUID
    if guid ~= self.lastRejectedGUID then
        self.lastRejectedGUID = guid
        self.notify(message, self.completed, 4)
    end
end

function Test:BeginTile(selected)
    if selected.isLocked or not selected.decorID or not selected.decorGUID then
        self:Reject(selected, "Choose an editable tile with saved dimensions, pivots and axis answers."); return
    end
    local dimensions, reason = MHT.ItemProfiles.CalibratedDimensions(selected.decorID, self.measurements)
    if not dimensions then self:Reject(selected, reason); return end
    local rotationAxes, pivots = MHT.RotationAxes.ForItem(selected.decorID, self.measurements), {}
    for _, axis in ipairs({ "x", "y", "z" }) do pivots[axis] = MHT.ItemProfiles.Pivot(selected.decorID, axis, self.measurements) end
    local points = {}
    for i, corner in ipairs(Test.Corners) do
        points[i] = { x = corner.x * dimensions[1] / 2, y = corner.y * dimensions[2] / 2, z = 0 }
    end
    local expected, center = MHT.Transform.RotatePoints(points, self.case.rotation, pivots, rotationAxes)
    self.predictions = {}
    for i, point in ipairs(points) do
        local shift = {}
        for _, coordinate in ipairs({ "x", "y", "z" }) do
            shift[coordinate] = expected[i][coordinate] - point[coordinate]
            if math.abs(shift[coordinate]) < 1e-9 then shift[coordinate] = 0 end
        end
        self.predictions[i] = { start = point, expected = expected[i], shift = shift }
    end
    self.calibration = { decorID = selected.decorID, dimensions = dimensions, axes = rotationAxes, pivots = pivots, center = center }
    self.tileGUID, self.activeGUID = selected.decorGUID, selected.decorGUID
    self:SetState("rotatingtile", self.case.id .. ": rotating the tile with raw X → Y → Z commands. Its pivot shift is left visible.")
    self.motion:Apply({ x = 0, y = 0, z = 0, rotation = self.case.rotation }, self.profile, self.activeGUID, function()
        self:SetState("committile", "Finishing the tile's in-game rotation...")
        self.api:Commit()
    end, true)
end

function Test:PromptMarker()
    local corner = Test.Corners[self.completed + 1]
    self.lastRejectedGUID = nil
    self:SetState("selectmarker", self.case.id .. ": click the " .. corner.name .. " marker (" .. corner.location .. ").")
end

function Test:BeginMarker(selected)
    local corner = Test.Corners[self.completed + 1]
    if selected.isLocked or not selected.decorGUID or selected.decorGUID == self.tileGUID or self.finished[selected.decorGUID] then
        self:Reject(selected, "Click the " .. corner.name .. " marker, not the tile or a finished marker."); return
    end
    self.activeGUID = selected.decorGUID
    local shift = self.predictions[self.completed + 1].shift
    self:SetState("movingmarker", self.case.id .. ": moving " .. corner.name .. " to its predicted corner; no marker rotation or scaling.")
    self.motion:Apply(shift, self.profile, self.activeGUID, function()
        self:SetState("commitmarker", "Finishing the " .. corner.name .. " marker's in-game move...")
        self.api:Commit()
    end, true)
end

function Test:Update(elapsed)
    if not self:Busy() then return end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        self:Abort("Advanced mode closed; corner test stopped."); return
    end
    self.age = self.age + elapsed
    local selected = self.api:Selected()
    if self.state == "selecttile" and selected then self:BeginTile(selected)
    elseif self.state == "selectmarker" and selected then self:BeginMarker(selected)
    elseif self.state == "rotatingtile" or self.state == "movingmarker" then
        self.motion:Update(elapsed)
    elseif (self.state == "committile" or self.state == "commitmarker") and self.age > 10 then
        self:Abort("The game did not confirm the corner test edit.")
    end
end

function Test:OnEvent(event, ...)
    if not self:Busy() then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD"
        or event == "HOUSE_EDITOR_MODE_CHANGE_FAILURE" or event == "HOUSING_DECOR_PLACE_FAILURE" then
        self:Abort("Corner test interrupted. Completed in-game edits remain placed."); return
    end
    if event ~= "HOUSING_DECOR_PLACE_SUCCESS" then return end
    local guid, _, isNew, isPreview = ...
    if isNew or isPreview or (guid and guid ~= self.activeGUID) then return end
    if self.state == "committile" then
        self.activeGUID = nil
        self:PromptMarker()
    elseif self.state == "commitmarker" then
        self.finished[self.activeGUID] = true
        self.activeGUID, self.completed = nil, self.completed + 1
        if self.completed == 4 then
            self:SetState("done", self.case.id .. ": all four predicted corners placed. Compare with the tile and take screenshots. Restore the starting layout before another case.")
        else self:PromptMarker() end
    end
end

function Test:Abort(message)
    self.motion:Stop()
    local selected = self.api:Selected()
    if self.activeGUID and selected and selected.decorGUID == self.activeGUID then pcall(self.api.Cancel, self.api) end
    self.activeGUID = nil
    self:SetState("idle", message or "Corner test stopped. Completed in-game edits remain placed.")
end
