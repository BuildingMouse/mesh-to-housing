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

local function reparentInvisibleButton(button, parent)
    button:SetParent(parent)
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 2, 2)
    button:SetSize(1, 1)
    button:SetAlpha(0)
    button:Show()
end

function EditorControls.New(window)
    local self = setmetatable({
        window = window,
        bindingsInstalled = false,
        currentParent = UIParent,
    }, EditorControls)

    local UI = MHT.UI

    self.frame = UI.Panel(UIParent, 278, 150)
    self.frame:SetPoint("RIGHT", UIParent, "RIGHT", -24, 130)
    self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    self.frame:SetClampedToScreen(true)
    self.frame:SetToplevel(true)

    UI.Text(self.frame, "MouseHousingTools", 12, 12, 220, "GameFontNormal")
    self.close = UI.Button(self.frame, "X", 244, 7, 22, function()
        self.hidden = true
        self.frame:Hide()
    end)

    self.start = UI.Button(self.frame, "Ctrl+S  Start", 12, 37, 121, function()
        if editorIsActive() then window:StartPlacement() end
    end)

    self.finish = UI.Button(self.frame, "Ctrl+E  End", 143, 37, 121, function()
        window:EndPlacement()
    end)

    UI.Button(self.frame, "Settings", 12, 70, 100, function()
        window:Toggle()
    end)

    self.progress = UI.Text(self.frame, "", 128, 77, 130)
    self.status = UI.Text(
        self.frame,
        "Hover over the source, then Ctrl+S.",
        12, 106, 250
    )

    window.onStatus = function(message, completed, total)
        self.status:SetText(message)
        self.progress:SetText(total and total > 0 and string.format("%d / %d", completed or 0, total) or "")
        self.start:SetEnabled(not window:Busy())
    end

    self.bindingOwner = CreateFrame("Frame")

    self.startBinding = CreateFrame("Button", "MouseHousingToolsStartBindingButton", UIParent)
    self.startBinding:RegisterForClicks("AnyUp")
    self.startBinding:SetScript("OnClick", function()
        if editorIsActive() then window:StartPlacement() end
    end)

    self.endBinding = CreateFrame("Button", "MouseHousingToolsEndBindingButton", UIParent)
    self.endBinding:RegisterForClicks("AnyUp")
    self.endBinding:SetScript("OnClick", function()
        if editorIsActive() then window:EndPlacement() end
    end)

    reparentInvisibleButton(self.startBinding, UIParent)
    reparentInvisibleButton(self.endBinding, UIParent)

    self.frame:Hide()
    return self
end

function EditorControls:SetHousingParent(parent)
    parent = parent or UIParent
    if parent == self.currentParent then return end

    self.currentParent = parent

    local hudShown = self.frame:IsShown()
    self.frame:SetParent(parent)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("RIGHT", parent, "RIGHT", -24, 130)
    self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    self.frame:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 100)
    self.frame:SetShown(hudShown)

    reparentInvisibleButton(self.startBinding, parent)
    reparentInvisibleButton(self.endBinding, parent)

    self.window:SetHousingParent(parent)
end

function EditorControls:InstallBindings()
    if InCombatLockdown() then return end

    ClearOverrideBindings(self.bindingOwner)
    SetOverrideBindingClick(self.bindingOwner, true, "CTRL-S", "MouseHousingToolsStartBindingButton", "LeftButton")
    SetOverrideBindingClick(self.bindingOwner, true, "CTRL-E", "MouseHousingToolsEndBindingButton", "LeftButton")
    self.bindingsInstalled = true
end

function EditorControls:ClearBindings()
    if InCombatLockdown() then return end
    ClearOverrideBindings(self.bindingOwner)
    self.bindingsInstalled = false
end

function EditorControls:ApplyState(active)
    if active then
        self:SetHousingParent(housingParent())

        self.frame:SetShown(not self.hidden)

        if not self.bindingsInstalled then self:InstallBindings() end
    else
        self:ClearBindings()
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

    -- Let the housing frame finish its event handler before reparenting.
    C_Timer.After(0, function()
        if MHT.editorControls == self then
            self:ApplyState(editorIsActive())
        end
    end)
end
