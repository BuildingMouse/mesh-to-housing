local _, MHT = ...
local UI = {}
MHT.UI = UI
local Theme = MHT.Theme
local Colors = Theme.Colors

function UI.Surface(parent, width, height, skin)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    Theme.Skin(frame, skin or "panel")
    return frame
end

function UI.Text(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, -y)
    if width then label:SetWidth(width) end
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetText(text)
    label:SetTextColor(unpack(Colors.text))
    Theme.Font(label, font == "GameFontNormalLarge" and "title" or font == "GameFontNormal" and "heading" or "label")
    return label
end

function UI.Heading(parent, text, x, y, width)
    local label = UI.Text(parent, text, x, y, width, "GameFontNormal")
    label:SetTextColor(unpack(Colors.heading))
    return label
end

function UI.Muted(parent, text, x, y, width)
    local label = UI.Text(parent, text, x, y, width)
    Theme.Font(label, "secondary")
    label:SetTextColor(unpack(Colors.muted))
    return label
end

function UI.Rule(parent, y, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 0, -y)
    line:SetSize(width, 1)
    line:SetColorTexture(unpack(Colors.subtle))
    return line
end

function UI.Tooltip(widget, title, description)
    widget:HookScript("OnEnter", function()
        GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
        local text, muted = Colors.text, Colors.muted
        GameTooltip:SetText(title, text[1], text[2], text[3])
        if description then GameTooltip:AddLine(description, muted[1], muted[2], muted[3], true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.Bar(parent, width, color)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width, 6)
    local pieces = Theme.BarPieces(bar)
    for _, piece in ipairs(pieces) do piece:SetVertexColor(unpack(color)) end
    local function draw()
        local shown = width * bar.fraction
        bar:SetWidth(math.max(0.01, shown))
        Theme.LayoutBar(pieces, width, shown)
    end
    function bar:SetFraction(portion)
        self.fraction = math.max(0, math.min(1, portion))
        draw()
        self:SetShown(self.fraction > 0)
    end
    function bar:SetLength(value)
        width = value
        draw()
    end
    bar:SetFraction(1)
    return bar
end

function UI.ResizeGrip(frame, onResized)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    local lines = {}
    for i = 1, 3 do
        local line = grip:CreateLine(nil, "OVERLAY")
        line:SetStartPoint("BOTTOMRIGHT", grip, -2 - i * 3, 2)
        line:SetEndPoint("BOTTOMRIGHT", grip, -2, 2 + i * 3)
        line:SetThickness(1.5)
        lines[i] = line
    end
    local function paint(color)
        for _, line in ipairs(lines) do line:SetColorTexture(unpack(color)) end
    end
    grip:SetScript("OnEnter", function() paint(Colors.gold) end)
    grip:SetScript("OnLeave", function() paint(Colors.muted) end)
    local start
    local function stop()
        if not start then return end
        start = nil
        grip:SetScript("OnUpdate", nil)
        onResized()
    end
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        local x, y = GetCursorPosition()
        start = { x = x, y = y, left = frame:GetLeft(), top = frame:GetTop(),
            width = frame:GetWidth(), height = frame:GetHeight(), scale = frame:GetEffectiveScale() }
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", start.left, start.top)
        grip:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then stop(); return end
            local cursorX, cursorY = GetCursorPosition()
            local minWidth, minHeight = frame:GetResizeBounds()
            local screenWidth = UIParent:GetWidth() * UIParent:GetEffectiveScale() / start.scale
            local width = start.width + (cursorX - start.x) / start.scale
            local height = start.height - (cursorY - start.y) / start.scale
            frame:SetSize(math.max(minWidth, math.min(width, screenWidth - start.left)),
                math.max(minHeight, math.min(height, start.top)))
        end)
    end)
    grip:SetScript("OnMouseUp", stop)
    grip:SetScript("OnHide", stop)
    paint(Colors.muted)
    return grip
end

-- Buttons

