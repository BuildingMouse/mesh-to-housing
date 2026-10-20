local _, MHT = ...
local Transform = {}
MHT.Transform = Transform

function Transform.Rotation(pose)
    if pose.rotation then return pose.rotation end
    return { x = 0, y = 0, z = (math.deg(pose.yaw or 0) + 180) % 360 - 180 }
end

-- Shape poses use a fixed reference frame: X tips right, Y tips forward.
-- RotationDelta converts that geometry to the item's measured native axes.
function Transform.HousingRotation(u, v, normal)
    local pitch = math.asin(math.max(-1, math.min(1, v.z)))
    local x, z
    if math.abs(math.cos(pitch)) > 1e-7 then
        x, z = math.atan2(-u.z, normal.z), math.atan2(-v.x, v.y)
    else
        x, z = 0, math.atan2(u.y, u.x)
    end
    local function degrees(angle)
        local value = (math.deg(angle) + 180) % 360 - 180
        return math.abs(value) < 1e-7 and 0 or value
    end
    return { x = degrees(x), y = degrees(-pitch), z = degrees(z) }
end

-- Scaled local pivot in placement coordinates. Native turns use moving axes;
-- their X/Y/Z product acts on a vector in reverse order.
function Transform.PivotOffset(pose, pivot)
    local scale = pose.scale or 1
    local x, y, z = pivot.x * scale, pivot.y * scale, pivot.z * scale
    local rotation = Transform.Rotation(pose)
    local rx, ry, rz = math.rad(rotation.x or 0), math.rad(rotation.y or 0), math.rad(rotation.z or 0)
    if pose.rotationAxes then
        for _, axis in ipairs({ "z", "y", "x" }) do
            local observed = pose.rotationAxes[axis]
            local angle = math.rad(rotation[axis] or 0) * observed.sign
            local c, s = math.cos(angle), math.sin(angle)
            if observed.axis == "x" then y, z = c * y - s * z, s * y + c * z
            elseif observed.axis == "y" then x, z = c * x + s * z, -s * x + c * z
            else x, y = c * x - s * y, s * x + c * y end
        end
        return { x = x, y = y, z = z }
    end
    if pose.rotationSpace == "housing" then
        -- Initial direction convention: +X tips a flat tile right, +Y forward.
        x, z = x * math.cos(rx) + z * math.sin(rx), -x * math.sin(rx) + z * math.cos(rx)
        y, z = y * math.cos(ry) + z * math.sin(ry), -y * math.sin(ry) + z * math.cos(ry)
    else
        y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
        x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
    end
    x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
    return { x = x, y = y, z = z }
end

-- Rotation to apply to a known starting pose, without resetting the item.
function Transform.RotationDelta(from, target, rotationAxes)
    local basis = { { x = 1, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1 } }
    local start, finish = {}, {}
    for i, vector in ipairs(basis) do
        start[i] = Transform.PivotOffset({ rotation = Transform.Rotation(from), rotationSpace = from.rotationSpace }, vector)
        finish[i] = Transform.PivotOffset({ rotation = Transform.Rotation(target), rotationSpace = target.rotationSpace }, vector)
    end
    local index = { x = 1, y = 2, z = 3 }
    local function entry(row, column)
        if rotationAxes then
            -- Local turns: R_start * R_delta = R_target.
            local a, b = start[index[row]], finish[index[column]]
            return a.x * b.x + a.y * b.y + a.z * b.z
        end
        return finish[1][row] * start[1][column] + finish[2][row] * start[2][column]
            + finish[3][row] * start[3][column]
    end
    if target.rotationSpace == "housing" and not rotationAxes then
        return Transform.HousingRotation({ x = entry("x", "x"), y = entry("y", "x"), z = entry("z", "x") },
            { x = entry("x", "y"), y = entry("y", "y"), z = entry("z", "y") },
            { x = entry("x", "z"), y = entry("y", "z"), z = entry("z", "z") })
    end
    local signs
    if rotationAxes then
        local order = { rotationAxes.x.axis, rotationAxes.y.axis, rotationAxes.z.axis }
        local permutation = table.concat(order)
        local handedness = (permutation == "xyz" or permutation == "yzx" or permutation == "zxy") and 1 or -1
        signs = { x = handedness * rotationAxes.x.sign, y = handedness * rotationAxes.y.sign,
            z = handedness * rotationAxes.z.sign }
        local originalEntry = entry
        -- Express the desired rotation in the observed axis order, solve XYZ,
        -- then convert each angle back to the API's positive direction.
        entry = function(row, column) return originalEntry(order[index[row]], order[index[column]]) end
    end
    local rx, ry, rz
    if rotationAxes then
        -- Intrinsic X/Y/Z: R_delta = Rx * Ry * Rz.
        ry = math.asin(math.max(-1, math.min(1, entry("x", "z"))))
        if math.abs(math.cos(ry)) > 1e-7 then
            rx, rz = math.atan2(-entry("y", "z"), entry("z", "z")), math.atan2(-entry("x", "y"), entry("x", "x"))
        else
            rx, rz = math.atan2(entry("z", "y"), entry("y", "y")), 0
        end
    else
        ry = math.asin(math.max(-1, math.min(1, -entry("z", "x"))))
        if math.abs(math.cos(ry)) > 1e-7 then
            rx, rz = math.atan2(entry("z", "y"), entry("z", "z")), math.atan2(entry("y", "x"), entry("x", "x"))
        else
            rx, rz = math.atan2(-entry("y", "z"), entry("y", "y")), 0
        end
    end
    local function degrees(angle)
        local value = (math.deg(angle) + 180) % 360 - 180
        return math.abs(value) < 1e-7 and 0 or value
    end
    return { x = degrees(rx) * (signs and signs.x or 1), y = degrees(ry) * (signs and signs.y or 1),
        z = degrees(rz) * (signs and signs.z or 1) }
