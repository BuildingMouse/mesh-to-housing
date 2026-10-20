local _, MHT = ...
local Shape = {}
MHT.TiltedCircle = Shape

function Shape.Build(settings, dimensions)
    dimensions = dimensions or { settings.width, settings.depth, settings.thickness }
    local width, depth, height = unpack(dimensions)
    local scale, tilt = settings.scale, math.rad(30)
    local radius = 1.5 * math.max(width, depth) * scale
    local centerZ = 4 * height * scale + width * scale / 2 * math.sin(tilt)
        + height * scale / 2 * math.cos(tilt)
    local items = {}
    for i = 0, 4 do
        -- Offset the ring so its five poses need combined, non-cardinal turns.
        local angle = math.rad(22.5 + settings.rotation + i * 72)
        local c, s, ct, st = math.cos(angle), math.sin(angle), math.cos(tilt), math.sin(tilt)
        local u = { x = ct * c, y = ct * s, z = -st }
        local v = { x = -s, y = c, z = 0 }
        local normal = { x = st * c, y = st * s, z = ct }
        items[#items + 1] = {
            x = radius * c, y = radius * s, z = centerZ,
            rotation = MHT.Transform.HousingRotation(u, v, normal), rotationSpace = "housing",
            scale = scale, label = "Tilted tile " .. (i + 1) .. " / 5",
        }
    end
    return { shape = "tilted_circle", items = items, dimensions = { width, depth, height },
        radius = radius, tilt = 30,
        source = { x = 0, y = 0, z = 0, scale = 1, yaw = 0, rotationSpace = "housing" },
        settings = { width = width, depth = depth, thickness = height, scale = scale, rotation = settings.rotation } }
end

function Shape.ForItem(plan, decorID, measurements)
    local dimensions, reason = MHT.ItemProfiles.CalibratedDimensions(decorID, measurements)
    if not dimensions then return nil, reason end
    return Shape.Build(plan.settings, dimensions)
end
