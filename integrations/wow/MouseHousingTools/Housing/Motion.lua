local _, MHT = ...
local Motion = {}
Motion.__index = Motion
MHT.Motion = Motion

-- Initial speed from the tile test; the first cycled axis still needs calibration.
Motion.StandardProfile = { right = 1, forward = 1, up = 1, grow = 0.2, shrink = 0.2,
                           rotate = 45, firstRotationAxis = 1 }

function Motion.New(api, measurements)
    return setmetatable({ api = api, measurements = measurements, active = {} }, Motion)
end

function Motion:Stop()
    for name in pairs(self.active) do
        pcall(self.api.Increment, self.api, name, false)
    end
    self.active, self.queue, self.phase = {}, nil, nil
end

function Motion:Begin(phases, guid, done, onPhase)
    self:Stop()
    self.queue, self.guid, self.done = phases, guid, done
    self.onPhase = onPhase
end

-- options: known starting pose, decor ID or explicit pivots, and API movement speeds.
function Motion:MoveIntoPlace(target, options, guid, done, onPhase)
    options = options or {}
    local pivot, rotationPivots = options.pivot, options.rotationPivots
    local rotationAxes = options.rotationAxes
    if options.decorID then
        pivot = MHT.ItemProfiles.Pivot(options.decorID)
        rotationPivots = {}
        for _, axis in ipairs({ "x", "y", "z" }) do
            rotationPivots[axis] = MHT.ItemProfiles.Pivot(options.decorID, axis, self.measurements)
        end
        rotationAxes = MHT.RotationAxes.ForItem(options.decorID, self.measurements)
    end
    local item = MHT.Transform.Translation(options.from, target, pivot, rotationPivots, rotationAxes)
    -- Keep the measured copy pose when its size is already correct. Even an
    -- empty Scale phase would otherwise reset engine state before rotation.
    local sourceScale = options.from and options.from.scale or 1
    local targetScale = target.scale or 1
    if targetScale ~= sourceScale then item.scale = targetScale end
    item.rotation = MHT.Transform.RotationDelta(options.from or {}, target, rotationAxes)
    self:Apply(item, options.motionProfile, guid, done, false, onPhase)
end

-- Raw increments for the diagnostic test; no starting pose is available from the API.
function Motion:Apply(item, profile, guid, done, relative, onPhase)
    profile = profile or Motion.StandardProfile
    local move = {}
    for _, axis in ipairs({ { "x", "right", "Right", "Left" },
                            { "y", "forward", "Forward", "Back" },
                            { "z", "up", "Up", "Down" } }) do
        local value = item[axis[1]]
        if value ~= 0 then
            move[#move + 1] = { name = value > 0 and axis[3] or axis[4],
                               duration = math.abs(value) / profile[axis[2]] }
        end
    end
    local resize = {}
    if item.scale and item.scale ~= 1 then
        local growing = item.scale > 1
        resize[1] = { name = growing and "ScaleUp" or "ScaleDown",
                      duration = math.abs(item.scale - 1) / profile[growing and "grow" or "shrink"] }
    end
    local phases = { { mode = "Translate", label = "Moving", controls = move } }
    if item.scale then
        phases[#phases + 1] = { mode = "Scale", label = "Resizing", reset = not relative, controls = resize }
    end
    local rotation = item.rotation or { x = 0, y = 0, z = (math.deg(item.yaw or 0) + 180) % 360 - 180 }
    if (rotation.x or 0) ~= 0 or (rotation.y or 0) ~= 0 or (rotation.z or 0) ~= 0 then
        phases[#phases + 1] = { mode = "Rotate", label = "Preparing rotation", controls = {} }
        local first = profile.firstRotationAxis or 1
        local previous
        for i, axis in ipairs({ "x", "y", "z" }) do
            local angle = rotation[axis] or 0
            if angle ~= 0 then
                phases[#phases + 1] = {
                    label = "Rotating " .. axis:upper(),
                    cycles = previous and (i - previous) % 3 or (i - first) % 3 + 1,
                    controls = {
                        { name = angle > 0 and "RotateRight" or "RotateLeft",
                          duration = math.abs(angle) / profile.rotate },
                    },
                }
                previous = i
            end
        end
    end
    self:Begin(phases, guid, done, onPhase)
end

function Motion:Update(elapsed)
    if not self.queue then return end
    local selected = self.api:Selected()
    if not selected or selected.decorGUID ~= self.guid then error("Selection changed; placement stopped.") end
    if elapsed > 0.25 and next(self.active) then error("Frame delay interrupted timed movement. Try again.") end
    if not self.phase then
        self.phase = table.remove(self.queue, 1)
        if not self.phase then
            local done = self.done
            self.queue = nil
            done()
            return
        end
        if self.phase.mode then self.api:PrepareSubmode(self.phase.mode, self.phase.reset) end
        for _ = 1, self.phase.cycles or 0 do self.api:CycleRotationAxis() end
        if self.onPhase then self.onPhase(self.phase.label) end
        self.phase.wait = 0.08
        return
    end
    if self.phase.wait then
        self.phase.wait = self.phase.wait - elapsed
        if self.phase.wait > 0 then return end
        self.phase.wait = nil
        for _, control in ipairs(self.phase.controls) do
            self.active[control.name] = control.duration
            self.api:Increment(control.name, true)
        end
        return
    end
    for name, remaining in pairs(self.active) do
        remaining = remaining - elapsed
        if remaining <= 0 then
            self.api:Increment(name, false)
            self.active[name] = nil
        else
            self.active[name] = remaining
        end
    end
    if not next(self.active) then self.phase = nil end
end
