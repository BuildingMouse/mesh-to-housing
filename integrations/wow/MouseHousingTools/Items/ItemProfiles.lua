local _, MHT = ...
local ItemProfiles = {}
MHT.ItemProfiles = ItemProfiles
local finite = MHT.Util.Finite

-- What placement knows about a decor item. Logged profiles are in
-- ItemCatalog.lua; calibration saved in game replaces their values.
-- What isn't logged or saved is assumed: all rotation axes and the resize
-- pivot meet at the item's center and the dimensions are unknown.

-- Shape previews use this item's size until the real item is known.
ItemProfiles.DEFAULT_DECOR_ID = 23553

local RINGS = { "x", "y", "z" }

local function saved(decorID, measurements)
    return measurements and measurements[decorID] or {}
end

function ItemProfiles.Logged(decorID)
    return MHT.ItemCatalog[decorID] or {}
end

local function point(value)
    if value and finite(value.x) and finite(value.y) and finite(value.z) then
        return { x = value.x, y = value.y, z = value.z }
    end
end

function ItemProfiles.Dimensions(decorID, measurements)
    local size, logged = saved(decorID, measurements).size, ItemProfiles.Logged(decorID).dimensions
    local dimensions = {}
    for i, axis in ipairs(RINGS) do
        local record = size and size[axis]
        local value = record and record.units and record.units[axis]
        if not finite(value) or value <= 0 then value = logged and logged[i] end
        if not finite(value) or value <= 0 then
            return nil, "This item has no logged or saved size for all three axes."
        end
        dimensions[i] = value
    end
    return dimensions
end

-- The ring's pivot.
function ItemProfiles.Pivot(decorID, ring, measurements)
    local logged = ItemProfiles.Logged(decorID).pivots
    local pivot = point(logged and logged[ring]) or { x = 0, y = 0, z = 0 }
    local record = saved(decorID, measurements).pivot
    local units = record and record[ring] and record[ring].units
    for _, axis in ipairs(RINGS) do
        if units and finite(units[axis]) then pivot[axis] = units[axis] end
    end
    return pivot
end

-- The resize pivot, and whether it is known (logged or saved).
function ItemProfiles.ResizePivot(decorID, measurements)
    local record = saved(decorID, measurements).resizePivot
    local pivot = point(record and record.units) or point(ItemProfiles.Logged(decorID).resizePivot)
    if pivot then return pivot, true end
    return { x = 0, y = 0, z = 0 }, false
end

-- Everything NativeEdit needs to place the item.
function ItemProfiles.Calibration(decorID, measurements)
    local pivots = {}
    for _, ring in ipairs(RINGS) do pivots[ring] = ItemProfiles.Pivot(decorID, ring, measurements) end
    return { pivots = pivots, resizePivot = (ItemProfiles.ResizePivot(decorID, measurements)),
        axes = MHT.RotationAxes.ForItem(decorID, measurements) }
end

local FOOTPRINT = { { "near-left", -1, -1 }, { "far-left", -1, 1 }, { "far-right", 1, 1 }, { "near-right", 1, -1 } }

-- The outline of an item with `profile.dimensions` and `profile.shape`, in its
-- own axes at 100% size: vertices, edges as pairs of vertex indices, and faces
-- wound counterclockwise seen from outside. Nil when the size isn't known.
function ItemProfiles.Outline(profile)
    local d = profile and profile.dimensions
    if not d then return nil end
    local shape = profile.shape or {}
    local footprint = {}
    for _, corner in ipairs(FOOTPRINT) do
        if not (shape.kind == "triangle" and shape.cut == corner[1]) then
            footprint[#footprint + 1] = { corner[2] * d[1] / 2, corner[3] * d[2] / 2 }
        end
    end
    local vertices, edges, n = {}, {}, #footprint
    for _, z in ipairs({ -d[3] / 2, d[3] / 2 }) do
        for _, p in ipairs(footprint) do vertices[#vertices + 1] = { x = p[1], y = p[2], z = z } end
    end
    -- The footprint runs clockwise seen from above.
    local bottom, top, faces = {}, {}, {}
    for i = 1, n do
        local j = i % n + 1
        edges[#edges + 1] = { i, j }
        edges[#edges + 1] = { n + i, n + j }
        edges[#edges + 1] = { i, n + i }
        bottom[i], top[i] = i, 2 * n + 1 - i
        faces[#faces + 1] = { i, n + i, n + j, j }
    end
    faces[#faces + 1], faces[#faces + 2] = bottom, top
    return vertices, edges, faces
end
