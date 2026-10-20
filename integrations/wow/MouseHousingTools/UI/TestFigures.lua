local _, MHT = ...
local Panel = {}
Panel.__index = Panel
MHT.TestFiguresPanel = Panel

Panel.Cases = {
    { id = "cube", name = "Cube", shape = "cube",
        description = "6 square tiles, with thickness facing inward. Each face tests at most one rotation axis." },
    { id = "sphere", name = "Sphere", shape = "rhombicosidodecahedron",
        description = "30 square tiles, with thickness facing inward and triangular and pentagonal openings." },
    { id = "tilted_circle", name = "Tilted circle", shape = "tilted_circle",
        description = "5 tiles, 72° apart, tilted 30° outward. Each tile tests combined rotations." },
}

function Panel.New(parent, start, finish)
    local self = setmetatable({}, Panel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    self.title = UI.Text(self.frame, "", 18, 120, 260, "GameFontNormalLarge")
    self.description = UI.Text(self.frame, "", 18, 160, 260)
    UI.Text(self.frame,
        "Uses this item's saved sizes, pivots and rotation axes. Start with a copy at 100% size in its calibrated pose. The figure starts four tile thicknesses above it.",
        18, 245, 260)
    UI.Text(self.frame,
        "Press Start, then hover the source. Keep still while copies are placed, then click each copy in Advanced mode. The source stays in place.",
        18, 355, 260)
    UI.Text(self.frame, "Preview uses example tile dimensions; placement uses your saved measurements.", 302, 510, 490)
    self.preview = MHT.Preview.New(self.frame)
    self.start = UI.Button(self.frame, "Start test", 18, 525, 95, start)
    self.finish = UI.Button(self.frame, "End", 121, 525, 95, finish)
    self.progress = UI.Text(self.frame, "", 227, 532, 70)
    self:Select("cube")
    self:SetBlocked(false)
    return self
end

function Panel:Select(id)
    for _, case in ipairs(Panel.Cases) do
        if case.id == id then
            self.plan = assert(MHT.Layout.Solids[case.shape].Build({
                width = 2, depth = 2, thickness = 0.25, scale = 1, rotation = 0,
            }))
            self.case = case
            self.title:SetText(case.name .. " test")
            self.description:SetText(case.description)
            self.progress:SetText("")
            self.preview:SetPlan(self.plan, case.shape)
            return true
        end
    end
end

function Panel:SetBlocked(blocked)
    self.start:SetEnabled(not blocked)
    self.finish:SetEnabled(blocked)
end
