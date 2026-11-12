local _, MHT = ...
local UI = MHT.UI

-- A captioned number field.
function UI.Number(parent, label, x, y, value, onChange, limits)
    local caption = UI.Text(parent, label, x, y, 230)
    local edit = UI.NumberBox(parent, x, y + 20, 105, value, onChange, limits)
    edit:SetJustifyH("LEFT")
    edit.label = caption
    return edit
end