local function buttonLook(button, style)
    local selected, hovered, pressed = button.selected, button.hovered, button.pressed
    if button:IsEnabled() == false then
        local skin = style == "tab" and (selected and "tabDisabledSelected" or "tabDisabled")
            or style ~= "disclosure" and (selected and "disabledSelected" or "disabled") or nil
        return skin, selected and Colors.gold or Colors.muted
    end
    if style == "tab" then
        local base = selected and "tabSelected" or "tab"
        return pressed and base .. "Down" or hovered and base .. "Hover" or base,
            selected and Colors.gold or hovered and Colors.text or Colors.muted
    elseif style == "disclosure" then
        return nil, hovered and Colors.text or Colors.muted
    elseif style == "icon" then
        if not hovered then return nil, Colors.muted end
        return pressed and "buttonDown" or "buttonHover", Colors.gold
    elseif style == "primary" then
        return pressed and "primaryDown" or hovered and "primaryHover" or "primary", Colors.text
    elseif selected then
        return hovered and not pressed and "selectedHover" or "selected", Colors.gold
    end
    return pressed and "buttonDown" or hovered and "buttonHover" or "button", Colors.text
end

function UI.Button(parent, text, x, y, width, onClick, style, height)
    height = height or 28
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(width, height)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Theme.Font(label, height < 30 and "value" or "label")
    label:SetAllPoints(button)
    label:SetJustifyH("CENTER")
    button:SetFontString(label)
    button:SetText(text)
    button.label = label
    local function paint()
        local disabled = button:IsEnabled() == false
        local skin, color = buttonLook(button, style)
        Theme.Skin(button, skin)
        label:SetAlpha(style == "disclosure" and disabled and 0.45 or 1)
        label:SetTextColor(unpack(color))
        if button.icon then
            local iconColor = disabled and color or (button.hovered or button.expanded) and Colors.gold or Colors.muted
            button.icon:SetVertexColor(unpack(iconColor))
        end
    end
    function button:SetSelected(selected) self.selected = selected; paint() end
    button.Repaint = paint
    button:SetScript("OnEnter", function() button.hovered = true; paint() end)
    button:SetScript("OnLeave", function() button.hovered, button.pressed = false, false; paint() end)
    button:SetScript("OnMouseDown", function() button.pressed = true; paint() end)
    button:SetScript("OnMouseUp", function() button.pressed = false; paint() end)
    button:SetScript("OnEnable", paint)
    button:SetScript("OnDisable", function() button.hovered, button.pressed = false, false; paint() end)
    button:SetScript("OnClick", onClick)
    paint()
    return button
end

function UI.IconButton(parent, icon, x, y, size, iconSize, onClick)
    local button = UI.Button(parent, "", x, y, size, onClick, "icon", size)
    button.label:Hide()
    button.icon = Theme.Icon(button, icon, iconSize)
    button:Repaint()
    return button
end

function UI.ResetButton(parent, x, y, onClick)
    return UI.IconButton(parent, "reset", x, y, 24, 16, onClick)
end

function UI.CloseButton(parent, x, y, size, onClick)
    local button = UI.IconButton(parent, "close", x, y, size, math.min(10, size * 0.4), onClick)
    UI.Tooltip(button, "Close")
    return button
end

-- Text inputs

local function paintInput(edit, background)
    local function paint()
        local enabled = edit:IsEnabled() ~= false
        local focused = enabled and edit:HasFocus()
        Theme.Skin(background, not enabled and "inputDisabled" or focused and "inputFocus" or "input")
        edit:SetAlpha(enabled and 1 or 0.45)
        if edit.label then edit.label:SetAlpha(enabled and 1 or 0.45) end
        edit:SetTextColor(unpack(focused and Colors.text or Colors.muted))
    end
    local setEnabled = edit.SetEnabled
    function edit:SetEnabled(enabled) setEnabled(self, enabled); paint() end
    edit:HookScript("OnEditFocusGained", paint)
    edit:HookScript("OnEditFocusLost", paint)
    paint()
end

