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

--- Scan bags only, return { [itemId] = count }.  Cheap, runs every BAG_UPDATE.
local function ScanBagsOnly()
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

-- Personal bank container IDs.  -1 is the main 28-slot bank; 5..11 are the
-- purchasable bank bag slots.  GetContainerNumSlots returns 0 for unowned
-- slots so we can scan the full range unconditionally.
local BANK_CONTAINER = -1
local FIRST_BANK_BAG = 5
local LAST_BANK_BAG  = 11

--- Scan personal bank slots and overwrite Ace.db.char.bankCounts.
-- Only meaningful while at the bank — GetContainerItemInfo for these IDs
-- returns nil otherwise, so calling this when not at the bank would erase
-- the cache.  Caller must gate this on BANKFRAME_OPENED having fired.
local function ScanPersonalBank()
    local counts = {}
    local function scanBag(bag)
        local slots = addon:GetContainerNumSlots(bag) or 0
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
    scanBag(BANK_CONTAINER)
    for bag = FIRST_BANK_BAG, LAST_BANK_BAG do scanBag(bag) end
    Ace.db.char.bankCounts = counts
end

--- Scan personal mailbox attachments and overwrite Ace.db.char.mailCounts.
-- Mirrors TOGBankClassic's MailInventory pattern: scan on MAIL_CLOSED to
-- capture all changes (items added, taken, mail expired, etc.).  COD mail
-- is excluded because the attachments aren't really in our possession
-- until we pay — the WoW mail UI also forbids partial-take on COD.
local function ScanPersonalMail()
    local counts = {}
    local numItems = (GetInboxNumItems and GetInboxNumItems()) or 0
    local maxAttachments = ATTACHMENTS_MAX_RECEIVE or 16
    for i = 1, numItems do
        local _, _, _, _, _, codAmount, _, hasItem = GetInboxHeaderInfo(i)
        if hasItem and (codAmount or 0) == 0 then
            for j = 1, maxAttachments do
                local _, itemID, _, count = GetInboxItem(i, j)
                if itemID and count and count > 0 then
                    counts[itemID] = (counts[itemID] or 0) + count
                end
            end
        end
    end
    Ace.db.char.mailCounts = counts
end

--- Scan bags AND merge in cached personal bank + cached mail counts.
-- Returns { [itemId] = count }.  This is the "have" view used by Reagent
-- Watch alerts and the Reagent Tracker — anything in the player's bags,
-- personal bank, or mailbox counts as in possession.  Guild bank stock
-- (TOGBankClassic) is intentionally NOT included here; that's surfaced
-- separately as a +<bank> annotation in the UI.
local function ScanBags()
    local counts = ScanBagsOnly()
    local bank = Ace.db.char.bankCounts
    if bank then
        for id, n in pairs(bank) do counts[id] = (counts[id] or 0) + n end
    end
    local mail = Ace.db.char.mailCounts
    if mail then
        for id, n in pairs(mail) do counts[id] = (counts[id] or 0) + n end
    end
    return counts
end

-- Expose the personal-bank/mail scanners for slash-command refresh.
RW._ScanPersonalBank = ScanPersonalBank
RW._ScanPersonalMail = ScanPersonalMail

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

--- Return true if itemId is currently on the watch list.
function RW:IsWatching(itemId)
    itemId = tonumber(itemId)
    if not itemId then return false end
    return Ace.db.char.reagentWatch[itemId] == true
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

-- Bank: scan on close (mirrors TOGBankClassic).  GetContainerItemInfo for
-- bank slots is reliable while the bank window is shown; scanning on close
-- captures the final state after the player finishes moving items around.
-- Cached counts persist via SavedVariables so the data stays usable away
-- from the bank.
Ace:RegisterEvent("BANKFRAME_CLOSED", function()
    ScanPersonalBank()
    addon.callbacks:Fire("REAGENT_WATCH_UPDATED")
    CheckAlerts(ScanBags())
end)

-- Mail: same scan-on-close pattern.  COD-attached mail is filtered out
-- inside ScanPersonalMail (we don't actually possess those items yet).
Ace:RegisterEvent("MAIL_CLOSED", function()
    ScanPersonalMail()
    addon.callbacks:Fire("REAGENT_WATCH_UPDATED")
    CheckAlerts(ScanBags())
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
