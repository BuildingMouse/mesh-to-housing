local _, MHT = ...
local Preview = {}
Preview.__index = Preview
MHT.Preview = Preview

-- Draws a plan's items as outlines (or points) in a turnable 3D view.

local SOURCE_OPACITY, SEAM_OPACITY = 0.12, 0.3
local PILE_DOT = 10
local MIN_ZOOM, MAX_ZOOM = 0.2, 8

-- Each kind of plan starts from its own angle.
local VIEWS = {
    stairs = { yaw = -0.80, pitch = 0.25, coverage = 0.65, x = 0.50, y = 0.45 },
    curveRight = { yaw = -0.15, pitch = 0.30, coverage = 0.65, x = 0.50, y = 0.45 },
    curveLeft = { yaw = 0.15, pitch = 0.30, coverage = 0.65, x = 0.50, y = 0.45 },
    circle = { yaw = 0, pitch = 0.45, coverage = 0.52, x = 0.50, y = 0.42 },
    vertical = { yaw = -0.20, pitch = 0.30, coverage = 0.65, x = 0.50, y = 0.42 },
    model = { yaw = -0.60, pitch = 0.55, coverage = 0.72, x = 0.50, y = 0.50 },
}
VIEWS.sketch, VIEWS.sculpt = VIEWS.model, VIEWS.model

local ROOM_LINES = {
    outline = { room = true, opacity = 0.22 },
    grid = { room = true, opacity = 0.07 },
    wall = { room = true, opacity = 0.16 },
    arrow = { room = true, opacity = 0.22 },
}

-- How previews look during the build
local ITEM_LOOKS = {
    placing = { color = "placing", thickness = 2.5, opacity = 1, seams = 1, dot = 8 },
    built = { color = "preview", thickness = 1.5, opacity = 1, seams = SEAM_OPACITY, dot = 6 },
    waiting = { color = "preview", thickness = 1, opacity = 0.55, seams = SEAM_OPACITY, dot = 5 },
}

-- The item's outline from Items; placements of other items use their logged shape.
local function outline(plan, item)
    local logged = item.item and MHT.ItemProfiles.Logged(item.item) or {}
    return MHT.ItemProfiles.Outline({ dimensions = MHT.Plan.Box(plan, item), shape = logged.shape })
end

function Preview.New(parent, compact)
    local self = setmetatable({ lines = {}, points = {}, compact = compact }, Preview)
    self.frame = MHT.UI.Surface(parent, 490, 390, "window")
    self.frame:SetClipsChildren(true)
    self.originDot = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    MHT.Theme.Font(self.originDot, "title")
    self.originDot:SetText("●")
    self.originDot:SetTextColor(unpack(MHT.Theme.Colors.muted))
    self.frame:SetScript("OnSizeChanged", function() self.framing = nil; self:Draw() end)
    self:ResetView()
    if compact then
        self.frame:EnableMouse(false)
        return self
    end
    self.frame:EnableMouse(true)
    self.frame:EnableMouseWheel(true)
    self.frame:SetScript("OnMouseWheel", function(_, delta) self:Zoom(delta > 0 and 1.1 or 1 / 1.1) end)
    self.frame:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        local x, y = GetCursorPosition()
        self.drag = { x = x, y = y, yaw = self.yaw, pitch = self.pitch, panX = self.panX, panY = self.panY,
            pan = button == "RightButton" }
        self.lastX, self.lastY = x, y
    end)
    self.frame:SetScript("OnMouseUp", function() self.drag = nil end)
    self.frame:SetScript("OnHide", function() self.drag = nil end)
    self.frame:SetScript("OnUpdate", function()
        local drag = self.drag
        if not drag then return end
        local x, y = GetCursorPosition()
        if self.lastX == x and self.lastY == y then return end
        self.lastX, self.lastY = x, y
        if drag.pan then
            local scale = self.frame:GetEffectiveScale()
            self.panX, self.panY = drag.panX + (x - drag.x) / scale, drag.panY + (y - drag.y) / scale
        else
            self.yaw = drag.yaw + (x - drag.x) / 180
            self.pitch = math.max(0.15, math.min(1.4, drag.pitch + (y - drag.y) / 180))
        end
        self:Draw()
    end)
    return self
end

function Preview:View()
    return not self.compact and VIEWS[self.view] or VIEWS.model
end

function Preview:Center(w, h)
    if self.compact then return w / 2, h / 2 end
    local view = self:View()
    return w * view.x, h * view.y
end

function Preview:ResetView()
    local view = self:View()
    self.yaw, self.pitch, self.zoom, self.panX, self.panY, self.drag = view.yaw, view.pitch, 1, 0, 0, nil
    self.framing = nil
    self:Draw()
