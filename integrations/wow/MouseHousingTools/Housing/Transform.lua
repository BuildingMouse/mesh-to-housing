local _, MHT = ...
local Transform = {}
MHT.Transform = Transform

function Transform.Rotation(pose)
    if pose.rotation then return pose.rotation end
    return { x = 0, y = 0, z = (math.deg(pose.yaw or 0) + 180) % 360 - 180 }
end

-- Scaled local pivot in placement coordinates. Fixed-axis rotations: X, then Y, then Z.
function Transform.PivotOffset(pose, pivot)
    local scale = pose.scale or 1
    local x, y, z = pivot.x * scale, pivot.y * scale, pivot.z * scale
    local rotation = Transform.Rotation(pose)
    local rx, ry, rz = math.rad(rotation.x or 0), math.rad(rotation.y or 0), math.rad(rotation.z or 0)
    y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
    x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
    x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
    return { x = x, y = y, z = z }
end

-- Rotation to apply to a known starting pose, without resetting the item.
function Transform.RotationDelta(from, target)
    local basis = { { x = 1, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1 } }
    local start, finish = {}, {}
    for i, vector in ipairs(basis) do
        start[i] = Transform.PivotOffset({ rotation = Transform.Rotation(from) }, vector)
        finish[i] = Transform.PivotOffset({ rotation = Transform.Rotation(target) }, vector)
    end
    -- R_delta = R_target * transpose(R_start).
    local function entry(row, column)
        return finish[1][row] * start[1][column] + finish[2][row] * start[2][column]
            + finish[3][row] * start[3][column]
    end
    local ry = math.asin(math.max(-1, math.min(1, -entry("z", "x"))))
    local rx, rz
    if math.abs(math.cos(ry)) > 1e-7 then
        rx, rz = math.atan2(entry("z", "y"), entry("z", "z")), math.atan2(entry("y", "x"), entry("x", "x"))
    else
        rx, rz = math.atan2(-entry("y", "z"), entry("y", "y")), 0
    end
    local function degrees(angle)
        local value = (math.deg(angle) + 180) % 360 - 180
        return math.abs(value) < 1e-7 and 0 or value
    end
    return { x = degrees(rx), y = degrees(ry), z = degrees(rz) }
end

-- Poses describe visual centers; the game moves the pivot. Precompensate so
-- resizing and rotating after translation leave the center at the target.
function Transform.Translation(from, target, pivot)
    from = from or {}
    pivot = pivot or { x = 0, y = 0, z = 0 }
    local startOffset = Transform.PivotOffset(from, pivot)
    local endOffset = Transform.PivotOffset(target, pivot)
    return {
        x = (target.x or 0) - (from.x or 0) + endOffset.x - startOffset.x,
        y = (target.y or 0) - (from.y or 0) + endOffset.y - startOffset.y,
        z = (target.z or 0) - (from.z or 0) + endOffset.z - startOffset.z,
    }
end
