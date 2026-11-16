local _, MHT = ...
local ModelPicker = {}
ModelPicker.__index = ModelPicker
MHT.ModelPicker = ModelPicker

-- Choosing a model on the 3D tabs: a card per library model, or a pasted copy string

local Library, CopyString = MHT.ModelLibrary, MHT.CopyString
local IMPORT_BOTTOM = 182
local CARD, CARD_GAP = 94, 10
local LIST_HEIGHT = 2 * (CARD + CARD_GAP) + 42

local function selectionFor(window, library)
    local selection = window.modelSettings[library] or {}
    window.modelSettings[library] = selection
    if not Library.Get(library, selection.id) then selection.id = Library.Entries(library)[1].id end
    if selection.source ~= "import" then selection.source = "library" end
    if type(selection.code) ~= "string" then selection.code = nil end
    return selection
end

function ModelPicker.New(window, parent, width, options)
    local library = options.library
    local self = setmetatable({ window = window, container = options.container, library = library,
        selection = selectionFor(window, library), details = options.details, cards = {} }, ModelPicker)
    local UI, track = MHT.UI, options.track
    local entries = Library.Entries(library)

    UI.Heading(parent, "Model", 0, 0, width)
    if options.onReset then
        UI.Tooltip(track(UI.ResetButton(parent, width - 24, 0, options.onReset)), "Reset model and sizes")
    end
    self.libraryButton = track(UI.Button(parent, "Library", 0, 28, 160, function() self:SetSource("library") end, nil, 30))
    self.importButton = track(UI.Button(parent, "Import Code", 168, 28, 160, function() self:SetSource("import") end, nil, 30))

    self.catalog = CreateFrame("Frame", nil, parent)
    self.catalog:SetAllPoints(parent)
    local listHeight = #entries * (CARD + CARD_GAP) - CARD_GAP
    local scrolls = listHeight > LIST_HEIGHT
    local cardWidth = scrolls and width - 16 or width
    local list = CreateFrame("ScrollFrame", nil, self.catalog)
    list:SetPoint("TOPLEFT", 0, -68)
    list:SetSize(cardWidth, math.min(listHeight, LIST_HEIGHT))
    local cards = CreateFrame("Frame", nil, list)
    cards:SetSize(cardWidth, listHeight)
    list:SetScrollChild(cards)
    if scrolls then UI.Scrollbar(list, cards) end
    for i, entry in ipairs(entries) do
        local card = track(UI.Button(cards, "", 0, (i - 1) * (CARD + CARD_GAP), cardWidth, function()
            self.selection.id = entry.id
            window:Refresh()
        end, nil, CARD))
        card.label:Hide()
        local thumbnail = MHT.Preview.New(card, true)
        thumbnail.frame:SetPoint("TOPLEFT", 12, -12)
        thumbnail.frame:SetSize(68, 68)
        local plan = Library.Plan(library, entry.id)
        thumbnail:SetPlan(plan)
        local name = UI.Text(card, entry.name, 94, self.details and 26 or 39, 190)
        local detail = UI.Muted(card, plan and string.format("%d points", #plan.items) or "", 94, 48, 190)
        detail:SetShown(self.details == true)
        self.cards[#self.cards + 1] = { id = entry.id, button = card, name = name }
    end
    self.libraryBottom = 68 + math.min(listHeight, LIST_HEIGHT) + CARD_GAP

    self.importFields = CreateFrame("Frame", nil, parent)
    self.importFields:SetAllPoints(parent)
    local code = track(UI.TextArea(self.importFields, 0, 68, width, 104))
    code:SetText(self.selection.code or "")
    local hint = UI.Muted(code.box, "mouse:…", 8, 8, width - 28)
    local function showHint() hint:SetShown(code:GetText() == "" and not code:HasFocus()) end
    -- Everything is selected on click
    code:HookScript("OnEditFocusGained", function() code:HighlightText(); showHint() end)
    code:HookScript("OnEditFocusLost", showHint)
    code:SetScript("OnTextChanged", function(_, userInput)
        showHint()
        if not userInput then return end
        self.selection.code = code:GetText()
        window:Refresh()
    end)
    showHint()
    self.code = code
    -- Errors only show while the options below are hidden, so they can use that space.
    self.importNote = UI.Muted(self.importFields, "", 0, IMPORT_BOTTOM, width)
    return self
end

-- Keep the result until the string changes to not parse on every refresh.
function ModelPicker:Imported()
    local code = self.selection.code
    if self.importedCode ~= code or not self.imported then
        local model, reason = CopyString.Read(code)
        self.importedCode, self.imported = code, { model = model, reason = reason }
    end
    return self.imported.model, self.imported.reason
end

-- The chosen model at 100% size.
function ModelPicker:Plan()
    if self.selection.source == "import" then
        local model, reason = self:Imported()
        if not model then return nil, reason end
        return CopyString.Plan(model)
    end
    return Library.Plan(self.library, self.selection.id)
end

function ModelPicker:PlaceBelow(frame)
    local top = self.selection.source == "import" and IMPORT_BOTTOM or self.libraryBottom
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", 0, -top)
    frame:SetPoint("BOTTOMRIGHT")
    return top
end

function ModelPicker:ImportNote()
    local plan, reason = self:Plan()
    return plan and "" or reason
end

function ModelPicker:ReplacedItem(plan)
    if self.selection.source ~= "import" then return nil end
    local model = self:Imported()
    if model and model.item ~= plan.requires then return model.item end
end

function ModelPicker:SetSource(source)
    self.selection.source = source
    self.container:ScrollToTop()
    self.window:Refresh()
end

function ModelPicker:Reset()
    self.selection.id, self.selection.source = Library.Entries(self.library)[1].id, "library"
end

function ModelPicker:Refresh()
    local library = self.selection.source == "library"
    self.catalog:SetShown(library)
    self.importFields:SetShown(not library)
    if library then return end
    self.importNote:SetText(self:ImportNote())
end

function ModelPicker:UpdateControls()
    self.libraryButton:SetSelected(self.selection.source == "library")
    self.importButton:SetSelected(self.selection.source == "import")
    for _, card in ipairs(self.cards) do
        card.button:SetSelected(card.id == self.selection.id)
    end
end
