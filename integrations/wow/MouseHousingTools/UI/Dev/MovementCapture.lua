local _, MHT = ...
local CapturePanel = {}
CapturePanel.__index = CapturePanel
MHT.CapturePanel = CapturePanel

function CapturePanel.New(parent, api, start, notify)
    local clock = GetTimePreciseSec or GetTime
    local self = setmetatable({
        api = api, notify = notify, recorder = MHT.MovementCapture.New(clock),
        buttons = {}, held = {}, moving = {}, values = {}, keyLabels = {},
    }, CapturePanel)
    local UI = MHT.UI
    self.frame = CreateFrame("Frame", nil, parent)
    self.frame:SetAllPoints(parent)
    UI.Text(self.frame, "Movement capture", 18, 105, 740, "GameFontNormalLarge")
    UI.Text(self.frame,
        "Select an item in Advanced mode, press Start, then use your housing movement keybinds. Stop keeps the totals; Start begins again from the item's current position.",
        18, 145, 740)
    self.itemLabel = UI.Text(self.frame, "No item captured.", 18, 205, 740)
    for i, axis in ipairs(MHT.MovementCapture.Axes) do
        UI.Text(self.frame, axis.axis:upper() .. "  " .. axis.positive .. " - " .. axis.negative,
            18, 255 + (i - 1) * 55, 200)
        self.keyLabels[axis.axis] = UI.Text(self.frame, "", 225, 255 + (i - 1) * 55, 220)
        self.values[axis.axis] = UI.Text(self.frame, "", 455, 255 + (i - 1) * 55, 300)
        for _, direction in ipairs({ axis.positive, axis.negative }) do
            local name = direction
            local button = CreateFrame("Button", "MouseHousingToolsCapture" .. name .. "Binding", UIParent)
            button:RegisterForClicks("AnyDown", "AnyUp")
            button:SetScript("OnClick", function(_, key, down)
                local ok, reason = pcall(self.Input, self, name, key, down)
                if not ok then self:Stop(tostring(reason)) end
            end)
            self.buttons[name] = button
        end
    end
    UI.Text(self.frame,
        "Ticks count active frames, with opposite directions subtracting. Signed hold time is shown too because frame lengths vary. These are input totals, not measured game coordinates. Mouse dragging is not recorded.",
        18, 425, 740)
    self.startButton = UI.Button(self.frame, "Start", 18, 505, 95, start)
    self.stopButton = UI.Button(self.frame, "Stop", 121, 505, 95, function() self:Stop() end)
    self.bindingOwner = CreateFrame("Frame")
    self:SetHousingParent(UIParent)
    self:Refresh()
    self:SetBlocked(false)
    return self
end

function CapturePanel:Busy()
    return self.recorder.running
end

function CapturePanel:SetHousingParent(parent)
    for _, button in pairs(self.buttons) do
        button:SetParent(parent)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 2, 2)
        button:SetSize(1, 1)
        button:SetAlpha(0)
        button:Show()
    end
end

function CapturePanel:SetBlocked(blocked)
    self.blocked = blocked
    self.startButton:SetEnabled(not blocked and not self:Busy())
    self.stopButton:SetEnabled(self:Busy())
end

function CapturePanel:Refresh()
    local result = self.recorder:Snapshot()
    for _, axis in ipairs(MHT.MovementCapture.Axes) do
        self.values[axis.axis]:SetText(string.format("%+d ticks    %+.3f s",
            result.ticks[axis.axis], result.seconds[axis.axis]))
    end
end

