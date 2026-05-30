---@diagnostic disable: undefined-global
-- TOG Profession Master — price provider
--
-- One accessor, addon.Price.Get(itemId), behind which several price sources are
-- tried in order. The crafting tab's "Crafting Cost" never cares where a number
-- came from — it just sums reagent prices via addon.Price.CraftCost().
--
-- Sources, in priority order (configurable via Ace.db.profile.priceSource):
--   1. Auction House
--      a. Auctionator (LibStub-free public API) — only when the addon is loaded.
--         This is OPTIONAL; TOGPM never depends on it.
--      b. TOGPM's own scanned prices — persisted lowest-buyout from our AH
--         scanner (Modules/AHScanner.lua), stored realm+faction scoped.
--   2. Vendor (for reagents that aren't on the AH — thread, vials, etc.)
--      a. Auctionator vendor cache (when present).
--      b. TOGPM live merchant capture — buy prices cached as the user opens
--         vendors (MERCHANT_SHOW), realm+faction scoped.
--      c. Static fallback — addon.VendorPrices[itemId], a shipped table the
--         build pipeline generates from ItemSparse for vendor-sold reagents.
--   3. nil — the cost shows "—" and a "missing price" marker.
--
-- Prices are money in copper. Storage is Ace.db.factionrealm (AH prices are
-- per-realm, and Vanilla/TBC factions have separate auction houses), so the
-- data lives inside TOGPM_Settings with no extra SavedVariable.

local _, addon = ...
local Ace = addon.lib

local Price = {}
addon.Price = Price

local AUCTIONATOR_CALLER = "TOGProfessionMaster"

-- Treat a persisted AH price older than this (seconds) as stale-but-usable; we
-- still return it, flagged, so the UI can warn. 14 days mirrors Auctionator's
-- own price-history window.
local AH_STALE_AFTER = 14 * 24 * 60 * 60

-- ---------------------------------------------------------------------------
-- Storage (realm + faction scoped, lazily created)
-- ---------------------------------------------------------------------------
local function store()
    local db = Ace and Ace.db and Ace.db.factionrealm
    if not db then return nil end
    db.ahPrices     = db.ahPrices     or {}   -- [itemId] = { p = copper, at = epoch }
    db.vendorPrices = db.vendorPrices or {}   -- [itemId] = copper
    return db
end

-- ---------------------------------------------------------------------------
-- Auctionator bridge (optional — feature-detected every call, never required)
-- ---------------------------------------------------------------------------
-- Auctionator is opt-in: the user must tick "Use Auctionator pricing" in
-- Settings (off by default — TOGPM uses its own scanned data first). Gating
-- here means both the AH and vendor Auctionator tiers switch off together.
local function auctionatorEnabled()
    return Ace and Ace.db and Ace.db.profile and Ace.db.profile.useAuctionator == true
end

local function auctionatorReady()
    return auctionatorEnabled()
       and Auctionator and Auctionator.API and Auctionator.API.v1
       and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

local function auctionatorAH(itemId)
    if not auctionatorReady() then return nil end
    local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, AUCTIONATOR_CALLER, itemId)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

local function auctionatorVendor(itemId)
    if not (auctionatorReady() and type(Auctionator.API.v1.GetVendorPriceByItemID) == "function") then
        return nil
    end
    local ok, price = pcall(Auctionator.API.v1.GetVendorPriceByItemID, AUCTIONATOR_CALLER, itemId)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

-- ---------------------------------------------------------------------------
-- Writers — called by the AH scanner (AH prices) and the merchant hook (vendor)
-- ---------------------------------------------------------------------------

--- Persist a scanned lowest-buyout for an item. Ignores non-positive prices.
function Price.StoreAHPrice(itemId, copper)
    local db = store()
    if not db or type(itemId) ~= "number" or type(copper) ~= "number" or copper <= 0 then return end
    db.ahPrices[itemId] = { p = copper, at = (GetServerTime and GetServerTime()) or time() }
end

--- Persist a vendor buy price (per single item, not per stack).
function Price.StoreVendorPrice(itemId, copper)
    local db = store()
    if not db or type(itemId) ~= "number" or type(copper) ~= "number" or copper <= 0 then return end
    db.vendorPrices[itemId] = copper
end

-- ---------------------------------------------------------------------------
-- Reader
-- ---------------------------------------------------------------------------

