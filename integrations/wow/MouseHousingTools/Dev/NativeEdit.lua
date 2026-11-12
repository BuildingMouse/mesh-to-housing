local _, MHT = ...
local NativeEdit = MHT.NativeEdit
local Rotation = MHT.Rotation

local RINGS = { "x", "y", "z" }

-- Where points on the item end up after the rings turn, and the center's shift.
function NativeEdit.TurnedPoints(points, turns, item)
    local center, before = { x = 0, y = 0, z = 0 }, Rotation.Identity()
    for _, ring in ipairs(RINGS) do
        local after = NativeEdit.Turned(turns, item.axes, ring)
        local from, to = Rotation.Apply(before, item.pivots[ring]), Rotation.Apply(after, item.pivots[ring])
        for _, axis in ipairs(RINGS) do center[axis] = center[axis] + from[axis] - to[axis] end
        before = after
    end
    local result = {}
    for i, point in ipairs(points) do
        local offset = Rotation.Apply(before, point)
        result[i] = { x = center.x + offset.x, y = center.y + offset.y, z = center.z + offset.z }
    end
    return result, center
end
