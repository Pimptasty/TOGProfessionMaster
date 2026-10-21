-- Ultimate Profession Master — Minimap Button
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

-- FOR THE OFFLINE TEST SUITE, not a production requirement: in game this file
-- loads once and GetDataObjectByName is always nil here. The suite reloads the
-- file (Tests/reloadleak_spec.lua) while LibDataBroker lives for the whole run,
-- and NewDataObject answers nil for a name it already holds, which left the
-- reloaded copy with no object to register. Peer Review 427847d6.
local dataObj = LDB:GetDataObjectByName("TOGProfessionMaster") or LDB:NewDataObject("TOGProfessionMaster", {
    type  = "launcher",
    label = "Ultimate Profession Master",
    icon  = "Interface\\AddOns\\TOGProfessionMaster\\icons\\UPM_MMB_Icon",
    -- The UPM art is a disc with transparent margin around it, so drawn whole
    -- into LibDBIcon's 17px slot it came out small inside the dark backing
    -- (operator, in game 2026-10-21: "the rest of the icons aren't squished
    -- like mine"). LibDBIcon crops by dataObject.iconCoords (LibDBIcon-1.0
    -- updateCoord); zoom past the margin so the disc fills the slot. The
    -- window spans 0.69 of the art, so one pixel of the 17px slot is ~0.04;
    -- it sits off-centre to centre the coin, tuned in game by the operator
    -- ("needs to go down 1px and right 1px", then "about 50% of that back
    -- up and left" -> net window up and left 0.02).
    -- Order is { left, right, top, bottom }.
    iconCoords = { 0.135, 0.825, 0.105, 0.795 },

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
        tt:AddLine("|c" .. (addon.BrandColor or "ffFF8000") .. "Ultimate Profession Master|r", nil, nil, nil, true)
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
