local _, MHT = ...
local Circle = {}
MHT.Circle = Circle
local Plan, Rotation = MHT.Plan, MHT.Rotation

-- Items evenly around a flat ring, each turned to follow it.
function Circle.Placements(settings)
    local placements = {}
    for i = 0, settings.count - 1 do
        local angle = i * 2 * math.pi / settings.count
        local rotation = Rotation.About("z", angle + math.rad(settings.rotation))
        placements[#placements + 1] = Plan.Placement(settings.radius * math.sin(angle),
            settings.radius * (1 - math.cos(angle)), 0, rotation, settings.scale)
    end
    return placements
end
