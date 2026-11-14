local _, MHT = ...
local Footer = {}
Footer.__index = Footer
MHT.Footer = Footer

-- The main window's bottom bar.

-- Room for the longest time text, so the ticking clock never changes the layout.
local TIME_WIDTH = 130

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
    self.frame = frame
    self.count = UI.Heading(frame, "", 14, 12, 170)
    local clock = MHT.Theme.Icon(frame, "clock", 12)
    clock:ClearAllPoints()
    clock:SetPoint("TOPLEFT", 14, -35)
    self.time = UI.Muted(frame, "", 0, 0)
    self.time:ClearAllPoints()
    self.time:SetPoint("LEFT", clock, "RIGHT", 6, 0)
    MHT.Theme.Font(self.time, "value")
    local timeHint = CreateFrame("Frame", nil, frame)
    timeHint:SetPoint("TOPLEFT", clock, "TOPLEFT", -4, 5)
    timeHint:SetPoint("BOTTOMRIGHT", self.time, "BOTTOMRIGHT", 4, -3)
    timeHint:EnableMouse(true)
    UI.Tooltip(timeHint, "Time", "The addon's own work at the measured editor speeds. Clicking copies and waiting for WoW can add time.")
    self.progress = UI.Bar(frame, 560, MHT.Theme.Colors.rail)
    self.progress:SetPoint("TOPLEFT", 14, -52)
    self.progress:EnableMouse(true)
    UI.Tooltip(self.progress, "Progress", "Copies made while preparing, then finished items and the current item's move. An item counts once WoW saves it.")
    self.progressFill = UI.Bar(self.progress, 560, MHT.Theme.Colors.gold)
    self.progressFill:SetPoint("LEFT", 0, 0)
    -- The buttons line up from the right edge, so they stay in place when the footer changes width.
    local function anchor(widget, ...)
        widget:ClearAllPoints()
        widget:SetPoint(...)
        return widget
    end
    self.start = anchor(UI.Button(frame, "Prepare items", 0, 0, 120, function() window:StartPlacement() end, "primary", 40),
        "TOPRIGHT", -14, -14)
    self.stop = anchor(UI.Button(frame, "End", 0, 0, 120, function() window:EndPlacement() end, nil, 40),
        "TOPRIGHT", self.start, "TOPLEFT", -8, 0)
    self.skip = anchor(UI.Button(frame, "Skip item", 0, 0, 120, function() window:SkipItem() end, nil, 40),
        "TOPRIGHT", self.stop, "TOPLEFT", -8, 0)
    UI.Tooltip(self.skip, "Skip item", "Leave this item where it is and continue with the next one.")
    self.skip:Hide()
    self.pile = anchor(UI.Check(frame, "Use existing pile", 0, 0, false, function(checked) window:UseExistingPile(checked) end),
        "TOPRIGHT", self.start, "TOPLEFT", -120, -8)
    self.pile:SetLabelWidth(110)
    MHT.Theme.Font(self.pile.label, "secondary")
    UI.Tooltip(self.pile, "Use existing pile", "Skip preparation and move each copy you click from the pile.")
    self.status = UI.Muted(frame, "", 14, 61, 936)
    frame:HookScript("OnSizeChanged", function() self:Resize() end)
    return self
end

function Footer:SetCompact(compact)
    self.compact = compact
    self:Resize()
end

function Footer:RowWidth()
    local buttons = 120
    if self.pile:IsShown() then buttons = buttons + 144 end
    if self.stop:IsShown() then buttons = buttons + 128 end
    if self.skip:IsShown() then buttons = buttons + 128 end
    return 14 + math.max(self.count:GetStringWidth(), TIME_WIDTH) + 16 + buttons + 14
end

-- The small window gives the progress bar and the status their own rows below the buttons.
-- When the buttons don't fit beside the count and the time, they move to a row of their own.
function Footer:Resize()
    local compact = self.compact
    local width = self.frame:GetWidth() - 28
    local stacked = compact and width + 28 < self:RowWidth()
    if self.laidOut and self.laidOut.width == width and self.laidOut.stacked == stacked
        and self.laidOut.compact == compact then return end
    self.laidOut = { width = width, stacked = stacked, compact = compact }
    local barY = stacked and 110 or compact and 62 or 52
    self.frame:SetHeight(stacked and 158 or compact and 104 or 78)
    self.start:SetPoint("TOPRIGHT", -14, stacked and -58 or -14)
    local barWidth = compact and width or width - 394
    self.progress:SetPoint("TOPLEFT", 14, -barY)
    self.progress:SetLength(barWidth)
    self.progressFill:SetLength(barWidth)
    self.status:SetPoint("TOPLEFT", 14, compact and -(barY + 12) or -61)
    self.status:SetWidth(math.max(1, width))
end

function Footer:SetCount(text)
    self.count:SetText(text)
    self:Resize()
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
    self:Resize()
end
