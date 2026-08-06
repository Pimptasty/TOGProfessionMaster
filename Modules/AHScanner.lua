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
local L   = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

local AH = {}
addon.AH = AH

-- ---------------------------------------------------------------------------
-- API generation detection
-- ---------------------------------------------------------------------------
-- Cata Classic, MoP Classic, and Retail use the modern C_AuctionHouse API
-- backed by AuctionHouseFrame. Vanilla / TBC Classic / Wrath Classic still
-- use the legacy AuctionFrame + QueryAuctionItems path. Feature-detect at
-- file-load time rather than gating on version flags — keeps the check
-- robust if Blizzard backports the modern API to other Classic flavors.
-- Every dispatch in this module branches on AH._isModernAH.
AH._isModernAH = C_AuctionHouse ~= nil
              and type(C_AuctionHouse.SendSearchQuery) == "function"
              and type(C_AuctionHouse.MakeItemKey) == "function"

addon:DebugPrint("AH: modern API path =", tostring(AH._isModernAH))

-- ---------------------------------------------------------------------------
-- Open-state tracking
-- ---------------------------------------------------------------------------

AH._isOpen = false
AH._scanBtn = nil
AH._scanBtnHookedFrames = AH._scanBtnHookedFrames or {}

local function scanButtonIdleText()
    return "|c" .. (addon.BrandColor or "ffFF8000") .. "TOGPM|r Scan"
end

local function scanButtonBusyText()
    return "Scanning..."
end

function AH.UpdateScanButtonState()
    local b = AH._scanBtn
    if not b then return end
    local busy = (AH._isScanning == true) or (AH._fullScanning == true)
    if busy then
        b:SetText(scanButtonBusyText())
        b:Disable()
        return
    end
    b:SetText(scanButtonIdleText())
    if AH.IsOpen() then
        b:Enable()
    else
        b:Disable()
    end
end

