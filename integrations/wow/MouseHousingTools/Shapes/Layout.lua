local _, MHT = ...
local Layout = {}
MHT.Layout = Layout

Layout.defaults = {
    shape = "stairs", count = 12, scale = 1,
    width = 2, depth = 1, thickness = 0.25,
    spacing = 0.8, slope = 30, turns = 0, radius = 3,
    rotation = 0, clearance = 2,
}

local ranges = {
    count = { 2, 200 }, scale = { 0.2, 2 },
    width = { 0.05, 100 }, depth = { 0.05, 100 }, thickness = { 0.01, 100 },
    spacing = { 0.01, 100 }, slope = { 0, 80 }, turns = { -5, 5 },
    radius = { 0.05, 100 }, rotation = { -360, 360 }, clearance = { 0.1, 100 },
}

function Layout.Validate(settings)
    if settings.shape ~= "stairs" and settings.shape ~= "circle" then
        return nil, "Choose stairs or circle."
    end
    for key, range in pairs(ranges) do
        local value = settings[key]
        if type(value) ~= "number" or value ~= value or value < range[1] or value > range[2] then
            return nil, key .. " must be between " .. range[1] .. " and " .. range[2] .. "."
        end
    end
    if settings.count % 1 ~= 0 then return nil, "Item count must be a whole number." end
    return true
end

function Layout.Corners(item, dimensions)
    local c, s = math.cos(item.yaw), math.sin(item.yaw)
    local corners = {}
    for _, z in ipairs({ -1, 1 }) do
        for _, xy in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
            local x = xy[1] * dimensions[1] * item.scale / 2
            local y = xy[2] * dimensions[2] * item.scale / 2
            corners[#corners + 1] = {
                item.x + c * x - s * y, item.y + s * x + c * y,
                item.z + z * dimensions[3] * item.scale / 2,
            }
        end
    end
    return corners
end

function Layout.Build(settings)
    local valid, reason = Layout.Validate(settings)
    if not valid then return nil, reason end
    local items = {}
    local totalAngle = settings.turns * 2 * math.pi
    local run = settings.spacing
    if settings.shape == "stairs" and totalAngle ~= 0 then
        run = settings.radius * math.abs(totalAngle) / (settings.count - 1)
    end
    for i = 0, settings.count - 1 do
        local item = { x = 0, y = i * run, z = i * run * math.tan(math.rad(settings.slope)),
                       yaw = 0, scale = settings.scale }
        if settings.shape == "circle" then
            local angle = i * 2 * math.pi / settings.count
            item.x = settings.radius * math.sin(angle)
            item.y = settings.radius * (1 - math.cos(angle))
            item.z, item.yaw = 0, angle
        elseif totalAngle ~= 0 then
            local angle = i * totalAngle / (settings.count - 1)
            local direction = totalAngle > 0 and 1 or -1
            item.x = direction * settings.radius * (1 - math.cos(angle))
            item.y = settings.radius * math.sin(math.abs(angle))
            item.yaw = -angle
        end
        item.yaw = item.yaw + math.rad(settings.rotation)
        items[#items + 1] = item
    end
    local dimensions = { settings.width, settings.depth, settings.thickness }
    local front = math.huge
    for _, item in ipairs(items) do
        for _, point in ipairs(Layout.Corners(item, dimensions)) do
            front = math.min(front, point[2])
        end
    end
    local offset = settings.clearance + settings.depth / 2 - front
    for _, item in ipairs(items) do item.y = item.y + offset end
    return {
        items = items, dimensions = dimensions, spacing = run,
        source = { x = 0, y = 0, z = 0, yaw = 0, scale = 1 },
    }
end
