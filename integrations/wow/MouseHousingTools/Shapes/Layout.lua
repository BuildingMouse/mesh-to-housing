local _, MHT = ...
local Layout = {}
MHT.Layout = Layout
local Rotation = MHT.Rotation
local Plan = MHT.Plan

-- Shape settings, and turning them into a plan (Geometry/Plan.lua).
-- Nothing here depends on the game movement/rotation mechanics.

Layout.Solids = {}

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
    if settings.shape ~= "stairs" and settings.shape ~= "circle" then return nil, "Choose a shape." end
    for key, range in pairs(ranges) do
        local value = settings[key]
        if type(value) ~= "number" or value ~= value or value < range[1] or value > range[2] then
            return nil, key .. " must be between " .. range[1] .. " and " .. range[2] .. "."
        end
    end
    if settings.count % 1 ~= 0 then return nil, "Item count must be a whole number." end
    return true
end

-- How far a placed item's box reaches from its center along a world axis
-- (1 = X, 2 = Y, 3 = Z), given the box's dimensions at 100% size.
local function reach(item, dimensions, axis)
    local r, total = item.rotation, 0
    for j = 1, 3 do total = total + math.abs(r[axis][j]) * dimensions[j] end
    return item.scale * total / 2
end

function Layout.Build(settings)
    local valid, reason = Layout.Validate(settings)
    if not valid then return nil, reason end
    local items = (settings.shape == "stairs" and MHT.Stairs or MHT.Circle).Placements(settings)
    -- Keep the whole shape in front of the source item.
    local dimensions = { settings.width, settings.depth, settings.thickness }
    local front = math.huge
    for _, item in ipairs(items) do
        front = math.min(front, item.y - reach(item, dimensions, 2))
    end
    local offset = settings.clearance + dimensions[2] / 2 - front
    for _, item in ipairs(items) do item.y = item.y + offset end
    local plan = Plan.New(items, dimensions)
    plan.source = Plan.Placement(0, 0, 0, Rotation.Identity(), 1)
    return plan
end
