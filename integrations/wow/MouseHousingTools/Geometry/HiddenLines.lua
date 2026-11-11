local _, MHT = ...
local HiddenLines = {}
MHT.HiddenLines = HiddenLines

-- The visible parts of convex shapes' edges, in screen space with depth growing toward the viewer.

local EPSILON, CELL, MIN_SEGMENT = 1e-5, 24, 0.25

local function edgeKey(a, b)
    return math.min(a, b) .. ":" .. math.max(a, b)
end

-- A face turned toward the viewer: its depth plane and the lines bounding it on screen.
local function frontFace(shape, indices)
    local points = shape.vertices
    local a, b, c = points[indices[1]], points[indices[2]], points[indices[3]]
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nz = ux * vy - uy * vx
    if nz <= 1e-8 then return end
    local face = { owner = shape, planes = {},
        minX = math.huge, minY = math.huge, maxX = -math.huge, maxY = -math.huge, maxZ = -math.huge }
    face.zx, face.zy = -(uy * vz - uz * vy) / nz, -(uz * vx - ux * vz) / nz
    face.zc = a[3] - face.zx * a[1] - face.zy * a[2]
    for i, index in ipairs(indices) do
        local p, q = points[index], points[indices[i % #indices + 1]]
        face.minX, face.minY = math.min(face.minX, p[1]), math.min(face.minY, p[2])
        face.maxX, face.maxY = math.max(face.maxX, p[1]), math.max(face.maxY, p[2])
        face.maxZ = math.max(face.maxZ, p[3])
        local dx, dy = q[1] - p[1], q[2] - p[2]
        local length = math.sqrt(dx * dx + dy * dy)
        if length > EPSILON then
            local nx, ny = -dy / length, dx / length
            face.planes[#face.planes + 1] = { nx, ny, -nx * p[1] - ny * p[2] }
        end
    end
    return face
end

-- The part of segment a-b inside a convex outline, as parameters 0..1.
local function inside(outline, a, b, margin)
    local first, last = 0, 1
    for _, plane in ipairs(outline.planes) do
        local value = plane[1] * a[1] + plane[2] * a[2] + plane[3] - margin
        local change = plane[1] * (b[1] - a[1]) + plane[2] * (b[2] - a[2])
        if math.abs(change) < 1e-10 then
            if value < 0 then return end
        elseif change > 0 then first = math.max(first, -value / change)
        else last = math.min(last, -value / change) end
        if first > last then return end
    end
    return first, last
end

-- A shape hides what lies behind its screen silhouette.
local function occluder(shape, front)
    local sorted, hull = {}, {}
    local result = { owner = shape, front = front, planes = {},
        minX = math.huge, minY = math.huge, maxX = -math.huge, maxY = -math.huge,
        minZ = math.huge, maxZ = -math.huge }
    for _, p in ipairs(shape.vertices) do
        sorted[#sorted + 1] = p
        result.minX, result.minY = math.min(result.minX, p[1]), math.min(result.minY, p[2])
        result.maxX, result.maxY = math.max(result.maxX, p[1]), math.max(result.maxY, p[2])
        result.minZ, result.maxZ = math.min(result.minZ, p[3]), math.max(result.maxZ, p[3])
    end
    table.sort(sorted, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
    local function cross(a, b, p) return (b[1] - a[1]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[1] - a[1]) end
    for _, p in ipairs(sorted) do
        while #hull >= 2 and cross(hull[#hull - 1], hull[#hull], p) <= 1e-10 do hull[#hull] = nil end
        hull[#hull + 1] = p
    end
    local lower = #hull
    for i = #sorted - 1, 1, -1 do
        local p = sorted[i]
        while #hull > lower and cross(hull[#hull - 1], hull[#hull], p) <= 1e-10 do hull[#hull] = nil end
        hull[#hull + 1] = p
    end
    hull[#hull] = nil
    for i, p in ipairs(hull) do
        local q = hull[i % #hull + 1]
        local dx, dy = q[1] - p[1], q[2] - p[2]
        local length = math.sqrt(dx * dx + dy * dy)
        if length > EPSILON then
            local nx, ny = -dy / length, dx / length
            result.planes[#result.planes + 1] = { nx, ny, -nx * p[1] - ny * p[2] }
        end
    end
    return result
end

local function occluded(item, a, b)
    local first, last = 0, 1
    for _, face in ipairs(item.front) do
        local za = face.zx * a[1] + face.zy * a[2] + face.zc - a[3]
        local zb = face.zx * b[1] + face.zy * b[2] + face.zc - b[3]
        if math.abs(za) <= EPSILON and math.abs(zb) <= EPSILON then
            local lo, hi = inside(face, a, b, EPSILON * 4)
            return lo, hi, true
        end
        local change = zb - za
        if math.abs(change) < 1e-10 then
            if za <= EPSILON then return end
        elseif change > 0 then first = math.max(first, (EPSILON - za) / change)
        else last = math.min(last, (EPSILON - za) / change) end
        if first >= last then return end
    end
    local lo, hi = inside(item, a, b, -EPSILON)
    if lo then
        first, last = math.max(first, lo), math.min(last, hi)
        if first < last then return first, last end
    end
end

local function clipViewport(a, b, width, height)
    local first, last = 0, 1
    for axis, limit in ipairs({ width, height }) do
        local delta = b[axis] - a[axis]
        if math.abs(delta) < 1e-10 then
            if a[axis] < 0 or a[axis] > limit then return end
        else
            local lo, hi = -a[axis] / delta, (limit - a[axis]) / delta
            if lo > hi then lo, hi = hi, lo end
            first, last = math.max(first, lo), math.min(last, hi)
            if first > last then return end
        end
    end
    return first, last
end

local function at(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Where two visible faces cut through each other: the line where their depth
-- planes agree, clipped to both faces.
local function intersection(left, right)
    if left.maxX < right.minX or left.minX > right.maxX or left.maxY < right.minY or left.minY > right.maxY then return end
    local nx, ny, offset = left.zx - right.zx, left.zy - right.zy, left.zc - right.zc
    local length = math.sqrt(nx * nx + ny * ny)
    if length < EPSILON then return end
    nx, ny, offset = nx / length, ny / length, offset / length
    local x, y = -offset * nx, -offset * ny
    local dx, dy, first, last = -ny, nx, -math.huge, math.huge
    for _, face in ipairs({ left, right }) do
        for _, plane in ipairs(face.planes) do
            local value = plane[1] * x + plane[2] * y + plane[3] - EPSILON * 4
            local change = plane[1] * dx + plane[2] * dy
            if math.abs(change) < 1e-10 then
                if value < -EPSILON then return end
            elseif change > 0 then first = math.max(first, -value / change)
            else last = math.min(last, -value / change) end
            if first >= last then return end
        end
    end
    if first == -math.huge or last == math.huge then return end
    local a, b = { x + first * dx, y + first * dy }, { x + last * dx, y + last * dy }
    a[3], b[3] = left.zx * a[1] + left.zy * a[2] + left.zc, left.zx * b[1] + left.zy * b[2] + left.zc
    return a, b
end

function HiddenLines.Visible(shapes, width, height)
    local grid, items, columns = {}, {}, math.max(1, math.ceil(width / CELL))
    local rows = math.max(1, math.ceil(height / CELL))
    local function cells(x1, y1, x2, y2)
        if x2 < 0 or y2 < 0 or x1 > width or y1 > height then return end
        return math.max(0, math.floor(x1 / CELL)), math.max(0, math.floor(y1 / CELL)),
            math.min(columns - 1, math.floor(x2 / CELL)), math.min(rows - 1, math.floor(y2 / CELL))
    end
    local frontEdges = {}
    for _, shape in ipairs(shapes) do
        local front, edges = {}, {}
        frontEdges[shape] = edges
        for _, indices in ipairs(shape.faces) do
            local face = frontFace(shape, indices)
            if face then
                front[#front + 1] = face
                for i, index in ipairs(indices) do edges[edgeKey(index, indices[i % #indices + 1])] = true end
            end
        end
        if #front > 0 then
            local item = occluder(shape, front)
            item.order = #items + 1
            items[#items + 1] = item
            local x1, y1, x2, y2 = cells(item.minX, item.minY, item.maxX, item.maxY)
            if x1 then
                for y = y1, y2 do for x = x1, x2 do
                    local key = y * columns + x + 1
                    grid[key] = grid[key] or {}
                    grid[key][#grid[key] + 1] = item
                end end
            end
        end
    end

    local result, seen, stamp = {}, {}, 0
    local function candidates(a, b, owner)
        local list = {}
        stamp = stamp + 1
        local minX, minY = math.min(a[1], b[1]), math.min(a[2], b[2])
        local maxX, maxY = math.max(a[1], b[1]), math.max(a[2], b[2])
        local minZ = math.min(a[3], b[3]) - EPSILON
        local x1, y1, x2, y2 = cells(minX, minY, maxX, maxY)
        if x1 then
            for y = y1, y2 do for x = x1, x2 do
                for _, item in ipairs(grid[y * columns + x + 1] or {}) do
                    if item.stamp ~= stamp then
                        item.stamp = stamp
                        if item.owner ~= owner and item.maxZ >= minZ
                            and item.minX <= maxX + EPSILON and item.maxX >= minX - EPSILON
                            and item.minY <= maxY + EPSILON and item.maxY >= minY - EPSILON then
                            list[#list + 1] = item
                        end
                    end
                end
            end end
        end
        return list
    end
    local function emit(a, b, first, last, owner, seam)
        if last - first < 1e-7 then return end
        local p, q = at(a, b, first), at(a, b, last)
        for _, point in ipairs({ p, q }) do
            point[1], point[2] = math.max(0, math.min(width, point[1])), math.max(0, math.min(height, point[2]))
        end
        if math.abs(q[1] - p[1]) + math.abs(q[2] - p[2]) < MIN_SEGMENT then return end
        -- Items placed on the same spot share edges; draw each edge once.
        local keyA = string.format("%.4f:%.4f:%.4f", p[1], p[2], p[3])
        local keyB = string.format("%.4f:%.4f:%.4f", q[1], q[2], q[3])
        local key = keyA < keyB and keyA .. "/" .. keyB or keyB .. "/" .. keyA
        if not seen[key] then
            seen[key] = true
            result[#result + 1] = { a = p, b = q, owner = owner, seam = seam }
        end
    end
    local function visible(a, b, owner, seam, other)
        local first, last = clipViewport(a, b, width, height)
        if not first then return end
        a, b = at(a, b, first), at(a, b, last)
        local remaining = { { 0, 1, seam } }
        local minimum = MIN_SEGMENT / math.max(MIN_SEGMENT, math.abs(b[1] - a[1]) + math.abs(b[2] - a[2]))
        for _, item in ipairs(candidates(a, b, owner)) do
            if item.owner ~= other then
                local lo, hi, surface = occluded(item, a, b)
                if lo then
                    for i = #remaining, 1, -1 do
                        local interval = remaining[i]
                        local start, finish = interval[1], interval[2]
                        local overlapStart, overlapEnd = math.max(start, lo), math.min(finish, hi)
                        if overlapStart < overlapEnd and (not surface or not interval[3]) then
                            table.remove(remaining, i)
                            if finish - overlapEnd > minimum then table.insert(remaining, i, { overlapEnd, finish, interval[3] }) end
                            if surface and overlapEnd - overlapStart > minimum then table.insert(remaining, i, { overlapStart, overlapEnd, true }) end
                            if overlapStart - start > minimum then table.insert(remaining, i, { start, overlapStart, interval[3] }) end
                        end
                    end
                    if #remaining == 0 then break end
                end
            end
        end
        for _, interval in ipairs(remaining) do emit(a, b, interval[1], interval[2], owner, interval[3]) end
    end
    for _, shape in ipairs(shapes) do
        for _, edge in ipairs(shape.edges) do
            if frontEdges[shape][edgeKey(edge[1], edge[2])] then
                visible(shape.vertices[edge[1]], shape.vertices[edge[2]], shape)
            end
        end
    end
    for _, item in ipairs(items) do
        local low, high = { item.minX, item.minY, item.minZ }, { item.maxX, item.maxY, item.maxZ }
        for _, other in ipairs(candidates(low, high, item.owner)) do
            if other.order > item.order and other.minZ <= item.maxZ + EPSILON then
                for _, left in ipairs(item.front) do
                    for _, right in ipairs(other.front) do
                        local a, b = intersection(left, right)
                        if a then visible(a, b, item.owner, true, other.owner) end
                    end
                end
            end
        end
    end
    return result
end
