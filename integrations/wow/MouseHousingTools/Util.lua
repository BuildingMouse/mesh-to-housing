local _, MHT = ...
local Util = {}
MHT.Util = Util

function Util.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = Util.Copy(entry) end
    return result
end

function Util.Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
