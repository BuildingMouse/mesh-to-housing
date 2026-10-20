local _, MHT = ...
local Cube = {}
MHT.Cube = Cube

-- Each face uses at most one rotation axis, so a failed face identifies the
-- turn to check without relying on the order of combined rotations.
local faces = {
    { label = "Bottom face", normal = { 0, 0, -1 }, rotation = { x = 180, y = 0, z = 0 } },
    { label = "Top face", normal = { 0, 0, 1 }, rotation = { x = 0, y = 0, z = 0 } },
    { label = "Right face", normal = { 1, 0, 0 }, rotation = { x = 90, y = 0, z = 0 } },
    { label = "Left face", normal = { -1, 0, 0 }, rotation = { x = -90, y = 0, z = 0 } },
    { label = "Forward face", normal = { 0, 1, 0 }, rotation = { x = 0, y = 90, z = 0 } },
    { label = "Back face", normal = { 0, -1, 0 }, rotation = { x = 0, y = -90, z = 0 } },
}

function Cube.Build(settings, dimensions)
    dimensions = dimensions or { settings.width, settings.width, settings.thickness }
    local side, depth, height = unpack(dimensions)
    if math.abs(side - depth) > 1e-6 * math.max(side, depth) then
        return nil, "The cube needs square tiles: saved X and Y sizes must match."
    end
    if height >= side then return nil, "Use a square tile thinner than its side length." end
    local edge, thickness = side * settings.scale, height * settings.scale
    local centerZ, inset = 4 * thickness + edge / 2, (edge - thickness) / 2
    local items = {}
    for _, face in ipairs(faces) do
        items[#items + 1] = {
            x = face.normal[1] * inset, y = face.normal[2] * inset, z = centerZ + face.normal[3] * inset,
            rotation = { x = face.rotation.x, y = face.rotation.y, z = face.rotation.z },
            rotationSpace = "housing", scale = settings.scale, label = face.label,
        }
    end
    return { shape = "cube", items = items, dimensions = { side, depth, height },
        source = { x = 0, y = 0, z = 0, scale = 1, yaw = 0, rotationSpace = "housing" },
        settings = { width = side, depth = depth, thickness = height, scale = settings.scale } }
end

function Cube.ForItem(plan, decorID, measurements)
    local dimensions, reason = MHT.ItemProfiles.CalibratedDimensions(decorID, measurements)
    if not dimensions then return nil, reason end
    return Cube.Build(plan.settings, dimensions)
end
