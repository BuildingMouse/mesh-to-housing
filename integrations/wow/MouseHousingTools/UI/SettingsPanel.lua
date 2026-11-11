local _, MHT = ...
local SettingsPanel = {}
SettingsPanel.__index = SettingsPanel
MHT.SettingsPanel = SettingsPanel

-- The main window's left column.

local WIDTH, VIEWPORT = 328, 484

function SettingsPanel.New(window, parent)
    local self = setmetatable({ window = window, width = WIDTH }, SettingsPanel)
    local UI = MHT.UI
    local inset = UI.Surface(parent, 364, 512, "settings")
    inset:SetPoint("TOPLEFT", 18, -104)
    local scroll = CreateFrame("ScrollFrame", nil, inset)
    scroll:SetPoint("TOPLEFT", 14, -14)
    scroll:SetSize(WIDTH, VIEWPORT)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(WIDTH, VIEWPORT)
    scroll:SetScrollChild(body)
    UI.Scrollbar(scroll, body)
    self.scroll, self.body = scroll, body
    self.sections = {
        shapes = MHT.ShapePanel.New(window, self, body),
        sketch = MHT.SketchPanel.New(window, self, body),
        sculpt = MHT.SculptPanel.New(window, self, body),
    }
    return self
end

function SettingsPanel:Section()
    return self.sections[self.window.mode]
end

function SettingsPanel:Plan()
    return self:Section():Plan()
end

function SettingsPanel:SetContentHeight(height)
    height = math.max(VIEWPORT, height)
    local scroll = self.scroll
    local maximum = math.max(0, height - scroll:GetHeight())
    if scroll:GetVerticalScroll() > maximum then scroll:SetVerticalScroll(maximum) end
    self.body:SetHeight(height)
    scroll:UpdateScrollChildRect()
end

-- Scrolls down just enough to show the content down to `bottom`.
function SettingsPanel:Reveal(bottom)
    local scroll = self.scroll
    local maximum = math.max(0, self.body:GetHeight() - scroll:GetHeight())
    local target = math.min(maximum, math.max(0, bottom - scroll:GetHeight()))
    if target > scroll:GetVerticalScroll() then scroll:SetVerticalScroll(target) end
end

function SettingsPanel:ScrollToTop()
    self.scroll:SetVerticalScroll(0)
end

function SettingsPanel:CommitEdits()
    for _, section in pairs(self.sections) do
        for _, control in ipairs(section.controls) do
            if control.Commit and control:HasFocus() then control:Commit(); control:ClearFocus() end
        end
    end
end

function SettingsPanel:Refresh()
    local current = self:Section()
    for _, section in pairs(self.sections) do section.frame:SetShown(section == current) end
    current:Refresh()
end

-- Settings can't change while something runs.
function SettingsPanel:UpdateControls(busy)
    for _, section in pairs(self.sections) do
        for _, control in ipairs(section.controls) do control:SetEnabled(not busy) end
        section:UpdateControls(busy)
    end
end
