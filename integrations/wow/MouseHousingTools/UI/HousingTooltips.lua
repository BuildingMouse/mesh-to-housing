local _, MHT = ...

local function editing()
    return C_HouseEditor and C_HouseEditor.IsHouseEditorActive() and not InCombatLockdown()
end

local function hideHandleTooltip(tooltip)
    if not editing() then return end
    local data = tooltip.GetTooltipData and tooltip:GetTooltipData()
    if data then
        if data.type == Enum.TooltipDataType.Debug then tooltip:Hide() end
        return
    end

    -- Some native handle labels use plain text instead of tooltip data.
    local name = tooltip:GetName()
    local line = name and _G[name .. "TextLeft1"]
    local text = line and line:GetText()
    if type(text) == "string" and (text:match("^Rotation [XYZ] Ring$")
        or text:match("^Translation [XYZ]$") or text:match("^Translation [XYZ] ")) then
        tooltip:Hide()
    end
end

function MHT.HideHousingHandleTooltips()
    -- A pre-call stops Blizzard before it draws the debug tooltip; a post-call
    -- would run before Blizzard's final Show() and let the label reappear.
    TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Debug, function(tooltip)
        if editing() then
            tooltip:Hide()
            return true
        end
    end)

    for _, name in ipairs({ "GameTooltip", "GameSmallHeaderTooltip" }) do
        local tooltip = _G[name]
        if tooltip then
            tooltip:HookScript("OnShow", hideHandleTooltip)
            tooltip:HookScript("OnUpdate", hideHandleTooltip)
            hideHandleTooltip(tooltip)
        end
    end
end
