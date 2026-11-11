local _, MHT = ...
local SketchPanel = {}
SketchPanel.__index = SketchPanel
MHT.SketchPanel = SketchPanel

-- The 3D Sketch tab.

function SketchPanel.New(window, container, parent)
    local self = setmetatable({ window = window, container = container, controls = {}, points = true,
        settings = window.modelSettings }, SketchPanel)
    local UI, width, settings = MHT.UI, container.width, self.settings
    local function track(control)
        self.controls[#self.controls + 1] = control
        return control
    end
    local function changed() window:Refresh() end

    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    self.picker = MHT.ModelPicker.New(window, self.frame, width,
        { track = track, container = container, details = true, onReset = function() self:Reset() end })

    local y = self.picker.bottom
    self.options = CreateFrame("Frame", nil, self.frame)
    self.options:SetAllPoints(self.frame)
    UI.Rule(self.options, y + 2, width)
    UI.Heading(self.options, "Size", 0, y + 16, width)
    self.modelSize = track(UI.Range(self.options, "Model size (%)", 0, y + 44, width, 20, 200, 1,
        settings.percent, function(value) settings.percent = value; changed() end))
    UI.Muted(self.options, "Size of the whole point guide.", 0, y + 78, width)
    self.itemSize = track(UI.Range(self.options, "Point item (%)", 0, y + 114, width, 20, 200, 1,
        settings.itemPercent, function(value) settings.itemPercent = value; changed() end))
    UI.Muted(self.options, "Size of the item placed at each point.", 0, y + 148, width)
    self.height = y + 194
    return self
end

function SketchPanel:Plan()
    local entry, reason = self.picker:Entry()
    if not entry then return nil, reason end
    local settings = self.settings
    return MHT.ModelLibrary.Sketch(entry.id, settings.percent / 100, settings.itemPercent / 100,
        (self.window:ItemDimensions(entry.decorID)))
end

function SketchPanel:Reset()
    self.picker:Reset()
    self.settings.percent, self.settings.itemPercent = 100, 100
    self.window:Refresh()
end

function SketchPanel:Refresh()
    self.picker:Refresh()
    self.options:SetShown(self.picker:Entry() ~= nil)
    self.modelSize:SetNumber(self.settings.percent)
    self.itemSize:SetNumber(self.settings.itemPercent)
    self.container:SetContentHeight(self.height)
end

function SketchPanel:UpdateControls()
    self.picker:UpdateControls()
end
