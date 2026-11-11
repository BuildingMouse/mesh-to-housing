local _, MHT = ...
local Theme = {}
MHT.Theme = Theme

Theme.Colors = {
    gold = { 1, 0.827, 0.125, 1 }, subtle = { 0.443, 0.545, 0.608, 0.16 },
    text = { 0.906, 0.925, 0.925, 1 }, muted = { 0.596, 0.663, 0.682, 1 },
    rail = { 0.30, 0.32, 0.34, 0.75 },
    preview = { 0.58, 0.71, 0.79, 0.92 },
}

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FONTS = {
    title = { FONT, 21 }, heading = { FONT, 16 }, label = { FONT, 14 },
    value = { FONT, 13 }, secondary = { FONT, 12 },
}

function Theme.Font(widget, role)
    local font = FONTS[role]
    widget:SetFont(font[1], font[2], "")
end

local GOLD = Theme.Colors.gold
local EDGE, SUBTLE, CLEAR = { 0.443, 0.545, 0.608, 0.28 }, { 0.443, 0.545, 0.608, 0.16 }, { 0, 0, 0, 0 }
local CONTROL, HOVER, ACTIVE = { 0.155, 0.165, 0.175, 0.92 }, { 0.240, 0.250, 0.260, 0.97 }, { 0.205, 0.215, 0.225, 0.97 }
local DEEP, DISABLED = { 0.020, 0.055, 0.090, 0.42 }, { 0.12, 0.13, 0.14, 0.72 }
local SKINS = {
    window = { { 0.04, 0.085, 0.13, 0.94 }, { 0.443, 0.545, 0.608, 0.42 } },
    panel = { { 0.06, 0.115, 0.17, 0.48 }, SUBTLE }, deep = { DEEP, SUBTLE },
    settings = { { 0.06, 0.115, 0.17, 0.72 }, CLEAR }, footer = { { 0.055, 0.10, 0.14, 0.85 }, CLEAR },
    menu = { { 0.06, 0.115, 0.17, 0.96 }, SUBTLE },
    button = { CONTROL, EDGE }, buttonHover = { HOVER, EDGE }, buttonDown = { ACTIVE, EDGE },
    primary = { { 0.40, 0.33, 0.16, 0.97 }, { 0.85, 0.69, 0.27, 0.9 } },
    primaryHover = { { 0.48, 0.40, 0.20, 0.97 }, GOLD }, primaryDown = { { 0.34, 0.28, 0.13, 0.97 }, GOLD },
    selected = { ACTIVE, GOLD }, selectedHover = { HOVER, GOLD },
    disabled = { DISABLED, { 0.28, 0.30, 0.32, 0.40 } }, disabledSelected = { DISABLED, GOLD },
    tab = { { 0.11, 0.14, 0.17, 0.94 }, CLEAR }, tabHover = { { 0.16, 0.20, 0.23, 0.97 }, CLEAR },
    tabDown = { { 0.14, 0.18, 0.21, 0.97 }, CLEAR }, tabDisabled = { { 0.09, 0.12, 0.14, 0.85 }, CLEAR },
    tabSelected = { { 0.15, 0.19, 0.22, 0.97 }, GOLD }, tabSelectedHover = { { 0.18, 0.22, 0.25, 0.97 }, GOLD },
    tabSelectedDown = { { 0.14, 0.18, 0.21, 0.97 }, GOLD }, tabDisabledSelected = { { 0.15, 0.19, 0.22, 0.97 }, GOLD },
    input = { DEEP, { 0.443, 0.545, 0.608, 0.12 } }, inputFocus = { DEEP, GOLD },
    inputDisabled = { { 0.015, 0.035, 0.055, 0.80 }, { 0.443, 0.545, 0.608, 0.06 } },
    scrollRail = { { 0.30, 0.32, 0.34, 0.35 }, CLEAR }, scrollThumb = { { 0.443, 0.545, 0.608, 0.42 }, CLEAR },
    scrollThumbHover = { GOLD, CLEAR },
}

function Theme.Skin(frame, name)
    if frame.skinName == name and frame.skinned then return end
    frame.skinName, frame.skinned = name, true
    local colors = name and SKINS[name]
    if not colors then frame:SetBackdrop(nil); return end
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(unpack(colors[1]))
    frame:SetBackdropBorderColor(unpack(colors[2]))
end

-- Keeps thin or scaled textures from shimmering as they move.
function Theme.Unsnapped(texture)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
end

local ICONS = {
    close = "Interface\\Buttons\\UI-StopButton",
    check = "Interface\\Buttons\\UI-CheckBox-Check",
    reset = "Interface\\Buttons\\UI-RefreshButton",
    down = "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up",
    up = "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up",
    right = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
}

function Theme.Icon(parent, name, size, x, y)
    local icon = parent:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("CENTER", parent, "CENTER", x or 0, y or 0)
    icon:SetSize(size, size)
    Theme.Unsnapped(icon)
    function icon:SetShape(value) self:SetTexture(ICONS[value]) end
    icon:SetShape(name)
    icon:SetDesaturated(true)
    icon:SetVertexColor(unpack(Theme.Colors.muted))
    return icon
end

local LOGO = "Interface\\AddOns\\MouseHousingTools\\Media\\Logo.tga"

function Theme.Logo(parent, x, y, size)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(LOGO)
    texture:SetPoint("TOPLEFT", x, -y)
    texture:SetSize(size, size)
    return texture
end
