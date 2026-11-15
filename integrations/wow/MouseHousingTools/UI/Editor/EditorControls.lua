local _, MHT = ...
local EditorControls = {}
EditorControls.__index = EditorControls
MHT.EditorControls = EditorControls

local function editorIsActive()
    return C_HouseEditor and C_HouseEditor.IsHouseEditorActive() and not InCombatLockdown()
end

local function housingParent()
    return HouseEditorFrame or UIParent
end

-- A logo button in the housing editor that opens the main window.
function EditorControls.New(window)
    local self = setmetatable({
        window = window,
        currentParent = UIParent,
    }, EditorControls)

    self.frame = MHT.UI.Button(UIParent, "", 0, 0, 48, function() window:Toggle() end, "icon", 48)
    self.frame.label:Hide()
    self:PositionLauncher()
    self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    self.frame:SetClampedToScreen(true)
    self.frame:SetToplevel(true)
    MHT.UI.Tooltip(self.frame, "Mouse Housing Tools")

    self.logo = MHT.Theme.Logo(self.frame, 0, 0, 48)
    self.frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    self.frame:RegisterEvent("UI_SCALE_CHANGED")
    self.frame:SetScript("OnEvent", function() self:PositionLauncher() end)

    self.frame:Hide()
    return self
end

function EditorControls:PositionLauncher()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -UIParent:GetHeight() / 7)
end

function EditorControls:SetHousingParent(parent)
    parent = parent or UIParent
    if parent == self.currentParent then return end

    self.currentParent = parent

    local hudShown = self.frame:IsShown()
    self.frame:SetParent(parent)
    self:PositionLauncher()
    self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    self.frame:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 100)
    self.frame:SetShown(hudShown)

    self.window:SetHousingParent(parent)
end

function EditorControls:ApplyState(active)
    if active then
        self:SetHousingParent(housingParent())

        self.frame:SetShown(not self.hidden)
    else
        self.frame:Hide()

        self:SetHousingParent(UIParent)
    end
end

function EditorControls:Show()
    self.hidden = false
    self:Sync()
end

function EditorControls:Sync(leavingWorld)
    if leavingWorld then
        self:ApplyState(false)
        return
    end

    self:ApplyState(editorIsActive())

    C_Timer.After(0, function()
        if MHT.editorControls == self then
            self:ApplyState(editorIsActive())
        end
    end)
end