end

-- Zooms toward the cursor.
function Preview:Zoom(factor)
    local previous = self.zoom
    self.zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, self.zoom * factor))
    local left, bottom = self.frame:GetLeft(), self.frame:GetBottom()
    if left and bottom then
        local scale = self.frame:GetEffectiveScale()
        local x, y = GetCursorPosition()
        local centerX, centerY = self:Center(self.frame:GetWidth(), self.frame:GetHeight())
        x, y = x / scale - left - centerX, y / scale - bottom - centerY
        local ratio = self.zoom / previous
        self.panX, self.panY = x - (x - self.panX) * ratio, y - (y - self.panY) * ratio
    end
    self:Draw()
end

function Preview:SetPlan(plan, points, view)
    local changed = view ~= self.view
    self.plan, self.pointMode, self.view = plan, points, view
    if changed then self:ResetView() else self:Draw() end
end

function Preview:SetRoom(id)
    self.roomID = id
    self:Draw()
end

function Preview:SetItemLooks(looks)
    local previous = self.itemLooks or {}
    local changed = #looks ~= #previous
    for index, look in ipairs(looks) do changed = changed or previous[index] ~= look end
    self.itemLooks = looks
    if changed then self:Draw() end
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
    -- Screen X and Y, and depth toward the viewer.
    local function project(p)
        local along = s * p[1] + c * p[2]
        return { c * p[1] - s * p[2], sp * along + cp * p[3], -cp * along + sp * p[3] }
    end

    local source = not self.compact and plan.source
    local looks = {}
    for index, look in ipairs(self.itemLooks or {}) do
        if plan.items[index] then looks[plan.items[index]] = ITEM_LOOKS[look] end
    end
    local items, low, high = {}, { math.huge, math.huge }, { -math.huge, -math.huge }
    -- Without a source item, keep the origin in view for its dot.
    if source then items[1] = source else low, high = { 0, 0 }, { 0, 0 } end
    for _, item in ipairs(plan.items) do items[#items + 1] = item end
    local world = { low = { math.huge, math.huge, math.huge }, high = { -math.huge, -math.huge, -math.huge } }
    local span = source and { low = { math.huge, math.huge, math.huge }, high = { -math.huge, -math.huge, -math.huge } }
        or { low = { 0, 0, 0 }, high = { 0, 0, 0 } }
    -- The room is placed around the plan's items, without the source.
    local function include(vertex, p, isSource)
        for a = 1, 2 do low[a], high[a] = math.min(low[a], p[a]), math.max(high[a], p[a]) end
        for a = 1, 3 do
            span.low[a], span.high[a] = math.min(span.low[a], vertex[a]), math.max(span.high[a], vertex[a])
        end
        if isSource then return end
        for a = 1, 3 do
            world.low[a], world.high[a] = math.min(world.low[a], vertex[a]), math.max(world.high[a], vertex[a])
        end
    end
    local shapes, floor = {}, nil
    for _, item in ipairs(items) do
        local center = { item.x, item.y, item.z }
        local drawn = { center = project(center), source = item == source, look = looks[item], scale = item.scale }
        include(center, drawn.center, drawn.source)
        if not self.pointMode then
            local vertices, edges, faces = outline(plan, item)
            drawn.edges, drawn.faces = edges, faces
            for _, vertex in ipairs(vertices or {}) do
                local offset = MHT.Rotation.Apply(item.rotation,
                    { x = vertex.x * item.scale, y = vertex.y * item.scale, z = vertex.z * item.scale })
                local point = { item.x + offset.x, item.y + offset.y, item.z + offset.z }
                local p = project(point)
                drawn[#drawn + 1] = p
                include(point, p, drawn.source)
                if item == source then floor = math.min(floor or math.huge, point[3]) end
            end
        end
        shapes[#shapes + 1] = drawn
    end

    local framing = not self.compact and self.framing
    if not framing then
        local view = self:View()
        local width = self.compact and w - 16 or w * view.coverage
        local height = self.compact and h - 16 or h * view.coverage
        local center = { (span.low[1] + span.high[1]) / 2, (span.low[2] + span.high[2]) / 2,
            (span.low[3] + span.high[3]) / 2 }
        local projected = project(center)
        -- The room is placed with the framing, so changing settings moves only the items.
        framing = { center = center,
            scale = math.min(width / math.max(0.01, high[1] - low[1]), height / math.max(0.01, high[2] - low[2])),
            shift = { (low[1] + high[1]) / 2 - projected[1], (low[2] + high[2]) / 2 - projected[2] },
            floor = floor or source and source.z or world.low[3],
            middle = #plan.items > 0
                and { (world.low[1] + world.high[1]) / 2, (world.low[2] + world.high[2]) / 2 } or { 0, 0 } }
        if not self.compact then self.framing = framing end
    end
    local scale = framing.scale * self.zoom
    local focus = project(framing.center)
    local centerX, centerY = self:Center(w, h)
    local function screen(p)
        return centerX + (p[1] - focus[1] - framing.shift[1]) * scale + self.panX,
               centerY + (p[2] - focus[2] - framing.shift[2]) * scale + self.panY
    end
    local function toScreen(vertex)
        local p = project(vertex)
        local x, y = screen(p)
        return { x, y, p[3] * scale }
    end

    local extra = {}
    local room = not self.compact and MHT.Rooms.Get(self.roomID)
    floor = framing.floor
    if room then
        for _, line in ipairs(MHT.Rooms.Lines(room, framing.middle, floor, self.yaw)) do
            extra[#extra + 1] = { a = toScreen(line.a), b = toScreen(line.b), owner = ROOM_LINES[line.style] }
        end
    end
    if not self.compact and plan.dimensions then
        -- An arrow on the floor in front of the start shows which way is forward.
        local d = plan.dimensions
        local size = math.min(d[1], d[2]) * 0.45
        -- In point mode the arrow's tip touches the pile's point.
        local y = self.pointMode and -size / 2 or -d[2] / 2 - size * 0.75 - 0.05
        local z = floor + 0.002
        local tail, tip = { 0, y - size / 2, z }, { 0, y + size / 2, z }
        local back = tip[2] - size * 0.22
        for _, line in ipairs({ { tail, tip }, { tip, { -size * 0.18, back, z } }, { tip, { size * 0.18, back, z } } }) do
            extra[#extra + 1] = { a = toScreen(line[1]), b = toScreen(line[2]), owner = ROOM_LINES.arrow }
        end
    end

    local colors = MHT.Theme.Colors
    local outlines = {}
    if self.pointMode then
        for i, drawn in ipairs(shapes) do
            local point = self.points[i]
            if not point then
                point = self.frame:CreateTexture(nil, "ARTWORK")
                self.points[i] = point
            end
            local x, y = screen(drawn.center)
            local look = drawn.look
            local color = look and colors[look.color] or colors.preview
            local opacity = drawn.source and SOURCE_OPACITY or look and look.opacity or 1
            -- Item size shows gently on points; placement still uses the exact scale.
            local factor = math.max(0.6, math.min(1.5, 1 + (drawn.scale - 1) * 0.5))
            local size = drawn.source and PILE_DOT or (look and look.dot or 5) * factor
            point:SetSize(size, size)
            point:SetColorTexture(color[1], color[2], color[3], color[4] * opacity)
            point:ClearAllPoints()
            point:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
            point:Show()
        end
    else
        for _, drawn in ipairs(shapes) do
            if drawn.faces then
                local vertices = {}
                for i, p in ipairs(drawn) do
                    local x, y = screen(p)
                    vertices[i] = { x, y, p[3] * scale }
                end
                outlines[#outlines + 1] = { vertices = vertices, faces = drawn.faces, edges = drawn.edges,
                    source = drawn.source, look = drawn.look, seeThrough = drawn.source }
            end
        end
    end
    for index, segment in ipairs(MHT.HiddenLines.Visible(outlines, w, h, extra)) do
        local line = self.lines[index]
        if not line then
            line = self.frame:CreateLine(nil, "ARTWORK")
            self.lines[index] = line
        end
        local owner, look = segment.owner, segment.owner.look
        local color = owner.room and colors.room or look and colors[look.color] or colors.preview
        local opacity = owner.room and owner.opacity or owner.source and SOURCE_OPACITY or look and look.opacity or 1
        if segment.seam then opacity = opacity * (look and look.seams or SEAM_OPACITY) end
        line:SetStartPoint("BOTTOMLEFT", self.frame, segment.a[1], segment.a[2])
        line:SetEndPoint("BOTTOMLEFT", self.frame, segment.b[1], segment.b[2])
        line:SetThickness(look and look.thickness or (owner.room or segment.seam) and 0.75 or 1)
        line:SetColorTexture(color[1], color[2], color[3], color[4] * opacity)
        line:Show()
    end
    if self.compact or source or room then return end
    local x, y = screen(project({ 0, 0, 0 }))
    self.originDot:ClearAllPoints()
    self.originDot:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
    self.originDot:Show()
end
