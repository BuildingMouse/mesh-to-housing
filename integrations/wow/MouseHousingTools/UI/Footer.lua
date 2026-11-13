local _, MHT = ...
local Footer = {}
Footer.__index = Footer
MHT.Footer = Footer

-- The main window's bottom bar.

local function formatTime(seconds)
    local rounded = math.max(0, math.ceil(seconds))
    if rounded < 60 then return rounded .. "s" end
    if rounded < 3600 then return string.format("%dm %02ds", math.floor(rounded / 60), rounded % 60) end
    return string.format("%dh %02dm", math.floor(rounded / 3600), math.floor(rounded / 60) % 60)
end

function Footer.New(window, parent)
    local self = setmetatable({}, Footer)
    local UI = MHT.UI
    local frame = UI.Surface(parent, 964, 78, "footer")
    frame:SetPoint("TOPLEFT", 18, -628)
    self.frame = frame
    self.count = UI.Heading(frame, "", 14, 12, 180)
    self.time = UI.Muted(frame, "", 14, 34, 200)
    MHT.Theme.Font(self.time, "value")
    local timeHint = CreateFrame("Frame", nil, frame)
    timeHint:SetPoint("TOPLEFT", 10, -30)
    timeHint:SetSize(200, 20)
    timeHint:EnableMouse(true)
    UI.Tooltip(timeHint, "Time", "The addon's own work at the measured editor speeds. Clicking copies and waiting for WoW can add time.")
    self.progress = UI.Bar(frame, 560, MHT.Theme.Colors.rail)
    self.progress:SetPoint("TOPLEFT", 14, -52)
    self.progress:EnableMouse(true)
    UI.Tooltip(self.progress, "Progress", "Copies made while preparing, then finished items and the current item's move. An item counts once WoW saves it.")
    self.progressFill = UI.Bar(self.progress, 560, MHT.Theme.Colors.gold)
    self.progressFill:SetPoint("LEFT", 0, 0)
    self.pile = UI.Check(frame, "Use existing pile", 230, 22, false, function(checked) window:UseExistingPile(checked) end)
    self.pile:SetLabelWidth(150)
    MHT.Theme.Font(self.pile.label, "secondary")
    UI.Tooltip(self.pile, "Use existing pile", "Skip preparation and move each copy you click from the pile.")
    self.skip = UI.Button(frame, "Skip item", 592, 14, 100, function() window:SkipItem() end, nil, 40)
    UI.Tooltip(self.skip, "Skip item", "Leave this item where it is and continue with the next one.")
    self.skip:Hide()
    self.stop = UI.Button(frame, "End", 700, 14, 92, function() window:EndPlacement() end, nil, 40)
    self.start = UI.Button(frame, "Prepare items", 804, 14, 146, function() window:StartPlacement() end, "primary", 40)
    MHT.Theme.Font(self.start.label, "heading")
    self.status = UI.Muted(frame, "", 14, 61, 936)
    return self
end

function Footer:SetCount(text)
    self.count:SetText(text)
end

function Footer:SetTime(seconds)
    self.time:SetText(seconds and "Time: " .. formatTime(seconds) or "Time: —")
end

function Footer:SetProgress(fraction)
    self.progress:SetShown(fraction ~= nil)
    self.progressFill:SetFraction(fraction or 0)
end

function Footer:SetStatus(message)
    self.status:SetText(message)
end

local function startText(placement, fromPile)
    if placement:Ready() then return "Build" end
    if placement:Paused() then return "Resume" end
    if placement.stage == "preparing" then return "Preparing…" end
    if placement.pauseRequested then return "Pausing…" end
    if placement:CanPause() then return "Pause" end
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
    self.skip:SetShown(placement:CanSkip())
end
