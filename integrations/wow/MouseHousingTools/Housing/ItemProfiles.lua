local _, MHT = ...
local ItemProfiles = {}
MHT.ItemProfiles = ItemProfiles
local finite = MHT.Util.Finite

-- Rotation and resizing don't always turn an item around its center: the
-- pivot is the point they turn around, so placement can undo the shift.
-- Values measured by hand in game, so they're estimates.
-- Calibration saved in game replaces them.
ItemProfiles.ByDecorID = {
    [23553] = { -- Small Wooden Floor Tile
        pivot = { x = 0.8, y = 4 / 3, z = 0 },
    },
}

local function loggedPivot(decorID)
    local profile = ItemProfiles.ByDecorID[decorID]
    local pivot = profile and profile.pivot or {}
    return { x = pivot.x or 0, y = pivot.y or 0, z = pivot.z or 0 }
end

function ItemProfiles.Dimensions(decorID, measurements)
    local item = measurements and measurements[decorID]
    local dimensions = {}
    for i, axis in ipairs({ "x", "y", "z" }) do
        local record = item and item.size and item.size[axis]
        local value = record and record.units and record.units[axis]
        if not finite(value) or value <= 0 then
            return nil, "Save all three size measurements for this item before building this shape."
        end
        dimensions[i] = value
    end
    return dimensions
end

function ItemProfiles.Pivot(decorID, ring, measurements)
    local item = measurements and measurements[decorID]
    local measured = item and item.pivot and item.pivot[ring]
    local pivot = loggedPivot(decorID)
    for _, axis in ipairs({ "x", "y", "z" }) do
        local value = measured and measured.units and measured.units[axis]
        if finite(value) then pivot[axis] = value end
    end
    return pivot
end

function ItemProfiles.ResizePivot(decorID, measurements)
    local item = measurements and measurements[decorID]
    local units = item and item.resizePivot and item.resizePivot.units
    if units and finite(units.x) and finite(units.y) and finite(units.z) then
        return { x = units.x, y = units.y, z = units.z }, true
    end
    return loggedPivot(decorID), false
end

function ItemProfiles.Calibration(decorID, measurements)
    local pivots = {}
    for _, ring in ipairs({ "x", "y", "z" }) do pivots[ring] = ItemProfiles.Pivot(decorID, ring, measurements) end
    return { pivots = pivots, resizePivot = (ItemProfiles.ResizePivot(decorID, measurements)),
        axes = MHT.RotationAxes.ForItem(decorID, measurements) }
end

function ItemProfiles.CalibratedDimensions(decorID, measurements)
    local dimensions, reason = ItemProfiles.Dimensions(decorID, measurements)
    if not dimensions then return nil, reason end
    local item = measurements[decorID]
    for _, ring in ipairs({ "x", "y", "z" }) do
        if not (item.pivot and item.pivot[ring] and item.pivot[ring].units) then
            return nil, "Save pivots for all three rotation axes before building this shape."
        end
    end
    if not MHT.RotationAxes.ForItem(decorID, measurements) then
        return nil, "Save the X, Y and Z answers in Rotation axes before building this shape."
    end
    return dimensions
end
