local addonName, MHT = ...
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")

local function stopOnError(action, ...)
    local ok, reason = pcall(action, ...)
    if not ok and MHT.window then MHT.window.placement:Abort(tostring(reason)) end
end

local function initialize()
    MouseHousingToolsDB = MouseHousingToolsDB or {}
    local db = MouseHousingToolsDB
    db.settings = db.settings or {}
    for key, value in pairs(MHT.Layout.defaults) do
        if db.settings[key] == nil then db.settings[key] = value end
    end
    db.calibration = db.calibration or { right = 0, forward = 0, up = 0, grow = 0, shrink = 0 }
    if not MHT.Layout.Validate(db.settings) then
        db.settings = {}
        for key, value in pairs(MHT.Layout.defaults) do db.settings[key] = value end
    end
    MHT.window = MHT.Window.New(db.settings, db.calibration)
    SLASH_MOUSEHOUSINGTOOLS1 = "/mht"
    SLASH_MOUSEHOUSINGTOOLS2 = "/mousehousingtools"
    SlashCmdList.MOUSEHOUSINGTOOLS = function()
        MHT.window.frame:SetShown(not MHT.window.frame:IsShown())
        if not MHT.Housing:Available() then
            MHT.window.status:SetText("Preview is available. Placement needs Retail housing with catalog variants (12.0.5+).")
        end
    end
    for _, event in ipairs({ "HOUSE_EDITOR_MODE_CHANGE_FAILURE", "HOUSING_DECOR_PLACE_FAILURE",
                            "HOUSING_DECOR_PLACE_SUCCESS", "PLAYER_REGEN_DISABLED", "PLAYER_LEAVING_WORLD" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnUpdate", function(_, elapsed)
        stopOnError(MHT.window.placement.Update, MHT.window.placement, elapsed)
    end)
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == addonName then initialize(); events:UnregisterEvent("ADDON_LOADED") end
    elseif MHT.window then
        stopOnError(MHT.window.placement.OnEvent, MHT.window.placement, event, ...)
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then MHT.window.calibration:Restore() end
    end
end)
