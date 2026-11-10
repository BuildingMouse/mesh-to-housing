local _, MHT = ...
local API = MHT.Housing

-- Editor calls only the dev tools use. Calibration copies use two colors, so
-- the copies can be told apart.

function API:CalibrationCopies(source)
    local stock, reason = self:CheckStock(source, 2, true)
    if not stock then return nil, reason end
    local first, second = stock.storedVariants[1]
    local signature = API.DyeKey(source.dyeSlots)
    for _, variant in ipairs(stock.storedVariants) do
        if API.DyeKey(variant.dyeSlots) == signature then first = variant; break end
    end
    for _, variant in ipairs(stock.storedVariants) do
        if API.DyeKey(variant.dyeSlots) ~= API.DyeKey(first.dyeSlots) then second = variant; break end
    end
    if not second then
        for _, variant in ipairs(stock.storedVariants) do
            if variant ~= first or variant.numStored > 1 then second = variant; break end
        end
    end
    return { first.entryVariantID, second.entryVariantID }
end

function API:BeginColorCopy(source, remaining, variantID)
    local stock, reason = self:CheckStock(source, remaining, true)
    if not stock then error(reason) end
    local variant = C_HousingCatalog.GetCatalogEntryVariantInfo(variantID)
    if not variant or variant.numStored < 1 then error("The chosen calibration color is no longer in storage.") end
    C_HousingBasicMode.StartPlacingNewDecor(variantID)
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
