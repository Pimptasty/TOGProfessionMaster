---@diagnostic disable: undefined-global
-- TOG Profession Master -- prices: what this addon still DECIDES about money,
-- over what LibItemDB now KNOWS about it.
--
-- THE LADDER LEFT THIS FILE ON 2026-09-14 (v1.1.0). The Auctionator / Auctioneer
-- / TSM adapters, the realm+faction scan store, the merchant capture and the
-- nine source toggles all moved into ItemDB (LibItemDB-1.0 MINOR 25,
-- `Price/Sources.lua`) at the user's direction -- "we need to move those 3rd
-- party integrations into itemDB now" -- so one copy serves every TOG addon.
-- TOGBankClassic's storefront reads the same numbers. What is here is TOGPM's
-- POLICY, which the library deliberately does not carry (its README: "Not
-- here, on purpose: crafting-cost maths ... stale thresholds"):
--
--   * GetReagentCost -- a reagent a vendor sells is costed at the VENDOR price
--     even when someone has listed it on the AH (the user's directive,
--     2026-09-11). The library answers "what is it worth" and "what does a
--     vendor charge" as two separate questions; the ordering is ours.
--   * CraftCost / CraftCostForReagents -- the sum, the BoP exclusion, the
--     lower-bound flag and the STALE flag (AH_STALE_AFTER).
--   * GetVendorSell -- the client's own number first, then the library's
--     shipped one; the tooltip's SELL row.
--   * The source labels and colours every TOGPM surface paints provenance with.
--
-- Everything else is a thin read of the library, feature-gated on the METHOD
-- (`DB.GetPrice`), never on a MINOR: against an older ItemDB the AH tiers answer
-- nil, the static vendor tier still answers through `GetVendorBasePrice`, and
-- nothing raises. Three-return shape (copper, source, ageSeconds) kept on every
-- reader so the ~20 call sites across the tabs did not have to change.
--
-- Source ids are ItemDB's now: "auctionator" | "auctioneer" | "tsm" | "scan"
-- | "auctionator-vendor" | "merchant" | "vendor-static", plus this file's own
-- "vendor-sell-client" | "vendor-sell-static". addon.PriceSourceLabels /
-- PriceSourceColors (TOGProfessionMaster.lua) are keyed by exactly that set.

local _, addon = ...

local Price = {}
addon.Price = Price

-- Treat a scanned AH price older than this (seconds) as stale-but-usable; the
-- number is still used, flagged, so the crafting cost can warn. 14 days mirrors
-- Auctionator's own price-history window.
local AH_STALE_AFTER = 14 * 24 * 60 * 60

-- Item bind type from GetItemInfo: 1 = Bind on Pickup.
local BIND_ON_PICKUP = 1

local function isBoPItem(itemId)
    if type(itemId) ~= "number" then return false end
    local bindType = select(14, addon.Item.GetInfo(itemId))
    return bindType == BIND_ON_PICKUP
end

--- The price library, when it carries the price API. `addon:GetItemDB()` is
--- resolved lazily (load order does not matter) and cached; the METHOD test is
--- what gates every AH read below.
local function priceDB()
    local DB = addon.GetItemDB and addon:GetItemDB()
    if DB and type(DB.GetPrice) == "function" then return DB end
    return nil
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
-- Readers over the library
-- ---------------------------------------------------------------------------

--- One library lookup, in this file's three-return shape. pcall-wrapped
--- because it is a cross-addon call whose failure must not take a tooltip or a
--- tab draw down with it.
local function libraryPrice(itemId, statistic)
    local DB = priceDB()
    if not DB then return nil end
    local ok, copper, why = pcall(DB.GetPrice, DB, itemId, statistic)
    if ok and type(copper) == "number" and copper > 0 then
        return copper, why and why.source or "scan", why and why.age or nil
    end
    return nil
end

--- What this item is WORTH, in copper: the library's "best" ladder (every
--- enabled source in the user's order, each source's statistics in turn --
--- exactly the ladder this file used to run), falling back to what a vendor
--- charges when no auction source knows it.
--- @return number|nil copper
--- @return string|nil source
--- @return number|nil ageSeconds  nil when the source cannot say
function Price.Get(itemId)
    if type(itemId) ~= "number" then return nil end
    local p, src, age = libraryPrice(itemId, "best")
    if p then return p, src, age end
    return Price.GetVendorBuy(itemId)
