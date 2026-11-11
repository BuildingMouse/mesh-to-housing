local _, MHT = ...
local Stairs = { id = "stairs", name = "Stairs" }
MHT.Stairs = Stairs
local Plan, Rotation = MHT.Plan, MHT.Rotation

-- A positive curve turns right.

Stairs.Defaults = { spacing = 0.8, stepX = 0, stepZ = 0.8 * math.tan(math.rad(30)),
    curveEnabled = false, curve = 90, radius = 5 }

Stairs.Ranges = { spacing = { 0, 100 }, stepX = { -100, 100 }, stepZ = { 0, 100 },
    curve = { -1800, 1800 }, radius = { 0.05, 100 } }

function Stairs.Placements(values)
    local total = values.curveEnabled and math.rad(values.curve) or 0
    local placements = {}
    for i = 0, values.count - 1 do
        local x, y, heading = i * values.stepX, i * values.spacing, 0
        if total ~= 0 then
            local angle = i * total / (values.count - 1)
            x = (total > 0 and 1 or -1) * values.radius * (1 - math.cos(angle))
            y = values.radius * math.sin(math.abs(angle))
            heading = -angle
        end
        placements[#placements + 1] = Plan.Placement(x, y, i * values.stepZ, Rotation.About("z", heading), values.scale)
    end
    return placements
end

MHT.Layout.AddShape(Stairs)
