-- TOG Profession Master — Tooltip hook
-- Appends crafters to any item tooltip (SetItem / SetHyperlink).
-- Uses AceHook-3.0 (mixed into Ace in TOGProfessionMaster.lua).
-- Only runs when the player is in a guild with data.

local _, addon = ...
local Ace = addon.lib

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

-- Returns ordered list {name, profession, skillLevel, maxLevel, online}
-- for every guild member who can craft itemID.
local function FindCrafters(itemID)
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.recipes then return nil end

    local GuildCache = addon.Scanner and addon.Scanner.GuildCache
    local roster     = {}

    for profId, profRecipes in pairs(gdb.recipes) do
        for recipeId, rd in pairs(profRecipes) do
            if not rd.isSpell and recipeId == itemID then
                for charKey in pairs(rd.crafters or {}) do
                    local name      = charKey:match("^(.-)%-") or charKey
                    local skillData = gdb.skills and gdb.skills[charKey] and gdb.skills[charKey][profId]
                    local online    = GuildCache and GuildCache:IsPlayerOnline(charKey) or false
                    if not online and gdb.altGroups and gdb.altGroups[charKey] then
                        for _, altCk in ipairs(gdb.altGroups[charKey]) do
                            if altCk ~= charKey and GuildCache and GuildCache:IsPlayerOnline(altCk) then
                                online = true
                                break
                            end
                        end
                    end
                    roster[#roster + 1] = {
                        name       = name,
                        profession = addon.PROF_NAMES[profId] or tostring(profId),
                        skillLevel = skillData and skillData.skillRank or 0,
                        maxLevel   = skillData and skillData.skillMax  or 0,
                        online     = online,
                    }
                end
                break
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

local HEADER_COLOR  = "|c" .. (addon.BrandColor  or "ffDA8CFF")
local ONLINE_COLOR  = "|c" .. (addon.ColorOnline  or "ffffffff")
local OFFLINE_COLOR = "|c" .. (addon.ColorOffline or "ff888888")
local RESET_COLOR   = "|r"

local function AppendCrafters(tooltip, itemID)
    tooltip._togpmAppended = itemID  -- mark processed so post-hooks skip
    if IsBOP(itemID) then return end

    local crafters = FindCrafters(itemID)
    if not crafters then return end

    local parts = {}
    for _, c in ipairs(crafters) do
        local col = c.online and ONLINE_COLOR or OFFLINE_COLOR
        parts[#parts + 1] = col .. c.name .. RESET_COLOR
    end
    -- |n embeds the blank line inside a single AddLine so it can't be
    -- reordered by the tooltip's internal build order.
    tooltip:AddLine("|n" .. HEADER_COLOR .. "[TOGPM]" .. RESET_COLOR .. " " .. table.concat(parts, ", "),
        1, 1, 1, true)
end

-- Exposed so BrowserTab can call it directly on its custom-built tooltips
-- (those paths bypass SetHyperlink so the hook never fires).
addon.Tooltip.AppendCrafters = AppendCrafters

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------

local function OnTooltipSetItem(tooltip)
    if tooltip._togpmAppended then return end
    local itemID = ItemIdFromTooltip(tooltip)
    if itemID then AppendCrafters(tooltip, itemID) end
end

local function OnTooltipCleared(tooltip)
    tooltip._togpmAppended = nil
end

-- Register after PLAYER_LOGIN so SavedVariables are loaded
Ace:RegisterEvent("PLAYER_LOGIN", function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
       and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        -- MoP Classic+ / Retail: single post-call fires for every item tooltip
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if data and data.id then AppendCrafters(tooltip, data.id) end
        end)
    else
        -- Vanilla / TBC / Wrath / Cata Classic: hook OnTooltipSetItem on every
        -- item-displaying tooltip. OnTooltipCleared resets the de-dup flag.
        local frames = { GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2, ShoppingTooltip3 }
        for _, tt in ipairs(frames) do
            if tt then
                tt:HookScript("OnTooltipSetItem", OnTooltipSetItem)
                tt:HookScript("OnTooltipCleared", OnTooltipCleared)
            end
        end
    end
end)
