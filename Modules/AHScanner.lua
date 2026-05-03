---@diagnostic disable: undefined-global
-- TOG Profession Master — Auction House helper
-- Owns:
--   addon.AH.IsOpen()           - true while the AH frame is showing
--   addon.AH.SearchFor(name)    - switch AH to Browse, populate the name
--                                 field, fire the search; user sees the
--                                 results in the standard AH UI and bids/
--                                 buys manually
--
-- Used by per-row [AH] buttons across the addon (MissingRecipesTab,
-- BrowserTab, CooldownsTab, ShoppingListTab) — each row's button calls
-- addon.AH.SearchFor(itemName) when clicked. Buttons show only while
-- addon.AH.IsOpen() is true so they're never visible when the AH isn't
-- accessible. Sibling pattern to addon.Bank in Compat.lua, where
-- per-row [Bank] buttons gate on addon.Bank.GetStock(itemId) > 0.
--
-- API surface here is intentionally minimal — populate-and-search, no
-- result aggregation, no buyout. The user sees the live AH UI and acts
-- on it directly. A later phase can layer a scan/buyout module on top
-- of this without changing any of the call-site code in the tabs.

local _, addon = ...
local Ace = addon.lib

local AH = {}
addon.AH = AH

-- ---------------------------------------------------------------------------
-- Open-state tracking
-- ---------------------------------------------------------------------------

AH._isOpen = false

-- Fires the addon-wide AH_OPEN_STATE_CHANGED callback so per-tab UI can
-- show/hide its [AH] buttons in real time when the user opens or closes
-- the auction house. Listeners register via addon:RegisterCallback(
-- "AH_OPEN_STATE_CHANGED", handler, owner). Done through addon.callbacks
-- (CallbackHandler-1.0) rather than each tab calling Ace:RegisterEvent
-- directly because Ace:RegisterEvent on the shared Ace addon instance
-- replaces previous handlers — only the last subscriber would fire.
Ace:RegisterEvent("AUCTION_HOUSE_SHOW", function()
    AH._isOpen = true
    if addon.callbacks then
        addon.callbacks:Fire("AH_OPEN_STATE_CHANGED", true)
    end
end)
Ace:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
    AH._isOpen = false
    -- Auto-clear scan results — listings go stale fast and we don't want
    -- old prices lying around between AH visits. Cancels an in-progress
    -- scan first if one is running. The clear runs BEFORE the state-
    -- changed fire so callback subscribers see the cleared state.
    if AH._isScanning then AH.CancelScan() end
    AH.ClearResults()
    if addon.callbacks then
        addon.callbacks:Fire("AH_OPEN_STATE_CHANGED", false)
    end
end)

function AH.IsOpen()
    -- Defensive: if the events haven't fired yet but the frame is visible,
    -- still treat it as open. AuctionFrame is the legacy Classic-through-MoP
    -- frame that all our targeted versions use.
    if AH._isOpen then return true end
    return AuctionFrame and AuctionFrame:IsShown() == true
end

-- ---------------------------------------------------------------------------
-- Browse-and-search
-- ---------------------------------------------------------------------------

