-- TOG Profession Master — Minimap Button
-- LibDataBroker-1.1 data object + LibDBIcon-1.0 minimap button.
--
-- Left-click        → open profession browser
-- Right-click       → open missing reagents (shopping list)
-- Shift+Left-click  → open settings

local _, addon = ...
local Ace = addon.lib

-- ---------------------------------------------------------------------------
-- LDB data object
-- ---------------------------------------------------------------------------

local LDB = LibStub("LibDataBroker-1.1", true)
if not LDB then
    addon:DebugPrint("MinimapButton: LibDataBroker-1.1 not found — minimap button disabled")
    return
end

local dataObj = LDB:NewDataObject("TOGProfessionMaster", {
    type  = "launcher",
    label = "TOG Profession Master",
    icon  = "Interface\\AddOns\\TOGProfessionMaster\\icons\\TOGPM_MMB_Icon",

    OnClick = function(_self, button)
        if button == "LeftButton" then
            if IsShiftKeyDown() then
                addon:OpenSettings()
            else
                addon:OpenBrowser()
            end
        elseif button == "RightButton" then
            addon:OpenReagents()
        end
    end,

    OnTooltipShow = function(tt)
        tt:AddLine("|cffda8cffTOG Profession Master|r")
        tt:AddLine(" ")
        tt:AddLine("|cffffd100Left-click|r to toggle profession browser")
        tt:AddLine("|cffffd100Right-click|r to toggle reagents")
        tt:AddLine("|cffffd100Shift+Left|r to open settings")
    end,
})

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

local function SetupMinimapButton()
    local icon = LibStub("LibDBIcon-1.0", true)
    if not icon then
        addon:DebugPrint("MinimapButton: LibDBIcon-1.0 not found")
        return
    end

    -- LibDBIcon expects a db table with:
    --   minimapPos  (number)  — angle in degrees, default 220
    --   hide        (bool)    — whether the button is hidden
    if type(Ace.db.profile.minimapPos) ~= "number" then
        Ace.db.profile.minimapPos = 220
    end

    local minimapData = {
        hide       = not Ace.db.profile.minimapButton,
        minimapPos = Ace.db.profile.minimapPos,
    }

    icon:Register("TOGProfessionMaster", dataObj, minimapData)
    addon:DebugPrint("MinimapButton: registered")
end

-- ---------------------------------------------------------------------------
-- ShowMinimapButton (called by /togpm minimap)
-- ---------------------------------------------------------------------------

function addon:ShowMinimapButton()
    Ace.db.profile.minimapButton = true
    local icon = LibStub("LibDBIcon-1.0", true)
    if icon then
        icon:Show("TOGProfessionMaster")
    end
    addon:Print("Minimap button shown.")
end

-- ---------------------------------------------------------------------------
-- Hook Ace lifecycle
-- ---------------------------------------------------------------------------

hooksecurefunc(Ace, "OnEnable", function(_self)
    SetupMinimapButton()
end)
