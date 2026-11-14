local _, MHT = ...
local Rooms = {}
MHT.Rooms = Rooms

-- Room sizes for the preview.

local TINY_WIDTH, TINY_DEPTH, TINY_HEIGHT = 12, 12, 12
local FLOOR_GRID = 2

Rooms.DEFAULT_ID = "small"
Rooms.Entries = {
    { id = "tiny", name = "Tiny", width = TINY_WIDTH, depth = TINY_DEPTH, height = TINY_HEIGHT },
    { id = "small", name = "Small", width = TINY_WIDTH * 2, depth = TINY_DEPTH * 2, height = TINY_HEIGHT },
    { id = "medium", name = "Medium", width = TINY_WIDTH * 3, depth = TINY_DEPTH * 3, height = TINY_HEIGHT },
    { id = "large", name = "Large", width = TINY_WIDTH * 4, depth = TINY_DEPTH * 4, height = TINY_HEIGHT },
}

function Rooms.Get(id)
    for _, room in ipairs(Rooms.Entries) do
        if room.id == id then return room end
    end
end

-- Only the walls on the far side are drawn.
function Rooms.Lines(room, center, floor, yaw)
    local x1, x2 = center[1] - room.width / 2, center[1] + room.width / 2
    local y1, y2 = center[2] - room.depth / 2, center[2] + room.depth / 2
    local ceiling = floor + room.height
    local lines = {}
    local function line(a, b, style) lines[#lines + 1] = { a = a, b = b, style = style } end

    local corners = { { x1, y1 }, { x2, y1 }, { x2, y2 }, { x1, y2 } }
    for i, p in ipairs(corners) do
        local q = corners[i % 4 + 1]
        line({ p[1], p[2], floor }, { q[1], q[2], floor }, "outline")
    end
    for x = x1 + FLOOR_GRID, x2 - FLOOR_GRID / 2, FLOOR_GRID do line({ x, y1, floor }, { x, y2, floor }, "grid") end
    for y = y1 + FLOOR_GRID, y2 - FLOOR_GRID / 2, FLOOR_GRID do line({ x1, y, floor }, { x2, y, floor }, "grid") end

    local farX, nearX = x2, x1
    local farY, nearY = y2, y1
    if math.sin(yaw) < 0 then farX, nearX = x1, x2 end
    if math.cos(yaw) < 0 then farY, nearY = y1, y2 end
    for _, p in ipairs({ { farX, nearY }, { farX, farY }, { nearX, farY } }) do
        line({ p[1], p[2], floor }, { p[1], p[2], ceiling }, "wall")
    end
    line({ farX, nearY, ceiling }, { farX, farY, ceiling }, "wall")
    line({ farX, farY, ceiling }, { nearX, farY, ceiling }, "wall")
    return lines
end
