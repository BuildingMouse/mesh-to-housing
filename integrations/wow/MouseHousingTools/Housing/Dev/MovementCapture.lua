local _, MHT = ...
local MovementCapture = {}
MovementCapture.__index = MovementCapture
MHT.MovementCapture = MovementCapture

MovementCapture.Axes = {
    { axis = "x", positive = "Right", negative = "Left" },
    { axis = "y", positive = "Forward", negative = "Back" },
    { axis = "z", positive = "Up", negative = "Down" },
}

function MovementCapture.New(clock)
    return setmetatable({
        running = false, active = {}, clock = clock,
        ticks = { x = 0, y = 0, z = 0 },
        seconds = { x = 0, y = 0, z = 0 },
    }, MovementCapture)
end

function MovementCapture:Start()
    self.active = {}
    self.ticks = { x = 0, y = 0, z = 0 }
    self.seconds = { x = 0, y = 0, z = 0 }
    self.running = true
    self.lastTime = self.clock and self.clock()
end

function MovementCapture:SetActive(direction, active)
    if not self.running then return end
    self:FlushTime()
    self.active[direction] = active or nil
end

function MovementCapture:AddTime(elapsed)
    for _, axis in ipairs(MovementCapture.Axes) do
        local sign = (self.active[axis.positive] and 1 or 0) - (self.active[axis.negative] and 1 or 0)
        self.seconds[axis.axis] = self.seconds[axis.axis] + sign * elapsed
    end
end

function MovementCapture:FlushTime()
    if not self.running or not self.clock then return end
    local now = self.clock()
    self:AddTime(now - self.lastTime)
    self.lastTime = now
end

function MovementCapture:Update(elapsed)
    if not self.running then return end
    if self.clock then self:FlushTime() else self:AddTime(elapsed) end
    -- One tick is one observed frame with movement active, not a measured distance.
    for _, axis in ipairs(MovementCapture.Axes) do
        local sign = (self.active[axis.positive] and 1 or 0) - (self.active[axis.negative] and 1 or 0)
        self.ticks[axis.axis] = self.ticks[axis.axis] + sign
    end
end

function MovementCapture:Snapshot()
    self:FlushTime()
    local result = { ticks = {}, seconds = {} }
    for _, axis in ipairs(MovementCapture.Axes) do
        result.ticks[axis.axis] = self.ticks[axis.axis]
        result.seconds[axis.axis] = self.seconds[axis.axis]
    end
    return result
end

function MovementCapture:Stop()
    self:FlushTime()
    self.running = false
    self.active = {}
    return self:Snapshot()
end
