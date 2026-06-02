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
--      b. TradeSkillMaster live/historical APIs (optional, toggle-gated).
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

-- Item bind type from GetItemInfo: 1 = Bind on Pickup.
local BIND_ON_PICKUP = 1

local function isBoPItem(itemId)
    if type(itemId) ~= "number" then return false end
    local bindType = select(14, GetItemInfo(itemId))
    return bindType == BIND_ON_PICKUP
end

-- ---------------------------------------------------------------------------
-- Source presentation helpers
-- ---------------------------------------------------------------------------
function Price.GetSourceLabel(source)
    if not source then return "Unknown" end
    return (addon.PriceSourceLabels and addon.PriceSourceLabels[source]) or source
end

function Price.GetSourceColor(source)
    if not source then return "ffaaaaaa" end
    return (addon.PriceSourceColors and addon.PriceSourceColors[source]) or "ffaaaaaa"
end

function Price.ColorizeSource(source)
    local label = Price.GetSourceLabel(source)
    local color = Price.GetSourceColor(source)
    return "|c" .. color .. label .. "|r"
end

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

local function auctionatorHistoricalEnabled()
    local profile = Ace and Ace.db and Ace.db.profile
    if not profile then return false end
    if profile.useAuctionator ~= true then return false end
    if profile.useAuctionatorHistorical == nil then return true end
    return profile.useAuctionatorHistorical == true
end

local function togpmAHEnabled()
    local profile = Ace and Ace.db and Ace.db.profile
    -- Back-compat default for existing SavedVariables: nil means enabled.
    if not profile then return true end
    if profile.useTOGPMAH == nil then return true end
    return profile.useTOGPMAH == true
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

local function auctionatorHistorical(itemId)
    if not auctionatorHistoricalEnabled() then return nil end
    if not (Auctionator and Auctionator.API and Auctionator.API.v1) then return nil end
    local api = Auctionator.API.v1
    local fn = api.GetHistoricalPriceByItemID or api.GetAuctionPriceByItemID
    if type(fn) ~= "function" then return nil end
    local ok, price = pcall(fn, AUCTIONATOR_CALLER, itemId)
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
-- Auctioneer bridge (optional, feature-detected)
-- ---------------------------------------------------------------------------
local function auctioneerEnabled()
    return Ace and Ace.db and Ace.db.profile and Ace.db.profile.useAuctioneer == true
end

local function auctioneerCachedEnabled()
    local profile = Ace and Ace.db and Ace.db.profile
    if not profile then return false end
    if profile.useAuctioneer ~= true then return false end
    if profile.useAuctioneerCached == nil then return true end
    return profile.useAuctioneerCached == true
end

local function auctioneerReady()
    return auctioneerEnabled()
       and type(AucAdvanced) == "table"
       and type(AucAdvanced.API) == "table"
       and type(AucAdvanced.API.GetMarketValue) == "function"
end

local function auctioneerLive(itemId)
    if not auctioneerReady() then return nil end
    local fn = AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetMarketValue
    if type(fn) ~= "function" then return nil end

    local itemLink = select(2, GetItemInfo(itemId))
    local fallbackLinks = {
        itemLink,
        -- Canonical WoW itemstring form (8 fields) tends to sanitize/parse
        -- consistently across pricing addons.
        ("item:%d:0:0:0:0:0:0:0"):format(itemId),
        -- Keep compact form as a final fallback.
        ("item:%d"):format(itemId),
    }
    local serverKey = AucAdvanced and AucAdvanced.Resources and AucAdvanced.Resources.ServerKey

    local function normalizePrice(v)
        if type(v) == "number" and v > 0 then
            return floor(v + 0.5)
        end
        return nil
    end

    local function firstNumeric(...)
        for i = 1, select("#", ...) do
            local v = normalizePrice(select(i, ...))
            if v then return v end
        end
        return nil
    end

    for _, link in ipairs(fallbackLinks) do
        if link and link ~= "" then
            -- Auctioneer variants differ by branch/version; probe common call shapes.
            local p
            local ok, r1, r2, r3 = pcall(fn, link, serverKey, 0.5)
            if ok then p = firstNumeric(r1, r2, r3) end
            if not p then
                ok, r1, r2, r3 = pcall(fn, link, serverKey)
                if ok then p = firstNumeric(r1, r2, r3) end
            end
            if not p then
                ok, r1, r2, r3 = pcall(fn, link)
                if ok then p = firstNumeric(r1, r2, r3) end
            end
            if p then
                return p
            end
        end
    end
    return nil
