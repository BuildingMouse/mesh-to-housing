local _, MHT = ...
local Motion = {}
Motion.__index = Motion
MHT.Motion = Motion
local copy = MHT.Util.Copy

-- Moves the selected item by holding the editor's keys for timed durations.

local PHASE_WAIT = 0.08

-- Measured editor speeds: units, scale or degrees per second.
Motion.StandardProfile = { right = 1, forward = 1, up = 1, grow = 0.2, shrink = 0.2,
                           rotate = 45, firstRotationAxis = 1 }

function Motion.Phases(edit, profile)
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
        resizing = { mode = "Scale", label = "Resizing", reset = true, controls = controls }
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
    if #result > 1 then result[#result + 1] = { mode = "Translate", label = "Finishing", controls = {} } end
    return result
end

local function longest(controls)
    local duration = 0
    for _, control in ipairs(controls) do duration = math.max(duration, control.duration) end
    return duration
end

function Motion.Seconds(phases)
    local total = 0
    for _, phase in ipairs(phases) do total = total + PHASE_WAIT + longest(phase.controls) end
    return total
end

function Motion.MovePhases(target, item)
    return Motion.Phases(MHT.Maneuver.For(target, item), Motion.StandardProfile)
end

function Motion.New(api)
    return setmetatable({ api = api, active = {} }, Motion)
end

function Motion:MoveTo(target, item, guid, done, onPhase)
    self:Begin(Motion.MovePhases(target, item), guid, done, onPhase)
end

function Motion:Shift(shift, guid, done)
    self:Begin(Motion.Phases(shift, Motion.StandardProfile), guid, done)
end

function Motion:Begin(queue, guid, done, onPhase)
    self:Stop()
    self.queue, self.guid, self.done, self.onPhase = queue, guid, done, onPhase
    self.submode, self.rotationAxis = nil, nil
end

function Motion:Checkpoint()
    if not self.queue then return nil end
    local queue = {}
    if self.submode then
        local first = Motion.StandardProfile.firstRotationAxis
        queue[1] = { mode = self.submode, label = "Resuming", controls = {},
            reset = self.phase and self.phase.reset and not self.phase.resetDone or nil,
            cycles = self.submode == "Rotate" and self.rotationAxis and (self.rotationAxis - first) % 3 + 1 or 0 }
    end
    if self.phase then
        local controls = {}
        if not self.phase.started then
            controls = copy(self.phase.controls)
        else
            for name, remaining in pairs(self.active) do controls[#controls + 1] = { name = name, duration = remaining } end
        end
        if #controls > 0 then queue[#queue + 1] = { label = self.phase.label or "Resuming", controls = controls } end
    end
    for _, phase in ipairs(self.queue) do queue[#queue + 1] = copy(phase) end
    return queue
end

function Motion:Resume(checkpoint, guid, done, onPhase)
    self:Begin(copy(checkpoint), guid, done, onPhase)
end

function Motion:Stop()
    for name in pairs(self.active) do
        pcall(self.api.Increment, self.api, name, false)
    end
    self.active, self.queue, self.phase = {}, nil, nil
end

function Motion:RemainingSeconds()
    if not self.queue then return 0 end
    local current = 0
    if self.phase and self.phase.started then
        for _, remaining in pairs(self.active) do current = math.max(current, remaining) end
    elseif self.phase then
        current = (self.phase.wait or PHASE_WAIT) + longest(self.phase.controls)
    end
    return current + Motion.Seconds(self.queue)
end

function Motion:PreparingPhase()
    return self.phase ~= nil and not self.phase.started
end

-- The editor changes submode a few frames late; keys held before then act in the old one.
function Motion:SubmodeReady()
    return not self.submode or self.api:InSubmode(self.submode)
end

function Motion:WaitForSubmode(elapsed)
    self.phase.modeWait = (self.phase.modeWait or 0) + elapsed
    if self.phase.modeWait > 3 then error("Editing mode did not become ready. Click the copy again.") end
end

function Motion:Update(elapsed)
    if not self.queue then return end
    local selected = self.api:Selected()
    -- The selection can drop for a moment while the submode changes.
    if not selected and self:PreparingPhase() then self:WaitForSubmode(elapsed); return end
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
        if self.phase.mode then
            self.submode = self.phase.mode
            if self.submode == "Rotate" then self.rotationAxis = nil end
            self.api:PrepareSubmode(self.phase.mode)
            if not self.queue then return end
        end
        self.phase.setup = true
    end
    if self.phase.setup then
        if not self:SubmodeReady() then self:WaitForSubmode(elapsed); return end
        if self.phase.reset and not self.phase.resetDone then
            -- Reset acts on the active submode: resetting before Scale is active would undo the move.
            self.phase.resetDone = true
            self.api:ResetSubmode()
            if not self.queue then return end
            if not self:SubmodeReady() then self:WaitForSubmode(elapsed); return end
        end
        self.phase.setup = nil
        for _ = 1, self.phase.cycles or 0 do
            self.rotationAxis = self.rotationAxis and self.rotationAxis % 3 + 1 or Motion.StandardProfile.firstRotationAxis
            self.api:CycleRotationAxis()
            if not self.queue then return end
        end
        if self.onPhase then self.onPhase(self.phase.label) end
        if not self.queue then return end
        self.phase.wait = PHASE_WAIT
        return
    end
    if self.phase.wait then
        self.phase.wait = math.max(0, self.phase.wait - elapsed)
        if self.phase.wait > 0 then return end
        if not self:SubmodeReady() then self:WaitForSubmode(elapsed); return end
        self.phase.wait = nil
        for _, control in ipairs(self.phase.controls) do
            self.active[control.name] = control.duration
            self.api:Increment(control.name, true)
            if not self.queue then return end
        end
        self.phase.started = true
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