function CapturePanel:Start(coordinate)
    if self:Busy() then return end
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor then
        return nil, "Open Advanced mode first."
    end
    local selected = self.api:Selected()
    if not selected or selected.isLocked then return nil, "Select an unlocked item first." end
    local bindings, count = self.api:MovementBindings(), 0
    self.allowed = {}
    for _, axis in ipairs(MHT.MovementCapture.Axes) do
        local enabled = not coordinate or coordinate == axis.axis
        self.allowed[axis.positive], self.allowed[axis.negative] = enabled, enabled
        if enabled then count = count + #bindings[axis.positive] + #bindings[axis.negative] end
    end
    if count == 0 then return nil, "Set housing movement keybinds for the measured axes first." end

    self.api:PrepareSubmode("Translate")
    for _, axis in ipairs(MHT.MovementCapture.Axes) do
        for _, direction in ipairs({ axis.positive, axis.negative }) do self.api:Increment(direction, false) end
    end
    self.guid = selected.decorGUID
    self.held, self.moving = {}, {}
    self.stopReason = nil
    self.bindingsInstalled = true
    for direction, keys in pairs(bindings) do
        for _, key in ipairs(keys) do
            SetOverrideBindingClick(self.bindingOwner, true, key,
                "MouseHousingToolsCapture" .. direction .. "Binding", key)
        end
    end
    for _, axis in ipairs(MHT.MovementCapture.Axes) do
        local positive, negative = table.concat(bindings[axis.positive], ", "), table.concat(bindings[axis.negative], ", ")
        self.keyLabels[axis.axis]:SetText((positive ~= "" and positive or "unbound") .. " / "
            .. (negative ~= "" and negative or "unbound"))
    end
    self.recorder:Start()
    self.itemLabel:SetText(selected.name or ("Decor " .. tostring(selected.decorID)))
    self:Refresh()
    self.notify("Capturing movement. Use housing movement keys; Stop keeps the totals.")
    return true
end

function CapturePanel:Input(direction, key, down)
    if not self:Busy() then return end
    if not self:CheckSelection() then return end
    if not self.allowed[direction] then return end
    self.held[direction] = self.held[direction] or {}
    self.held[direction][key] = down or nil
    self:SyncInputs()
end

function CapturePanel:SyncInputs()
    local desired = {}
    for _, axis in ipairs(MHT.MovementCapture.Axes) do
        for _, pair in ipairs({ { axis.positive, axis.negative }, { axis.negative, axis.positive } }) do
            local active = self.held[pair[1]] and next(self.held[pair[1]]) ~= nil
                and not (self.held[pair[2]] and next(self.held[pair[2]]) ~= nil) or false
            desired[pair[1]] = active
        end
    end
    -- Release the previous direction before starting its opposite.
    for direction in pairs(self.moving) do
        if not desired[direction] then
            self.recorder:SetActive(direction, false)
            self.api:Increment(direction, false)
            self.moving[direction] = nil
        end
    end
    for direction, active in pairs(desired) do
        if active and not self.moving[direction] then
            self.recorder:SetActive(direction, true)
            self.api:Increment(direction, true)
            self.moving[direction] = true
        end
    end
end

function CapturePanel:CheckSelection()
    if not self.api:Active() or self.api:Mode() ~= Enum.HouseEditorMode.ExpertDecor
        or self.api:PrecisionSubmode() ~= Enum.HousingPrecisionSubmode.Translate then
        self:Stop("Editor mode changed; capture stopped. Input totals kept.")
        return false
    end
    local selected = self.api:Selected()
    if not selected or selected.decorGUID ~= self.guid then
        self:Stop("Selection changed; capture stopped. Input totals kept.")
        return false
    end
    return true
end

function CapturePanel:Update(elapsed)
    if not self:Busy() or not self:CheckSelection() then return end
    self.recorder:Update(elapsed)
    self:Refresh()
end

function CapturePanel:ClearBindings()
    if self.bindingsInstalled and not InCombatLockdown() then
        ClearOverrideBindings(self.bindingOwner)
        self.bindingsInstalled = false
    end
end

function CapturePanel:Stop(message)
    self.stopReason = message
    self.recorder:Stop()
    for direction in pairs(self.moving) do pcall(self.api.Increment, self.api, direction, false) end
    self.held, self.moving = {}, {}
    self:ClearBindings()
    self:Refresh()
    self.notify(message or "Capture stopped. Input totals kept; save the item with the housing controls if wanted.")
end

function CapturePanel:OnEvent(event)
    if event == "PLAYER_REGEN_ENABLED" and not self:Busy() then self:ClearBindings() end
    if not self:Busy() then return end
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" or event == "UPDATE_BINDINGS" then
        self:Stop("Capture interrupted. Input totals kept.")
    elseif event == "HOUSE_EDITOR_MODE_CHANGED" or event == "HOUSING_DECOR_PRECISION_SUBMODE_CHANGED"
        or event == "HOUSING_EXPERT_MODE_SELECTED_TARGET_CHANGED" then
        self:CheckSelection()
    end
end
