local _, MHT = ...
local SculptPanel = {}
SculptPanel.__index = SculptPanel
MHT.SculptPanel = SculptPanel

-- The 3D Sculpt tab.

function SculptPanel.New(window, container, parent)
    local self = setmetatable({ window = window, container = container, controls = {} }, SculptPanel)
    local UI, width = MHT.UI, container.width
    local function track(control)
        self.controls[#self.controls + 1] = control
        return control
    end

    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    self.picker = MHT.ModelPicker.New(window, self.frame, width, { track = track, container = container })

    local y = self.picker.bottom
    self.options = CreateFrame("Frame", nil, self.frame)
    self.options:SetAllPoints(self.frame)
    UI.Rule(self.options, y + 2, width)
    UI.Heading(self.options, "Item", 0, y + 16, width)
    self.item = UI.Text(self.options, "", 0, y + 44, width)
    self.count = UI.Muted(self.options, "", 0, y + 68, width)
    self.height = y + 100
    return self
end

function SculptPanel:Plan()
    local entry, reason = self.picker:Entry()
    if not entry then return nil, reason end
    return MHT.ModelLibrary.Build(entry.id, 1, (MHT.ItemProfiles.Dimensions(entry.decorID)))
end

function SculptPanel:Refresh()
    self.picker:Refresh()
    local entry = self.picker:Entry()
    self.options:SetShown(entry ~= nil)
    if entry then
        self.item:SetText(MHT.ItemProfiles.Logged(entry.decorID).name or ("Decor item " .. entry.decorID))
        self.count:SetText(string.format("%d copies", entry.count))
    end
    self.container:SetContentHeight(self.height)
end

function SculptPanel:UpdateControls()
    self.picker:UpdateControls()
end
