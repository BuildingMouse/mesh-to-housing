local _, MHT = ...
local Circle = { id = "circle", name = "Circle" }
MHT.Circle = Circle
local Layout, Plan, Rotation = MHT.Layout, MHT.Plan, MHT.Rotation

-- A flat or standing ring, or part of one.

Circle.Defaults = { radius = 3, orientation = "horizontal", partial = false, arc = 180 }

Circle.Ranges = { radius = { 0.05, 100 }, arc = { 1, 360 } }

Circle.Choices = { orientation = { horizontal = true, vertical = true } }

function Circle.Placements(values)
    local partial = values.partial and values.arc < 360
    local step = math.rad(partial and values.arc or 360) / values.count
    local radius, placements = values.radius, {}
    local vertical = values.orientation == "vertical"
    -- A standing partial arc is centered on the top of the ring.
    local start = vertical and partial and (math.pi - step * (values.count - 1)) / 2 or 0
    for i = 0, values.count - 1 do
        local angle = start + i * step
        local placement
        if not vertical then
            placement = Plan.Placement(radius * math.sin(angle), radius * (1 - math.cos(angle)), 0,
                Rotation.About("z", angle), values.scale)
        else
            local facing, x, z = angle, radius * math.sin(angle), radius * (1 - math.cos(angle))
            if partial then
                facing = math.pi / 2 - angle
                x, z = -radius * math.cos(angle), radius * (math.sin(angle) - math.sin(start))
            end
            local c, s = math.cos(facing), math.sin(facing)
            placement = Plan.Placement(x, 0, z,
                Rotation.FromAxes({ x = c, y = 0, z = s }, { x = -s, y = 0, z = c }, { x = 0, y = -1, z = 0 }),
                values.scale)
        end
        placements[#placements + 1] = placement
    end
    return placements
end

-- The flat ring keeps clear by the item's full reach, so turning the items doesn't move it.
function Circle.Offset(items, values, dimensions)
    if values.orientation == "vertical" then
        return 0, dimensions[3] / 2 - Layout.Lowest(items, dimensions)
    end
    local first, d = items[1], dimensions
    local reach = first.scale * math.sqrt(d[1] ^ 2 + d[2] ^ 2 + d[3] ^ 2) / 2
    return d[2] / 2 + reach + Layout.Gap(d), -d[3] / 2 - Layout.Lowest({ first }, d)
end

Layout.AddShape(Circle)
