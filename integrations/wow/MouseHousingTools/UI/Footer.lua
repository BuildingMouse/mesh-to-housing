local _, MHT = ...
local Footer = {}
Footer.__index = Footer
MHT.Footer = Footer

-- The main window's bottom bar.

function Footer.New(window, parent)
    local self = setmetatable({}, Footer)
    local UI = MHT.UI
    local frame = UI.Surface(parent, 964, 78, "footer")
    frame:SetPoint("TOPLEFT", 18, -628)
    self.frame = frame
    self.count = UI.Heading(frame, "", 14, 12, 180)
    self.pile = UI.Check(frame, "Use existing pile", 230, 22, false, function(checked) window:UseExistingPile(checked) end)
    self.pile:SetLabelWidth(150)
    MHT.Theme.Font(self.pile.label, "secondary")
    UI.Tooltip(self.pile, "Use existing pile", "Skip preparation and move each copy you click from the pile.")
    self.stop = UI.Button(frame, "End", 700, 14, 92, function() window:EndPlacement() end, nil, 40)
    self.start = UI.Button(frame, "Prepare items", 804, 14, 146, function() window:StartPlacement() end, "primary", 40)
    MHT.Theme.Font(self.start.label, "heading")
    self.status = UI.Muted(frame, "", 14, 61, 936)
    return self
end

function Footer:SetCount(text)
    self.count:SetText(text)
end

function Footer:SetStatus(message)
    self.status:SetText(message)
end

local function startText(placement, fromPile)
    if placement:Ready() then return "Build" end
    if placement.stage == "preparing" then return "Preparing…" end
    if placement.stage == "building" then return "Building…" end
    if placement:Busy() then return "Placing…" end
    return fromPile and "Build" or "Prepare items"
end

local function stopText(placement)
    if placement.stage == "preparing" then return "Stop" end
    return placement:HasSession() and "End build" or "End"
end

function Footer:Update(placement, canStart, running, fromPile)
    self.start:SetEnabled(canStart)
    self.start:SetText(startText(placement, fromPile))
    self.stop:SetText(stopText(placement))
    self.stop:SetEnabled(running)
    self.stop:SetShown(running)
    self.pile:SetChecked(fromPile)
    self.pile:SetShown(not running)
end
