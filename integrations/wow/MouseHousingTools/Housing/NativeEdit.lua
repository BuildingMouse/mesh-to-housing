local _, MHT = ...
local NativeEdit = {}
MHT.NativeEdit = NativeEdit
local Rotation = MHT.Rotation

-- Turns a plan item into editor moves for a fresh copy of the source.
-- Rings and resizing turn around item pivots, not the center, so the move
-- also cancels the shift they cause.

local RINGS = { "x", "y", "z" }

local function turned(turns, axes, last)
    local result = Rotation.Identity()
    for _, ring in ipairs(RINGS) do
        local spec = axes[ring]
        result = Rotation.Multiply(result, Rotation.About(spec.axis, math.rad(turns[ring] * spec.sign)))
        if ring == last then break end
    end
    return result
end

local function degrees(radians)
    local value = (math.deg(radians) + 180) % 360 - 180
    return math.abs(value) < 1e-7 and 0 or value
end

local function clamp(value) return math.max(-1, math.min(1, value)) end

local function ringTurns(rotation, axes)
    local order = { axes.x.axis, axes.y.axis, axes.z.axis }
    local function m(row, column) return Rotation.Get(rotation, order[row], order[column]) end
    local handedness = ({ xyz = 1, yzx = 1, zxy = 1 })[table.concat(order)] or -1
    local x, z
    local y = math.asin(clamp(m(1, 3)))
    if math.abs(math.cos(y)) > 1e-7 then
        x, z = math.atan2(-m(2, 3), m(3, 3)), math.atan2(-m(1, 2), m(1, 1))
    else
        x, z = math.atan2(m(3, 2), m(2, 2)), 0
    end
    return { x = degrees(x) * handedness * axes.x.sign, y = degrees(y) * handedness * axes.y.sign,
        z = degrees(z) * handedness * axes.z.sign }
end

local function scaled(v, factor) return { x = v.x * factor, y = v.y * factor, z = v.z * factor } end

function NativeEdit.For(target, item)
    local axes = item.axes or MHT.RotationAxes.DEFAULT
    local turns = ringTurns(target.rotation, axes)
    local shift = { x = target.x, y = target.y, z = target.z }
    local function add(vector, factor)
        for _, axis in ipairs(RINGS) do shift[axis] = shift[axis] + vector[axis] * factor end
    end
    add(item.resizePivot, target.scale - 1)
    local before = Rotation.Identity()
    for _, ring in ipairs(RINGS) do
        local after = turned(turns, axes, ring)
        local pivot = scaled(item.pivots[ring], target.scale)
        add(Rotation.Apply(after, pivot), 1)
        add(Rotation.Apply(before, pivot), -1)
        before = after
    end
    for _, axis in ipairs(RINGS) do
        if math.abs(shift[axis]) < 1e-9 then shift[axis] = 0 end
    end
    return { x = shift.x, y = shift.y, z = shift.z, scale = target.scale ~= 1 and target.scale or nil, turns = turns }
end

function NativeEdit.TurnedPoints(points, turns, item)
    local axes = item.axes or MHT.RotationAxes.DEFAULT
    local center, before = { x = 0, y = 0, z = 0 }, Rotation.Identity()
    for _, ring in ipairs(RINGS) do
        local after = turned(turns, axes, ring)
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
