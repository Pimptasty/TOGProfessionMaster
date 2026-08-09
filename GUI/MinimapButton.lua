-- TOG Profession Master — Minimap Button
-- LibDataBroker-1.1 data object + LibDBIcon-1.0 minimap button.
--
-- Left-click        → open profession browser
-- Right-click       → open missing reagents (shopping list)
-- Shift+Left-click  → open settings

local _, addon = ...
local Ace = addon.lib
local L   = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

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
        -- `nil, nil, nil, true` is Blizzard's own idiom for "default colour, but
        -- opt into the engine's wrap preset" -- PaperDollFrame.lua:880 in the
        -- Vanilla tree does exactly this. The flag has to sit fifth, so the three
        -- colour slots must be filled even when we do not want to set a colour.
        -- Audit finding 20: this file was outside the wrap sweep entirely, and
        -- these lines are localised, so their length is not ours to bound.
        tt:AddLine("|cffda8cffTOG Profession Master|r", nil, nil, nil, true)
        tt:AddLine(" ")
        tt:AddLine(L["MinimapTooltipLeftClick"], nil, nil, nil, true)
        tt:AddLine(L["MinimapTooltipRightClick"], nil, nil, nil, true)
        tt:AddLine(L["MinimapTooltipShiftLeft"], nil, nil, nil, true)
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
    --
    -- v0.7.1: the table passed here MUST be the one that persists across
    -- reloads — LibDBIcon writes the new angle into it when the user drags
    -- the button, so if we pass a throwaway local table the new position
    -- gets lost on the next /reload. Use a sub-table living directly on
    -- the AceDB profile so writes propagate automatically. The legacy
    -- profile.minimapPos field stays untouched as a one-time seed value
    -- so existing users don't lose their position on first v0.7.1 launch.
    if type(Ace.db.profile.minimap) ~= "table" then
        Ace.db.profile.minimap = {}
    end
    local md = Ace.db.profile.minimap
    if type(md.minimapPos) ~= "number" then
        md.minimapPos = Ace.db.profile.minimapPos or 220
    end
    md.hide = not Ace.db.profile.minimapButton

    icon:Register("TOGProfessionMaster", dataObj, md)
    addon:DebugPrint("MinimapButton: registered (pos:", md.minimapPos, "hide:", md.hide, ")")
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
    self:Print(L["MinimapButtonShown"])
end

-- ---------------------------------------------------------------------------
-- Hook Ace lifecycle
-- ---------------------------------------------------------------------------

hooksecurefunc(Ace, "OnEnable", function(_self)
    SetupMinimapButton()
end)