function UI.StyleInput(edit, width, height)
    height = height or 26
    if edit.background then
        edit:SetSize(width, height)
        edit.background:SetSize(width, height)
        return
    end
    for _, region in ipairs({ edit:GetRegions() }) do
        if region:GetObjectType() == "Texture" then region:Hide() end
    end
    local background = UI.Surface(edit, width, height, "input")
    background:SetPoint("TOPLEFT", 0, 0)
    background:SetFrameLevel(math.max(0, edit:GetFrameLevel() - 1))
    edit:SetSize(width, height)
    edit:SetTextInsets(7, 7, 0, 0)
    Theme.Font(edit, "value")
    edit.background = background
    paintInput(edit, background)
end

-- Scroll long text inside the box.
function UI.TextArea(parent, x, y, width, height)
    local box = UI.Surface(parent, width, height, "input")
    box:SetPoint("TOPLEFT", x, -y)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -20, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetSize(width - 28, height - 16)
    Theme.Font(edit, "value")
    scroll:SetScrollChild(edit)
    UI.Scrollbar(scroll, edit)
    edit.box = box
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() if edit:IsEnabled() then edit:SetFocus() end end)
    edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
    edit:SetScript("OnCursorChanged", function(_, _, cursorY, _, cursorHeight)
        local top, offset, view = -cursorY, scroll:GetVerticalScroll(), scroll:GetHeight()
        if top < offset then
            scroll:SetVerticalScroll(top)
        elseif top + cursorHeight > offset + view then
            scroll:SetVerticalScroll(top + cursorHeight - view)
        end
    end)
    paintInput(edit, box)
    return edit
end

-- A number field. `limits` = { min, max, integer = true } clamps typed values.
function UI.NumberBox(parent, x, y, width, value, onChange, limits)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetPoint("TOPLEFT", x, -y)
    UI.StyleInput(edit, width, 28)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(12)
    edit:SetJustifyH("RIGHT")
    edit:SetText(tostring(value))
    function edit:SetNumber(number)
        value = number
        self:SetText(tostring(number))
    end
    function edit:Commit()
        local number = tonumber(edit:GetText())
        if number and not MHT.Util.Finite(number) then number = nil end
        if number and limits then
            if limits.integer then number = math.floor(number + 0.5) end
            number = math.max(limits[1], math.min(limits[2], number))
        end
        if number and number ~= value then
            local previous = value
            value = number
            if onChange(number) == false then value = previous end
        end
        edit:SetText(tostring(value))
    end
    edit:SetScript("OnEnterPressed", function() edit:Commit(); edit:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function() edit:SetText(tostring(value)); edit:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function() edit:Commit() end)
    return edit
end

local function scrollParent(frame)
    local parent = frame:GetParent()
    while parent do
        if parent.scrollByWheel then return parent end
        parent = parent:GetParent()
    end
end

-- A slider with a number field

