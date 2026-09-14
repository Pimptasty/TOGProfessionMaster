-- Prices: what this addon still DECIDES about money, over what LibItemDB KNOWS.
--
-- THE LADDER LEFT THIS ADDON on 2026-09-14 (v1.1.0): the Auctionator /
-- Auctioneer / TSM bridges, the realm+faction scan store, the merchant capture
-- and the source toggles are ItemDB's now (`Price/Sources.lua`, MINOR 25).
--
-- writ-cannot: the "writers", "Auctionator bridge", "TSM bridge", "Auctioneer
-- bridge", "merchant capture" and "AH scan results" groups that stood here
-- until v1.1.0 tested code that was DELETED from this addon on purpose (the
-- user's directive: "we need to move those 3rd party integrations into itemDB
-- now"); every one of those cases lives in ItemDB's Tests/price_spec.lua
-- against the copy that now runs -- "the store", "Auctionator",
-- "TradeSkillMaster", "Auctioneer", "the ladder", "merchant capture". Keeping
-- them here would assert functions this addon no longer has.
--
-- What is pinned HERE is the policy that stayed:
--
--   * a vendor-sold reagent is COSTED at the vendor price, whatever the AH says;
--   * the crafting-cost sum, the BoP exclusion, the lower-bound and STALE flags;
--   * the three-return shape (copper, source, age) every tab was written to;
--   * that every read is feature-gated on the METHOD, so an older ItemDB
--     degrades to its static vendor tier and a raising one takes nothing down.
--
-- Driven against the REAL library and the REAL Price/ files (env.priceDB), not
-- a stub of GetPrice: every price this addon shows is the library's answer, so
-- a stub here could only confirm the stub author's idea of the ladder. The
-- hand-made objects below appear ONLY where the real library cannot be made to
-- do the thing under test (raise, or predate the API).

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Price, DB

local ORE    = 2770   -- Copper Ore
local BOP    = 12345  -- stands in for a soulbound reagent
local THREAD = 2320   -- Coarse Thread, a vendor staple
local VIAL   = 3371   -- Empty Vial

setup(function()
	ns    = env.initDb()
	Price = env.loadModule("Modules/Price.lua").Price
end)

before_each(function()
	env.install()
	_G.GetCoinTextureString = nil
	-- Both spellings -- Price.lua reads through addon.Item.GetInfo, which
	-- prefers C_Item exactly as the client does. See env.itemAPI.
	env.itemAPI("GetItemInfo", function() return nil end)
	-- The real library with its price API, over an empty store, no third-party
	-- price addon present. Fresh per example: settings AND store.
	DB = env.priceDB()
end)

after_each(function()
	-- `_itemDB` is cached on the addon for the session; a fresh load per example
	-- above means nothing leaks, but a later spec file must not inherit this
	-- one's library either.
	ns._itemDB = nil
end)

--- The library's SHIPPED vendor prices (its static tier), loaded through its
--- own `LoadVendorPrices` so its validation runs too (rejects 0, negatives,
--- non-numerics).
local function shippedVendorPrices(prices)
	DB.vendorPrice = {}
	DB:LoadVendorPrices(prices or {})
end

--- A hand-made object standing in for the library, used ONLY where the real
--- one cannot be made to do the thing under test.
local function standIn(stub)
	ns._itemDB = stub or false
end

--- Auctionator present, as ItemDB's adapter sees it (API v1, callerID first).
local function installAuctionator(live, vendor, historical)
	_G.Auctionator = { API = { v1 = {
		GetAuctionPriceByItemID    = function() return live end,
		GetVendorPriceByItemID     = function() return vendor end,
		GetHistoricalPriceByItemID = historical and function() return historical end or nil,
	} } }
end

-- Mark an item Bind-on-Pickup through the real GetItemInfo contract (bindType
-- is the 14th return).
local function bindOnPickup(itemId)
	env.itemAPI("GetItemInfo", function(id)
		if id == itemId then
			return "Soulbound Thing", "|cffffffff|Hitem:" .. id .. "|h[x]|h|r",
			       1, 60, 60, "", "", 1, "", "", 0, 0, 0, 1
		end
		return nil
	end)
end

describe("source presentation", function()
	it("labels and colours a known source from the shared tables", function()
		assert.equal(ns.PriceSourceLabels["scan"], Price.GetSourceLabel("scan"))
		assert.equal(ns.PriceSourceColors["scan"], Price.GetSourceColor("scan"))
	end)

	it("carries a label and a colour for EVERY id the library can answer with", function()
		-- ItemDB's provenance ids plus this file's own two vendor-sell ids. A
		-- new source in the library with no entry here would render as its raw
		-- id in a neutral grey on every tab -- loud enough, but this says so
		-- first. The AH sources come from the library's own registry rather
		-- than a list typed here.
		local sources = DB:GetPriceSources()
		assert.is_true(#sources >= 4, "the library lists its sources")
		for _, src in ipairs(sources) do
			assert.is_string(ns.PriceSourceLabels[src.id], "no label for " .. src.id)
			assert.is_string(ns.PriceSourceColors[src.id], "no colour for " .. src.id)
		end
		for _, id in ipairs({ "auctionator-vendor", "merchant", "vendor-static",
		                      "vendor-sell-client", "vendor-sell-static" }) do
			assert.is_string(ns.PriceSourceLabels[id], "no label for " .. id)
			assert.is_string(ns.PriceSourceColors[id], "no colour for " .. id)
		end
	end)

	it("falls back to the raw source name and a neutral grey", function()
		assert.equal("something-new", Price.GetSourceLabel("something-new"))
		assert.equal("ffaaaaaa", Price.GetSourceColor("something-new"))
	end)

	it("handles no source at all", function()
		assert.equal("Unknown", Price.GetSourceLabel(nil))
		assert.equal("ffaaaaaa", Price.GetSourceColor(nil))
	end)

	it("wraps the label in its colour code", function()
		local out = Price.ColorizeSource("scan")
		assert.is_true(out:find(ns.PriceSourceColors["scan"], 1, true) ~= nil)
		assert.is_true(out:sub(-2) == "|r")
	end)
end)

describe("Price.Get -- what an item is WORTH, through the library's ladder", function()
	it("rejects a non-numeric item", function()
		assert.is_nil(Price.Get("2770"))
		assert.is_nil(Price.Get(nil))
	end)

	it("returns nothing when no source knows the item", function()
		assert.is_nil(Price.Get(ORE))
	end)

	it("returns the library's scanned auction price, with its source and age", function()
		env.serverTime = 1000
		DB:StoreScannedPrice(ORE, 500, 3)
		env.serverTime = 1600
		local price, source, age = Price.Get(ORE)
		assert.equal(500, price)
		assert.equal("scan", source)
		assert.equal(600, age)
	end)

	it("honours the library's own-scan toggle, which is where the setting lives now", function()
		DB:StoreScannedPrice(ORE, 500)
		assert.is_true(DB:SetPriceSetting("useOwnScan", false))
		assert.is_nil(Price.Get(ORE))
	end)

	it("walks the library's precedence: an enabled Auctionator outranks the own scan", function()
		installAuctionator(777)
		DB:StoreScannedPrice(ORE, 500)
		-- Off by default in ItemDB exactly as it was here: nobody's numbers come
		-- from someone else's addon until they opt in.
		assert.equal("scan", select(2, Price.Get(ORE)))
		assert.is_true(DB:SetPriceSetting("useAuctionator", true))
		local price, source = Price.Get(ORE)
		assert.equal(777, price)
		assert.equal("auctionator", source)
	end)

	it("falls back to what a vendor charges when no auction source knows the item", function()
		DB:StoreVendorPrice(THREAD, 100)
		local price, source, age = Price.Get(THREAD)
		assert.equal(100, price)
		assert.equal("merchant", source)
		assert.is_nil(age)
	end)

	it("prefers the auction house over any vendor price", function()
		shippedVendorPrices({ [THREAD] = 999 })
		DB:StoreVendorPrice(THREAD, 100)
		DB:StoreScannedPrice(THREAD, 50)
		assert.equal("scan", select(2, Price.Get(THREAD)))
	end)

	it("survives the library raising, rather than taking a tab draw down", function()
		standIn({
			GetPrice          = function() error("boom") end,
			GetVendorBuyPrice = function() return nil end,
		})
		assert.is_nil(Price.Get(ORE))
	end)

	it("ignores a zero or a non-number from the library", function()
		for _, bad in ipairs({ 0, -1, "lots" }) do
			standIn({
				GetPrice          = function() return bad, { source = "scan" } end,
				GetVendorBuyPrice = function() return nil end,
			})
			assert.is_nil(Price.Get(ORE))
		end
	end)

	it("labels an answer with no provenance as the own scan rather than nothing", function()
		standIn({
			GetPrice          = function() return 42 end,
			GetVendorBuyPrice = function() return nil end,
		})
		local price, source, age = Price.Get(ORE)
		assert.equal(42, price)
		assert.equal("scan", source)
		assert.is_nil(age)
	end)
end)

describe("Price.GetVendorBuy -- what a vendor CHARGES", function()
	it("rejects a non-numeric item", function()
		assert.is_nil(Price.GetVendorBuy("2320"))
	end)

	it("prefers a price this account SAW at a merchant over the shipped base price", function()
		-- The correctness argument for the tier order, now the library's: the
		-- shipped number is the Neutral BASE price, while the merchant capture
		-- recorded what this character was actually charged, discount included.
		shippedVendorPrices({ [THREAD] = 999 })
		DB:StoreVendorPrice(THREAD, 100)
		local price, source, age = Price.GetVendorBuy(THREAD)
		assert.equal(100, price)
		assert.equal("merchant", source)
		assert.is_nil(age)
	end)

	it("falls back to the shipped base price last", function()
		shippedVendorPrices({ [THREAD] = 999 })
		local price, source = Price.GetVendorBuy(THREAD)
		assert.equal(999, price)
		assert.equal("vendor-static", source)
	end)

	it("takes Auctionator's vendor cache first when that source is on", function()
		installAuctionator(nil, 42)
		DB:StoreVendorPrice(THREAD, 100)
		assert.equal("merchant", select(2, Price.GetVendorBuy(THREAD)))
		DB:SetPriceSetting("useAuctionator", true)
		local price, source = Price.GetVendorBuy(THREAD)
		assert.equal(42, price)
		assert.equal("auctionator-vendor", source)
	end)

	it("answers nothing for an item with no vendor record", function()
		-- `nil` means "no vendor RECORD", not "no vendor sells this" -- ItemDB
		-- retracted the stronger claim on 2026-08-07 (their
		-- docs/DEPENDENCY_CONTRACTS.md §7). Omitting the price is right;
		-- asserting "no vendor sells this" from it would not be.
		shippedVendorPrices({})
		assert.is_nil(Price.GetVendorBuy(VIAL))
	end)

	it("ignores a zero price, because the library refuses to store one", function()
		-- Driven through the real LoadVendorPrices, which rejects 0 and
		-- negatives outright -- the two layers agree.
		shippedVendorPrices({ [VIAL] = 0, [4306] = -5 })
		assert.is_nil(Price.GetVendorBuy(VIAL))
		assert.is_nil(Price.GetVendorBuy(4306))
	end)

	it("still answers the static tier against an ItemDB that predates the price API", function()
		-- The behaviour that shipped before the move (MINOR 21's
		-- GetVendorBasePrice), kept so an older ItemDB is a degrade, not a hole.
		standIn({ GetVendorBasePrice = function(_, id) return id == VIAL and 25 or nil end })
		local price, source, age = Price.GetVendorBuy(VIAL)
		assert.equal(25, price)
		assert.equal("vendor-static", source)
		assert.is_nil(age)
		assert.is_nil(Price.GetVendorBuy(ORE))
		-- And Price.Get lands there too, with no auction tier to try first.
		assert.equal("vendor-static", select(2, Price.Get(VIAL)))
	end)

	it("ignores a junk answer from that older tier", function()
		standIn({ GetVendorBasePrice = function() return "free" end })
		assert.is_nil(Price.GetVendorBuy(VIAL))
	end)

	it("degrades quietly against a LibItemDB with neither API", function()
		standIn({ GetLink = function() end })
		assert.is_nil(Price.GetVendorBuy(VIAL))
		assert.is_nil(Price.Get(VIAL))
	end)

	it("degrades quietly when ItemDB is not installed at all", function()
		standIn(nil)
		assert.is_nil(Price.GetVendorBuy(VIAL))
		assert.is_nil(Price.Get(VIAL))
	end)

	it("survives either tier raising", function()
		standIn({ GetVendorBasePrice = function() error("boom") end })
		assert.is_nil(Price.GetVendorBuy(VIAL))
		standIn({ GetPrice = function() return nil end, GetVendorBuyPrice = function() error("boom") end })
		assert.is_nil(Price.GetVendorBuy(VIAL))
	end)

	it("ignores a zero from the price API's vendor tier", function()
		standIn({ GetPrice = function() return nil end, GetVendorBuyPrice = function() return 0 end })
		assert.is_nil(Price.GetVendorBuy(VIAL))
	end)

	it("labels a vendor answer with no provenance as the static tier", function()
		standIn({ GetPrice = function() return nil end, GetVendorBuyPrice = function() return 7 end })
		assert.equal("vendor-static", select(2, Price.GetVendorBuy(VIAL)))
	end)
end)

describe("sale prices", function()
	it("GetSaleLive reports the scan's price and age", function()
		env.serverTime = 1000
		DB:StoreScannedPrice(ORE, 400)
		env.serverTime = 1100
		local price, source, age = Price.GetSaleLive(ORE)
		assert.equal(400, price)
		assert.equal("scan", source)
		assert.equal(100, age)
	end)

	it("GetSaleLive never falls back to a vendor price", function()
		-- The Profit Planner is asking what the AH would pay; a vendor buy price
		-- is the wrong side of the counter.
		shippedVendorPrices({ [THREAD] = 999 })
		DB:StoreVendorPrice(THREAD, 100)
		assert.is_nil(Price.GetSaleLive(THREAD))
	end)

	it("GetSaleHistorical is answered only by a source carrying a history", function()
		-- The own scan has a minimum buyout and nothing else, so it cannot
		-- answer; Auctionator's historical figure can, once that source is on.
		DB:StoreScannedPrice(ORE, 400)
		assert.is_nil(Price.GetSaleHistorical(ORE))
		installAuctionator(nil, nil, 321)
		DB:SetPriceSetting("useAuctionator", true)
		local price, source = Price.GetSaleHistorical(ORE)
		assert.equal(321, price)
		assert.equal("auctionator", source)
	end)

	it("GetSaleHistorical returns nothing when no history source knows the item", function()
		assert.is_nil(Price.GetSaleHistorical(ORE))
	end)

	it("both answer nothing against an ItemDB without the price API", function()
		standIn({ GetVendorBasePrice = function() return 25 end })
		assert.is_nil(Price.GetSaleLive(ORE))
		assert.is_nil(Price.GetSaleHistorical(ORE))
	end)

	it("both reject a non-numeric item", function()
		assert.is_nil(Price.GetSaleLive("x"))
		assert.is_nil(Price.GetSaleHistorical("x"))
	end)
end)

describe("craft cost", function()
	it("sums priced reagents across the quantity", function()
		DB:StoreVendorPrice(THREAD, 10)
		DB:StoreVendorPrice(ORE, 100)
		local total, priced, count, stale = Price.CraftCostForReagents({
			{ itemId = THREAD, need = 2 },
			{ itemId = ORE,    need = 3 },
		}, 4)
		assert.equal((10 * 2 + 100 * 3) * 4, total)
		assert.equal(2, priced)
		assert.equal(2, count)
		assert.is_false(stale)
	end)

	it("counts an unpriced reagent so the caller can flag a lower bound", function()
		DB:StoreVendorPrice(THREAD, 10)
		local total, priced, count = Price.CraftCostForReagents({
			{ itemId = THREAD, need = 1 },
			{ itemId = ORE,    need = 1 },
		})
		assert.equal(10, total)
		assert.equal(1, priced)
		assert.equal(2, count)
	end)

	it("leaves a soulbound reagent out of the completeness count", function()
		-- A BoP reagent has no market or vendor price by definition; counting it
		-- would permanently mark every recipe using one as under-priced.
		bindOnPickup(BOP)
		DB:StoreVendorPrice(THREAD, 10)
		local total, priced, count = Price.CraftCostForReagents({
			{ itemId = THREAD, need = 1 },
			{ itemId = BOP,    need = 1 },
		})
		assert.equal(10, total)
		assert.equal(1, priced)
		assert.equal(1, count)
	end)

	it("still adds a soulbound reagent's price when one exists", function()
		-- Excluded from the COUNT, not from the SUM: a BoP reagent someone did
		-- price (a scanned one, say) still costs what it costs.
		bindOnPickup(BOP)
		DB:StoreScannedPrice(BOP, 30)
		local total, priced, count = Price.CraftCostForReagents({ { itemId = BOP, need = 2 } })
		assert.equal(60, total)
		assert.equal(0, priced)
		assert.equal(0, count)
	end)

	it("flags a contributing price that has gone stale", function()
		env.serverTime = 1000
		DB:StoreScannedPrice(ORE, 100)
		env.serverTime = 1000 + 15 * 24 * 60 * 60
		local _, _, _, stale = Price.CraftCostForReagents({ { itemId = ORE, need = 1 } })
		assert.is_true(stale)
	end)

	it("skips malformed reagent rows", function()
		local total, _, count = Price.CraftCostForReagents({
			{ itemId = nil, need = 1 }, { itemId = ORE }, {},
		})
		assert.equal(0, total)
		assert.equal(0, count)
	end)

	it("returns zeroes for anything that isn't a reagent list", function()
		local total, priced, count, stale = Price.CraftCostForReagents("nope")
		assert.equal(0, total); assert.equal(0, priced)
		assert.equal(0, count); assert.is_false(stale)
	end)

	it("prices a recipe straight from LibProfessionDB", function()
		-- Real library, real shipped Vanilla Alchemy data. Minor Healing Potion
		-- (spell 2330) takes one Peacebloom (2447) and one Empty Vial (3371).
		local lib = assert(env.professionDB(), "sibling ProfessionDB install required")
		local reagents = lib:GetReagents(171, 2330)
		assert.is_true(reagents ~= nil)

		local n = 0
		for itemId, need in pairs(reagents) do
			n = n + 1
			DB:StoreVendorPrice(itemId, 10 * need)
		end
		local total, priced, count = Price.CraftCost(171, 2330, 3)

		local expected = 0
		for _, need in pairs(reagents) do expected = expected + (10 * need) * need * 3 end
		assert.equal(expected, total)
		assert.equal(n, priced)
		assert.equal(n, count)
	end)

	it("leaves a soulbound reagent out of a LibProfessionDB recipe's count too", function()
		local lib = assert(env.professionDB(), "sibling ProfessionDB install required")
		local reagents = lib:GetReagents(171, 2330)
		local first
		for itemId in pairs(reagents) do first = first or itemId end
		bindOnPickup(first)
		local _, _, count = Price.CraftCost(171, 2330, 1)
		local n = 0
		for _ in pairs(reagents) do n = n + 1 end
		assert.equal(n - 1, count)
	end)

	it("flags a stale scanned price in a LibProfessionDB recipe", function()
		local lib = assert(env.professionDB(), "sibling ProfessionDB install required")
		local reagents = lib:GetReagents(171, 2330)
		env.serverTime = 1000
		for itemId in pairs(reagents) do DB:StoreScannedPrice(itemId, 5) end
		env.serverTime = 1000 + 15 * 24 * 60 * 60
		local _, _, _, stale = Price.CraftCost(171, 2330, 1)
		assert.is_true(stale)
	end)

	it("returns zeroes for a recipe the library has never heard of", function()
		local total, priced, count, stale = Price.CraftCost(99999, 99999, 1)
		assert.equal(0, total); assert.equal(0, priced)
		assert.equal(0, count); assert.is_false(stale)
	end)

	it("defaults the quantity to one", function()
		DB:StoreVendorPrice(THREAD, 10)
		assert.equal(10, (Price.CraftCostForReagents({ { itemId = THREAD, need = 1 } })))
	end)
end)

-- Discord 2026-08-23: "togpm uses the auction house price for easy to obtain
-- vendor items like vials". Price.Get prefers the AH because it answers "what
-- is this worth"; a reagent's COST is what you pay to get one, and nobody pays
-- the AH for a vial a vendor stocks. The operator's directive: a vendor-sold
-- reagent is costed at the vendor price even when someone has listed it. This
-- is the policy the library deliberately does not carry, so it stays here.
describe("a vendor-sold reagent's cost", function()
	it("REPRODUCES the report through Price.Get: a listing outranks the vendor", function()
		DB:StoreVendorPrice(THREAD, 10)
		DB:StoreScannedPrice(THREAD, 500)
		assert.equal(500, (Price.Get(THREAD)))
	end)

	it("is the vendor price even when the same item is listed on the AH", function()
		DB:StoreVendorPrice(THREAD, 10)
		DB:StoreScannedPrice(THREAD, 500)
		local p, src, age = Price.GetReagentCost(THREAD)
		assert.equal(10, p)
		assert.equal("merchant", src)
		assert.is_nil(age)
	end)

	it("is the vendor price when an Auctionator listing exists too", function()
		DB:StoreVendorPrice(THREAD, 10)
		installAuctionator(900, nil)
		DB:SetPriceSetting("useAuctionator", true)
		assert.equal(10, (Price.GetReagentCost(THREAD)))
	end)

	it("falls through to the AH ladder for a reagent no vendor sells", function()
		DB:StoreScannedPrice(ORE, 500)
		local p, src = Price.GetReagentCost(ORE)
		assert.equal(500, p)
		assert.equal("scan", src)
	end)

	it("is nil for a reagent nobody prices, and for a non-number", function()
		assert.is_nil(Price.GetReagentCost(ORE))
		assert.is_nil(Price.GetReagentCost("x"))
	end)

	it("drives the crafting total: a listed vial does not inflate the cost", function()
		DB:StoreVendorPrice(THREAD, 10)        -- the "vial": vendor 10c, listed at 5g
		DB:StoreScannedPrice(THREAD, 50000)
		DB:StoreScannedPrice(ORE, 100)         -- a real AH reagent
		local total, priced, count, stale = Price.CraftCostForReagents({
			{ itemId = THREAD, need = 1 },
			{ itemId = ORE,    need = 2 },
		})
		assert.equal(10 + 200, total)
		assert.equal(2, priced); assert.equal(2, count)
		assert.is_false(stale)
	end)

	it("and a vendor price never reads as stale, however old the listing beside it", function()
		env.serverTime = 1000
		DB:StoreScannedPrice(THREAD, 500)
		DB:StoreVendorPrice(THREAD, 10)
		env.serverTime = 1000 + 30 * 24 * 60 * 60
		local _, _, _, stale = Price.CraftCostForReagents({ { itemId = THREAD, need = 1 } })
		assert.is_false(stale)
	end)

	it("drives Price.CraftCost the same way", function()
		local lib = assert(env.professionDB(), "sibling ProfessionDB install required")
		local reagents = lib:GetReagents(171, 2330)     -- Minor Healing Potion
		local vendorTotal = 0
		for itemId, need in pairs(reagents) do
			DB:StoreVendorPrice(itemId, 7)
			DB:StoreScannedPrice(itemId, 7000)
			vendorTotal = vendorTotal + 7 * need
		end
		assert.equal(vendorTotal, (Price.CraftCost(171, 2330, 1)))
	end)
end)

describe("Money", function()
	it("is the library's formatter when the library has one -- one rule, one copy", function()
		_G.GetCoinTextureString = function(c) return "COIN:" .. c end
		DB.FormatMoney = function(_, c) return "LIB:" .. c end
		assert.equal("LIB:1234", Price.Money(1234))
	end)

	it("uses the client's coin string when there is no price library", function()
		standIn(nil)
		_G.GetCoinTextureString = function(c) return "COIN:" .. c end
		assert.equal("COIN:1234", Price.Money(1234))
	end)

	it("falls back to plain text", function()
		standIn(nil)
		assert.equal("1g 23s 45c", Price.Money(12345))
	end)

	it("returns empty for a non-number", function()
		assert.equal("", Price.Money(nil))
		assert.equal("", Price.Money("lots"))
	end)
end)
