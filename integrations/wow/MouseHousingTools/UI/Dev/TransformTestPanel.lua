local _, MHT = ...
local Panel = {}
Panel.__index = Panel
MHT.TransformTestPanel = Panel

-- Its rotation speed and first ring apply to every build.

local FIELDS = {
    { "x", "Shift X", 0 }, { "y", "Shift Y", 0 }, { "z", "Shift Z", 0 },
    { "rx", "Rotate X", 0 }, { "ry", "Rotate Y", 0 }, { "rz", "Rotate Z", 45 },
    { "rotate", "Rotation ° / sec" },
    { "firstRotationAxis", "First cycled axis (1-3)" },
}

function Panel.New(parent, settings, start, finish)
    local self = setmetatable({ inputs = {} }, Panel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    for i, field in ipairs(FIELDS) do
        local key = field[1]
        if settings[key] == nil then settings[key] = field[3] end
        self.inputs[#self.inputs + 1] = UI.Number(self.frame, field[2], 18 + ((i - 1) % 3) * 260,
            120 + math.floor((i - 1) / 3) * 60, settings[key], function(value) settings[key] = value end)
    end
    UI.Text(self.frame,
        "Deselect the item, press Start, then click it in Advanced mode. This raw API test shifts the pivot and adds rotation on X, Y, Z one at a time. No pivot compensation; size stays unchanged. End cancels the test.",
        18, 380, 740)
    UI.Text(self.frame,
        "Use an item with all three rings. Test one nonzero angle at a time. Timing is an estimate; adjust ° / sec. First cycled axis: 1 = X, 2 = Y, 3 = Z. These rotation settings also apply to shapes.",
        18, 440, 740)
    self.start = UI.Button(self.frame, "Start", 18, 490, 95, start)
    self.finish = UI.Button(self.frame, "End", 121, 490, 95, finish)
    return self
end

function Panel:SetBlocked(busy)
    for _, input in ipairs(self.inputs) do input:SetEnabled(not busy) end
    self.start:SetEnabled(not busy)
    self.finish:SetEnabled(busy)
end
