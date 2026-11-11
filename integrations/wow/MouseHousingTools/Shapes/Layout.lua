local _, MHT = ...
local Layout = {}
MHT.Layout = Layout
local Rotation = MHT.Rotation
local Plan = MHT.Plan
local finite = MHT.Util.Finite

-- Turns shape settings into a plan.

Layout.Solids = {}
Layout.Shapes, Layout.ShapeOrder = {}, {}

-- Values every shape has, on top of its own.
local COMMON = { count = 10, scale = 1, itemPitch = 0, itemYaw = 0, itemRoll = 0 }
local COMMON_RANGES = { count = { 2, 200 }, scale = { 0.2, 2 } }

function Layout.AddShape(shape)
    Layout.Shapes[shape.id] = shape
    Layout.ShapeOrder[#Layout.ShapeOrder + 1] = shape.id
end

function Layout.Defaults(id)
    local defaults = MHT.Util.Copy(COMMON)
    for key, value in pairs(Layout.Shapes[id].Defaults) do defaults[key] = value end
    return defaults
end

function Layout.Validate(id, values)
    local shape = Layout.Shapes[id]
    if not shape then return nil, "Choose a shape." end
    if type(values) ~= "table" then return nil, "Shape settings are missing." end
    for key, default in pairs(Layout.Defaults(id)) do
        local value = values[key]
        local range = COMMON_RANGES[key] or shape.Ranges and shape.Ranges[key]
        local choices = shape.Choices and shape.Choices[key]
        if type(value) ~= type(default) then return nil, key .. " is missing." end
        if type(value) == "number" and not finite(value) then return nil, key .. " must be a number." end
        if range and (value < range[1] or value > range[2]) then
            return nil, key .. " must be between " .. range[1] .. " and " .. range[2] .. "."
        end
        if choices and not choices[value] then return nil, "Choose a valid " .. key .. "." end
    end
    if values.count % 1 ~= 0 then return nil, "Item count must be a whole number." end
    return true
end

function Layout.Reset(settings, id)
    settings[id] = Layout.Defaults(id)
end

-- Fills in missing values and replaces invalid ones with defaults.
function Layout.Load(settings)
    for key in pairs(settings) do
        if key ~= "shape" and not Layout.Shapes[key] then settings[key] = nil end
    end
    if not Layout.Shapes[settings.shape] then settings.shape = Layout.ShapeOrder[1] end
    for id in pairs(Layout.Shapes) do
        local values = type(settings[id]) == "table" and settings[id] or {}
        settings[id] = values
        for key, value in pairs(Layout.Defaults(id)) do
            if values[key] == nil then values[key] = value end
        end
        if not Layout.Validate(id, values) then Layout.Reset(settings, id) end
    end
    return settings
end

-- How far a placed item's box reaches from its center along a world axis
-- (1 = X, 2 = Y, 3 = Z), given the box's dimensions at 100% size.
function Layout.Reach(item, dimensions, axis)
    local r, total = item.rotation, 0
    for j = 1, 3 do total = total + math.abs(r[axis][j]) * dimensions[j] end
    return item.scale * total / 2
end

function Layout.Lowest(items, dimensions)
    local result = math.huge
    for _, item in ipairs(items) do result = math.min(result, item.z - Layout.Reach(item, dimensions, 3)) end
    return result
end

-- The space left between the source and the shape.
function Layout.Gap(dimensions)
    return math.min(dimensions[1], dimensions[2]) * 0.025
end

function Layout.InFront(items, _, dimensions)
    local first = items[1]
    local front = first.y - Layout.Reach(first, dimensions, 2)
    return dimensions[2] / 2 + Layout.Gap(dimensions) - front, -dimensions[3] / 2 - Layout.Lowest({ first }, dimensions)
end

function Layout.Build(settings, dimensions)
    local id = settings.shape
    local values = settings[id]
    local valid, reason = Layout.Validate(id, values)
    if not valid then return nil, reason end
    if not dimensions then return nil, "The item's size is unknown." end
    local shape = Layout.Shapes[id]
    local items = shape.Placements(values)
    if values.itemPitch ~= 0 or values.itemYaw ~= 0 or values.itemRoll ~= 0 then
        local turn = Rotation.FromPitchRollYaw(values.itemPitch, values.itemRoll, values.itemYaw)
        for _, item in ipairs(items) do item.rotation = Rotation.Multiply(item.rotation, turn) end
    end
    local forward, lift = (shape.Offset or Layout.InFront)(items, values, dimensions)
    for _, item in ipairs(items) do item.y, item.z = item.y + forward, item.z + lift end
    local plan = Plan.New(items, dimensions)
    plan.source = Plan.Placement(0, 0, 0, Rotation.Identity(), 1)
    return plan
end
