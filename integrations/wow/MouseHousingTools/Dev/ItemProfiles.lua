local _, MHT = ...
local ItemProfiles = MHT.ItemProfiles
local finite, copy = MHT.Util.Finite, MHT.Util.Copy

-- Saved calibration stands in for the catalog in dev mode, so builds and
-- tests use it before its values are copied into ItemCatalog.lua.

local RINGS = { "x", "y", "z" }
local logged = {}

local function withSaved(entry, saved)
    local merged = copy(entry or {})
    if saved.size then
        local dimensions = copy(merged.dimensions or {})
        for i, axis in ipairs(RINGS) do
            local record = saved.size[axis]
            local value = record and record.units and record.units[axis]
            if finite(value) and value > 0 then dimensions[i] = value end
        end
        merged.dimensions = dimensions
    end
    if saved.pivot then
        merged.pivots = copy(merged.pivots or {})
        for _, ring in ipairs(RINGS) do
            local units = saved.pivot[ring] and saved.pivot[ring].units
            if units then
                local pivot = copy(merged.pivots[ring] or { x = 0, y = 0, z = 0 })
                for _, axis in ipairs(RINGS) do
                    if finite(units[axis]) then pivot[axis] = units[axis] end
                end
                merged.pivots[ring] = pivot
            end
        end
    end
    local resize = saved.resizePivot and saved.resizePivot.units
    if resize and finite(resize.x) and finite(resize.y) and finite(resize.z) then
        merged.resizePivot = copy(resize)
    end
    if MHT.RotationAxes.Validate(saved.rotationAxes) then merged.rotationAxes = copy(saved.rotationAxes) end
    return merged
end

function ItemProfiles.UseSaved(measurements)
    for decorID, saved in pairs(measurements) do
        if logged[decorID] == nil then logged[decorID] = MHT.ItemCatalog[decorID] or false end
        MHT.ItemCatalog[decorID] = withSaved(logged[decorID] or nil, saved)
    end
end