function UI.Range(parent, text, x, y, width, minimum, maximum, step, value, onChange, limits)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", x, -y)
    row:SetSize(width, 30)
    local caption = UI.Text(row, text, 0, 8, 130)
    local edit = UI.NumberBox(row, width - 72, 0, 72, value, onChange, limits or { minimum, maximum })
    local trackWidth = width - 222
    local slider = CreateFrame("Slider", nil, row)
    slider:SetPoint("TOPLEFT", 136, -10)
    slider:SetSize(trackWidth, 12)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetThumbTexture(Theme.THUMB)
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(16, 16)
    Theme.Unsnapped(thumb)
    local track = UI.Bar(slider, trackWidth, Colors.rail)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetFrameLevel(math.max(0, slider:GetFrameLevel() - 1))
    local fill = UI.Bar(slider, trackWidth, Colors.gold)
    fill:SetPoint("LEFT", slider, "LEFT", 0, 0)
    fill:SetFrameLevel(track:GetFrameLevel())
    local setNumber, setEnabled = edit.SetNumber, edit.SetEnabled
    local syncing = false
    function edit:SetNumber(number)
        setNumber(self, number)
        syncing = true
        slider:SetValue(math.max(minimum, math.min(maximum, number)))
        syncing = false
        fill:SetFraction((number - minimum) / (maximum - minimum))
        fill:SetShown(slider:IsEnabled() ~= false and fill.fraction > 0)
    end
    function edit:SetEnabled(enabled)
        setEnabled(self, enabled)
        slider:SetEnabled(enabled)
        slider:SetAlpha(enabled and 1 or 0.45)
        fill:SetShown(enabled and fill.fraction > 0)
        caption:SetAlpha(enabled and 1 or 0.45)
        caption:SetTextColor(unpack(enabled and Colors.text or Colors.muted))
    end
    edit.row, edit.slider = row, slider
    local function commit(number)
        edit:SetText(string.format("%.6g", number))
        edit:Commit()
    end
    slider:SetScript("OnValueChanged", function(_, number)
        if not syncing then commit(math.floor(number / step + 0.5) * step) end
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        -- Scrolling the panel shouldn't change the sliders it passes over; Shift adjusts them.
        local scroll = scrollParent(slider)
        if scroll and scroll.scrollbar:IsShown() and not IsShiftKeyDown() then
            scroll.scrollByWheel(delta)
            return
        end
        commit(math.max(minimum, math.min(maximum, (tonumber(edit:GetText()) or value) + delta * step)))
    end)
    edit:SetNumber(value)
    return edit
end

-- Scrolling

function UI.Scrollbar(scroll, body)
    local bar = CreateFrame("Slider", nil, scroll:GetParent())
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -4)
    bar:SetSize(8, math.max(28, scroll:GetHeight() - 8))
    bar:SetOrientation("VERTICAL")
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(false)
    bar:SetThumbTexture(Theme.THUMB)
    local thumb = bar:GetThumbTexture()
    thumb:SetAlpha(0)
    local rail = UI.Surface(bar, 8, bar:GetHeight(), "scrollRail")
    rail:SetAllPoints(bar)
    rail:SetFrameLevel(math.max(0, bar:GetFrameLevel() - 1))
    local handle = UI.Surface(bar, 8, 28, "scrollThumb")
    handle:SetAllPoints(thumb)
    scroll.scrollbar = bar
    local syncing, maximum = false, 0
    local function position(value)
        syncing = true
        bar:SetValue(math.max(0, math.min(maximum, value or 0)))
        syncing = false
    end
    local function update()
        local viewport = scroll:GetHeight()
        maximum = math.max(0, body:GetHeight() - viewport)
        local height = math.max(28, viewport - 8)
        bar:SetHeight(height)
        bar:SetMinMaxValues(0, math.max(1, maximum))
        thumb:SetSize(8, math.max(28, height * viewport / math.max(1, viewport + maximum)))
        local value = math.max(0, math.min(maximum, scroll:GetVerticalScroll()))
        if value ~= scroll:GetVerticalScroll() then scroll:SetVerticalScroll(value) end
        position(value)
        bar:SetShown(maximum > 1 and scroll:IsShown())
    end
    bar:SetScript("OnValueChanged", function(_, value)
        if not syncing then scroll:SetVerticalScroll(math.max(0, math.min(maximum, value))) end
    end)
    bar:SetScript("OnEnter", function() Theme.Skin(handle, "scrollThumbHover") end)
    bar:SetScript("OnLeave", function() Theme.Skin(handle, "scrollThumb") end)
    function scroll.scrollByWheel(delta)
        scroll:SetVerticalScroll(math.max(0, math.min(maximum, scroll:GetVerticalScroll() - delta * 28)))
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) scroll.scrollByWheel(delta) end)
    scroll:HookScript("OnVerticalScroll", function(_, value) position(value) end)
    scroll:HookScript("OnScrollRangeChanged", update)
    scroll:HookScript("OnSizeChanged", update)
    scroll:HookScript("OnShow", update)
    scroll:HookScript("OnHide", function() bar:Hide() end)
    body:HookScript("OnSizeChanged", update)
    update()
    return bar
end

-- Choices

local openMenu