end

local function auctioneerCached(itemId)
    if not auctioneerReady() then return nil end
    if not auctioneerCachedEnabled() then return nil end
    local fn = AucAdvanced and AucAdvanced.API and AucAdvanced.API.GetAlgorithmValue

    local itemLink = select(2, GetItemInfo(itemId))
    local fallbackLinks = {
        itemLink,
        ("item:%d:0:0:0:0:0:0:0"):format(itemId),
        ("item:%d"):format(itemId),
    }
    local serverKey = AucAdvanced and AucAdvanced.Resources and AucAdvanced.Resources.ServerKey

    local function normalizePrice(v)
        if type(v) == "number" and v > 0 then
            return floor(v + 0.5)
        end
        return nil
    end

    local function firstNumeric(...)
        for i = 1, select("#", ...) do
            local v = normalizePrice(select(i, ...))
            if v then return v end
        end
        return nil
    end

    local statEngines = {
        "stat_simple",
        "stat_histogram",
        "stat_stddev",
        "stat_iLevel",
        -- Alternate names used by some Auctioneer builds/plugins.
        "Simple",
        "Histogram",
        "StdDev",
        "iLevel",
        "stat:simple",
        "stat:histogram",
        "stat:stddev",
        "stat:ilevel",
    }
    if type(fn) == "function" then
        for _, link in ipairs(fallbackLinks) do
            if link and link ~= "" then
                for _, engine in ipairs(statEngines) do
                    local pNorm
                    -- Probe multiple signatures because GetAlgorithmValue differs
                    -- between Auctioneer branch/plugin combinations.
                    local ok, r1, r2, r3 = pcall(fn, engine, link, serverKey)
                    if ok then pNorm = firstNumeric(r1, r2, r3) end
                    if not pNorm then
                        ok, r1, r2, r3 = pcall(fn, link, engine, serverKey)
                        if ok then pNorm = firstNumeric(r1, r2, r3) end
                    end
                    if not pNorm then
                        ok, r1, r2, r3 = pcall(fn, engine, link)
                        if ok then pNorm = firstNumeric(r1, r2, r3) end
                    end
                    if not pNorm then
                        ok, r1, r2, r3 = pcall(fn, link, engine)
                        if ok then pNorm = firstNumeric(r1, r2, r3) end
                    end
                    if pNorm then
                        return pNorm
                    end
                end
            end
        end
    end

    -- Some Auctioneer builds expose cached data via Stat modules only (with
    -- no useful GetAlgorithmValue path). Probe loaded Stat modules directly.
    if type(AucAdvanced) == "table" and type(AucAdvanced.GetAllModules) == "function" then
        local okMods, modules = pcall(AucAdvanced.GetAllModules, nil, "Stat")
        if okMods and type(modules) == "table" then
            local bestPrice, bestSeen
            for _, link in ipairs(fallbackLinks) do
                if link and link ~= "" then
                    for _, mod in ipairs(modules) do
                        if type(mod) == "table" and type(mod.GetPriceArray) == "function" then
                            local okArr, arr = pcall(mod.GetPriceArray, link, serverKey)
                            if okArr and type(arr) == "table" then
                                local pNorm = firstNumeric(arr.price, arr.minBuyout, arr.mean, arr[1])
                                if pNorm then
                                    local seen = tonumber(arr.seen or arr.auctionsCount or arr.dayCount or 0) or 0
                                    if not bestPrice or seen > (bestSeen or -1) then
                                        bestPrice, bestSeen = pNorm, seen
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if bestPrice then
                return bestPrice
            end
        end
    end

    return nil
end

