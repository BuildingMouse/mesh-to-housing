local _, MHT = ...
local Shape = {}
MHT.Rhombicosidodecahedron = Shape

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function subtract(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function cross(a, b)
    return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end
local function unit(v)
    local length = math.sqrt(dot(v, v))
    return { x = v.x / length, y = v.y / length, z = v.z / length }
end

local faces
local function squareFaces()
    if faces then return faces end
    -- Edge length 2: signed cyclic permutations of the three vertex families.
    local phi = (1 + math.sqrt(5)) / 2
    local vertices = {}
    for _, family in ipairs({ { 1, 1, phi ^ 3 }, { phi ^ 2, phi, 2 * phi }, { 2 + phi, 0, phi ^ 2 } }) do
        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs(family[2] == 0 and { 1 } or { -1, 1 }) do
                for _, sz in ipairs({ -1, 1 }) do
                    local a, b, c = sx * family[1], sy * family[2], sz * family[3]
                    vertices[#vertices + 1] = { x = a, y = b, z = c }
                    vertices[#vertices + 1] = { x = b, y = c, z = a }
                    vertices[#vertices + 1] = { x = c, y = a, z = b }
                end
            end
        end
    end
    local neighbors = {}
    for i, a in ipairs(vertices) do
        neighbors[i] = {}
        for j, b in ipairs(vertices) do
            local d = subtract(a, b)
            if math.abs(dot(d, d) - 4) < 1e-8 then neighbors[i][j] = true end
        end
    end
    faces = {}
    for i, a in ipairs(vertices) do
        for j = i + 1, #vertices do
            if neighbors[i][j] then
                for k = j + 1, #vertices do
                    if neighbors[i][k] then
                        for l = i + 1, #vertices do
                            if neighbors[j][l] and neighbors[k][l] then
                                local b, c, d = vertices[j], vertices[l], vertices[k]
                                local u, v = unit(subtract(b, a)), unit(subtract(d, a))
                                if math.abs(dot(u, v)) < 1e-8 then
                                    local center = { x = (a.x + b.x + c.x + d.x) / 4,
                                        y = (a.y + b.y + c.y + d.y) / 4, z = (a.z + b.z + c.z + d.z) / 4 }
                                    local normal = cross(u, v)
                                    if dot(normal, center) < 0 then u, v = v, u; normal = cross(u, v) end
                                    faces[#faces + 1] = { center = center, u = u, v = v, normal = normal }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Build from the bottom upward, with a stable order within each level.
    table.sort(faces, function(a, b)
        for _, axis in ipairs({ "z", "y", "x" }) do
            if math.abs(a.center[axis] - b.center[axis]) > 1e-8 then return a.center[axis] < b.center[axis] end
        end
        return false
    end)
    return faces
end

function Shape.Build(settings, dimensions)
    dimensions = dimensions or { settings.width, settings.width, settings.thickness }
    local side, depth, height = unpack(dimensions)
    if math.abs(side - depth) > 1e-6 * math.max(side, depth) then
        return nil, "This shape needs square tiles: X and Y sizes must match. Adjust the saved sizes if this tile is square."
    end
    if height >= side then return nil, "Use a square tile thinner than its side length." end
    local scale = settings.scale
    local edge, thickness = side * scale, height * scale
    local turn = math.rad(settings.rotation)
    local c, s = math.cos(turn), math.sin(turn)
    local function turnVector(v) return { x = c * v.x - s * v.y, y = s * v.x + c * v.y, z = v.z } end
    local centerZ = 4 * thickness + ((1 + math.sqrt(5)) / 2) ^ 3 * edge / 2
    local items = {}
    for _, face in ipairs(squareFaces()) do
        local center, normal = turnVector(face.center), turnVector(face.normal)
        local rotation = MHT.Transform.HousingRotation(turnVector(face.u), turnVector(face.v), normal)
        items[#items + 1] = {
            x = center.x * edge / 2 - normal.x * thickness / 2,
            y = center.y * edge / 2 - normal.y * thickness / 2,
            z = centerZ + center.z * edge / 2 - normal.z * thickness / 2,
            scale = scale, rotation = rotation, rotationSpace = "housing",
        }
    end
    return { shape = "rhombicosidodecahedron", items = items, dimensions = { side, depth, height },
        source = { x = 0, y = 0, z = 0, scale = 1, yaw = 0, rotationSpace = "housing" },
        settings = { width = side, depth = depth, thickness = height, scale = scale, rotation = settings.rotation } }
end

function Shape.ForItem(plan, decorID, measurements)
    local dimensions, reason = MHT.ItemProfiles.CalibratedDimensions(decorID, measurements)
    if not dimensions then return nil, reason end
    return Shape.Build(plan.settings, dimensions)
end
