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

local TILE = MHT.ItemProfiles.DEFAULT_DECOR_ID

function Panel.New(parent, start, finish, settings)
    settings = settings or {}
    settings.percent = settings.percent or settings.spherePercent or 100
    local self = setmetatable({ settings = settings }, Panel)
    local tileName = MHT.ItemProfiles.Logged(TILE).name or ("decor item " .. TILE)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    self.title = UI.Text(self.frame, "", 18, 120, 260, "GameFontNormalLarge")
    self.description = UI.Muted(self.frame, "", 18, 160, 260)
    self.size = UI.Number(self.frame, "Item size (20–200%)", 18, 225, settings.percent,
        function(value) settings.percent = value; self:Preview() end)
    UI.Text(self.frame,
        "Uses saved size, pivots and axes. Resizing needs a saved resize pivot. Use a " .. tileName
            .. " at 100%. Copies rotate, resize, then move above the source.",
        18, 300, 260)
    UI.Text(self.frame,
        "Start, then hover your source and keep still while the pile is made. Press Build, then click copies in Advanced mode; keep the camera still.",
        18, 425, 260)
    self.preview = MHT.Preview.New(self.frame)
    self.preview.frame:SetPoint("TOPLEFT", 302, -120)
    self.preview.frame:SetHeight(380)
    MHT.Theme.Skin(self.preview.frame, "deep")
    UI.Text(self.preview.frame, "Preview", 12, 12, 450)
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
    local dimensions
    if not self.reason then dimensions, self.reason = MHT.ItemProfiles.Dimensions(TILE) end
    if not self.reason then
        self.plan, self.reason = MHT.Layout.Solids[self.case.shape].Build(percent / 100, dimensions)
    end
    if self.plan then self.plan.requires = TILE end
    self.preview:SetPlan(self.plan)
end

function Panel:Prepare()
    self.settings.percent = tonumber(self.size:GetText())
    self:Preview()
    return self.plan, self.reason
end

function Panel:SetBlocked(blocked, ready)
    self.size:SetEnabled(not blocked)
    self.start:SetEnabled(not blocked or ready)
    self.start:SetText(ready and "Build" or "Start test")
    self.finish:SetEnabled(blocked)
end