end

--- What a VENDOR CHARGES for this item, in copper, or nil.
---
--- The library's `GetVendorBuyPrice` -- Auctionator's vendor cache (when the
--- user has that source on), then a price this account SAW at a merchant (the
--- only tier that knows the reputation discount; the MERCHANT_SHOW capture
--- moved to ItemDB with the rest), then the shipped BASE price. Against an
--- ItemDB older than the price API the last tier still answers directly
--- through `GetVendorBasePrice` (MINOR 21), which is the behaviour that
--- shipped before the move.
---
--- Kept separate from `Price.Get` because on a tooltip "vendor buy price" is a
--- fact in its own right, not a fallback for a missing auction price. Three
--- returns for arity parity with `Price.Get`; the age is always nil -- a vendor
--- price does not go stale the way a scanned auction price does.
--- @return number|nil copper
--- @return string|nil source  "auctionator-vendor" | "merchant" | "vendor-static"
--- @return number|nil ageSeconds  always nil
function Price.GetVendorBuy(itemId)
    if type(itemId) ~= "number" then return nil end
    local DB = priceDB()
    if DB then
        local ok, copper, why = pcall(DB.GetVendorBuyPrice, DB, itemId)
        if ok and type(copper) == "number" and copper > 0 then
            return copper, why and why.source or "vendor-static", nil
        end
        return nil
    end
    -- Older ItemDB: the static tier alone. THIS IS THE BASE PRICE -- what a
    -- Neutral player pays; discounts are server-side and invisible here.
    local itemDB = addon.GetItemDB and addon:GetItemDB()
    if itemDB and itemDB.GetVendorBasePrice then
        local ok, price = pcall(itemDB.GetVendorBasePrice, itemDB, itemId)
        if ok and type(price) == "number" and price > 0 then
            return price, "vendor-static", nil
        end
    end
    return nil
end

--- What a VENDOR pays the player for an item, in copper. The mirror of
--- `GetVendorBuy`, and roughly 4x smaller -- never substitute one for the other
--- (Schematic: Accurate Scope sells for 500 and buys for 2000).
---
--- TWO TIERS, and the order is deliberate:
---
---   1. `GetItemInfo`'s eleventh return. The client's own number for the item,
---      and therefore the most authoritative thing available -- but only for an
---      item the client has CACHED. Nil otherwise, which is precisely the hole
---      this function exists to close: the sell row went missing exactly when a
---      player met an item for the first time. Reading it starts the async
---      fetch, so a second hover lands warm -- a mitigation, never a fix.
---   2. `LibItemDB-1.0:GetVendorSellPrice` (MINOR 22). Static, shipped,
---      version-scoped, and ALWAYS populated -- no cache, no retry loop.
---
--- The client tier is first because it cannot regress a number that already
--- renders correctly; the static tier only ever adds an answer where there was
--- none. Both derive from the same DBC field, so where both answer they agree.
--- Feature-detected on the method and pcall-wrapped, so an ItemDB that
--- predates the API simply falls back to tier 1. NO REPUTATION DISCOUNT is
--- applied -- this is the Neutral number. `nil` means "no sell value" (a quest
--- item, a token), a clean answer rather than an absence.
--- @return number|nil copper
--- @return string|nil source  "vendor-sell-client" | "vendor-sell-static"
function Price.GetVendorSell(itemId)
    if type(itemId) ~= "number" then return nil end

    -- A type check rather than a truthiness test: 0 is a real answer for an item
    -- no vendor will buy, and must not render as a price.
    local sell = select(11, addon.Item.GetInfo(itemId))
    if type(sell) == "number" and sell > 0 then return sell, "vendor-sell-client" end

    local itemDB = addon.GetItemDB and addon:GetItemDB()
    if itemDB and itemDB.GetVendorSellPrice then
        local ok, price = pcall(itemDB.GetVendorSellPrice, itemDB, itemId)
        if ok and type(price) == "number" and price > 0 then
            return price, "vendor-sell-static"
        end
    end

    return nil
