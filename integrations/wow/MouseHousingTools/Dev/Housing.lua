local _, MHT = ...
local API = MHT.Housing

-- Editor calls only the dev tools use. Calibration copies use two colors, so
-- the copies can be told apart.

local function anyColorStock(api, source, count)
    local entry, stored = api:Stored(source)
    if not entry then return nil, stored end
    local total = 0
    for _, variant in ipairs(stored) do total = total + variant.numStored end
    if total < count then return nil, string.format("%d copies in storage; %d needed.", total, count) end
    return stored
end

function API:CalibrationCopies(source)
    local stored, reason = anyColorStock(self, source, 2)
    if not stored then return nil, reason end
    local first, second = stored[1]
    local signature = API.DyeKey(source.dyeSlots)
    for _, variant in ipairs(stored) do
        if API.DyeKey(variant.dyeSlots) == signature then first = variant; break end
    end
    for _, variant in ipairs(stored) do
        if API.DyeKey(variant.dyeSlots) ~= API.DyeKey(first.dyeSlots) then second = variant; break end
    end
    if not second then
        for _, variant in ipairs(stored) do
            if variant ~= first or variant.numStored > 1 then second = variant; break end
        end
    end
    return { first.entryVariantID, second.entryVariantID }
end

function API:BeginColorCopy(source, remaining, variantID)
    local stored, reason = anyColorStock(self, source, remaining)
    if not stored then error(reason) end
    local variant = C_HousingCatalog.GetCatalogEntryVariantInfo(variantID)
    if not variant or variant.numStored < 1 then error("The chosen calibration color is no longer in storage.") end
    C_HousingBasicMode.StartPlacingNewDecor(variantID)
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
