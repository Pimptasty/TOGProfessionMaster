-- TOG Profession Master — reagent counts + Shopping List Alerts
-- Handles BAG_UPDATE logic only; it has no UI of its own.
--
-- Reagent counts
--   Caches the personal bank (BANKFRAME_CLOSED) and mailbox (MAIL_CLOSED)
--   counts, and fires addon.callbacks "REAGENT_WATCH_UPDATED" on each
--   BAG_UPDATE so the tabs that colour reagents by stock can repaint. (The
--   event keeps its old name. The item watch list it was named for lived on
--   the Shopping List tab, which the main window never drew; both were
--   removed as dead code in v1.1.2.)
--
-- Shopping List Alerts
--   When ALL reagents for a queued craft are satisfied in bags, print a chat
--   notification once (guarded by the module-local `alerted` latch -- NOT
--   db.char.shoppingAlerts, which is the crafter-online opt-in).
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
--- The implementation is addon:ScanBagCounts in Compat.lua.
local function ScanBagsOnly()
    return addon:ScanBagCounts()
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

--- Cached personal-bank count for one item id (0 if none / never scanned).
-- This is the last snapshot taken when the player closed their bank
-- (BANKFRAME_CLOSED), so it persists between sessions but can be stale until
-- the next bank visit. Used by the Crafting tab's bank/bags/need reagent column.
function RW:GetBankCount(itemId)
    local bc = Ace.db and Ace.db.char and Ace.db.char.bankCounts
    return (bc and itemId and bc[itemId]) or 0
end

-- ---------------------------------------------------------------------------
-- Shopping List Alerts
-- ---------------------------------------------------------------------------

-- The "already told them" latch, keyed by shopping-list id. It is NOT
-- db.char.shoppingAlerts: that table is the player's per-recipe opt-in for the
-- crafter-online alert (the "!" on a Professions-tab shopping-list row, read by
-- addon:OnCrafterCameOnline). This module used to latch into it, so a
-- reagents-ready alert silently switched the crafter alert on for that recipe
-- and running out switched it off again. In memory only: PLAYER_LOGIN re-arms
-- it from the bags, which is all a saved copy would have done.
local alerted = {}

--- The reagents one craft of a shopping-list entry needs, as
--- { { id = itemId, qty = n }, ... }. Every entry the Professions tab adds
--- carries the recipe's full reagent list (the one the Reagent Tracker sums);
--- an entry without one falls back to the cooldown catalogue, which knows the
--- reagent of each cooldown craft. nil when neither knows.
local function EntryReagents(spellId, entry)
    local out = {}
    for _, r in ipairs(entry.reagents or {}) do
        local id = (r.itemLink and tonumber(r.itemLink:match("item:(%d+)")))
                or (r.itemId and r.itemId > 0 and r.itemId or nil)
        if id then out[#out + 1] = { id = id, qty = r.count or 1 } end
    end
    if #out > 0 then return out end
    local data = addon:GetCooldownData()
    local rg = data.reagents[spellId] or data.transReagents[spellId]
    if rg then return { { id = rg.id, qty = rg.qty } } end
    return nil
end

--- Is every reagent for `qty` crafts of this entry in `bags`?
local function EntryReady(reagents, qty, bags)
    for _, r in ipairs(reagents) do
        if (bags[r.id] or 0) < r.qty * qty then return false end
    end
    return true
end

--- Check every shopping list entry; fire a chat alert the first time all
--- reagents for a craft are present in bags.  Clear the latch when bags drop
--- below requirements so the player gets a fresh alert next time.
local function CheckAlerts(bags)
    local bl = Ace.db.char.shoppingList

    -- An entry removed from the list re-arms, so queuing it again alerts.
    for spellId in pairs(alerted) do
        if not bl[spellId] then alerted[spellId] = nil end
    end

    for spellId, entry in pairs(bl) do
        local qty      = (entry and entry.quantity) or 1
        local reagents = entry and EntryReagents(spellId, entry)
        if reagents then
            local ready = EntryReady(reagents, qty, bags)

            if ready and not alerted[spellId] then
                -- First time ready — alert
                alerted[spellId] = true
                local craftName = entry.name or addon.Spell.GetInfo(spellId) or tostring(spellId)
                if #reagents == 1 then
                    local r = reagents[1]
                    local itemName = addon.Item.GetInfo(r.id) or tostring(r.id)
                    addon:Print(string.format(
                        L["AlertReadyFormat"],
                        craftName, qty, itemName, bags[r.id] or 0
                    ))
                else
                    addon:Print(string.format(
                        L["AlertReadyAllFormat"], craftName, qty, #reagents
                    ))
                end
            elseif not ready and alerted[spellId] then
                -- Bags dropped below requirement — clear flag so next restock
                -- triggers a fresh alert
                alerted[spellId] = nil
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
    -- The item watch list (removed in v1.1.2 with the Shopping List tab it
    -- lived on) left a saved table behind; drop it.
    Ace.db.char.reagentWatch = nil

    local bags = ScanBags()
    -- Don't alert on login — pre-populate the latch silently so the first
    -- legitimate restock triggers the message
    local bl = Ace.db.char.shoppingList
    for spellId, entry in pairs(bl) do
        local qty      = (entry and entry.quantity) or 1
        local reagents = entry and EntryReagents(spellId, entry)
        if reagents and EntryReady(reagents, qty, bags) then
            alerted[spellId] = true  -- already ready on login, don't spam
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Public helper: clear alert state for a spell (called when removed from BL)
-- ---------------------------------------------------------------------------

function RW:ClearAlert(spellId)
    alerted[spellId] = nil
end

--- Test seam: the latch is module state, and the offline suite loads this file
--- once per spec file, so each spec starts from an empty latch.
function RW:_ResetAlertLatch()
    for k in pairs(alerted) do alerted[k] = nil end
end
