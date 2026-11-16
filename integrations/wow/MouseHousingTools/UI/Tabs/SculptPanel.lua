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
    self.picker = MHT.ModelPicker.New(window, self.frame, width, { track = track, container = container, library = "sculpt" })

    self.options = CreateFrame("Frame", nil, self.frame)
    self.picker:PlaceBelow(self.options)
    UI.Rule(self.options, 2, width)
    UI.Heading(self.options, "Item", 0, 16, width)
    self.item = UI.Text(self.options, "", 0, 44, width)
    self.count = UI.Muted(self.options, "", 0, 68, width)
    self.replaced = UI.Muted(self.options, "", 0, 92, width)
    self.height = 124
    return self
end

function SculptPanel:Plan()
    return self.picker:Plan()
end

function SculptPanel:Refresh()
    self.picker:Refresh()
    local plan = self.picker:Plan()
    self.options:SetShown(plan ~= nil)
    if plan then
        self.item:SetText(MHT.ItemProfiles.Name(plan.requires))
        self.count:SetText(string.format("%d copies", #plan.items))
        local replaced = self.picker:ReplacedItem(plan)
        self.replaced:SetText(replaced
            and string.format("The code asks for item %d, which has no logged size yet.", replaced) or "")
    end
    self.container:SetContentHeight(self.picker:PlaceBelow(self.options) + self.height)
end

function SculptPanel:UpdateControls()
    self.picker:UpdateControls()
end