-- choices = { { id, name, disabled }, ... }
function UI.Dropdown(parent, x, y, width, choices, value, onSelect)
    local button = UI.Button(parent, "", x, y, width, function() end, nil, 30)
    button.label:ClearAllPoints()
    button.label:SetPoint("TOPLEFT", button, "TOPLEFT", 10, 0)
    button.label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -28, 0)
    button.label:SetJustifyH("LEFT")
    button.icon = Theme.Icon(button, "down", 10, width / 2 - 16, 0)
    local menu = UI.Surface(button, width, #choices * 32 + 8, "menu")
    menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    menu:SetFrameStrata("TOOLTIP")
    button.menu, button.options = menu, {}
    local function expanded(shown)
        button.expanded = shown
        button.icon:SetShape(shown and "up" or "down")
        button:Repaint()
    end
    menu:HookScript("OnShow", function() expanded(true) end)
    menu:HookScript("OnHide", function() expanded(false) end)
    function button:SetValue(selected)
        self.value = selected
        for _, choice in ipairs(choices) do
            if choice.id == selected then self:SetText(choice.name); break end
        end
        for id, option in pairs(self.options) do option:SetSelected(id == selected) end
    end
    for i, choice in ipairs(choices) do
        local option = UI.Button(menu, choice.name, 4, 4 + (i - 1) * 32, width - 8, function()
            menu:Hide()
            button:SetValue(choice.id)
            onSelect(choice.id)
        end, nil, 30)
        option:SetEnabled(not choice.disabled)
        button.options[choice.id] = option
    end
    button:SetScript("OnClick", function()
        local show = not menu:IsShown()
        if openMenu then openMenu:Hide() end
        menu:SetShown(show)
        openMenu = show and menu or nil
    end)
    menu:RegisterEvent("GLOBAL_MOUSE_DOWN")
    menu:SetScript("OnEvent", function()
        if menu:IsShown() and not button:IsMouseOver() and not menu:IsMouseOver() then menu:Hide() end
    end)
    button:HookScript("OnHide", function() menu:Hide() end)
    button:HookScript("OnDisable", function() menu:Hide() end)
    button:SetValue(value)
    menu:Hide()
    return button
end

function UI.Check(parent, label, x, y, checked, onChange)
    local button = CreateFrame("CheckButton", nil, parent)
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(24, 24)
    local box = UI.Surface(button, 18, 18, "check")
    box:SetPoint("LEFT", 0, 0)
    box:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
    local mark = Theme.Icon(box, "check", 14)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Theme.Font(text, "label")
    text:SetTextColor(unpack(Colors.text))
    text:SetPoint("LEFT", button, "RIGHT", 3, 0)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    button.label = text
    -- The label is clickable too.
    function button:SetLabelWidth(width)
        text:SetWidth(width)
        self:SetHitRectInsets(0, -width - 3, 0, 0)
    end
    local parentWidth = (parent:GetWidth() or 0) - x - 31
    if parentWidth > 0 then button:SetLabelWidth(parentWidth) end
    local function paint()
        local enabled, checked = button:IsEnabled(), button:GetChecked()
        text:SetTextColor(unpack(enabled and Colors.text or Colors.muted))
        box:SetAlpha(enabled and 1 or 0.45)
        Theme.Skin(box, (checked or button.hovered and enabled) and "inputFocus" or "check")
        mark:SetShown(checked)
        mark:SetVertexColor(unpack(enabled and Colors.gold or Colors.muted))
    end
    -- The addon draws its own checkmark, so it must also update when code checks the box.
    local setChecked = button.SetChecked
    function button:SetChecked(value) setChecked(self, value); paint() end
    button:SetScript("OnEnable", paint)
    button:SetScript("OnDisable", paint)
    button:SetScript("OnEnter", function() button.hovered = true; paint() end)
    button:SetScript("OnLeave", function() button.hovered = false; paint() end)
    button:SetScript("OnClick", function() paint(); onChange(button:GetChecked()) end)
    button:SetChecked(checked)
    return button
end
