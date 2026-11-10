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

function Panel.New(parent, start, finish, settings)
    settings = settings or {}
    settings.percent = settings.percent or settings.spherePercent or 100
    local self = setmetatable({ settings = settings }, Panel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    self.title = UI.Text(self.frame, "", 18, 120, 260, "GameFontNormalLarge")
    self.description = UI.Text(self.frame, "", 18, 160, 260)
    self.size = UI.Number(self.frame, "Item size (20–200%)", 18, 225, settings.percent,
        function(value) settings.percent = value; self:Preview() end)
    UI.Text(self.frame,
        "Uses saved sizes, pivots and rotation axes. Resizing also needs a saved resize pivot. Start with a calibrated copy at 100%. Each tile rotates, resizes, then moves into place. The figure starts four resized tile thicknesses above the source.",
        18, 300, 260)
    UI.Text(self.frame,
        "Press Start, then hover the source. Keep still while copies are placed, then click each copy in Advanced mode. The source stays in place.",
        18, 425, 260)
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
            self.case = case
            self.title:SetText(case.name .. " test")
            self.description:SetText(case.description)
            self.progress:SetText("")
            self:Preview()
            return true
        end
    end
end

function Panel:Preview()
    self.plan, self.reason = nil, nil
    local percent = self.settings.percent
    if type(percent) ~= "number" or percent ~= percent or percent < 20 or percent > 200 then
        self.reason = "Item size must be between 20% and 200%."
    end
    if not self.reason then
        self.plan, self.reason = MHT.Layout.Solids[self.case.shape].Build({
            width = 2, depth = 2, thickness = 0.25, scale = percent / 100, rotation = 0,
        })
        if self.plan then self.plan.rotateFirst = true end
    end
    self.preview:SetPlan(self.plan, self.case.shape)
end

function Panel:Prepare()
    self.settings.percent = tonumber(self.size:GetText())
    self:Preview()
    return self.plan, self.reason
end

function Panel:SetBlocked(blocked)
    self.size:SetEnabled(not blocked)
    self.start:SetEnabled(not blocked)
    self.finish:SetEnabled(blocked)
end
