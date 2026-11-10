local _, MHT = ...
local Rotation = {}
MHT.Rotation = Rotation

-- Item orientations as 3 x 3 rotation matrices (X right, Y forward, Z up).

local AXIS = { x = 1, y = 2, z = 3 }

function Rotation.Identity()
    return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
end

function Rotation.About(axis, radians)
    local c, s = math.cos(radians), math.sin(radians)
    if axis == "x" then return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } } end
    if axis == "y" then return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } } end
    return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } }
end

function Rotation.FromAxes(right, forward, up)
    return { { right.x, forward.x, up.x }, { right.y, forward.y, up.y }, { right.z, forward.z, up.z } }
end

-- a * b: turn by b first, then by a.
function Rotation.Multiply(a, b)
    local result = {}
    for row = 1, 3 do
        result[row] = {}
        for column = 1, 3 do
            result[row][column] = a[row][1] * b[1][column] + a[row][2] * b[2][column] + a[row][3] * b[3][column]
        end
    end
    return result
end

function Rotation.Apply(r, v)
    return { x = r[1][1] * v.x + r[1][2] * v.y + r[1][3] * v.z,
             y = r[2][1] * v.x + r[2][2] * v.y + r[2][3] * v.z,
             z = r[3][1] * v.x + r[3][2] * v.y + r[3][3] * v.z }
end

function Rotation.Get(r, row, column)
    return r[AXIS[row]][AXIS[column]]
end

function Rotation.FromPitchRollYaw(pitch, roll, yaw)
    return Rotation.Multiply(Rotation.About("z", math.rad(yaw)),
        Rotation.Multiply(Rotation.About("y", math.rad(roll)), Rotation.About("x", math.rad(pitch))))
end
