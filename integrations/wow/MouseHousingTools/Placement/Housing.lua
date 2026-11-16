local _, MHT = ...
local API = {}
MHT.Housing = API

function API:Available()
    return C_HousingBasicMode and C_HousingExpertMode and C_HouseEditor
        and C_HousingCatalog and C_HousingCatalog.GetAllVariantInfosForEntry
end

function API:Active()
    return self:Available() and C_HouseEditor.IsHouseEditorActive() and not InCombatLockdown()
end

function API:Mode()
    return C_HouseEditor.GetActiveHouseEditorMode()
end

function API:Switch(mode)
    local result = C_HouseEditor.ActivateHouseEditorMode(Enum.HouseEditorMode[mode])
    if result ~= Enum.HousingResult.Success then
        error("Cannot change housing mode (" .. tostring(result) .. ").")
    end
end

function API:Hovered()
    return C_HousingDecor.GetHoveredDecorInfo()
end

function API:Selected()
    return C_HousingExpertMode.GetSelectedDecorInfo()
end

function API:IsSelected()
    return C_HousingDecor.IsDecorSelected()
end

function API:PendingInfo()
    return C_HousingBasicMode.GetSelectedDecorInfo()
end

function API.DyeKey(slots)
    local values = {}
    for _, slot in ipairs(slots or {}) do
        if slot.dyeColorID and slot.dyeColorID ~= 0 then
            values[#values + 1] = tostring(slot.ID) .. ":" .. tostring(slot.dyeColorID)
        end
    end
    table.sort(values)
    return table.concat(values, ";")
end

local function entryID(decorID)
    return { entryType = Enum.HousingCatalogEntryType.Decor, recordID = decorID }
end

-- The budget the current house has left.
function API:BudgetLeft()
    if not self:Active() then return nil end
    local maximum, spent = C_HousingDecor.GetMaxPlacementBudget(), C_HousingDecor.GetSpentPlacementBudget()
    if maximum and spent then return maximum - spent end
end

-- The source's decor entry and its variants in storage, in any color.
function API:Stored(source)
    local id = entryID(source.decorID)
    local entry = C_HousingCatalog.GetCatalogEntryInfo(id)
    if not entry then return nil, "Item information is not ready. Try again." end
    local variants = {}
    for _, variant in ipairs(C_HousingCatalog.GetAllVariantInfosForEntry(id)) do
        if variant.numStored > 0 then variants[#variants + 1] = variant end
    end
    return entry, variants
end

local SHORT_STOCK = {
    same = "%d copies in the item's colors in storage; %d needed.",
    none = "%d undyed copies in storage; %d needed.",
    any = "%d copies in storage, in any color; %d needed.",
}

-- Copies in storage for a color setting: "same" as the source, "none" for undyed, or "any".
-- "any" uses the source's colors first, then undyed copies, then the rest.
function API:Stock(source, color)
    local entry, stored = self:Stored(source)
    if not entry then return nil, stored end
    color = color or "same"
    local signature = API.DyeKey(source.dyeSlots)
    local stock = { count = 0, variants = {}, name = entry.name, cost = entry.placementCost }
    for _, pass in ipairs({ "same", "none", "other" }) do
        for _, variant in ipairs(stored) do
            local key = API.DyeKey(variant.dyeSlots)
            local group = key == signature and "same" or key == "" and "none" or "other"
            local wanted = color == "any" or color == "same" and key == signature or color == "none" and key == ""
            if group == pass and wanted then
                stock.count = stock.count + variant.numStored
                stock.variants[#stock.variants + 1] = variant.entryVariantID
            end
        end
    end
    return stock
end

function API:CheckStock(source, count, color)
    local stock, reason = self:Stock(source, color)
    if not stock then return nil, reason end
    if stock.count < count then
        return nil, string.format(SHORT_STOCK[color or "same"], stock.count, count)
    end
    local left = self:BudgetLeft()
    if left and stock.cost * count > left then
        return nil, "Not enough housing placement budget for this shape."
    end
    return stock
end

function API:BeginCopy(source, remaining, color)
    local stock, reason = self:CheckStock(source, remaining, color)
    if not stock then error(reason) end
    C_HousingBasicMode.StartPlacingNewDecor(stock.variants[1])
end

function API:HasPendingCopy()
    return C_HousingBasicMode.IsPlacingNewDecor()
end

function API:PlaceCopy()
    C_HousingBasicMode.FinishPlacingNewDecor()
end

function API:Commit()
    C_HousingExpertMode.CommitDecorMovement()
end

function API:Cancel()
    C_HousingDecor.CancelActiveEditing()
end

function API:PrepareSubmode(mode)
    local submode = Enum.HousingPrecisionSubmode[mode]
    if C_HousingExpertMode.GetPrecisionSubmodeRestriction(submode) ~= Enum.HousingExpertSubmodeRestriction.None then
        error("This item cannot use " .. mode:lower() .. " mode.")
    end
    C_HousingExpertMode.SetPrecisionSubmode(submode)
end

function API:InSubmode(mode)
    return C_HousingExpertMode.GetPrecisionSubmode() == Enum.HousingPrecisionSubmode[mode]
end

function API:ResetSubmode()
    C_HousingExpertMode.ResetPrecisionChanges(true)
end

function API:Increment(name, active)
    C_HousingExpertMode.SetPrecisionIncrementingActive(Enum.HousingIncrementType[name], active)
end

function API:CycleRotationAxis()
    C_HousingExpertMode.SelectNextRotationAxis()
end

function API:SaveSettings()
    return {
        free = C_HousingBasicMode.IsFreePlaceEnabled(),
        snap = C_HousingBasicMode.IsGridSnapEnabled(),
    }
end

function API:UsePlacementSettings()
    C_HousingBasicMode.SetFreePlaceEnabled(true)
    C_HousingBasicMode.SetGridSnapEnabled(false)
end

function API:RestoreSettings(settings)
    if not settings then return end
    C_HousingBasicMode.SetFreePlaceEnabled(settings.free)
    C_HousingBasicMode.SetGridSnapEnabled(settings.snap)
end
