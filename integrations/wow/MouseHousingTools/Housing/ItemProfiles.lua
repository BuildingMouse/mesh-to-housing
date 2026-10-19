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
