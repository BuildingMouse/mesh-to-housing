local _, MHT = ...
local Motion = MHT.Motion

-- A raw edit; resizing scales from the current size.
function Motion:Apply(edit, profile, guid, done, onPhase)
    local queue = Motion.Phases(edit, profile)
    for _, phase in ipairs(queue) do phase.reset = nil end
    self:Begin(queue, guid, done, onPhase)
end
