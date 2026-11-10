local _, MHT = ...
local RotationAxes = MHT.RotationAxes

-- Match observed quarter turns to the existing placement convention. These
-- signs are stored placement values; changing the labels must not migrate them.
RotationAxes.Choices = {
    { text = "Top toward Right (+X); Right edge lowers", axis = "y", sign = 1 },
    { text = "Top toward Left (-X); Right edge rises", axis = "y", sign = -1 },
    { text = "Top toward Forward (+Y); Back edge rises", axis = "x", sign = 1 },
    { text = "Top toward Back (-Y); Back edge lowers", axis = "x", sign = -1 },
    { text = "Top stays up; Forward edge turns Left", axis = "z", sign = -1 },
    { text = "Top stays up; Forward edge turns Right", axis = "z", sign = 1 },
}

function RotationAxes.WithBindings(text, bindings)
    return (text:gsub("%a+", function(word)
        local keys = bindings and bindings[word]
        if keys and #keys > 0 then return word .. " [" .. table.concat(keys, "/") .. "]" end
        return word
    end))
end

function RotationAxes.Describe(record)
    for _, choice in ipairs(RotationAxes.Choices) do
        if record and record.axis == choice.axis and record.sign == choice.sign then return choice.text end
    end
    return "not tested"
end
