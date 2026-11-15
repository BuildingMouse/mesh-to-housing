local _, MHT = ...
local Theme = {}
MHT.Theme = Theme

Theme.Colors = {
    gold = { 1, 0.827, 0.125, 1 }, subtle = { 0.443, 0.545, 0.608, 0.16 },
    heading = { 1, 1, 1, 1 }, text = { 0.906, 0.925, 0.925, 1 }, muted = { 0.596, 0.663, 0.682, 1 },
    rail = { 0.30, 0.32, 0.34, 0.75 },
    preview = { 0.58, 0.71, 0.79, 0.92 },
    placing = { 0.90, 0.79, 0.38, 1 }, room = { 0.46, 0.57, 0.64, 1 },
}

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONTS = {
    title = { FONT, 21 }, heading = { FONT, 17 }, label = { FONT, 14 },
    value = { FONT, 13 }, secondary = { FONT, 12 },
}

function Theme.Font(widget, role)
    local font = FONTS[role]
    widget:SetFont(font[1], font[2], "")
end

local MEDIA = "Interface\\AddOns\\MouseHousingTools\\Media\\"

-- Keeps thin or scaled textures from shimmering as they move.
function Theme.Unsnapped(texture)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
end

local PANEL = { size = 64, border = 16, inset = 8 }
local CONTROL = { size = 64, border = 8, inset = 4 }
local SCROLL = { size = 64, border = 8, inset = 4, vertical = true }
local SKINS = {
    window = PANEL, panel = PANEL, deep = PANEL, settings = PANEL, footer = PANEL,
    menu = CONTROL, button = CONTROL, buttonHover = CONTROL, buttonDown = CONTROL,
    primary = CONTROL, primaryHover = CONTROL, primaryDown = CONTROL,
    selected = CONTROL, selectedHover = CONTROL, disabled = CONTROL, disabledSelected = CONTROL,
    tab = CONTROL, tabHover = CONTROL, tabDown = CONTROL, tabDisabled = CONTROL,
    tabSelected = CONTROL, tabSelectedHover = CONTROL, tabSelectedDown = CONTROL, tabDisabledSelected = CONTROL,
    input = CONTROL, inputFocus = CONTROL, inputDisabled = CONTROL, check = CONTROL,
    scrollRail = SCROLL, scrollThumb = SCROLL, scrollThumbHover = SCROLL,
}

local function layout(frame, skin)
    local slices = skin.slices
    local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
    local cap = slices and math.min(slices.inset, w / 2, h / 2) or 0
    local cut = slices and slices.border / slices.size or 0
    local xs, ys, uv = { 0, cap, w - cap, w }, { 0, cap, h - cap, h }, { 0, cut, 1 - cut, 1 }
    local vertical = slices and slices.vertical
    local count = slices and (vertical and 3 or 9) or 0
    for i, piece in ipairs(skin.pieces) do
        local row = vertical and i or math.floor((i - 1) / 3) + 1
        local column = vertical and 1 or (i - 1) % 3 + 1
        local x, width = vertical and 0 or xs[column], vertical and w or xs[column + 1] - xs[column]
        local height = i <= count and ys[row + 1] - ys[row] or 0
        piece:SetShown(width > 0 and height > 0)
        if height > 0 then
            piece:ClearAllPoints()
            piece:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -ys[row])
            piece:SetSize(width, height)
            piece:SetTexCoord(vertical and 0 or uv[column], vertical and 1 or uv[column + 1], uv[row], uv[row + 1])
        end
    end
end

function Theme.Skin(frame, name)
    local skin = frame.skin
    if not skin then
        skin = { pieces = {} }
        frame.skin = skin
        frame:HookScript("OnSizeChanged", function() layout(frame, skin) end)
    elseif skin.name == name then
        return
    end
    skin.name, skin.slices = name, name and SKINS[name]
    for i = 1, skin.slices and (skin.slices.vertical and 3 or 9) or 0 do
        if not skin.pieces[i] then
            skin.pieces[i] = frame:CreateTexture(nil, "BACKGROUND")
            Theme.Unsnapped(skin.pieces[i])
        end
        skin.pieces[i]:SetTexture(MEDIA .. "Skins\\" .. name .. ".tga")
    end
    layout(frame, skin)
end

local BAR_LENGTH, BAR_TEXTURE, BAR_END = 32, 64, 3

function Theme.BarPieces(bar)
    local pieces = {}
    for i = 1, 3 do
        pieces[i] = bar:CreateTexture(nil, "BACKGROUND")
        Theme.Unsnapped(pieces[i])
        pieces[i]:SetTexture(MEDIA .. "Bar.tga")
    end
    return pieces
end

function Theme.LayoutBar(pieces, width, shown)
    local spans = { math.min(shown, BAR_END), math.max(0, math.min(shown, width - BAR_END) - BAR_END),
        math.max(0, shown - (width - BAR_END)) }
    local starts = { 0, BAR_END, BAR_LENGTH - BAR_END }
    local x = 0
    for i, piece in ipairs(pieces) do
        local span = spans[i]
        piece:SetShown(span > 0)
        if span > 0 then
            local u = starts[i] * 2 / BAR_TEXTURE
            local length = i == 2 and BAR_LENGTH - 2 * BAR_END or span
            piece:ClearAllPoints()
            piece:SetPoint("TOPLEFT", x, 0)
            piece:SetSize(span, 6)
            piece:SetTexCoord(u, u + length * 2 / BAR_TEXTURE, 0, 12 / 16)
        end
        x = x + span
    end
end

Theme.THUMB = MEDIA .. "Thumb.tga"

-- Icons are white, so they can take any color.
function Theme.Icon(parent, name, size, x, y)
    local icon = parent:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("CENTER", parent, "CENTER", x or 0, y or 0)
    icon:SetSize(size, size)
    Theme.Unsnapped(icon)
    function icon:SetShape(value) self:SetTexture(MEDIA .. "Icons\\" .. value .. ".tga") end
    icon:SetShape(name)
    icon:SetVertexColor(unpack(Theme.Colors.muted))
    return icon
end

function Theme.Logo(parent, x, y, size)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(MEDIA .. "Logo.tga")
    texture:SetPoint("TOPLEFT", x, -y)
    texture:SetSize(size, size)
    return texture
end
