local _, MHT = ...
local Plan = {}
MHT.Plan = Plan

-- A plan says which items to place where. Positions are relative to the source item.

function Plan.New(items, dimensions, boxes)
    return { items = items, dimensions = dimensions, boxes = boxes }
end

function Plan.Placement(x, y, z, rotation, scale, label, item)
    return { x = x, y = y, z = z, rotation = rotation, scale = scale, label = label, item = item }
end

-- The box at 100% size of the item a placement uses.
function Plan.Box(plan, placement)
    return placement.item and plan.boxes and plan.boxes[placement.item] or plan.dimensions
end

-- Whether every placement uses the source item.
function Plan.SingleItem(plan)
    for _, placement in ipairs(plan.items) do
        if placement.item ~= nil then return false end
    end
    return true
end
