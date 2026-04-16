-- TOG Profession Master — Tooltip hook
-- Appends crafters to any item tooltip (SetItem / SetHyperlink).
-- Uses AceHook-3.0 (mixed into Ace in TOGProfessionMaster.lua).
-- Only runs when the player is in a guild with data.

local _, addon = ...
local Ace = addon.lib
local L   = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- Attempt to locate AceHook-3.0 on the addon object.
-- AceAddon-3.0 mixes it in if listed in the :NewAddon() call; we rely on
-- that rather than require the lib directly.
if not Ace.HookScript then
    addon:DebugPrint("Tooltip: AceHook-3.0 not mixed in — tooltip hooks disabled")
    return
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Extract numeric item ID from a hyperlink, e.g. "|cff...|Hitem:1234:...|h".
local function ItemIdFromLink(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Extract item ID from a link or plain itemstring returned by GetItem().
local function ItemIdFromTooltip(tooltip)
    local _, link = tooltip:GetItem()
    return link and ItemIdFromLink(link)
end

-- Return true when the item flags indicate Bind-on-Pickup so we skip BOPs.
local function IsBOP(itemID)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemID)
    return bindType == 1  -- LE_ITEM_BIND_ON_ACQUIRE
end

-- ---------------------------------------------------------------------------
-- Core lookup
-- ---------------------------------------------------------------------------

-- Returns ordered list {charKey, charName, profession, skillLevel, online}
-- for every guild member who can craft itemID.
local function FindCrafters(itemID)
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.guildData then return nil end

    local roster = {}
    for charKey, charData in pairs(gdb.guildData) do
        if charData.professions then
            for _, prof in ipairs(charData.professions) do
                if prof.recipes then
                    for _, recipe in ipairs(prof.recipes) do
                        if recipe.craftedItemId == itemID then
                            local name, realm = charKey:match("^(.+)-(.+)$")
                            roster[#roster + 1] = {
                                charKey    = charKey,
                                name       = name or charKey,
                                profession = prof.name,
                                skillLevel = prof.skillLevel or 0,
                                maxLevel   = prof.maxLevel   or 0,
                                online     = (gdb.factions and gdb.factions[charKey] ~= nil)
                                              and (GetGuildRosterMOTD and true or false),
                            }
                            break  -- each profession can only output an item once
                        end
                    end
                end
            end
        end
    end

    if #roster == 0 then return nil end

    -- Online first, then alpha by name
    table.sort(roster, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return roster
end

-- ---------------------------------------------------------------------------
-- Append lines to a GameTooltip frame
-- ---------------------------------------------------------------------------

local HEADER_COLOR  = "|cff00ccff"
local ONLINE_COLOR  = "|cffffffff"
local OFFLINE_COLOR = "|cff888888"
local RESET_COLOR   = "|r"

local function AppendCrafters(tooltip, itemID)
    if IsBOP(itemID) then return end

    local crafters = FindCrafters(itemID)
    if not crafters then return end

    tooltip:AddLine(HEADER_COLOR .. L["CraftedBy"] .. RESET_COLOR)
    for _, c in ipairs(crafters) do
        local col  = c.online and ONLINE_COLOR or OFFLINE_COLOR
        local line = string.format("%s%s|r  %s(%d/%d)",
            col, c.name, c.profession, c.skillLevel, c.maxLevel)
        tooltip:AddLine("  " .. line)
    end
    tooltip:Show()  -- resize to fit new lines
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------

local function OnTooltipSetItem(tooltip)
    local itemID = ItemIdFromTooltip(tooltip)
    if itemID then AppendCrafters(tooltip, itemID) end
end

local function OnTooltipSetHyperlink(tooltip, link)
    local itemID = ItemIdFromLink(link)
    if itemID then AppendCrafters(tooltip, itemID) end
end

-- Register after PLAYER_LOGIN so SavedVariables are loaded
Ace:RegisterEvent("PLAYER_LOGIN", function()
    -- Use raw hooks so we don't need the secure-hook wrapper variants
    if GameTooltip.SetItem then
        Ace:HookScript(GameTooltip, "OnTooltipSetItem", OnTooltipSetItem)
    end
    if GameTooltip.SetHyperlink then
        Ace:Hook(GameTooltip, "SetHyperlink", OnTooltipSetHyperlink, true)
    end

    -- Also hook ItemRefTooltip used when clicking links in chat
    if ItemRefTooltip and ItemRefTooltip.SetHyperlink then
        Ace:Hook(ItemRefTooltip, "SetHyperlink", OnTooltipSetHyperlink, true)
    end
end)