--- Trigger an AH search for itemName. Returns true if the search was fired,
--- false if the AH wasn't open or the call-site passed garbage.
---
--- Mechanism: switches AuctionFrame to the Browse tab, sets BrowseName's text
--- to itemName, clears the level / quality / usable filters that would
--- otherwise narrow the search, then calls AuctionFrameBrowse_Search() — the
--- exact function the AH UI's Search button binds to. Results populate in
--- the live AH frame, the user sees them and acts manually (bid / buyout /
--- nothing). No popup, no aggregation, no automation.
---
--- This works on Vanilla / TBC / Wrath / Cata / MoP — they all share the
--- legacy AuctionFrame UI. Retail (8.0+) replaced this entirely with
--- C_AuctionHouse and would need a separate path; out of scope here since
--- the addon's targeted versions don't include it.
function AH.SearchFor(itemName)
    if type(itemName) ~= "string" or itemName == "" then return false end
    if not AH.IsOpen() then
        addon:Print("Open the auction house to search.")
        return false
    end

    -- Switch to the Browse tab. AuctionFrameTab1 is the Browse tab; calling
    -- :Click() runs the standard tab-switch flow including show/hide of the
    -- Browse vs Bid vs Auctions panes. PanelTemplates_SetTab is the
    -- lower-level fallback used by the same path internally.
    if AuctionFrameTab1 and AuctionFrameTab1.Click then
        AuctionFrameTab1:Click()
    end

    -- Populate the name field. BrowseName is the global edit box on the
    -- Browse pane; setting its text feeds AuctionFrameBrowse_Search via
    -- BrowseName:GetText() when the search fires.
    if BrowseName and BrowseName.SetText then
        BrowseName:SetText(itemName)
    end

    -- Reset the secondary filters so a previous narrow search (e.g. "epic
    -- only", "level 60+", subclass filter) doesn't accidentally hide the
    -- exact item we're looking for. These are no-ops if the field is
    -- already empty / default.
    if BrowseMinLevel and BrowseMinLevel.SetText then BrowseMinLevel:SetText("") end
    if BrowseMaxLevel and BrowseMaxLevel.SetText then BrowseMaxLevel:SetText("") end
    if IsUsableCheckButton and IsUsableCheckButton.SetChecked then
        IsUsableCheckButton:SetChecked(false)
    end
    if ShowOnPlayerCheckButton and ShowOnPlayerCheckButton.SetChecked then
        ShowOnPlayerCheckButton:SetChecked(false)
    end
    -- UIDropDownMenu_SetSelectedValue clears the quality dropdown back to
    -- "all qualities". Guarded because the global isn't always defined
    -- before the AH UI has been opened at least once this session.
    if BrowseDropDown and UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(BrowseDropDown, -1)
    end

    -- Fire the search. AuctionFrameBrowse_Search reads BrowseName + the
    -- filters above and calls QueryAuctionItems with the right shape;
    -- AUCTION_ITEM_LIST_UPDATE then populates the results list in the AH
    -- UI (no event handling needed here — the AH UI does that itself).
    if AuctionFrameBrowse_Search then
        AuctionFrameBrowse_Search()
    elseif BrowseSearchButton and BrowseSearchButton.Click then
        BrowseSearchButton:Click()
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Throttled scanner — fires QueryAuctionItems for each item in turn, waits
-- for AUCTION_ITEM_LIST_UPDATE, collects matching listings, then advances
-- after a small delay (~1.5s) to dodge the client-side rate limit. Results
-- are cached per itemId in AH._results and queried by callers via
-- AH.GetListingsFor(itemId). Sibling pattern to addon.Bank.GetStock — UI
-- code shows or hides per-row [AH] buttons based on whether scan results
-- exist for that item, just like [Bank] gates on bank stock > 0.
-- ---------------------------------------------------------------------------

AH._isScanning  = false
AH._queue       = {}        -- queue of pending items: { {itemId, itemName}, ... }
AH._results     = {}        -- [itemId] = { listings, lowestBuyout, count, scannedAt }
AH._currentItem = nil       -- item currently awaiting AUCTION_ITEM_LIST_UPDATE
AH._scanDelay   = 1.5       -- seconds between queries (rate-limit-safe)
AH._totalItems  = 0
AH._scannedItems = 0
AH._opts        = nil

--- Begin a scan over the supplied item list. items is an array of
--- { itemId = N, itemName = "..." } pairs. opts.onProgress(scanned, total,
--- currentItem) fires after each item completes; opts.onComplete(reason,
--- results) fires when the queue drains or the scan is cancelled / the AH
--- closes mid-scan. Returns false + reason if a scan can't be started
--- (already running, AH closed, empty list).
---
--- After completion, individual results are accessible via
--- AH.GetListingsFor(itemId), and addon.callbacks fires "AH_SCAN_COMPLETE"
--- so any subscribed tab can refresh its row pool.
function AH.StartScan(items, opts)
    if AH._isScanning then return false, "scan-in-progress" end
    if not AH.IsOpen()    then return false, "ah-closed" end
    if type(items) ~= "table" or #items == 0 then return false, "no-items" end

    AH._isScanning   = true
    AH._queue        = {}
    AH._results      = {}    -- fresh scan replaces previous results
    AH._opts         = opts or {}
    AH._scannedItems = 0

    -- Filter out items missing a usable name; we query by name on Classic.
    -- Dedupe by itemId so the same scroll/reagent isn't fetched twice when
    -- multiple call-site rows reference it. Strict type check on itemName
    -- (string only) — historically a callsite passed GetItemInfoInstant's
    -- first return (which is the itemID NUMBER, not the name) and the
    -- scanner crashed on the first :lower() call. Skip silently.
    local seen = {}
    for _, item in ipairs(items) do
        local id, name = item.itemId, item.itemName
        if id and type(name) == "string" and name ~= "" and not seen[id] then
            seen[id] = true
            AH._queue[#AH._queue + 1] = { itemId = id, itemName = name }
        end
    end
    AH._totalItems = #AH._queue

    if AH._totalItems == 0 then
        AH._isScanning = false
        return false, "no-items"
    end

    addon:Print(("AH scan starting on %d items..."):format(AH._totalItems))
    AH._scanNext()
    return true
end

--- Internal: pop the next queued item and fire QueryAuctionItems for it.
--- AUCTION_ITEM_LIST_UPDATE then drives the result-collection step below.
function AH._scanNext()
    if not AH._isScanning then return end
    if not AH.IsOpen() then
        AH._finishScan("ah-closed")
        return
    end

    local nextItem = table.remove(AH._queue, 1)
    if not nextItem then
        AH._finishScan("complete")
        return
    end

    AH._currentItem = nextItem
    if AH._opts and AH._opts.onProgress then
        pcall(AH._opts.onProgress, AH._scannedItems, AH._totalItems, nextItem)
    end

    -- QueryAuctionItems signature on Vanilla→MoP:
    --   (name, minLevel, maxLevel, page, isUsable, qualityIndex, getAll,
    --    exactMatch, filterData)
    -- exactMatch=false (matches PS's working scanner). With exactMatch=true,
    -- some Classic builds inconsistently return empty result sets even when
    -- listings exist; we'll still match-filter results by name+itemId in
    -- the handler below, so fuzzy server matches just get discarded.
    addon:DebugPrint(("AH Scan: querying %d/%d %s (id=%d)"):format(
        AH._scannedItems + 1, AH._totalItems, nextItem.itemName, nextItem.itemId))
    QueryAuctionItems(nextItem.itemName, nil, nil, 0, 0, 0, false, false, false, false)
end

--- Internal: collect listings from the current AUCTION_ITEM_LIST_UPDATE,
--- store them under the current item's id, then schedule the next query.
local function onAuctionItemListUpdate()
    if not AH._isScanning or not AH._currentItem then return end

    local current = AH._currentItem
    local n = GetNumAuctionItems("list") or 0
    local listings = {}
    local lowestBuyout

    -- Defensive: tostring guard against a caller passing a non-string
    -- itemName (e.g. earlier callsite that mistakenly used
    -- GetItemInfoInstant whose first return is the itemID number, not the
    -- name). Without this, calling :lower on a number crashes the scan.
    local wantNameLower = tostring(current.itemName or ""):lower()
    local wantId = current.itemId

    for i = 1, n do
        -- Classic Era signature returns 17 values; the ones we need are
        -- name(1), count(3), buyoutPrice(10), bidAmount(11), owner(14),
        -- itemId(17). Older / retail builds return slightly different
        -- shapes; we read positionally from the front and tolerate trailing
        -- nil for fields that don't exist on this client.
        local name, _, count, _, _, _, _, _, _, buyoutPrice, bidAmount, _, _, owner, _, _, itemId =
            GetAuctionItemInfo("list", i)

        -- Match either by name (case-insensitive) OR itemId. Either alone
        -- is enough — itemId is the most reliable identifier when the
        -- client returns it, name is the fallback when itemId is nil
        -- (some Classic builds don't return itemId from this API).
        local nameMatches = name and wantNameLower ~= "" and name:lower() == wantNameLower
        local idMatches   = itemId and wantId and itemId == wantId
        if nameMatches or idMatches then
            listings[#listings + 1] = {
                itemName    = name,
                count       = count or 1,
                buyoutPrice = buyoutPrice or 0,
                bidAmount   = bidAmount or 0,
                owner       = owner,
                itemId      = itemId,
            }
            if buyoutPrice and buyoutPrice > 0 and (not lowestBuyout or buyoutPrice < lowestBuyout) then
                lowestBuyout = buyoutPrice
            end
        end
    end

    addon:DebugPrint(("AH Scan: %s — %d server result(s), %d matched"):format(
        current.itemName or "?", n, #listings))

    if current.itemId then
        AH._results[current.itemId] = {
            listings     = listings,
            lowestBuyout = lowestBuyout,
            count        = #listings,
            scannedAt    = (GetServerTime and GetServerTime()) or time(),
        }
    end

    AH._scannedItems = AH._scannedItems + 1
    AH._currentItem  = nil

    -- Throttle: 1.5s between queries dodges the "you cannot perform that
    -- query so often" rate limit. Schedule via AceTimer (already loaded as
    -- part of the addon's AceAddon mixins).
    Ace:ScheduleTimer(function() AH._scanNext() end, AH._scanDelay)
end

Ace:RegisterEvent("AUCTION_ITEM_LIST_UPDATE", onAuctionItemListUpdate)

--- Internal: finalise scan state and fire callbacks.
function AH._finishScan(reason)
    AH._isScanning  = false
    AH._currentItem = nil

    -- Summary line so the user sees at a glance whether the scan found
    -- anything. Counts items in the results map that have at least one
    -- listing — items with count==0 (queried, no listings found) don't
    -- count as "found" for this summary.
    local found = 0
    for _, r in pairs(AH._results) do
        if r.count and r.count > 0 then found = found + 1 end
    end
    addon:Print(("AH scan %s: %d of %d items have listings."):format(
        reason or "complete", found, AH._scannedItems or 0))

    if AH._opts and AH._opts.onComplete then
        pcall(AH._opts.onComplete, reason or "complete", AH._results)
    end
    AH._opts = nil
    if addon.callbacks then
        addon.callbacks:Fire("AH_SCAN_COMPLETE", AH._results, reason)
    end
end

--- Cancel an in-progress scan. Safe to call when no scan is active.
function AH.CancelScan()
    if not AH._isScanning then return end
    AH._queue = {}
    AH._finishScan("cancelled")
end

--- True while a scan is running.
function AH.IsScanning() return AH._isScanning == true end

--- Returns the cached scan result for itemId, or nil if not scanned this
--- session. Result shape: { listings, lowestBuyout, count, scannedAt }.
--- count == 0 means the scan ran but found no listings.
function AH.GetListingsFor(itemId)
    return AH._results[itemId]
end

--- Scan progress: returns (scanned, total). Both 0 when no scan has run.
function AH.GetScanProgress()
    return AH._scannedItems or 0, AH._totalItems or 0
end

--- Discard all scan results. Useful for forcing a fresh scan when the
--- session has been running long enough that prices may have shifted.
--- Auto-invoked by the AUCTION_HOUSE_CLOSED handler at the top of this file.
function AH.ClearResults()
    AH._results = {}
end
