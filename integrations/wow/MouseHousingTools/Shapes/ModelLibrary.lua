local _, MHT = ...
local Library = {}
MHT.ModelLibrary = Library
local Plan, Rotation = MHT.Plan, MHT.Rotation
local finite = MHT.Util.Finite

-- Saved models. The test sphere is temporary, until real models exist.

Library.Entries = {
    { id = "sphere", name = "Test sphere", solid = "rhombicosidodecahedron", decorID = 23553, count = 30,
      description = "30 square tiles form a sphere with small openings." },
}

function Library.Get(id)
    for _, entry in ipairs(Library.Entries) do
        if entry.id == id then return entry end
    end
end

local function validScale(value)
    return finite(value) and value >= 0.2 and value <= 2
end

function Library.Build(id, scale, dimensions)
    local entry = Library.Get(id)
    if not entry then return nil, "Choose a model from the library." end
    if not validScale(scale) then return nil, "Item size must be between 20% and 200%." end
    if not dimensions then return nil, "The model's item has no logged size." end
    local solid = MHT.Layout.Solids[entry.solid]
    local function build(itemDimensions)
        local plan, reason = solid.Build(scale, itemDimensions)
        if not plan then return nil, reason end
        plan.requires, plan.fit = entry.decorID, build
        plan.source = Plan.Placement(0, 0, 0, Rotation.Identity(), 1)
        return plan
    end
    return build(dimensions)
end

function Library.Sketch(id, modelScale, itemScale, dimensions)
    if not validScale(modelScale) then return nil, "Model size must be between 20% and 200%." end
    if not validScale(itemScale) then return nil, "Point item size must be between 20% and 200%." end
    local plan, reason = Library.Build(id, 1, dimensions)
    if not plan then return nil, reason end
    for _, item in ipairs(plan.items) do
        item.x, item.y, item.z = item.x * modelScale, item.y * modelScale, item.z * modelScale
        item.rotation, item.scale = Rotation.Identity(), itemScale
    end
    plan.requires, plan.fit = nil, nil
    return plan
end
