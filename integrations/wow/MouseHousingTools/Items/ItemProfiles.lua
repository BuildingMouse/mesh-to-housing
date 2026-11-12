local _, MHT = ...
local ItemProfiles = {}
MHT.ItemProfiles = ItemProfiles
local finite = MHT.Util.Finite

-- What placement knows about a decor item, from ItemCatalog.lua.
-- What isn't logged is assumed: all rotation axes and the resize pivot meet
-- at the item's center, the rings turn as RotationAxes.DEFAULT, and the
-- dimensions are unknown.

-- Shape previews use this item's size until the real item is known.
ItemProfiles.DEFAULT_DECOR_ID = 23553

local RINGS = { "x", "y", "z" }
local ORIGIN = { x = 0, y = 0, z = 0 }
local ASIDE_STEP = { x = 1, y = 1, z = 0 }

function ItemProfiles.Logged(decorID)
    return MHT.ItemCatalog[decorID] or {}
end

local function point(value)
    if value and finite(value.x) and finite(value.y) and finite(value.z) then
        return { x = value.x, y = value.y, z = value.z }
    end
end

function ItemProfiles.Dimensions(decorID)
    local logged = ItemProfiles.Logged(decorID).dimensions
    local dimensions = {}
    for i = 1, 3 do
        local value = logged and logged[i]
        if not finite(value) or value <= 0 then return nil, "This item has no logged size for all three axes." end
        dimensions[i] = value
    end
    return dimensions
end

function ItemProfiles.AsideStep(decorID)
    local step = ItemProfiles.Logged(decorID).asideStep or ASIDE_STEP
    return { x = step.x or 0, y = step.y or 0, z = step.z or 0 }
end

-- Everything NativeEdit needs to place the item.
function ItemProfiles.Calibration(decorID)
    local logged = ItemProfiles.Logged(decorID)
    local pivots = {}
    for _, ring in ipairs(RINGS) do pivots[ring] = point(logged.pivots and logged.pivots[ring]) or point(ORIGIN) end
    return { pivots = pivots, resizePivot = point(logged.resizePivot) or point(ORIGIN),
        axes = MHT.Util.Copy(logged.rotationAxes or MHT.RotationAxes.DEFAULT) }
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
