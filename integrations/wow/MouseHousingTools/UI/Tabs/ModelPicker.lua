local _, MHT = ...
local ModelPicker = {}
ModelPicker.__index = ModelPicker
MHT.ModelPicker = ModelPicker

-- Choosing a model on the 3D tabs: a card per library model, or an import code

local Library = MHT.ModelLibrary
local IMPORT_LATER = "Import codes are coming later. Choose Library to use a saved model."

function ModelPicker.New(window, parent, width, options)
    local self = setmetatable({ window = window, container = options.container, selection = window.modelSettings,
        details = options.details, cards = {} }, ModelPicker)
    local UI, Theme, track = MHT.UI, MHT.Theme, options.track

    UI.Heading(parent, "Model", 0, 0, width)
    if options.onReset then
        UI.Tooltip(track(UI.ResetButton(parent, width - 24, 0, options.onReset)), "Reset model and sizes")
    end
    self.libraryButton = track(UI.Button(parent, "Library", 0, 28, 160, function() self:SetSource("library") end, nil, 30))
    self.importButton = track(UI.Button(parent, "Import Code", 168, 28, 160, function() self:SetSource("import") end, nil, 30))

    self.catalog = CreateFrame("Frame", nil, parent)
    self.catalog:SetAllPoints(parent)
    for i, entry in ipairs(Library.Entries) do
        local card = track(UI.Button(self.catalog, "", 0, 68 + (i - 1) * 104, width, function()
            self.selection.id = entry.id
            window:Refresh()
        end, nil, 94))
        card.label:Hide()
        local thumbnail = MHT.Preview.New(card, true)
        thumbnail.frame:SetPoint("TOPLEFT", 12, -12)
        thumbnail.frame:SetSize(68, 68)
        thumbnail:SetPlan((Library.Build(entry.id, 1, (window:ItemDimensions(entry.decorID)))))
        local check = CreateFrame("Frame", nil, card)
        check:SetPoint("TOPLEFT", 296, -36)
        check:SetSize(24, 24)
        Theme.Icon(check, "check", 14):SetVertexColor(unpack(Theme.Colors.gold))
        local name = UI.Text(card, entry.name, 94, self.details and 26 or 39, 190)
        local detail = UI.Muted(card, string.format("%d points", entry.count), 94, 48, 190)
        detail:SetShown(self.details == true)
        self.cards[#self.cards + 1] = { id = entry.id, button = card, check = check, name = name }
    end
    self.bottom = 78 + #Library.Entries * 104

    self.importFields = CreateFrame("Frame", nil, parent)
    self.importFields:SetAllPoints(parent)
    local code = CreateFrame("EditBox", nil, self.importFields, "InputBoxTemplate")
    code:SetPoint("TOPLEFT", 0, -68)
    code:SetAutoFocus(false)
    code:SetMultiLine(true)
    UI.StyleInput(code, width, 80)
    code:SetTextInsets(8, 8, 8, 8)
    code:SetJustifyV("TOP")
    code:SetText("Paste import code here…")
    code:Disable()
    UI.Muted(self.importFields, IMPORT_LATER, 0, 164, width)
    return self
end

function ModelPicker:Entry()
    if self.selection.source ~= "library" then return nil, IMPORT_LATER end
    return Library.Get(self.selection.id)
end

function ModelPicker:SetSource(source)
    self.selection.source = source
    self.container:ScrollToTop()
    self.window:Refresh()
end

function ModelPicker:Reset()
    self.selection.id, self.selection.source = Library.Entries[1].id, "library"
end

function ModelPicker:Refresh()
    local library = self.selection.source == "library"
    self.catalog:SetShown(library)
    self.importFields:SetShown(not library)
end

function ModelPicker:UpdateControls()
    self.libraryButton:SetSelected(self.selection.source == "library")
    self.importButton:SetSelected(self.selection.source == "import")
    for _, card in ipairs(self.cards) do
        local selected = card.id == self.selection.id
        card.button:SetSelected(selected)
        card.check:SetShown(selected)
    end
end
