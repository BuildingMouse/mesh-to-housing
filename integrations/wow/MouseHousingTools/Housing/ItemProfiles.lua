local _, MHT = ...
local ItemProfiles = {}
MHT.ItemProfiles = ItemProfiles

-- Pivot from the visual center, in movement units at scale 1.
-- +X is right, +Y is forward, +Z is up in the item's default orientation.
ItemProfiles.ByDecorID = {
    [23553] = { -- Small Wooden Floor Tile
        -- X estimated from opposite-tile alignment; Y still needs a depth measurement.
        pivot = { x = 0.8, y = 4 / 3, z = 0 },
    },
}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function ItemProfiles.Pivot(decorID, axis, measurements)
    local profile = ItemProfiles.ByDecorID[decorID]
    local preset = profile and profile.pivot or {}
    local axisPreset = profile and profile.rotationPivots and profile.rotationPivots[axis] or {}
    local item = measurements and measurements[decorID]
    local measured = item and item.pivot and item.pivot[axis]
    local pivot = {}
    for _, coordinate in ipairs({ "x", "y", "z" }) do
        local value = measured and measured.units and measured.units[coordinate]
        if finite(value) then
            pivot[coordinate] = value
        else
            pivot[coordinate] = axisPreset[coordinate] or preset[coordinate] or 0
        end
    end
    return pivot
end

function ItemProfiles.Dimensions(decorID, measurements)
    local item = measurements and measurements[decorID]
    local dimensions = {}
    for i, axis in ipairs({ "x", "y", "z" }) do
        local record = item and item.size and item.size[axis]
        local value = record and record.units and record.units[axis]
        if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
            return nil, "Save all three size measurements for this item before building this shape."
        end
        dimensions[i] = value
    end
    return dimensions
end

function ItemProfiles.ResizePivot(decorID, measurements)
    local item = measurements and measurements[decorID]
    local units = item and item.resizePivot and item.resizePivot.units
    if units and finite(units.x) and finite(units.y) and finite(units.z) then
        return { x = units.x, y = units.y, z = units.z }, true
    end
    local profile = ItemProfiles.ByDecorID[decorID]
    local preset = profile and profile.resizePivot
    if preset then return { x = preset.x or 0, y = preset.y or 0, z = preset.z or 0 } end
    return ItemProfiles.Pivot(decorID)
end

function ItemProfiles.CalibratedDimensions(decorID, measurements)
    local dimensions, reason = ItemProfiles.Dimensions(decorID, measurements)
    if not dimensions then return nil, reason end
    local item = measurements[decorID]
    for _, axis in ipairs({ "x", "y", "z" }) do
        if not (item.pivot and item.pivot[axis] and item.pivot[axis].units) then
            return nil, "Save pivots for all three rotation axes before building this shape."
        end
    end
    if not MHT.RotationAxes.ForItem(decorID, measurements) then
        return nil, "Save the X, Y and Z answers in Rotation axes before building this shape."
    end
    return dimensions
end
