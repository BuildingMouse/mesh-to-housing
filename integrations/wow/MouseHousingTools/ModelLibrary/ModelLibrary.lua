local _, MHT = ...
local Library = {}
MHT.ModelLibrary = Library
local Rotation = MHT.Rotation
local finite = MHT.Util.Finite

function Library.Entries(library)
    return MHT.ModelCatalog[library]
end

function Library.Get(library, id)
    for _, entry in ipairs(Library.Entries(library)) do
        if entry.id == id then return entry end
    end
end

local function validScale(value)
    return finite(value) and value >= 0.2 and value <= 2
end

local read = {}

function Library.Plan(library, id)
    local entry = Library.Get(library, id)
    if not entry then return nil, "Choose a model from the library." end
    if not read[entry] then read[entry] = { MHT.CopyString.Read(entry.code) } end
    local model, reason = read[entry][1], read[entry][2]
    if not model then return nil, reason end
    return MHT.CopyString.Plan(model)
end

function Library.Sketch(model, modelScale, itemScale)
    if not validScale(modelScale) then return nil, "Model size must be between 20% and 200%." end
    if not validScale(itemScale) then return nil, "Point item size must be between 20% and 200%." end
    local plan = MHT.Util.Copy(model)
    local z = math.huge
    for _, item in ipairs(plan.items) do z = math.min(z, item.z) end
    local x, y, count = 0, 0, 0
    for _, item in ipairs(plan.items) do
        if item.z - z < 1e-6 then x, y, count = x + item.x, y + item.y, count + 1 end
    end
    x, y = x / count, y / count
    for _, item in ipairs(plan.items) do
        item.x, item.y, item.z = x + (item.x - x) * modelScale, y + (item.y - y) * modelScale, z + (item.z - z) * modelScale
        item.rotation, item.scale = Rotation.Identity(), itemScale
    end
    plan.requires = nil
    return plan
end
