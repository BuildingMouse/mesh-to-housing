local _, MHT = ...

-- Logged item profiles by decor ID. Fields are described in ItemProfiles.lua.

MHT.ItemCatalog = {
    [23553] = {
        name = "Small Wooden Floor Tile",
        dimensions = { 2, 2, 0.43322 },
        pivots = {
            x = { x = 0.8, y = 0, z = 0.17 },
            y = { x = 0, y = 0.8, z = 0.17 },
            z = { x = 0.79, y = 0.79, z = 0 },
        },
        resizePivot = { x = -1, y = -1, z = -0.2 },
        rotationAxes = { x = { axis = "y", sign = -1 }, y = { axis = "x", sign = 1 }, z = { axis = "z", sign = 1 } },
    },
}
