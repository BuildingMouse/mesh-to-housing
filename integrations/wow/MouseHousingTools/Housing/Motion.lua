local _, MHT = ...
local Motion = {}
Motion.__index = Motion
MHT.Motion = Motion

-- Translation units/second and scale change/second.
Motion.StandardProfile = { right = 1, forward = 1, up = 1, grow = 0.2, shrink = 0.2 }

function Motion.New(api)
    return setmetatable({ api = api, active = {} }, Motion)
end

function Motion:Stop()
    for name in pairs(self.active) do
        pcall(self.api.Increment, self.api, name, false)
    end
    self.active, self.queue, self.phase = {}, nil, nil
end

function Motion:Begin(phases, guid, done)
    self:Stop()
    self.queue, self.guid, self.done = phases, guid, done
end

function Motion:Place(item, profile, guid, done)
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
    if item.scale ~= 1 then
        local growing = item.scale > 1
        resize[1] = { name = growing and "ScaleUp" or "ScaleDown",
                      duration = math.abs(item.scale - 1) / profile[growing and "grow" or "shrink"] }
    end
    self:Begin({ { mode = "Scale", reset = true, controls = resize },
                 { mode = "Translate", controls = move } }, guid, done)
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
        self.api:PrepareSubmode(self.phase.mode, self.phase.reset)
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