-- Diagnostic helper for slash tools; keeps Auctioneer troubleshooting in one
-- place so we can verify readiness/toggles and both live/cached probes.
function Price.GetAuctioneerDiagnostics(itemId)
    local profile = Ace and Ace.db and Ace.db.profile
    local ready = auctioneerReady()
    local hasAlgo = type(AucAdvanced) == "table"
                and type(AucAdvanced.API) == "table"
                and type(AucAdvanced.API.GetAlgorithmValue) == "function"
    local d = {
        itemId = itemId,
        useAuctioneer = profile and profile.useAuctioneer == true or false,
        useAuctioneerCached = profile and profile.useAuctioneerCached ~= false or false,
        ready = ready,
        hasAlgorithmAPI = hasAlgo,
        hasModuleRegistry = type(AucAdvanced) == "table" and type(AucAdvanced.GetAllModules) == "function",
        serverKey = AucAdvanced and AucAdvanced.Resources and AucAdvanced.Resources.ServerKey,
        live = auctioneerLive(itemId),
        cached = auctioneerCached(itemId),
    }
    return d
end

-- ---------------------------------------------------------------------------
-- TSM bridge (optional, feature-detected)
-- ---------------------------------------------------------------------------
local function tsmEnabled()
    return Ace and Ace.db and Ace.db.profile and Ace.db.profile.useTSM == true
end

local function tsmAppHelperEnabled()
    return Ace and Ace.db and Ace.db.profile and Ace.db.profile.useTSMAppHelper == true
end

local function tsmAppHelperLoaded()
    if addon and addon.IsAddOnLoaded then
        return addon:IsAddOnLoaded("TradeSkillMaster_AppHelper") == true
    end
    return IsAddOnLoaded and IsAddOnLoaded("TradeSkillMaster_AppHelper") == true
end

local function tsmReady()
    return (tsmEnabled() or tsmAppHelperEnabled())
       and type(TSM_API) == "table"
       and type(TSM_API.GetCustomPriceValue) == "function"
end

local function tsmCustomPrice(itemId, expr)
    if not tsmReady() then return nil end
    local itemStrings = {
        "i:" .. tostring(itemId),
        "item:" .. tostring(itemId),
    }

    for _, itemString in ipairs(itemStrings) do
        local ok, price = pcall(TSM_API.GetCustomPriceValue, expr, itemString)
        if ok and type(price) == "number" and price > 0 then return price end

        ok, price = pcall(TSM_API.GetCustomPriceValue, itemString, expr)
        if ok and type(price) == "number" and price > 0 then return price end
    end

    return nil
end

local function tsmFirst(itemId, sources)
    for _, expr in ipairs(sources or {}) do
        local p = tsmCustomPrice(itemId, expr)
        if p then return p, expr end
    end

    return nil
end

local function tsmSourceForExpr(expr)
    -- True realm-live style values.
    if expr == "DBMinBuyout" or expr == "DBRecent" then
        return "tsm-live"
    end
    -- AppHelper-backed / non-live style values.
    return "tsm-history"
end

local function tsmLive(itemId)
    -- Prefer true live values first, then progressively broader TSM fallbacks.
    return tsmFirst(itemId, {
        "DBMinBuyout",
        "DBRecent",
        "DBMarket",
        "DBHistorical",
        "DBRegionMarketAvg",
        "DBRegionSaleAvg",
    })
end

local function tsmHistorical(itemId)
    if not tsmReady() then return nil end
    -- Historical tab should still resolve when realm data is missing by using
    -- region-level fallbacks supplied by TSM/AppHelper datasets.
    return tsmFirst(itemId, {
        "DBMarket",
        "DBHistorical",
        "DBRegionMarketAvg",
        "DBRegionSaleAvg",
        "DBRecent",
        "DBMinBuyout",
    })
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

    local ah = auctionatorHistorical(itemId)
    if ah then return ah, "auctionator-history", nil end

    -- 1b. Auctioneer market (non-live; scan/app-derived)
    local am = auctioneerLive(itemId)
    if am then return am, "auctioneer-live", nil end

    local amc = auctioneerCached(itemId)
    if amc then return amc, "auctioneer-cached", nil end

    -- 1c. TSM live/historical (optional)
    local t, tExpr = tsmLive(itemId)
    if t then return t, tsmSourceForExpr(tExpr), nil end

    local th, thExpr = tsmHistorical(itemId)
    if th then return th, tsmSourceForExpr(thExpr), nil end

    -- 1d. TOGPM scanned AH
    if togpmAHEnabled() and db and db.ahPrices[itemId] then
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

