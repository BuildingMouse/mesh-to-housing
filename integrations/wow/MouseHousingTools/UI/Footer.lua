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
    self.stop = UI.Button(frame, "End", 700, 14, 92, function() window:EndPlacement() end, nil, 40)
    self.start = UI.Button(frame, "Start", 804, 14, 146, function() window:StartPlacement() end, "primary", 40)
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

function Footer:Update(canStart, placing, busy)
    self.start:SetEnabled(canStart)
    self.start:SetText(placing and "Placing…" or "Start")
    self.stop:SetEnabled(busy)
    self.stop:SetShown(busy)
end
