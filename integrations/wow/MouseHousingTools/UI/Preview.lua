local _, MHT = ...
local Preview = {}
Preview.__index = Preview
MHT.Preview = Preview

local edges = { {1,2}, {2,3}, {3,4}, {4,1}, {5,6}, {6,7}, {7,8}, {8,5}, {1,5}, {2,6}, {3,7}, {4,8} }

function Preview.New(parent)
    local self = setmetatable({ lines = {}, yaw = -0.6, pitch = 0.55 }, Preview)
    self.frame = MHT.UI.Panel(parent, 490, 390)
    self.frame:SetPoint("TOPLEFT", 302, -110)
    self.caption = MHT.UI.Text(self.frame, "Block approximation - drag to turn", 12, 12, 450)
    self.sourceLabel = MHT.UI.Text(self.frame, "SOURCE / START", 0, 0, 115)
    self.sourceLabel:SetTextColor(1, 0.76, 0.3)
    self.sourceDot = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.sourceDot:SetText("●")
    self.sourceDot:SetTextColor(1, 0.76, 0.3)
    self.frame:EnableMouse(true)
    self.frame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            local x, y = GetCursorPosition()
            self.drag = { x, y, self.yaw, self.pitch }
        end
    end)
    self.frame:SetScript("OnMouseUp", function() self.drag = nil end)
    self.frame:SetScript("OnHide", function() self.drag = nil end)
    self.frame:SetScript("OnUpdate", function()
        if self.drag then
            local x, y = GetCursorPosition()
            if self.lastX == x and self.lastY == y then return end
            self.lastX, self.lastY = x, y
            self.yaw = self.drag[3] + (x - self.drag[1]) / 180
            self.pitch = math.max(0.15, math.min(1.4, self.drag[4] + (y - self.drag[2]) / 180))
            self:Draw()
        end
    end)
    return self
end

function Preview:SetPlan(plan, shape)
    self.plan, self.shape = plan, shape
    self.caption:SetText(shape == "stairs" and "Block approximation - drag to turn" or "Shape preview - drag to turn")
    self:Draw()
end

function Preview:Draw()
    for _, line in ipairs(self.lines) do line:Hide() end
    self.sourceLabel:Hide()
    self.sourceDot:Hide()
    if not self.plan then return end
    local c, s = math.cos(self.yaw), math.sin(self.yaw)
    local cp, sp = math.cos(self.pitch), math.sin(self.pitch)
    local function project(p)
        return { c * p[1] - s * p[2], sp * (s * p[1] + c * p[2]) + cp * p[3] }
    end
    local boxes, low, high = {}, { math.huge, math.huge }, { -math.huge, -math.huge }
    local all = {}
    if self.shape == "stairs" then
        all[1] = self.plan.source
    else
        low, high = { 0, 0 }, { 0, 0 }
    end
    for _, item in ipairs(self.plan.items) do all[#all + 1] = item end
    for _, item in ipairs(all) do
        local box = {}
        for _, vertex in ipairs(MHT.Layout.Corners(item, self.plan.dimensions)) do
            local p = project(vertex)
            box[#box + 1] = p
            for a = 1, 2 do low[a], high[a] = math.min(low[a], p[a]), math.max(high[a], p[a]) end
        end
        boxes[#boxes + 1] = box
    end
    local w, h = self.frame:GetWidth(), self.frame:GetHeight()
    local scale = math.min((w - 65) / math.max(0.01, high[1] - low[1]), (h - 90) / math.max(0.01, high[2] - low[2]))
    local function screen(p)
        return w / 2 + (p[1] - (low[1] + high[1]) / 2) * scale,
               h / 2 + (p[2] - (low[2] + high[2]) / 2) * scale
    end
    local index = 0
    for b, box in ipairs(boxes) do
        local source = self.shape == "stairs" and b == 1
        for _, edge in ipairs(edges) do
            index = index + 1
            local line = self.lines[index]
            if not line then line = self.frame:CreateLine(nil, "ARTWORK"); self.lines[index] = line end
            local x1, y1 = screen(box[edge[1]])
            local x2, y2 = screen(box[edge[2]])
            line:SetStartPoint("BOTTOMLEFT", self.frame, x1, y1)
            line:SetEndPoint("BOTTOMLEFT", self.frame, x2, y2)
            line:SetThickness(source and 2 or 1)
            if source then line:SetColorTexture(1, 0.76, 0.3, 1)
            else line:SetColorTexture(0.38, 0.72, 0.82, 0.85) end
            line:Show()
        end
    end
    local x, y = screen(project({ 0, 0, 0 }))
    if self.shape == "stairs" then
        self.sourceLabel:ClearAllPoints()
        self.sourceLabel:SetPoint("TOP", self.frame, "BOTTOMLEFT", x, y - 12)
        self.sourceLabel:Show()
    else
        self.sourceDot:ClearAllPoints()
        self.sourceDot:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
        self.sourceDot:Show()
    end
end
