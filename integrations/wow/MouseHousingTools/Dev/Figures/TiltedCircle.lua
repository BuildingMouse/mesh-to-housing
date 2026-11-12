local _, MHT = ...
local TiltedCircle = {}
MHT.Layout.Solids.tilted_circle = TiltedCircle

-- Tilted tiles, so every pose needs turns on several rings.
function TiltedCircle.Build(scale, dimensions)
    local width, depth, height = unpack(dimensions)
    local tilt = math.rad(30)
    local ct, st = math.cos(tilt), math.sin(tilt)
    local radius = 1.5 * math.max(width, depth) * scale
    local centerZ = 4 * height * scale + width * scale / 2 * st + height * scale / 2 * ct
    local items = {}
    for i = 0, 4 do
        local angle = math.rad(22.5 + i * 72)
        local c, s = math.cos(angle), math.sin(angle)
        local rotation = MHT.Rotation.FromAxes({ x = ct * c, y = ct * s, z = -st }, { x = -s, y = c, z = 0 },
            { x = st * c, y = st * s, z = ct })
        items[#items + 1] = MHT.Plan.Placement(radius * c, radius * s, centerZ, rotation, scale,
            "Tilted tile " .. (i + 1) .. " / 5")
    end
    return MHT.Plan.New(items, { width, depth, height })
end
