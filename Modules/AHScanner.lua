---@diagnostic disable: undefined-global
-- TOG Profession Master -- the Auction House, as the tabs see it.
--
-- THE SCANNER LEFT THIS FILE ON 2026-09-14 (v1.1.0). The getAll full scan,
-- the throttled per-item scan, the AH-frame scan button, the open-state
-- tracking and the browse-and-search all moved into ItemDB (LibItemDB-1.0
-- MINOR 25, `Price/Scanner.lua`) at the user's direction, so one scanner feeds
-- one price store for every TOG addon. Two defects went with it, both found
-- by ItemDB's suite while porting: a cancelled targeted scan left its
-- next-item timer armed (a scan started inside that delay advanced early or
-- finished "0 of 0"), and the Auctionator "historical" read reached for an API
-- that does not exist and fell back to live.
--
-- What is left is `addon.AH`, the surface the per-row [AH] buttons and the
-- shared Scan AH button (GUI/SharedWidgets.lua) were written against -- kept
-- so those ~15 call sites did not change, and so the tabs keep their
-- `if addon.AH then` degrade: this table is only installed when the ItemDB in
-- play carries the scanner. The [AH] buttons therefore gate on ItemDB's scan
-- results (GetScanListings) and search through ItemDB (AuctionHouseSearch).
-- Two addon-internal events the tabs subscribe to are fed from the library's
-- callbacks in one place here:
--
--   AH_OPEN_STATE_CHANGED(isOpen)         <- LibItemDB_AuctionHouse
--   AH_SCAN_COMPLETE(results, reason)     <- LibItemDB_ScanComplete
--
-- Every function is a one-line read of the library; nothing here decides
-- anything about the auction house.

local _, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

local DB = addon.GetItemDB and addon:GetItemDB()
if not (DB and type(DB.StartTargetedScan) == "function") then
    -- An ItemDB older than the price API: no scanner anywhere, so no [AH]
    -- buttons and a disabled Scan AH button, which is what every caller's
    -- `if addon.AH` guard was written for.
    return
end

local AH = {}
addon.AH = AH

--- True while the auction house frame is showing.
function AH.IsOpen()
    return DB:IsAuctionHouseOpen() == true
end

--- Switch the open AH to Browse and search for `itemName`; the user sees the
--- live results and acts on them. Says so in chat when the AH is closed, which
--- is what every [AH] button relied on.
--- @return boolean fired
function AH.SearchFor(itemName)
    if type(itemName) ~= "string" or itemName == "" then return false end
    if not AH.IsOpen() then
        addon:Print(L["AHScannerOpenAH"])
        return false
    end
    return DB:AuctionHouseSearch(itemName) == true
end

--- A targeted scan over `items` ({ {itemId, itemName}, ... }); same opts and
--- refusal reasons the tabs already handle ("ah-closed", "no-items", ...).
function AH.StartScan(items, opts)
    return DB:StartTargetedScan(items, opts)
end

function AH.StartFullScan(auto)
    return DB:StartFullScan(auto)
end

function AH.CancelScan()
    DB:CancelScan()
end

function AH.IsScanning()     return DB:IsScanning() == true end
function AH.IsFullScanning() return DB:IsFullScanning() == true end

--- (scanned, total) of the running or last targeted scan.
function AH.GetScanProgress()
    local st = DB:GetScanState()
    return st.scanned or 0, st.total or 0
end

--- This session's scan record for an item -- `{ listings?, lowestBuyout,
--- count, scannedAt }`, `count == 0` meaning "looked, nobody is selling it" --
--- or nil. The per-row [AH] buttons gate on it.
function AH.GetListingsFor(itemId)
    return DB:GetScanListings(itemId)
end

-- The library's callbacks, re-fired as the two addon events the tabs and the
-- shared Scan AH button subscribe to (addon.callbacks is CallbackHandler-1.0;
-- one owner here, one registration each).
if DB.RegisterCallback and addon.callbacks then
    DB.RegisterCallback(AH, "LibItemDB_AuctionHouse", function(_, isOpen)
        addon.callbacks:Fire("AH_OPEN_STATE_CHANGED", isOpen == true)
    end)
    DB.RegisterCallback(AH, "LibItemDB_ScanComplete", function(_, _kind, reason, results)
        addon.callbacks:Fire("AH_SCAN_COMPLETE", results or {}, reason)
    end)
end