function AH.ShowScanButton(frame)
    if not frame then return end

    local b = AH._scanBtn
    if not b then
        b = CreateFrame("Button", "TOGPMAHScanButton", frame, "UIPanelButtonTemplate")
        b:SetSize(92, 18)
        b:SetScript("OnClick", function()
            if AH._fullScanning or AH._isScanning then return end
            AH.StartFullScan(false)
            AH.UpdateScanButtonState()
        end)
        b:SetScript("OnEnter", function(btn)
            addon.Tooltip.Owner(btn)
            GameTooltip:SetText(scanButtonIdleText(), 1, 1, 1)
            GameTooltip:AddLine("Run a TOGPM full AH scan to refresh TOGPM's own pricing cache.", 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine("Independent of Auto-scan: this is a manual one-click scan.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        AH._scanBtn = b
    end

    b:SetParent(frame)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 72, -15)
    b:SetFrameStrata("HIGH")
    b:Show()
    AH.UpdateScanButtonState()
end

function AH.HideScanButton()
    if AH._scanBtn then AH._scanBtn:Hide() end
end

function AH.EnsureScanButtonHook()
    for _, name in ipairs({ "AuctionFrame", "AuctionHouseFrame" }) do
        local frame = _G[name]
        if frame and not AH._scanBtnHookedFrames[frame] then
            AH._scanBtnHookedFrames[frame] = true
            frame:HookScript("OnShow", function() AH.ShowScanButton(frame) end)
            if frame:IsShown() then AH.ShowScanButton(frame) end
        end
    end
end

-- Fires the addon-wide AH_OPEN_STATE_CHANGED callback so per-tab UI can
-- show/hide its [AH] buttons in real time when the user opens or closes
-- the auction house. Listeners register via addon:RegisterCallback(
-- "AH_OPEN_STATE_CHANGED", handler, owner). Done through addon.callbacks
-- (CallbackHandler-1.0) rather than each tab calling Ace:RegisterEvent
-- directly because Ace:RegisterEvent on the shared Ace addon instance
-- replaces previous handlers — only the last subscriber would fire.
Ace:RegisterEvent("AUCTION_HOUSE_SHOW", function()
    AH._isOpen = true
    AH.EnsureScanButtonHook()
    AH.UpdateScanButtonState()
    if addon.callbacks then
        addon.callbacks:Fire("AH_OPEN_STATE_CHANGED", true)
    end
    -- Auto full-scan keeps TOGPM's own price DB fresh for cost-to-craft + lights
    -- up the [AH] buttons. It is OPT-IN (default OFF): the legacy getAll scan
    -- draws from a shared, ~once-per-15-min, CLIENT-WIDE budget, so auto-firing it
    -- on every AH open would starve a dedicated AH addon's own getAll
    -- (Auctionator / TSM / etc.). Only fire when the user has ticked "Auto-scan
    -- the Auction House on open". The getAll throttle is still enforced inside
    -- StartFullScan; the 1s delay lets the AH UI finish initialising first. (The
    -- per-tab "Scan AH" buttons do targeted per-item queries, NOT getAll, so they
    -- keep working regardless of this setting.)
    if Ace and Ace.db and Ace.db.profile and Ace.db.profile.autoScanAH then
        Ace:ScheduleTimer(function()
            if AH.IsOpen() then AH.StartFullScan(true) end
        end, 1.0)
    end
end)
Ace:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
    AH._isOpen = false
    AH.HideScanButton()
    -- Auto-clear scan results — listings go stale fast and we don't want
    -- old prices lying around between AH visits. Cancels an in-progress
    -- scan first if one is running. The clear runs BEFORE the state-
    -- changed fire so callback subscribers see the cleared state.
    if AH._isScanning then AH.CancelScan() end
    -- Stop any in-flight full scan (its batch loop bails on _fullScanning=false)
    -- but KEEP its cached results (AH._fullSeen). getAll is throttled to ~once
    -- /15 min, so we cache the full scan for the WHOLE session and overwrite it
    -- only on the next successful scan — closing and re-opening the AH inside the
    -- cooldown reuses the cache instead of showing nothing. (A scan aborted
    -- mid-flight by this close discards its partial data via fullScanFrame's own
    -- AUCTION_HOUSE_CLOSED handler.) GetListingsFor only exposes _fullSeen while
    -- the AH is open, so the per-row [AH] buttons still track the AH window.
    AH._fullScanning = false
    AH._fullPending  = false
    AH.ClearResults()
    AH.UpdateScanButtonState()
    if addon.callbacks then
        addon.callbacks:Fire("AH_OPEN_STATE_CHANGED", false)
    end
end)

function AH.IsOpen()
    -- Defensive: if the events haven't fired yet but the frame is visible,
    -- still treat it as open. Modern clients (Cata Classic, MoP Classic,
    -- Retail) use AuctionHouseFrame; legacy clients (Vanilla / TBC / Wrath
    -- Classic) use AuctionFrame. Check whichever is appropriate.
    if AH._isOpen then return true end
    if AH._isModernAH then
        return AuctionHouseFrame and AuctionHouseFrame:IsShown() == true
    end
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
--- Works on Vanilla, TBC, Wrath (legacy AuctionFrame UI) and on Cata Classic,
--- MoP Classic, Retail (modern C_AuctionHouse UI via AuctionHouseFrame).
--- Branches internally on AH._isModernAH set at module load.
function AH.SearchFor(itemName)
    if type(itemName) ~= "string" or itemName == "" then return false end
    if not AH.IsOpen() then
        addon:Print(L["AHScannerOpenAH"])
        return false
    end

    if AH._isModernAH then
        -- Modern UI: AuctionHouseFrame has a SearchBar with a text input.
        -- Setting the text and firing SearchBar:OnEnterPressed() / :Search()
        -- mimics the user typing and pressing enter. The exact method name
        -- varies across modern client builds — try the documented variants
        -- in order. The results will populate in the AH UI's Browse pane.
        if AuctionHouseFrame and AuctionHouseFrame.SearchBar then
            local sb = AuctionHouseFrame.SearchBar
            if sb.SetSearchText then
                sb:SetSearchText(itemName)
            elseif sb.SearchBox and sb.SearchBox.SetText then
                sb.SearchBox:SetText(itemName)
            end
            if sb.StartSearch then
                sb:StartSearch()
            elseif sb.OnEnterPressed then
                sb:OnEnterPressed()
            elseif AuctionHouseFrame.BrowseResultsFrame
               and AuctionHouseFrame.BrowseResultsFrame.SearchBar
               and AuctionHouseFrame.BrowseResultsFrame.SearchBar.OnEnterPressed then
                AuctionHouseFrame.BrowseResultsFrame.SearchBar:OnEnterPressed()
            end
        end
        return true
    end

    -- Legacy path follows.
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
-- Resolve the effective scan delay at scan time. Reads the user-tunable
-- setting from Ace.db.profile.ahScanDelay; falls back to a version-appropriate
-- default (1.5s on Classic Era / Anniversary where the server throttle is
-- loose, 3.0s on TBC / Wrath / Cata / MoP where it's stricter). Independent of
-- this floor, every QueryAuctionItems call is also gated on CanSendAuctionQuery()
-- with a 0.5s retry, so even when the floor isn't enough, the scan waits
-- instead of dropping the query into the void.
function AH.GetEffectiveScanDelay()
    local override = Ace and Ace.db and Ace.db.profile and Ace.db.profile.ahScanDelay
    if type(override) == "number" and override > 0 then return override end
    return addon.isVanilla and 1.5 or 3.0
end
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
    if AH._fullScanning then return false, "full-scan-in-progress" end
    if not AH.IsOpen()    then return false, "ah-closed" end
    if type(items) ~= "table" or #items == 0 then return false, "no-items" end

    AH._isScanning   = true
    AH.UpdateScanButtonState()
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
        AH.UpdateScanButtonState()
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

    addon:DebugPrint(("AH Scan: querying %d/%d %s (id=%d)"):format(
        AH._scannedItems + 1, AH._totalItems, nextItem.itemName, nextItem.itemId))

    if AH._isModernAH then
        -- Modern API path (Cata Classic, MoP Classic, Retail).
        -- C_AuctionHouse.SendSearchQuery takes an itemKey, sort table, and
        -- separateOwnerItems flag. The itemKey is built from the itemID via
        -- MakeItemKey. Results arrive via ITEM_SEARCH_RESULTS_UPDATED (for
        -- unique items) or COMMODITY_SEARCH_RESULTS_UPDATED (for commodity
        -- stackables like reagents); we listen for both. Modern AH has
        -- built-in throttling so we don't need an equivalent of the
        -- CanSendAuctionQuery gate that the legacy path requires.
        if type(GetItemInfo) == "function" and not GetItemInfo(nextItem.itemId) then
            -- Item not yet in the client cache — Blizzard's search will
            -- return empty. Force a cache fetch and retry in 0.5s.
            addon:DebugPrint("AH Scan: item not in cache, retrying in 0.5s")
            table.insert(AH._queue, 1, nextItem)
            AH._currentItem = nil
            Ace:ScheduleTimer(function() AH._scanNext() end, 0.5)
            return
        end
        local itemKey = C_AuctionHouse.MakeItemKey(nextItem.itemId)
        AH._currentItemKey = itemKey
        C_AuctionHouse.SendSearchQuery(itemKey, {}, false)
        -- Safety timer: if neither event fires within scanDelay+5s, treat as
        -- empty result and advance. Modern AH usually fires within ~1s.
        local thisItemId = nextItem.itemId
        Ace:ScheduleTimer(function()
            if AH._isScanning and AH._currentItem
               and AH._currentItem.itemId == thisItemId then
                addon:DebugPrint("AH Scan: modern result timeout for", thisItemId, "advancing")
                AH._completeCurrentItem({})
            end
        end, AH.GetEffectiveScanDelay() + 5)
        return
    end

    -- Legacy API path (Vanilla, TBC Classic, Wrath Classic).
    -- Gate every query on Blizzard's "is the next query allowed?" check.
    -- TBC Anniversary's throttle window is variable — even after our effective
    -- scan delay between queries, the server can still reject the next one.
    -- A rejected query fires no AUCTION_ITEM_LIST_UPDATE event, which would
    -- silently stall the scan. Retry in 0.5s slices until the API agrees we
    -- can send. AceTimer is already loaded as part of the addon's AceAddon
    -- mixins.
    if CanSendAuctionQuery and not CanSendAuctionQuery() then
        addon:DebugPrint("AH Scan: CanSendAuctionQuery=false, retrying in 0.5s")
        -- Put the item back at the front of the queue and re-call later.
        table.insert(AH._queue, 1, nextItem)
        AH._currentItem = nil
        Ace:ScheduleTimer(function() AH._scanNext() end, 0.5)
        return
    end

    -- QueryAuctionItems signature on Vanilla→Wrath:
    --   (name, minLevel, maxLevel, page, isUsable, qualityIndex, getAll,
    --    exactMatch, filterData)
    -- exactMatch=false (matches PS's working scanner). With exactMatch=true,
    -- some Classic builds inconsistently return empty result sets even when
    -- listings exist; we'll still match-filter results by name+itemId in
    -- the handler below, so fuzzy server matches just get discarded.
    QueryAuctionItems(nextItem.itemName, nil, nil, 0, 0, 0, false, false, false, false)
end

--- Internal: store collected listings for the current item, then schedule the
--- next query after the configured scan delay. Shared by both API paths.
function AH._completeCurrentItem(listings)
    if not AH._isScanning or not AH._currentItem then return end
    local current = AH._currentItem
    local lowestBuyout
    for _, l in ipairs(listings) do
        local b = l.buyoutPrice
        if b and b > 0 and (not lowestBuyout or b < lowestBuyout) then
            lowestBuyout = b
        end
    end

    if current.itemId then
        AH._results[current.itemId] = {
            listings     = listings,
            lowestBuyout = lowestBuyout,
            count        = #listings,
            scannedAt    = (GetServerTime and GetServerTime()) or time(),
        }
    end

    AH._scannedItems   = AH._scannedItems + 1
    AH._currentItem    = nil
    AH._currentItemKey = nil

    -- Throttle between queries dodges rate limits. Delay is version-aware
    -- (1.5s Classic, 3.0s elsewhere by default) and user-tunable via the AH
    -- scan delay setting. AceTimer is already loaded as part of the addon's
    -- AceAddon mixins.
    Ace:ScheduleTimer(function() AH._scanNext() end, AH.GetEffectiveScanDelay())
end

-- ===========================================================================
-- Full AH scan — one server-side "scan everything" pass that builds the local
-- price DB (addon.Price) used for cost-to-craft. This is TOGPM's OWN price
-- source, so the addon never depends on Auctionator. Auto-fires when the AH
-- opens (no button); see the AUCTION_HOUSE_SHOW handler. Results are the lowest
-- per-item unit buyout seen across all listings.
--
-- Legacy (Era/TBC/Wrath): QueryAuctionItems(..., getAll=true) — one shot,
-- server-throttled to ~once / 15 min (we honour CanSendAuctionQuery's canGetAll
-- and skip silently when it's not allowed). Modern (Cata/MoP): C_AuctionHouse
-- .ReplicateItems(). Either way we batch-process the returned list across frames
-- so a multi-thousand-row scan doesn't hitch.
-- ===========================================================================
AH._fullScanning = false
AH._fullPending  = false
AH._fullSeen     = nil      -- [itemId] = { count, lowestBuyout, scannedAt } this scan
AH._otherFrames  = nil      -- frames we silenced for AUCTION_ITEM_LIST_UPDATE
local FULL_BATCH = 500

-- Dedicated scan frame for the legacy getAll. Following Auctionator's
-- FullScan pattern: during a scan we silence EVERY other frame registered for
-- AUCTION_ITEM_LIST_UPDATE (Blizzard's AH UI, other addons) so ONLY this frame
-- receives the getAll response — a competing browse-query event can then never
-- make us process a partial / wrong result set. Frames are restored when done.
local fullScanFrame    = CreateFrame("Frame")
local FULL_SCAN_EVENTS = { "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_CLOSED" }
local fullProcessLegacy, fullProcessModern   -- forward declarations

local function fullRegisterEvents()
    AH._otherFrames = { GetFramesRegisteredForEvent("AUCTION_ITEM_LIST_UPDATE") }
    for _, f in ipairs(AH._otherFrames) do f:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE") end
    FrameUtil.RegisterFrameForEvents(fullScanFrame, FULL_SCAN_EVENTS)
end

local function fullUnregisterEvents()
    FrameUtil.UnregisterFrameForEvents(fullScanFrame, FULL_SCAN_EVENTS)
    if AH._otherFrames then
        for _, f in ipairs(AH._otherFrames) do f:RegisterEvent("AUCTION_ITEM_LIST_UPDATE") end
        AH._otherFrames = nil
    end
end

fullScanFrame:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_ITEM_LIST_UPDATE" then
        -- The getAll payload — process it exactly once, then stop listening.
        fullScanFrame:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
        if fullProcessLegacy then fullProcessLegacy() end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        fullUnregisterEvents()
        AH._fullScanning = false
        AH._fullSeen     = nil
        AH.UpdateScanButtonState()
    end
end)

local function fullStore()
    fullUnregisterEvents()   -- restore the frames we silenced (Auctionator pattern)
    local n = 0
    local now = (GetServerTime and GetServerTime()) or time()
    AH._lastFullScanAt = now   -- for the modern self-throttle (legacy uses CanSendAuctionQuery)
    if AH._fullSeen and addon.Price and addon.Price.StoreAHPrice then
        for itemId, rec in pairs(AH._fullSeen) do
            rec.scannedAt = now
            if rec.lowestBuyout then
                addon.Price.StoreAHPrice(itemId, rec.lowestBuyout)
                n = n + 1
            end
        end
    end
    -- Keep AH._fullSeen for the rest of the AH session: GetListingsFor falls
    -- back to it, so the per-row [AH] buttons on every tab light up from the
    -- full scan with no targeted "Scan AH" click. Cleared on AH close, reset on
    -- the next scan. Only the scanning flags reset here.
    AH._fullScanning = false
    AH._fullPending  = false
    AH.UpdateScanButtonState()
    addon:Print(("AH full scan complete — priced %d items."):format(n))
    -- Tabs refresh their [AH] buttons / costs against the new data (same hook
    -- the targeted scan uses). Empty payload: prices went straight to addon.Price.
    if addon.callbacks then addon.callbacks:Fire("AH_SCAN_COMPLETE", {}, "fullscan") end
end

-- Legacy getAll list processor (GetAuctionItemInfo positional: count=3,
-- buyout=10, itemId=17). Per-unit price = ceil(buyout/count), matching
-- Auctionator's effectivePrice = buyoutPrice / available.
fullProcessLegacy = function()
    local n = GetNumAuctionItems("list") or 0
    AH._fullSeen = AH._fullSeen or {}
    addon:DebugPrint("AH full scan (legacy): processing", n, "listings")
    local function batch(start)
        if not AH._fullScanning then return end
        local stop = math.min(start + FULL_BATCH - 1, n)
        for i = start, stop do
            local info   = { GetAuctionItemInfo("list", i) }
            local count  = info[3] or 1
            local buyout = info[10] or 0
            local itemId = info[17]
            if itemId and buyout > 0 and count > 0 then
                local unit = math.ceil(buyout / count)
                local rec  = AH._fullSeen[itemId]
                if not rec then rec = { count = 0 }; AH._fullSeen[itemId] = rec end
                rec.count = rec.count + 1
                if not rec.lowestBuyout or unit < rec.lowestBuyout then
                    rec.lowestBuyout = unit
                end
            end
        end
        if stop < n then
            Ace:ScheduleTimer(function() batch(stop + 1) end, 0.01)
        else
            fullStore()
        end
    end
    batch(1)
end

-- Offline-test seam. The per-unit arithmetic above is what every cost-to-craft
-- figure in the addon rests on, and it goes wrong silently: pricing a stack as
-- a single item inflates the whole price DB by the stack size.
-- See Tests/ahfullscan_spec.lua.
AH._fullProcessLegacy = function() return fullProcessLegacy() end

-- Modern replicate processor (C_AuctionHouse.GetReplicateItemInfo is 0-indexed).
fullProcessModern = function()
    local n = (C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetNumReplicateItems()) or 0
    AH._fullSeen = AH._fullSeen or {}
    addon:DebugPrint("AH full scan (modern): processing", n, "listings")
    local function batch(start)
        if not AH._fullScanning then return end
        local stop = math.min(start + FULL_BATCH - 1, n)
        for i = start, stop do
            local _name, _tex, count, _q, _u, _lvl, _lt, _minBid, _minInc, buyout,
                  _bid, _hb, _bn, _owner, _on, _sale, itemID =
                  C_AuctionHouse.GetReplicateItemInfo(i - 1)
            local cnt = count or 1
            if itemID and buyout and buyout > 0 and cnt > 0 then
                local unit = math.ceil(buyout / cnt)
                local rec  = AH._fullSeen[itemID]
                if not rec then rec = { count = 0 }; AH._fullSeen[itemID] = rec end
                rec.count = rec.count + 1
                if not rec.lowestBuyout or unit < rec.lowestBuyout then
                    rec.lowestBuyout = unit
                end
            end
        end
        if stop < n then
            Ace:ScheduleTimer(function() batch(stop + 1) end, 0.01)
        else
            fullStore()
        end
    end
    batch(1)
end

-- Offline-test seam for the Cata/MoP path. Its own case rather than sharing the
-- legacy one because the API it reads is **0-indexed** while the loop is
-- 1-based, and losing that `- 1` silently drops the first listing of every scan.
AH._fullProcessModern = function() return fullProcessModern() end

--- Kick off a full scan. `auto` suppresses the throttle message (used by the
--- auto-on-open trigger). Returns false + reason when it can't start.
function AH.StartFullScan(auto)
    if AH._fullScanning or AH._isScanning then return false, "busy" end
    if not AH.IsOpen() then return false, "ah-closed" end

    if AH._isModernAH then
        if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then return false, "no-api" end
        -- ReplicateItems has no CanSendAuctionQuery-style pre-check, so self-
        -- throttle: if we scanned < 15 min ago, keep the cached _fullSeen instead
        -- of resetting it and re-firing (which could briefly empty the buttons).
        local now = (GetServerTime and GetServerTime()) or time()
        if AH._lastFullScanAt and (now - AH._lastFullScanAt) < 15 * 60 then
            if not auto then addon:Print("AH full scan is on cooldown (~once / 15 min). Using cached prices.") end
            return false, "throttled"
        end
        AH._fullSeen     = {}
        AH._fullScanning = true
        AH._fullPending  = true
        AH.UpdateScanButtonState()
        C_AuctionHouse.ReplicateItems()
        return true
    end

    -- Legacy: getAll is gated server-side; the 2nd return of CanSendAuctionQuery
    -- is "can do a getAll right now". Skip quietly on the auto path when it's on
    -- cooldown — the next AH open inside the window will catch it.
    local _, canGetAll = CanSendAuctionQuery()
    if not canGetAll then
        if not auto then
            addon:Print("AH full scan is on cooldown (getAll allows ~once / 15 min). Try again shortly.")
        end
        return false, "throttled"
    end
    AH._fullSeen     = {}
    AH._fullScanning = true
    AH.UpdateScanButtonState()
    -- Guard against a Classic AH-code error on the getAll result set.
    if ITEM_QUALITY_COLORS and not ITEM_QUALITY_COLORS[-1] then
        ITEM_QUALITY_COLORS[-1] = { r = 0, g = 0, b = 0 }
    end
    -- Silence other AUCTION_ITEM_LIST_UPDATE listeners, then fire getAll; the
    -- dedicated fullScanFrame catches the response cleanly (Auctionator pattern).
    fullRegisterEvents()
    QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
    return true
end

function AH.IsFullScanning() return AH._fullScanning == true end

-- ---------------------------------------------------------------------------
-- Legacy result collector (Vanilla, TBC Classic, Wrath Classic)
-- ---------------------------------------------------------------------------

local function onAuctionItemListUpdate()
    -- Full-scan getAll is handled by the dedicated fullScanFrame (Auctionator
    -- pattern), not here — this shared handler is per-item targeted scans only.
    if not AH._isScanning or not AH._currentItem then return end
    if AH._isModernAH then return end  -- legacy event ignored on modern clients

    local current = AH._currentItem
    local n = GetNumAuctionItems("list") or 0
    local listings = {}

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
        end
    end

    addon:DebugPrint(("AH Scan: %s — %d server result(s), %d matched"):format(
        current.itemName or "?", n, #listings))
    AH._completeCurrentItem(listings)
end

-- ---------------------------------------------------------------------------
-- Modern result collectors (Cata Classic, MoP Classic, Retail)
-- ---------------------------------------------------------------------------

-- ITEM_SEARCH_RESULTS_UPDATED fires for non-commodity (unique) items.
-- Payload is the itemKey. We compare itemID against the current scan target.
local function onItemSearchResultsUpdated(itemKey)
    if not AH._isScanning or not AH._currentItem then return end
    if not itemKey or type(itemKey) ~= "table" then return end
    if itemKey.itemID ~= AH._currentItem.itemId then return end  -- different item

    local quantity = C_AuctionHouse.GetItemSearchResultsQuantity(itemKey) or 0
    local listings = {}
    for i = 1, quantity do
        local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if info then
            listings[#listings + 1] = {
                itemName    = AH._currentItem.itemName,  -- reuse the queued name; modern API doesn't return a separate plain-text name
                count       = info.quantity or 1,
                buyoutPrice = info.buyoutAmount or 0,
                bidAmount   = info.bidAmount or 0,
                owner       = info.owners and info.owners[1] or nil,
                itemId      = itemKey.itemID,
            }
        end
    end
    addon:DebugPrint(("AH Scan: %s — %d modern item result(s)"):format(
        AH._currentItem.itemName or "?", quantity))
    AH._completeCurrentItem(listings)
end

-- COMMODITY_SEARCH_RESULTS_UPDATED fires for stackable consumable items
-- (reagents, potions, etc.). Payload is just the itemID.
local function onCommoditySearchResultsUpdated(itemID)
    if not AH._isScanning or not AH._currentItem then return end
    if type(itemID) ~= "number" then return end
    if itemID ~= AH._currentItem.itemId then return end

    local quantity = C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) or 0
    local listings = {}
    for i = 1, quantity do
        local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        if info then
            listings[#listings + 1] = {
                itemName    = AH._currentItem.itemName,
                count       = info.quantity or 1,
                buyoutPrice = info.unitPrice or 0,  -- commodities have unitPrice, not buyoutAmount
                bidAmount   = 0,                    -- commodities are buyout-only on modern AH
                owner       = info.owner,
                itemId      = itemID,
            }
        end
    end
    addon:DebugPrint(("AH Scan: %s — %d modern commodity result(s)"):format(
        AH._currentItem.itemName or "?", quantity))
    AH._completeCurrentItem(listings)
end

-- Wire up the right event(s) for the active API generation.
if AH._isModernAH then
    Ace:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED",      onItemSearchResultsUpdated)
    Ace:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", onCommoditySearchResultsUpdated)
    -- Full-scan replicate result (modern getAll equivalent).
    Ace:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", function()
        if AH._fullPending then AH._fullPending = false; fullProcessModern() end
    end)
else
    Ace:RegisterEvent("AUCTION_ITEM_LIST_UPDATE", onAuctionItemListUpdate)
end

--- Internal: finalise scan state and fire callbacks.
function AH._finishScan(reason)
    AH._isScanning     = false
    AH._currentItem    = nil
    AH._currentItemKey = nil
    AH.UpdateScanButtonState()

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
    -- A targeted per-item scan (AH._results) wins when present — more specific /
    -- fresher. Otherwise fall back to the cached full scan (AH._fullSeen), so the
    -- [AH] buttons on every tab light up with no targeted "Scan AH" click.
    --
    -- The full-scan cache SURVIVES the AH closing and lives the whole session
    -- (only the next successful scan overwrites it) — so closing and re-opening
    -- the AH, even inside the ~15-min getAll cooldown, shows the buttons again
    -- straight from cache with no re-scan. We only surface it while the AH is
    -- open because the button's action (search the AH) can't do anything when
    -- it's closed; the data is never dropped.
    return AH._results[itemId]
        or (AH.IsOpen() and AH._fullSeen and AH._fullSeen[itemId])
        or nil
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