--- Live sell price for crafted-item profit calculations.
--- Sources: Auctionator live -> TSM live -> TOGPM scanned AH.
--- Returns: price, source, ageSeconds (age only for TOGPM scanned AH).
function Price.GetSaleLive(itemId)
    if type(itemId) ~= "number" then return nil end

    local a = auctionatorAH(itemId)
    if a then return a, "auctionator", nil end

    local ah = auctionatorHistorical(itemId)
    if ah then return ah, "auctionator-history", nil end

    -- Auctioneer values are not true live buyout quotes but are useful
    -- fallback sale estimates in the live tab.
    local am = auctioneerLive(itemId)
    if am then return am, "auctioneer-live", nil end

    local amc = auctioneerCached(itemId)
    if amc then return amc, "auctioneer-cached", nil end

    local t, tExpr = tsmLive(itemId)
    if t then return t, tsmSourceForExpr(tExpr), nil end

    local db = store()
    if togpmAHEnabled() and db and db.ahPrices[itemId] then
        local entry = db.ahPrices[itemId]
        local age = ((GetServerTime and GetServerTime()) or time()) - (entry.at or 0)
        return entry.p, "togpm-ah", age
    end

    return nil
end

--- Historical sell price for crafted-item profit calculations.
--- Sources: Auctionator history -> TSM history.
--- Returns: price, source.
function Price.GetSaleHistorical(itemId)
    if type(itemId) ~= "number" then return nil end

    local a = auctionatorHistorical(itemId)
    if a then return a, "auctionator-history" end

    local am = auctioneerLive(itemId)
    if am then return am, "auctioneer-live" end

    local amc = auctioneerCached(itemId)
    if amc then return amc, "auctioneer-cached" end

    local t, tExpr = tsmHistorical(itemId)
    if t then return t, tsmSourceForExpr(tExpr) end

    return nil
end

-- ---------------------------------------------------------------------------
-- Crafting cost
-- ---------------------------------------------------------------------------

--- Total material cost to craft `qty` of (profId, recipeId), from LibProfessionDB
--- reagents. Returns:
---   total      copper (sum of priced reagents × need × qty); 0 if none priced
---   priced     number of distinct NON-BoP reagents we had a price for
---   total#     number of distinct NON-BoP reagents in the recipe
---   stale      true if any contributing AH price is older than AH_STALE_AFTER
--- BoP reagents are excluded from priced/count completeness checks so they do
--- not block profit/cost calculations when no market/vendor price exists.
--- When priced < count the total is a LOWER BOUND — the caller should flag it.
function Price.CraftCost(profId, recipeId, qty)
    qty = qty or 1
    local lib = LibStub and LibStub("LibProfessionDB-1.0", true)
    local reagents = lib and lib:GetReagents(profId, recipeId)
    if type(reagents) ~= "table" then return 0, 0, 0, false end

    local total, priced, count, stale = 0, 0, 0, false
    for itemId, need in pairs(reagents) do
        local countable = not isBoPItem(itemId)
        -- BoP reagents cannot be reliably priced from AH/vendor datasets and
        -- should not disqualify an otherwise-priced recipe from profit math.
        if countable then
            count = count + 1
        end
        local p, _src, age = Price.Get(itemId)
        if p then
            if countable then
                priced = priced + 1
            end
            total = total + p * need * qty
            if age and age > AH_STALE_AFTER then stale = true end
        end
    end
    return total, priced, count, stale
end

--- Cost from an explicit reagent list (the crafting tab's live engine reagents:
--- an array of { itemId, need, ... }). Same returns as CraftCost (BoP-excluded
--- completeness). Preferred in
--- the crafting tab since it reflects the exact recipe the trade-skill API gave.
function Price.CraftCostForReagents(reagents, qty)
    qty = qty or 1
    if type(reagents) ~= "table" then return 0, 0, 0, false end
    local total, priced, count, stale = 0, 0, 0, false
    for _, r in ipairs(reagents) do
        if r.itemId and r.need then
            local countable = not isBoPItem(r.itemId)
            if countable then
                count = count + 1
            end
            local p, _src, age = Price.Get(r.itemId)
            if p then
                if countable then
                    priced = priced + 1
                end
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
