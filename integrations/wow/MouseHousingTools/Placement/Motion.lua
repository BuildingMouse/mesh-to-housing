local _, MHT = ...
local Motion = {}
Motion.__index = Motion
MHT.Motion = Motion

-- Moves the selected item by holding the editor's keys for timed durations.

local PHASE_WAIT = 0.08

-- Measured editor speeds: units, scale or degrees per second.
Motion.StandardProfile = { right = 1, forward = 1, up = 1, grow = 0.2, shrink = 0.2,
                           rotate = 45, firstRotationAxis = 1 }

local function phases(edit, profile, resetScale)
    local move = {}
    for _, axis in ipairs({ { "x", "right", "Right", "Left" }, { "y", "forward", "Forward", "Back" },
                            { "z", "up", "Up", "Down" } }) do
        local value = edit[axis[1]] or 0
        if value ~= 0 then
            move[#move + 1] = { name = value > 0 and axis[3] or axis[4], duration = math.abs(value) / profile[axis[2]] }
        end
    end
    local translation = { mode = "Translate", label = "Moving", controls = move }
    local resizing
    if edit.scale then
        local controls, growing = {}, edit.scale > 1
        if edit.scale ~= 1 then
            controls[1] = { name = growing and "ScaleUp" or "ScaleDown",
                            duration = math.abs(edit.scale - 1) / profile[growing and "grow" or "shrink"] }
        end
        resizing = { mode = "Scale", label = "Resizing", reset = resetScale, controls = controls }
    end
    local result = { translation }
    if resizing then result[2] = resizing end
    local turns = edit.turns or {}
    if (turns.x or 0) ~= 0 or (turns.y or 0) ~= 0 or (turns.z or 0) ~= 0 then
        result[#result + 1] = { mode = "Rotate", label = "Preparing rotation", controls = {} }
        local first, previous = profile.firstRotationAxis or 1, nil
        for i, axis in ipairs({ "x", "y", "z" }) do
            local angle = turns[axis] or 0
            if angle ~= 0 then
                result[#result + 1] = {
                    label = "Rotating " .. axis:upper(),
                    cycles = previous and (i - previous) % 3 or (i - first) % 3 + 1,
                    controls = { { name = angle > 0 and "RotateRight" or "RotateLeft",
                                   duration = math.abs(angle) / profile.rotate } },
                }
                previous = i
            end
        end
    end
    return result
end

function Motion.PlanMove(target, item, profile)
    return phases(MHT.NativeEdit.For(target, item), profile or Motion.StandardProfile, true)
end

function Motion.PlanEdit(edit, profile)
    return phases(edit, profile or Motion.StandardProfile, false)
end

function Motion.New(api)
    return setmetatable({ api = api, active = {} }, Motion)
end

function Motion:MoveTo(target, item, profile, guid, done, onPhase)
    self:Begin(Motion.PlanMove(target, item, profile), guid, done, onPhase)
end

function Motion:Apply(edit, profile, guid, done, onPhase)
    self:Begin(Motion.PlanEdit(edit, profile), guid, done, onPhase)
end

function Motion:Begin(queue, guid, done, onPhase)
    self:Stop()
    self.queue, self.guid, self.done, self.onPhase = queue, guid, done, onPhase
end

function Motion:Stop()
    for name in pairs(self.active) do
        pcall(self.api.Increment, self.api, name, false)
    end
    self.active, self.queue, self.phase = {}, nil, nil
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
        self.phase.wait = PHASE_WAIT
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
