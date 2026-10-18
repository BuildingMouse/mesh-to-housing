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

local function dyeKey(slots)
    local values = {}
    for _, slot in ipairs(slots or {}) do
        if slot.dyeColorID and slot.dyeColorID ~= 0 then
            values[#values + 1] = tostring(slot.ID) .. ":" .. tostring(slot.dyeColorID)
        end
    end
    table.sort(values)
    return table.concat(values, ";")
end
API.DyeKey = dyeKey

function API:Stock(source, anyColor)
    local entryID = { entryType = Enum.HousingCatalogEntryType.Decor, recordID = source.decorID }
    local entry = C_HousingCatalog.GetCatalogEntryInfo(entryID)
    if not entry then return nil, "Item information is not ready. Try again." end
    local signature = dyeKey(source.dyeSlots)
    local stock = { count = 0, variants = {}, storedVariants = {}, name = entry.name, cost = entry.placementCost }
    for _, variant in ipairs(C_HousingCatalog.GetAllVariantInfosForEntry(entryID)) do
        if variant.numStored > 0 and (anyColor or dyeKey(variant.dyeSlots) == signature) then
            stock.count = stock.count + variant.numStored
            stock.variants[#stock.variants + 1] = variant.entryVariantID
            stock.storedVariants[#stock.storedVariants + 1] = variant
        end
    end
    return stock
end

function API:CheckStock(source, count, anyColor)
    local stock, reason = self:Stock(source, anyColor)
    if not stock then return nil, reason end
    if stock.count < count then
        return nil, string.format("%d %scopies in storage; %d needed. Source item is kept.",
            stock.count, anyColor and "" or "matching ", count)
    end
    local maximum = C_HousingDecor.GetMaxPlacementBudget()
    local spent = C_HousingDecor.GetSpentPlacementBudget()
    if maximum and spent and spent + stock.cost * count > maximum then
        return nil, "Not enough housing placement budget for this shape."
    end
    return stock
end

function API:CalibrationCopies(source)
    local stock, reason = self:CheckStock(source, 2, true)
    if not stock then return nil, reason end
    local first, second = stock.storedVariants[1]
    local signature = dyeKey(source.dyeSlots)
    for _, variant in ipairs(stock.storedVariants) do
        if dyeKey(variant.dyeSlots) == signature then first = variant; break end
    end
    for _, variant in ipairs(stock.storedVariants) do
        if dyeKey(variant.dyeSlots) ~= dyeKey(first.dyeSlots) then second = variant; break end
    end
    if not second then
        for _, variant in ipairs(stock.storedVariants) do
            if variant ~= first or variant.numStored > 1 then second = variant; break end
        end
    end
    return { first.entryVariantID, second.entryVariantID }
end

function API:BeginCopy(source, remaining, variantID)
    local stock, reason = self:CheckStock(source, remaining, variantID ~= nil)
    if not stock then error(reason) end
    if variantID then
        local variant = C_HousingCatalog.GetCatalogEntryVariantInfo(variantID)
        if not variant or variant.numStored < 1 then error("The chosen calibration color is no longer in storage.") end
    end
    C_HousingBasicMode.StartPlacingNewDecor(variantID or stock.variants[1])
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

function API:PrepareSubmode(mode, reset)
    local submode = Enum.HousingPrecisionSubmode[mode]
    if C_HousingExpertMode.GetPrecisionSubmodeRestriction(submode) ~= Enum.HousingExpertSubmodeRestriction.None then
        error("This item cannot use " .. mode:lower() .. " mode.")
    end
    C_HousingExpertMode.SetPrecisionSubmode(submode)
    if reset then C_HousingExpertMode.ResetPrecisionChanges(true) end
end

function API:Increment(name, active)
    C_HousingExpertMode.SetPrecisionIncrementingActive(Enum.HousingIncrementType[name], active)
end

function API:CycleRotationAxis()
    C_HousingExpertMode.SelectNextRotationAxis()
end

function API:PrecisionSubmode()
    return C_HousingExpertMode.GetPrecisionSubmode()
end

function API:MovementBindings()
    local bindings = {}
    for _, axis in ipairs(MHT.MovementCapture.Axes) do
        for _, name in ipairs({ axis.positive, axis.negative }) do
            local action = "HOUSING_EXPERTDECORINCREMENT_" .. name:upper()
            local keys = { GetBindingKey(action) }
            if #keys == 0 and C_KeyBindings then
                local key = C_KeyBindings.GetBindingByKey(action, Enum.BindingContext.HousingEditorExpertDecorMode)
                if key and key ~= "" then keys[1] = key end
            end
            bindings[name] = keys
        end
    end
    return bindings
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
