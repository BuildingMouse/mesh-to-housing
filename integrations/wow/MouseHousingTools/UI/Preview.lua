local _, MHT = ...
local Preview = {}
Preview.__index = Preview
MHT.Preview = Preview

-- Draws a plan's items as outlines (or points) in a turnable 3D view.

local SOURCE_OPACITY = 0.12

-- The item's outline from Items; placements of other items use their logged shape.
local function outline(plan, item)
    local logged = item.item and MHT.ItemProfiles.Logged(item.item) or {}
    return MHT.ItemProfiles.Outline({ dimensions = MHT.Plan.Box(plan, item), shape = logged.shape })
end

function Preview.New(parent, compact)
    local self = setmetatable({ lines = {}, points = {}, compact = compact, yaw = -0.6, pitch = 0.55 }, Preview)
    self.frame = MHT.UI.Surface(parent, 490, 390, "window")
    self.frame:SetClipsChildren(true)
    self.originDot = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    MHT.Theme.Font(self.originDot, "title")
    self.originDot:SetText("●")
    self.originDot:SetTextColor(unpack(MHT.Theme.Colors.muted))
    self.frame:SetScript("OnSizeChanged", function() self:Draw() end)
    if compact then
        self.frame:EnableMouse(false)
        return self
    end
    self.frame:EnableMouse(true)
    self.frame:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            local x, y = GetCursorPosition()
            self.drag = { x = x, y = y, yaw = self.yaw, pitch = self.pitch }
            self.lastX, self.lastY = x, y
        end
    end)
    self.frame:SetScript("OnMouseUp", function() self.drag = nil end)
    self.frame:SetScript("OnHide", function() self.drag = nil end)
    self.frame:SetScript("OnUpdate", function()
        local drag = self.drag
        if not drag then return end
        local x, y = GetCursorPosition()
        if self.lastX == x and self.lastY == y then return end
        self.lastX, self.lastY = x, y
        self.yaw = drag.yaw + (x - drag.x) / 180
        self.pitch = math.max(0.15, math.min(1.4, drag.pitch + (y - drag.y) / 180))
        self:Draw()
    end)
    return self
end

-- With `points`, each item is drawn as a dot at its center.
function Preview:SetPlan(plan, points)
    self.plan, self.pointMode = plan, points
    self:Draw()
end

function Preview:Draw()
    for _, line in ipairs(self.lines) do line:Hide() end
    for _, point in ipairs(self.points) do point:Hide() end
    self.originDot:Hide()
    local plan = self.plan
    if not plan then return end
    local w, h = self.frame:GetWidth(), self.frame:GetHeight()
    if w < 32 or h < 32 then return end
    local c, s = math.cos(self.yaw), math.sin(self.yaw)
    local cp, sp = math.cos(self.pitch), math.sin(self.pitch)
    local function project(p)
        return { c * p[1] - s * p[2], sp * (s * p[1] + c * p[2]) + cp * p[3] }
    end

    local source = not self.compact and plan.source
    local items, low, high = {}, { math.huge, math.huge }, { -math.huge, -math.huge }
    -- Without a source item, keep the origin in view for its dot.
    if source then items[1] = source else low, high = { 0, 0 }, { 0, 0 } end
    for _, item in ipairs(plan.items) do items[#items + 1] = item end
    local function include(p)
        for a = 1, 2 do low[a], high[a] = math.min(low[a], p[a]), math.max(high[a], p[a]) end
    end
    local shapes = {}
    for _, item in ipairs(items) do
        local center = project({ item.x, item.y, item.z })
        local drawn = { center = center, edges = {}, source = item == source }
        include(center)
        if not self.pointMode then
            local vertices, edges = outline(plan, item)
            drawn.edges = edges or {}
            for _, vertex in ipairs(vertices or {}) do
                local offset = MHT.Rotation.Apply(item.rotation,
                    { x = vertex.x * item.scale, y = vertex.y * item.scale, z = vertex.z * item.scale })
                local p = project({ item.x + offset.x, item.y + offset.y, item.z + offset.z })
                drawn[#drawn + 1] = p
                include(p)
            end
        end
        shapes[#shapes + 1] = drawn
    end

    local margin = self.compact and 16 or 70
    local scale = math.min((w - margin) / math.max(0.01, high[1] - low[1]),
        (h - margin) / math.max(0.01, high[2] - low[2]))
    local function screen(p)
        return w / 2 + (p[1] - (low[1] + high[1]) / 2) * scale,
               h / 2 + (p[2] - (low[2] + high[2]) / 2) * scale
    end
    local color = MHT.Theme.Colors.preview
    local lineIndex = 0
    for i, drawn in ipairs(shapes) do
        local alpha = color[4] * (drawn.source and SOURCE_OPACITY or 1)
        if self.pointMode then
            local point = self.points[i]
            if not point then
                point = self.frame:CreateTexture(nil, "ARTWORK")
                point:SetSize(5, 5)
                self.points[i] = point
            end
            local x, y = screen(drawn.center)
            point:SetColorTexture(color[1], color[2], color[3], alpha)
            point:ClearAllPoints()
            point:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
            point:Show()
        else
            for _, edge in ipairs(drawn.edges) do
                lineIndex = lineIndex + 1
                local line = self.lines[lineIndex]
                if not line then
                    line = self.frame:CreateLine(nil, "ARTWORK")
                    line:SetThickness(1)
                    self.lines[lineIndex] = line
                end
                local x1, y1 = screen(drawn[edge[1]])
                local x2, y2 = screen(drawn[edge[2]])
                line:SetStartPoint("BOTTOMLEFT", self.frame, x1, y1)
                line:SetEndPoint("BOTTOMLEFT", self.frame, x2, y2)
                line:SetColorTexture(color[1], color[2], color[3], alpha)
                line:Show()
            end
        end
    end
    if self.compact or source then return end
    local x, y = screen(project({ 0, 0, 0 }))
    self.originDot:ClearAllPoints()
    self.originDot:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
    self.originDot:Show()
end
