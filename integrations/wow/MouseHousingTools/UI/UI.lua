local _, MHT = ...
local UI = {}
MHT.UI = UI

function UI.Panel(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.055, 0.065, 0.08, 0.98)
    frame:SetBackdropBorderColor(0.23, 0.27, 0.32, 1)
    return frame
end

function UI.Text(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, -y)
    if width then label:SetWidth(width) end
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    label:SetText(text)
    return label
end

function UI.Button(parent, text, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(width, 25)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

function UI.Number(parent, label, x, y, value, callback)
    UI.Text(parent, label, x, y, 125)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetPoint("TOPLEFT", x + 5, -y - 18)
    edit:SetSize(105, 22)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(12)
    edit:SetText(tostring(value))
    local function accept()
        local number = tonumber(edit:GetText())
        if number then
            value = number
            callback(number)
        end
        edit:SetText(tostring(value))
        edit:ClearFocus()
    end
    edit:SetScript("OnEnterPressed", accept)
    edit:SetScript("OnEscapePressed", function() edit:SetText(tostring(value)); edit:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function()
        local number = tonumber(edit:GetText())
        if number then value = number; callback(number) else edit:SetText(tostring(value)) end
    end)
    return edit
end

function UI.Check(parent, label, x, y, checked, callback)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetPoint("TOPLEFT", x, -y)
    button:SetSize(24, 24)
    button:SetChecked(checked)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", button, "RIGHT", 3, 0)
    text:SetText(label)
    button:SetScript("OnClick", function() callback(button:GetChecked()) end)
    return button
end