end

-- Poses describe visual centers; the game moves the pivot. Precompensate so
-- resizing and rotating after translation leave the center at the target.
function Transform.Translation(from, target, pivot, rotationPivots, rotationAxes)
    from = from or {}
    pivot = pivot or { x = 0, y = 0, z = 0 }
    local startOffset = Transform.PivotOffset(from, pivot)
    local scaled = { scale = target.scale or 1, rotation = Transform.Rotation(from), rotationSpace = from.rotationSpace }
    local scaledOffset = Transform.PivotOffset(scaled, pivot)
    local shift = {}
    for _, coordinate in ipairs({ "x", "y", "z" }) do
        shift[coordinate] = (target[coordinate] or 0) - (from[coordinate] or 0)
            + scaledOffset[coordinate] - startOffset[coordinate]
    end
    local rotation = Transform.RotationDelta(from, target, rotationAxes)
    local applied = { x = 0, y = 0, z = 0 }
    -- Follow the same X/Y/Z sequence as Motion, compensating each pivot separately.
    for _, axis in ipairs({ "x", "y", "z" }) do
        local localPivot = rotationPivots and rotationPivots[axis] or pivot
        local offset = rotationAxes and localPivot or Transform.PivotOffset(scaled, localPivot)
        local function currentOffset()
            local value = Transform.PivotOffset({ scale = rotationAxes and scaled.scale or 1,
                rotation = applied, rotationSpace = target.rotationSpace, rotationAxes = rotationAxes }, offset)
            if rotationAxes then
                -- The entire moving frame starts in the source orientation.
                value = Transform.PivotOffset({ rotation = scaled.rotation, rotationSpace = scaled.rotationSpace }, value)
            end
            return value
        end
        local before = currentOffset()
        applied[axis] = rotation[axis]
        local after = currentOffset()
        for _, coordinate in ipairs({ "x", "y", "z" }) do
            shift[coordinate] = shift[coordinate] + after[coordinate] - before[coordinate]
        end
    end
    -- Floating-point residue must not start an unwanted movement tick.
    for coordinate, value in pairs(shift) do
        if math.abs(value) < 1e-9 then shift[coordinate] = 0 end
    end
    return shift
end

-- Predict raw native turns, including the center's movement around each pivot.
-- Points and pivots start in the calibrated copy's frame, at scale 1.
function Transform.RotatePoints(points, rotation, rotationPivots, rotationAxes)
    local applied, center = { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }
    local pose = { rotation = applied, rotationAxes = rotationAxes }
    for _, axis in ipairs({ "x", "y", "z" }) do
        local before = Transform.PivotOffset(pose, rotationPivots[axis])
        applied[axis] = rotation[axis] or 0
        local after = Transform.PivotOffset(pose, rotationPivots[axis])
        for _, coordinate in ipairs({ "x", "y", "z" }) do
            center[coordinate] = center[coordinate] + before[coordinate] - after[coordinate]
        end
    end
    local result = {}
    for i, point in ipairs(points) do
        local offset = Transform.PivotOffset(pose, point)
        result[i] = { x = center.x + offset.x, y = center.y + offset.y, z = center.z + offset.z }
    end
    return result, center
end
