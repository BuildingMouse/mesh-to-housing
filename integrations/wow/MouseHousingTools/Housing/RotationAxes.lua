local _, MHT = ...
local RotationAxes = {}
MHT.RotationAxes = RotationAxes

RotationAxes.Choices = {
    { text = "Top toward Right (+X); Right edge lowers", axis = "y", sign = 1 },
    { text = "Top toward Left (-X); Right edge rises", axis = "y", sign = -1 },
    { text = "Top toward Forward (+Y); Back edge rises", axis = "x", sign = -1 },
    { text = "Top toward Back (-Y); Back edge lowers", axis = "x", sign = 1 },
    { text = "Top stays up; Forward edge turns Left", axis = "z", sign = 1 },
    { text = "Top stays up; Forward edge turns Right", axis = "z", sign = -1 },
}

function RotationAxes.WithBindings(text, bindings)
    return (text:gsub("%a+", function(word)
        local keys = bindings and bindings[word]
        if keys and #keys > 0 then return word .. " [" .. table.concat(keys, "/") .. "]" end
        return word
    end))
end

function RotationAxes.Copy(axes)
    local result = {}
    for axis, record in pairs(axes or {}) do
        result[axis] = {}
        for key, value in pairs(record) do result[axis][key] = value end
    end
    return result
end

function RotationAxes.Validate(axes)
    local seen = {}
    for _, axis in ipairs({ "x", "y", "z" }) do
        local record = axes and axes[axis]
        if not record then return nil, "Test and answer for X, Y and Z before saving." end
        if not ({ x = true, y = true, z = true })[record.axis] or (record.sign ~= 1 and record.sign ~= -1) then
            return nil, "Choose an observed direction for each rotation axis."
        end
        if seen[record.axis] then return nil, "Two answers describe the same rotation axis. Check those tests again." end
        seen[record.axis] = true
    end
    return true
end

function RotationAxes.ForItem(decorID, measurements)
    local item = measurements and measurements[decorID]
    local axes = item and item.rotationAxes
    if RotationAxes.Validate(axes) then return RotationAxes.Copy(axes) end
end

function RotationAxes.Describe(record)
    for _, choice in ipairs(RotationAxes.Choices) do
        if record and record.axis == choice.axis and record.sign == choice.sign then return choice.text end
    end
    return "not tested"
end
