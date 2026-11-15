local _, MHT = ...
local Chrome = {}
Chrome.__index = Chrome
MHT.EditorChrome = Chrome

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

function Chrome.HideHandleTooltips()
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

-- Storage panel and tips

function Chrome.New()
    return setmetatable({ suppressed = false, alphas = {} }, Chrome)
end

local function editor()
    return HouseEditorFrame
end

local function storageFrames(frame)
    return frame and frame.StoragePanel, frame and frame.StorageButton
end

local function tipContainers(frame)
    local result = {}
    for _, key in ipairs({ "BasicDecorModeFrame", "ExpertDecorModeFrame" }) do
        local mode = frame and frame[key]
        if mode and mode.Instructions then result[#result + 1] = mode.Instructions end
    end
    return result
end

function Chrome:HideStorage()
    local panel, button = storageFrames(editor())
    if panel then panel:Hide() end
    if button then button:Hide() end
end

-- Keeps the storage hidden if the editor tries to show it again.
function Chrome:Hook()
    local frame = editor()
    if not frame or self.hooked == frame then return self.hooked == frame end
    if not frame.ShowHouseStorage or not frame.HideHouseStorage then return false end
    hooksecurefunc(frame, "ShowHouseStorage", function()
        self.storageWanted = true
        if self.suppressed then self:HideStorage() end
    end)
    hooksecurefunc(frame, "HideHouseStorage", function() self.storageWanted = false end)
    local panel, button = storageFrames(frame)
    for _, region in ipairs({ panel, button }) do
        local function keepHidden() if self.suppressed then region:Hide() end end
        hooksecurefunc(region, "Show", keepHidden)
        hooksecurefunc(region, "SetShown", function(_, shown) if shown then keepHidden() end end)
    end
    self.hooked = frame
    return true
end

function Chrome:Suppress()
    local frame = editor()
    local panel, button = storageFrames(frame)
    self.storageWanted = (panel and panel:IsShown()) or (button and button:IsShown()) or false
    self.suppressed = true
    self:HideStorage()
    self.alphas = {}
    for _, tips in ipairs(tipContainers(frame)) do
        self.alphas[tips] = tips:GetAlpha()
        tips:SetAlpha(0)
    end
end

function Chrome:Restore()
    self.suppressed = false
    for tips, alpha in pairs(self.alphas) do pcall(tips.SetAlpha, tips, alpha) end
    self.alphas = {}
    local frame = editor()
    if self.storageWanted and frame and frame:IsShown() then pcall(frame.ShowHouseStorage, frame) end
    self.storageWanted = nil
end

function Chrome:SetSuppressed(on)
    on = on and editor() ~= nil and editor():IsShown() and true or false
    if on == self.suppressed then return end
    if on then
        local ok, hooked = pcall(self.Hook, self)
        if not ok or not hooked then return end
        if not pcall(self.Suppress, self) then self:Restore() end
    else
        self:Restore()
    end
end
