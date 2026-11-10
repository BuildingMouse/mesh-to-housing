local _, MHT = ...
local Cube = {}
MHT.Cube = Cube
local Rotation = MHT.Rotation

local FACES = {
    { label = "Bottom face", normal = { 0, 0, -1 }, axis = "y", degrees = 180 },
    { label = "Top face", normal = { 0, 0, 1 }, axis = "z", degrees = 0 },
    { label = "Right face", normal = { 1, 0, 0 }, axis = "y", degrees = 90 },
    { label = "Left face", normal = { -1, 0, 0 }, axis = "y", degrees = -90 },
    { label = "Forward face", normal = { 0, 1, 0 }, axis = "x", degrees = -90 },
    { label = "Back face", normal = { 0, -1, 0 }, axis = "x", degrees = 90 },
}

function Cube.Build(scale, dimensions)
    local side, depth, height = unpack(dimensions)
    if math.abs(side - depth) > 1e-6 * math.max(side, depth) then
        return nil, "The cube needs square tiles: saved X and Y sizes must match."
    end
    if height >= side then return nil, "Use a square tile thinner than its side length." end
    local edge, thickness = side * scale, height * scale
    local centerZ, inset = 4 * thickness + edge / 2, (edge - thickness) / 2
    local items = {}
    for _, face in ipairs(FACES) do
        items[#items + 1] = {
            x = face.normal[1] * inset, y = face.normal[2] * inset, z = centerZ + face.normal[3] * inset,
            rotation = Rotation.About(face.axis, math.rad(face.degrees)), scale = scale, label = face.label,
        }
    end
    return { solid = "cube", scale = scale, items = items, dimensions = { side, depth, height } }
end
