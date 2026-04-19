-- TOG Profession Master — Reagent Watch + Shopping List Alerts
-- Handles BAG_UPDATE logic only; the UI panel lives in GUI/ShoppingListTab.lua.
--
-- 9.3 Reagent Watch
--   db.char.reagentWatch = { [itemId] = true }
--   Tracks a custom list of item IDs the player cares about.
--   Fires addon.callbacks "REAGENT_WATCH_UPDATED" on each BAG_UPDATE so the
--   UI panel can refresh.
--
-- 9.4 Shopping List Alerts
--   When ALL reagents for a queued craft are satisfied in bags, print a chat
--   notification once (guarded by db.char.shoppingAlerts[spellId]).
--   The flag is cleared when reagents drop below the requirement so the player
--   gets a fresh alert next time they stock up.

local _, addon = ...
local Ace = addon.lib
local L   = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

local RW = {}
addon.ReagentWatch = RW

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Scan bags, return { [itemId] = count }.
local function ScanBags()
    local counts = {}
    local numBags = addon:GetNumBagSlots()
    for bag = 0, numBags do
        local slots = addon:GetContainerNumSlots(bag)
        for slot = 1, slots do
            local info = addon:GetContainerItemInfo(bag, slot)
            if info then
                local itemId = info.itemID or info.itemId
                if itemId then
                    counts[itemId] = (counts[itemId] or 0) + (info.stackCount or 1)
                end
            end
        end
    end
    return counts
end

-- ---------------------------------------------------------------------------
-- 9.3 — Reagent Watch
-- ---------------------------------------------------------------------------

--- Add an item to the watch list.
function RW:Watch(itemId)
    itemId = tonumber(itemId)
    if not itemId then return end
    Ace.db.char.reagentWatch[itemId] = true
    addon.callbacks:Fire("REAGENT_WATCH_UPDATED")
end

--- Remove an item from the watch list.
function RW:Unwatch(itemId)
    itemId = tonumber(itemId)
    if not itemId then return end
    Ace.db.char.reagentWatch[itemId] = nil
    addon.callbacks:Fire("REAGENT_WATCH_UPDATED")
end

--- Return sorted array of { itemId, itemName, count } for the watch list.
function RW:GetWatchedItems()
    local bags = ScanBags()
    local list = {}
    for itemId in pairs(Ace.db.char.reagentWatch) do
        local name = GetItemInfo(itemId) or "|cffaaaaaa(loading…)|r"
        list[#list + 1] = {
            itemId   = itemId,
            itemName = name,
            count    = bags[itemId] or 0,
        }
    end
    table.sort(list, function(a, b) return a.itemName < b.itemName end)
    return list
end

-- ---------------------------------------------------------------------------
-- 9.4 — Shopping List Alerts
-- ---------------------------------------------------------------------------

--- Check every shopping list entry; fire a chat alert the first time all
--- reagents for a craft are present in bags.  Clear the "alerted" flag when
--- bags drop below requirements so the player gets a fresh alert next time.
local function CheckAlerts(bags)
    local bl   = Ace.db.char.shoppingList
    local alrt = Ace.db.char.shoppingAlerts
    local data = addon:GetCooldownData()

    for spellId, entry in pairs(bl) do
        local qty     = (entry and entry.quantity) or 1
        local reagent = data.reagents[spellId] or data.transReagents[spellId]
        if reagent then
            local have    = bags[reagent.id] or 0
            local needed  = reagent.qty * qty
            local ready   = have >= needed

            if ready and not alrt[spellId] then
                -- First time ready — alert
                alrt[spellId] = true
                local spellName = GetSpellInfo(spellId) or tostring(spellId)
                local itemName  = GetItemInfo(reagent.id) or tostring(reagent.id)
                addon:Print(string.format(
                    L["AlertReadyFormat"],
                    spellName, qty, itemName, have
                ))
            elseif not ready and alrt[spellId] then
                -- Bags dropped below requirement — clear flag so next restock
                -- triggers a fresh alert
                alrt[spellId] = nil
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event wiring
-- ---------------------------------------------------------------------------

Ace:RegisterEvent("BAG_UPDATE", function()
    local bags = ScanBags()

    -- Notify the UI that bag counts may have changed
    addon.callbacks:Fire("REAGENT_WATCH_UPDATED")

    -- Run shopping list alert check
    CheckAlerts(bags)
end)

-- Also check on login in case bags are already stocked
Ace:RegisterEvent("PLAYER_LOGIN", function()
    local bags = ScanBags()
    -- Don't alert on login — pre-populate flags silently so first legitimate
    -- restock triggers the message
    local bl   = Ace.db.char.shoppingList
    local alrt = Ace.db.char.shoppingAlerts
    local data = addon:GetCooldownData()
    for spellId, entry in pairs(bl) do
        local qty     = (entry and entry.quantity) or 1
        local reagent = data.reagents[spellId] or data.transReagents[spellId]
        if reagent then
            local have = bags[reagent.id] or 0
            if have >= reagent.qty * qty then
                alrt[spellId] = true  -- already ready on login, don't spam
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Public helper: clear alert state for a spell (called when removed from BL)
-- ---------------------------------------------------------------------------

function RW:ClearAlert(spellId)
    Ace.db.char.shoppingAlerts[spellId] = nil
end
