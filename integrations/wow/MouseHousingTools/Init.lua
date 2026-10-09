local addonName, MHT = ...
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")

local function stopOnError(action, ...)
    local ok, reason = pcall(action, ...)
    if not ok and MHT.window then
        MHT.window.placement:Abort(tostring(reason))
    end
end

local function initialize()
    MouseHousingToolsDB = MouseHousingToolsDB or {}
    local db = MouseHousingToolsDB

    db.settings = db.settings or {}
    for key, value in pairs(MHT.Layout.defaults) do
        if db.settings[key] == nil then db.settings[key] = value end
    end

    if not MHT.Layout.Validate(db.settings) then
        db.settings = {}
        for key, value in pairs(MHT.Layout.defaults) do
            db.settings[key] = value
        end
    end

    db.ui = db.ui or {}

    MHT.window = MHT.Window.New(db.settings, db.ui)
    MHT.editorControls = MHT.EditorControls.New(MHT.window)

    SLASH_MOUSEHOUSINGTOOLS1 = "/mht"
    SLASH_MOUSEHOUSINGTOOLS2 = "/mousehousingtools"
    SlashCmdList.MOUSEHOUSINGTOOLS = function(message)
        local command = strtrim(string.lower(message or ""))

        if command == "start" then
            MHT.window:StartPlacement()
        elseif command == "stop" or command == "end" or command == "abort" then
            MHT.window:EndPlacement()
        elseif command == "show" or command == "settings" then
            if not MHT.window.frame:IsShown() then MHT.window:Toggle() end
        elseif command == "hide" then
            MHT.window.frame:Hide()
        else
            MHT.window:Toggle()
        end

        if not MHT.Housing:Available() then
            MHT.window:SetStatus("Preview is available. Placement needs Retail housing with catalog variants (12.0.5+).")
        end
    end

    for _, event in ipairs({
        "HOUSE_EDITOR_MODE_CHANGE_FAILURE",
        "HOUSING_DECOR_PLACE_FAILURE",
        "HOUSING_DECOR_PLACE_SUCCESS",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_LEAVING_WORLD",
        "HOUSE_EDITOR_MODE_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_REGEN_ENABLED",
    }) do
        events:RegisterEvent(event)
    end

    events:SetScript("OnUpdate", function(_, elapsed)
        stopOnError(MHT.window.placement.Update, MHT.window.placement, elapsed)
    end)

    MHT.editorControls:Sync()
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == addonName then
            initialize()
            events:UnregisterEvent("ADDON_LOADED")
        end
        return
    end

    if not MHT.window then return end

    stopOnError(MHT.window.placement.OnEvent, MHT.window.placement, event, ...)

    if event == "HOUSE_EDITOR_MODE_CHANGED"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_LEAVING_WORLD"
        or event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        stopOnError(
            MHT.editorControls.Sync,
            MHT.editorControls,
            event == "PLAYER_LEAVING_WORLD"
        )
    end
end)
