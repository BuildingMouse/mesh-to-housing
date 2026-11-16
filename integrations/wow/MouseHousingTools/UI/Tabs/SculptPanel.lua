local _, MHT = ...
local SculptPanel = {}
SculptPanel.__index = SculptPanel
MHT.SculptPanel = SculptPanel

-- The 3D Sculpt tab.

local LABEL_WIDTH, ROW = 76, 26

local function row(parent, label, y, width)
    local caption = MHT.UI.Text(parent, label, 0, y, LABEL_WIDTH)
    caption:SetTextColor(unpack(MHT.Theme.Colors.muted))
    local value = MHT.UI.Text(parent, "", LABEL_WIDTH, y, width - LABEL_WIDTH)
    value:SetMaxLines(1)
    return value
end

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
    UI.Heading(self.options, "Build", 0, 16, width)
    self.item = row(self.options, "Item", 46, width)
    self.available = row(self.options, "Available", 46 + ROW, width)
    self.budget = row(self.options, "Budget", 46 + ROW * 2, width)
    self.replaced = UI.Muted(self.options, "", 0, 50 + ROW * 3, width)
    self.height = 50 + ROW * 4
    return self
end

-- Copies in storage that the build needs, and whether there are too few.
function SculptPanel:AvailableText(plan)
    local needed, color = #plan.items, MHT.Placement.Color(plan)
    local stored = color and MHT.Housing:StoredCount(plan.requires, color)
    local suffix = color == "none" and " undyed" or ""
    if not stored then return string.format("? / %d%s", needed, suffix) end
    return string.format("%d / %d%s", math.min(stored, needed), needed, suffix), stored < needed
end

-- The text, and whether the house has enough budget left.
function SculptPanel:BudgetText(plan)
    local api = MHT.Housing
    local cost = api:PlacementCost(plan.requires)
    if not cost then return "Not known yet" end
    local total, left = cost * #plan.items, api:BudgetLeft()
    if not left then return tostring(total) end
    if total > left then return string.format("%d, but only %d left", total, left), true end
    return string.format("%d of %d left", total, left)
end

function SculptPanel:Plan()
    return self.picker:Plan()
end

function SculptPanel:Refresh()
    self.picker:Refresh()
    local plan = self.picker:Plan()
    self.options:SetShown(plan ~= nil)
    if plan then
        local colors = MHT.Theme.Colors
        self.item:SetText(MHT.ItemProfiles.Name(plan.requires))
        local available, fewer = self:AvailableText(plan)
        self.available:SetText(available)
        self.available:SetTextColor(unpack(fewer and colors.gold or colors.text))
        local budget, short = self:BudgetText(plan)
        self.budget:SetText(budget)
        self.budget:SetTextColor(unpack(short and colors.gold or colors.text))
        local replaced = self.picker:ReplacedItem(plan)
        self.replaced:SetText(replaced
            and string.format("The code asks for item %d, which has no logged size yet.", replaced) or "")
    end
    self.container:SetContentHeight(self.picker:PlaceBelow(self.options) + self.height)
end

function SculptPanel:UpdateControls()
    self.picker:UpdateControls()
end