end

--- Live sell price for crafted-item profit calculations: the library's "best"
--- ladder. Never a vendor price -- the Profit Planner is asking what the AH
--- would pay, and a vendor buy price is the wrong side of the counter.
--- @return number|nil copper
--- @return string|nil source
--- @return number|nil ageSeconds
function Price.GetSaleLive(itemId)
    if type(itemId) ~= "number" then return nil end
    return libraryPrice(itemId, "best")
end

--- Historical sell price for crafted-item profit calculations: the library's
--- "historical" statistic, answered only by a source that carries one
--- (Auctionator's 14-day mean, Auctioneer's cached stat, TSM's DBHistorical)
--- -- never a minimum buyout relabelled.
--- @return number|nil copper
--- @return string|nil source
function Price.GetSaleHistorical(itemId)
    if type(itemId) ~= "number" then return nil end
    local p, src = libraryPrice(itemId, "historical")
    return p, src
end

-- ---------------------------------------------------------------------------
-- Crafting cost -- TOGPM policy
-- ---------------------------------------------------------------------------

--- What it COSTS to obtain one of this reagent, in copper -- the number the
--- crafting-cost and profit maths are built from.
---
--- This is NOT `Price.Get`. That answers "what is this worth" and prefers the
--- auction house, which is right for the crafted item you are about to sell
--- and wrong for a reagent a vendor stocks: nobody buys Crystal Vials off the
--- AH at 5x the vendor price, and one player listing them there was making
--- every alchemy recipe's cost -- and profit -- wrong for everyone who scanned.
--- Reported on Discord 2026-08-23 ("it seems togpm uses the auction house
--- price for easy to obtain vendor items like vials"). The operator's
--- directive, 2026-09-11: a vendor-sold reagent is costed at the vendor price,
--- even when someone has listed it on the AH.
---
--- So: vendor buy price first, and only when NO vendor sells the item does the
--- AH ladder answer. Same three returns as `Price.Get`; age is nil for a
--- vendor price because it does not go stale.
--- @return number|nil copper
--- @return string|nil source
--- @return number|nil ageSeconds
function Price.GetReagentCost(itemId)
    if type(itemId) ~= "number" then return nil end
    local v, vSrc = Price.GetVendorBuy(itemId)
    if v then return v, vSrc, nil end
    return Price.Get(itemId)
end

--- Total material cost to craft `qty` of (profId, recipeId), from LibProfessionDB
--- reagents. Returns:
---   total      copper (sum of priced reagents x need x qty); 0 if none priced
---   priced     number of distinct NON-BoP reagents we had a price for
---   total#     number of distinct NON-BoP reagents in the recipe
---   stale      true if any contributing AH price is older than AH_STALE_AFTER
--- BoP reagents are excluded from priced/count completeness checks so they do
--- not block profit/cost calculations when no market/vendor price exists.
--- When priced < count the total is a LOWER BOUND -- the caller should flag it.
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
        local p, _, age = Price.GetReagentCost(itemId)
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
--- completeness). Preferred in the crafting tab since it reflects the exact
--- recipe the trade-skill API gave.
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
            local p, _, age = Price.GetReagentCost(r.itemId)
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

--- Format copper as a coin string, with a graceful text fallback. The
--- library's formatter when it has one (same rule, one copy); this file's own
--- otherwise, so the tabs render money against any ItemDB.
function Price.Money(copper)
    if type(copper) ~= "number" then return "" end
    local DB = priceDB()
    if DB and DB.FormatMoney then return DB:FormatMoney(copper) end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return ("%dg %ds %dc"):format(g, s, c)
end
