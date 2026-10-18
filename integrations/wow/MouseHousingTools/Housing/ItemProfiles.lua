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

function ItemProfiles.Pivot(decorID)
    local profile = ItemProfiles.ByDecorID[decorID]
    if not profile then return { x = 0, y = 0, z = 0 } end
    return {
        x = profile.pivot.x,
        y = profile.pivot.y,
        z = profile.pivot.z,
    }
end