--- Get the best price (copper) for an item. Returns price, source, ageSeconds.
--- source ∈ "auctionator" | "togpm-ah" | "auctionator-vendor" | "togpm-vendor"
--- | "vendor-static". Returns nil when nothing knows the item.
function Price.Get(itemId)
    if type(itemId) ~= "number" then return nil end
    local db = store()

    -- 1a. Auctionator AH
    local a = auctionatorAH(itemId)
    if a then return a, "auctionator", nil end

    -- 1b. TOGPM scanned AH
    if db and db.ahPrices[itemId] then
        local entry = db.ahPrices[itemId]
        local age = ((GetServerTime and GetServerTime()) or time()) - (entry.at or 0)
        return entry.p, "togpm-ah", age
    end

    -- 2a. Auctionator vendor
    local av = auctionatorVendor(itemId)
    if av then return av, "auctionator-vendor", nil end

    -- 2b. TOGPM live-captured vendor
    if db and db.vendorPrices[itemId] then
        return db.vendorPrices[itemId], "togpm-vendor", nil
    end

    -- 2c. Static shipped vendor table (generated from ItemSparse for vendor-sold
    -- reagents; nil until that data file ships).
    if addon.VendorPrices and addon.VendorPrices[itemId] then
        return addon.VendorPrices[itemId], "vendor-static", nil
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Crafting cost
-- ---------------------------------------------------------------------------

--- Total material cost to craft `qty` of (profId, recipeId), from LibProfessionDB
--- reagents. Returns:
---   total      copper (sum of priced reagents × need × qty); 0 if none priced
---   priced     number of distinct reagents we had a price for
---   total#     number of distinct reagents in the recipe
---   stale      true if any contributing AH price is older than AH_STALE_AFTER
--- When priced < count the total is a LOWER BOUND — the caller should flag it.
function Price.CraftCost(profId, recipeId, qty)
    qty = qty or 1
    local lib = LibStub and LibStub("LibProfessionDB-1.0", true)
    local reagents = lib and lib:GetReagents(profId, recipeId)
    if type(reagents) ~= "table" then return 0, 0, 0, false end

    local total, priced, count, stale = 0, 0, 0, false
    for itemId, need in pairs(reagents) do
        count = count + 1
        local p, _src, age = Price.Get(itemId)
        if p then
            priced = priced + 1
            total = total + p * need * qty
            if age and age > AH_STALE_AFTER then stale = true end
        end
    end
    return total, priced, count, stale
end

--- Cost from an explicit reagent list (the crafting tab's live engine reagents:
--- an array of { itemId, need, ... }). Same returns as CraftCost. Preferred in
--- the crafting tab since it reflects the exact recipe the trade-skill API gave.
function Price.CraftCostForReagents(reagents, qty)
    qty = qty or 1
    if type(reagents) ~= "table" then return 0, 0, 0, false end
    local total, priced, count, stale = 0, 0, 0, false
    for _, r in ipairs(reagents) do
        if r.itemId and r.need then
            count = count + 1
            local p, _src, age = Price.Get(r.itemId)
            if p then
                priced = priced + 1
                total = total + p * r.need * qty
                if age and age > AH_STALE_AFTER then stale = true end
            end
        end
    end
    return total, priced, count, stale
end

--- Format copper as a coin string, with a graceful text fallback.
function Price.Money(copper)
    if type(copper) ~= "number" then return "" end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return ("%dg %ds %dc"):format(g, s, c)
end

-- ---------------------------------------------------------------------------
-- Live merchant capture — cache vendor buy prices as the user opens vendors.
-- numAvailable == -1 means infinite stock = a true vendor-sold item (skip
-- limited-quantity/special-currency wares). price is per stack; divide.
-- Mirrors Auctionator.CraftingInfo.CacheVendorPrices.
-- ---------------------------------------------------------------------------
local function captureMerchant()
    local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
    for i = 1, n do
        local _, _, price, stack, numAvailable = GetMerchantItemInfo(i)
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        local itemId = link and tonumber(link:match("item:(%d+)"))
        if itemId and price and price > 0 and stack and stack > 0 and numAvailable == -1 then
            Price.StoreVendorPrice(itemId, math.floor(price / stack))
        end
    end
end

if Ace and Ace.RegisterEvent then
    Ace:RegisterEvent("MERCHANT_SHOW", function() captureMerchant() end)
end

-- Persist the AH scanner's lowest-buyout results when a scan completes so the
-- prices survive the AH closing (the scanner clears its session cache on close).
-- Distinct receiver (Price, not addon) so this coexists with the addon-keyed
-- AH_SCAN_COMPLETE handler in GUI/SharedWidgets.lua rather than stomping it.
if addon.RegisterCallback then
    addon.RegisterCallback(Price, "AH_SCAN_COMPLETE", function(_event, results)
        if type(results) ~= "table" then return end
        for itemId, r in pairs(results) do
            if r and r.lowestBuyout then Price.StoreAHPrice(itemId, r.lowestBuyout) end
        end
    end)
end
