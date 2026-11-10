local _, MHT = ...
local Stairs = {}
MHT.Stairs = Stairs
local Plan, Rotation = MHT.Plan, MHT.Rotation

-- Straight stairs step forward and rise by the slope. Curved stairs follow a
-- spiral of the given radius instead, still rising by the slope.
function Stairs.Placements(settings)
    local total = settings.turns * 2 * math.pi
    local run = total ~= 0 and settings.radius * math.abs(total) / (settings.count - 1) or settings.spacing
    local rise = run * math.tan(math.rad(settings.slope))
    local placements = {}
    for i = 0, settings.count - 1 do
        local x, y, heading = 0, i * run, 0
        if total ~= 0 then
            local angle = i * total / (settings.count - 1)
            x = (total > 0 and 1 or -1) * settings.radius * (1 - math.cos(angle))
            y = settings.radius * math.sin(math.abs(angle))
            heading = -angle
        end
        local rotation = Rotation.About("z", heading + math.rad(settings.rotation))
        placements[#placements + 1] = Plan.Placement(x, y, i * rise, rotation, settings.scale)
    end
    return placements
end
