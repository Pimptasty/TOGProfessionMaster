-- The price provider: one accessor, several sources, a fixed priority order.
--
-- What matters here is the LADDER — which source wins, and that every optional
-- integration (Auctionator, Auctioneer, TSM) is feature-detected AND toggle-
-- gated, so a user who hasn't opted in never has their numbers silently come
-- from someone else's addon. Each bridge probes several call shapes because the
-- third-party APIs differ by branch; that probing must never let a bad return
-- (a string, a zero, an error) escape as a price.
--
-- Every external addon is absent by default in this env, exactly as it is for a
-- player who has none installed — a spec opts one in explicitly.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Price, Ace

local ORE   = 2770   -- Copper Ore
local BOP   = 12345  -- stands in for a soulbound reagent
local THREAD = 2320  -- Coarse Thread, a vendor staple

setup(function()
	ns    = env.initDb()
	Price = env.loadModule("Modules/Price.lua").Price
	Ace   = ns.lib
end)

before_each(function()
	env.install()
	-- No third-party pricing addons present.
	_G.Auctionator, _G.AucAdvanced, _G.TSM_API = nil, nil, nil
	_G.GetCoinTextureString = nil
	_G.GetItemInfo = function() return nil end

	-- Blank the persisted price stores and every source toggle.
	local fr = Ace.db.factionrealm
	fr.ahPrices, fr.vendorPrices = {}, {}
	local p = Ace.db.profile
	p.useAuctionator, p.useAuctionatorHistorical = nil, nil
	p.useAuctioneer, p.useAuctioneerCached = nil, nil
	p.useTSM, p.useTSMAppHelper = nil, nil
	p.useTOGPMAH = nil
	-- Tier 2c is LibItemDB as of 2026-08-07; TOGPM's own Data/VendorPrices.lua
	-- is deleted. `_itemDB` is cached on the addon for the session, so it has to
	-- be cleared per test or a stub leaks into later files.
	ns._itemDB = nil
end)

--- Make tier 2c answer through the REAL LibItemDB — the harness manifest
--- carries it, so `env.libs.load` gives us the code that ships.
---
--- NOT A HAND-WRITTEN STUB, deliberately. A stub of a library encodes the
--- author's ASSUMPTION about that library, so a test using one can only ever
--- confirm the assumption. That is not hypothetical here: the sibling
--- LibProfessionDB shim was specced against a stub returning the shape its
--- author expected, both agreed, both were wrong, and the seam raised
--- `bad argument #1 to 'next'` 112 times on one in-game draw.
---
--- Loaded through the library's own `LoadVendorPrices`, so this exercises its
--- real validation too (it rejects 0, negatives and non-numerics).
local function realVendorPrices(prices)
	-- forget-then-load: `libs.load` is a no-op once anything has loaded the
	-- library, and other specs swap fakes into LibStub, so a bare load() can
	-- hand back someone else's stub. Asserted rather than assumed, because a
	-- silent fallback to a stub is the failure this whole approach exists to
	-- stop.
	env.libs.forget("LibItemDB-1.0")
	env.libs.load("LibItemDB-1.0")
	local lib = assert(LibStub("LibItemDB-1.0", true),
		"the real LibItemDB did not load; refusing to test against a stub")
	lib.vendorPrice = {}
	lib:LoadVendorPrices(prices or {})
	ns._itemDB = lib
	return lib
end

-- Mark an item Bind-on-Pickup through the real GetItemInfo contract (bindType
-- is the 14th return).
local function bindOnPickup(itemId)
	_G.GetItemInfo = function(id)
		if id == itemId then
			return "Soulbound Thing", "|cffffffff|Hitem:" .. id .. "|h[x]|h|r",
			       1, 60, 60, "", "", 1, "", "", 0, 0, 0, 1
		end
		return nil
	end
end

describe("source presentation", function()
	it("labels and colours a known source from the shared tables", function()
		assert.equal(ns.PriceSourceLabels["togpm-ah"], Price.GetSourceLabel("togpm-ah"))
		assert.equal(ns.PriceSourceColors["togpm-ah"], Price.GetSourceColor("togpm-ah"))
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
		local out = Price.ColorizeSource("togpm-ah")
		assert.is_true(out:find(ns.PriceSourceColors["togpm-ah"], 1, true) ~= nil)
		assert.is_true(out:sub(-2) == "|r")
	end)
end)

describe("writers", function()
	it("persists a scanned auction price with a timestamp", function()
		env.serverTime = 5000
		Price.StoreAHPrice(ORE, 1234)
		assert.same({ p = 1234, at = 5000 }, Ace.db.factionrealm.ahPrices[ORE])
	end)

	it("persists a vendor price", function()
		Price.StoreVendorPrice(THREAD, 100)
		assert.equal(100, Ace.db.factionrealm.vendorPrices[THREAD])
	end)

	it("refuses junk rather than storing it", function()
		Price.StoreAHPrice(ORE, 0)
		Price.StoreAHPrice(ORE, -5)
		Price.StoreAHPrice(ORE, "free")
		Price.StoreAHPrice("ore", 100)
		Price.StoreVendorPrice(THREAD, 0)
		Price.StoreVendorPrice(THREAD, nil)
		assert.is_nil(Ace.db.factionrealm.ahPrices[ORE])
		assert.is_nil(Ace.db.factionrealm.vendorPrices[THREAD])
	end)
end)

describe("Price.Get", function()
	it("rejects a non-numeric item", function()
		assert.is_nil(Price.Get("2770"))
		assert.is_nil(Price.Get(nil))
	end)

	it("returns nothing when no source knows the item", function()
		assert.is_nil(Price.Get(ORE))
	end)

	it("returns our own scanned auction price, with its age", function()
		env.serverTime = 1000
		Price.StoreAHPrice(ORE, 500)
		env.serverTime = 1600
		local price, source, age = Price.Get(ORE)
		assert.equal(500, price)
		assert.equal("togpm-ah", source)
		assert.equal(600, age)
	end)

	it("honours the toggle that turns our own AH data off", function()
		Price.StoreAHPrice(ORE, 500)
		Ace.db.profile.useTOGPMAH = false
		assert.is_nil(Price.Get(ORE))
	end)

	it("treats an unset TOGPM-AH toggle as ON for existing installs", function()
		Ace.db.profile.useTOGPMAH = nil
		Price.StoreAHPrice(ORE, 500)
		assert.equal(500, (Price.Get(ORE)))
	end)

	it("prefers a captured vendor price over the library's base price", function()
		-- The correctness argument for the tier order: LibItemDB ships the
		-- Neutral BASE price, while our MERCHANT_SHOW capture recorded what this
		-- character was actually charged, discount included.
		realVendorPrices({ [THREAD] = 999 })
		Price.StoreVendorPrice(THREAD, 100)
		local price, source = Price.Get(THREAD)
		assert.equal(100, price)
		assert.equal("togpm-vendor", source)
	end)

	it("falls back to the library's base price last", function()
		realVendorPrices({ [THREAD] = 999 })
		local price, source = Price.Get(THREAD)
		assert.equal(999, price)
		assert.equal("vendor-static", source)
	end)

	it("prefers the auction house over any vendor price", function()
		realVendorPrices({ [THREAD] = 999 })
		Price.StoreVendorPrice(THREAD, 100)
		Price.StoreAHPrice(THREAD, 50)
		assert.equal("togpm-ah", select(2, Price.Get(THREAD)))
	end)
end)

describe("Auctionator bridge", function()
	local function installAuctionator(auction, vendor, historical)
		_G.Auctionator = { API = { v1 = {
			GetAuctionPriceByItemID = function() return auction end,
			GetVendorPriceByItemID  = function() return vendor end,
			GetHistoricalPriceByItemID = historical and function() return historical end or nil,
		} } }
	end

	it("is ignored entirely until the user opts in", function()
		installAuctionator(777)
		Price.StoreAHPrice(ORE, 500)
		assert.equal("togpm-ah", select(2, Price.Get(ORE)))
	end)

	it("wins over our own scan once enabled", function()
		Ace.db.profile.useAuctionator = true
		installAuctionator(777)
		Price.StoreAHPrice(ORE, 500)
		local price, source = Price.Get(ORE)
		assert.equal(777, price)
		assert.equal("auctionator", source)
	end)

	it("falls through when Auctionator has no price for the item", function()
		Ace.db.profile.useAuctionator = true
		installAuctionator(nil)
		Price.StoreAHPrice(ORE, 500)
		assert.equal("togpm-ah", select(2, Price.Get(ORE)))
	end)

	it("ignores a zero, a negative, or a non-number from the API", function()
		Ace.db.profile.useAuctionator = true
		for _, bad in ipairs({ 0, -1, "lots" }) do
			installAuctionator(bad)
			assert.is_nil(Price.Get(ORE))
		end
	end)

	it("survives the API throwing", function()
		Ace.db.profile.useAuctionator = true
		_G.Auctionator = { API = { v1 = {
			GetAuctionPriceByItemID = function() error("boom") end,
		} } }
		assert.is_nil(Price.Get(ORE))
	end)

	it("uses the historical API when there is no live price", function()
		Ace.db.profile.useAuctionator = true
		installAuctionator(nil, nil, 321)
		local price, source = Price.Get(ORE)
		assert.equal(321, price)
		assert.equal("auctionator-history", source)
	end)

	it("can have historical turned off on its own", function()
		Ace.db.profile.useAuctionator = true
		Ace.db.profile.useAuctionatorHistorical = false
		installAuctionator(nil, nil, 321)
		assert.is_nil(Price.Get(ORE))
	end)

	it("supplies a vendor price when the auction house has none", function()
		Ace.db.profile.useAuctionator = true
		installAuctionator(nil, 42)
		local price, source = Price.Get(THREAD)
		assert.equal(42, price)
		assert.equal("auctionator-vendor", source)
	end)

	it("is inert when the addon is half-loaded", function()
		Ace.db.profile.useAuctionator = true
		_G.Auctionator = { API = {} }
		assert.is_nil(Price.Get(ORE))
	end)
end)

describe("TSM bridge", function()
	it("stays out of the way until enabled", function()
		_G.TSM_API = { GetCustomPriceValue = function() return 900 end }
		Price.StoreAHPrice(ORE, 500)
		assert.equal("togpm-ah", select(2, Price.Get(ORE)))
	end)

	it("reports a realm-live expression as live", function()
		Ace.db.profile.useTSM = true
		_G.TSM_API = { GetCustomPriceValue = function(expr)
			if expr == "DBMinBuyout" then return 900 end
		end }
		local price, source = Price.Get(ORE)
		assert.equal(900, price)
		assert.equal("tsm-live", source)
	end)

	it("reports a region/App expression as history", function()
		Ace.db.profile.useTSM = true
		_G.TSM_API = { GetCustomPriceValue = function(expr)
			if expr == "DBRegionMarketAvg" then return 850 end
		end }
		assert.equal("tsm-history", select(2, Price.Get(ORE)))
	end)

	it("can be driven by the AppHelper toggle alone", function()
		Ace.db.profile.useTSMAppHelper = true
		_G.TSM_API = { GetCustomPriceValue = function() return 800 end }
		assert.equal(800, (Price.Get(ORE)))
	end)

	it("tolerates the argument order differing between TSM builds", function()
		Ace.db.profile.useTSM = true
		_G.TSM_API = { GetCustomPriceValue = function(a, b)
			-- This build takes (itemString, expr).
			if a == "i:" .. ORE and b == "DBMinBuyout" then return 700 end
		end }
		assert.equal(700, (Price.Get(ORE)))
	end)
end)

describe("Auctioneer bridge", function()
	it("stays out of the way until enabled", function()
		_G.AucAdvanced = { API = { GetMarketValue = function() return 600 end } }
		Price.StoreAHPrice(ORE, 500)
		assert.equal("togpm-ah", select(2, Price.Get(ORE)))
	end)

	it("returns a market value, rounded to whole copper", function()
		Ace.db.profile.useAuctioneer = true
		_G.AucAdvanced = { API = { GetMarketValue = function() return 600.6 end } }
		local price, source = Price.Get(ORE)
		assert.equal(601, price)
		assert.equal("auctioneer-live", source)
	end)

	it("takes the first numeric of a multi-return", function()
		Ace.db.profile.useAuctioneer = true
		_G.AucAdvanced = { API = { GetMarketValue = function() return nil, 0, 55 end } }
		assert.equal(55, (Price.Get(ORE)))
	end)

	it("reads cached values through a stat module when the API path is empty", function()
		Ace.db.profile.useAuctioneer = true
		_G.AucAdvanced = {
			API = { GetMarketValue = function() return nil end },
			GetAllModules = function()
				return { { GetPriceArray = function() return { price = 250, seen = 3 } end } }
			end,
		}
		local price, source = Price.Get(ORE)
		assert.equal(250, price)
		assert.equal("auctioneer-cached", source)
	end)

	it("prefers the stat module with the most observations", function()
		Ace.db.profile.useAuctioneer = true
		_G.AucAdvanced = {
			API = { GetMarketValue = function() return nil end },
			GetAllModules = function()
				return {
					{ GetPriceArray = function() return { price = 100, seen = 1 } end },
					{ GetPriceArray = function() return { price = 300, seen = 9 } end },
				}
			end,
		}
		assert.equal(300, (Price.Get(ORE)))
	end)

	it("reads cached values through GetAlgorithmValue when that API exists", function()
		Ace.db.profile.useAuctioneer = true
		_G.AucAdvanced = {
			API = {
				GetMarketValue = function() return nil end,
				-- This build takes (link, engine) and only answers for one engine.
				GetAlgorithmValue = function(a, b)
					if a:find("^item:") and b == "stat_histogram" then return 175 end
				end,
			},
		}
		local price, source = Price.Get(ORE)
		assert.equal(175, price)
		assert.equal("auctioneer-cached", source)
	end)

	it("ignores a non-numeric answer from the algorithm API", function()
		Ace.db.profile.useAuctioneer = true
		_G.AucAdvanced = {
			API = {
				GetMarketValue    = function() return nil end,
				GetAlgorithmValue = function() return "not a price" end,
			},
		}
		assert.is_nil(Price.Get(ORE))
	end)

	it("can have the cached tier turned off on its own", function()
		Ace.db.profile.useAuctioneer = true
		Ace.db.profile.useAuctioneerCached = false
		_G.AucAdvanced = {
			API = { GetMarketValue = function() return nil end },
			GetAllModules = function()
				return { { GetPriceArray = function() return { price = 250 } end } }
			end,
		}
		assert.is_nil(Price.Get(ORE))
	end)

	it("reports its readiness for the diagnostic command", function()
		Ace.db.profile.useAuctioneer = true
		_G.AucAdvanced = {
			API = { GetMarketValue = function() return 42 end },
			Resources = { ServerKey = "Testrealm-Horde" },
		}
		local d = Price.GetAuctioneerDiagnostics(ORE)
		assert.is_true(d.useAuctioneer)
		assert.is_true(d.ready)
		assert.is_false(d.hasAlgorithmAPI)
		assert.equal("Testrealm-Horde", d.serverKey)
		assert.equal(42, d.live)
	end)

	it("reports not-ready when the addon is absent", function()
		local d = Price.GetAuctioneerDiagnostics(ORE)
		assert.is_false(d.ready)
		assert.is_nil(d.live)
	end)
end)

describe("sale prices", function()
	it("GetSaleLive prefers live sources and reports our scan's age", function()
		env.serverTime = 1000
		Price.StoreAHPrice(ORE, 400)
		env.serverTime = 1100
		local price, source, age = Price.GetSaleLive(ORE)
		assert.equal(400, price)
		assert.equal("togpm-ah", source)
		assert.equal(100, age)
	end)

	it("GetSaleLive never falls back to a vendor price", function()
		realVendorPrices({ [THREAD] = 999 })
		assert.is_nil(Price.GetSaleLive(THREAD))
	end)

	it("GetSaleHistorical uses history sources only", function()
		Ace.db.profile.useTSM = true
		_G.TSM_API = { GetCustomPriceValue = function(expr)
			if expr == "DBMarket" then return 777 end
		end }
		local price, source = Price.GetSaleHistorical(ORE)
		assert.equal(777, price)
		assert.equal("tsm-history", source)
	end)

	it("GetSaleHistorical returns nothing when no history source knows the item", function()
		assert.is_nil(Price.GetSaleHistorical(ORE))
	end)

	it("both reject a non-numeric item", function()
		assert.is_nil(Price.GetSaleLive("x"))
		assert.is_nil(Price.GetSaleHistorical("x"))
	end)
end)

describe("craft cost", function()
	it("sums priced reagents across the quantity", function()
		Price.StoreVendorPrice(THREAD, 10)
		Price.StoreVendorPrice(ORE, 100)
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
		Price.StoreVendorPrice(THREAD, 10)
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
		Price.StoreVendorPrice(THREAD, 10)
		local total, priced, count = Price.CraftCostForReagents({
			{ itemId = THREAD, need = 1 },
			{ itemId = BOP,    need = 1 },
		})
		assert.equal(10, total)
		assert.equal(1, priced)
		assert.equal(1, count)
	end)

	it("flags a contributing price that has gone stale", function()
		env.serverTime = 1000
		Price.StoreAHPrice(ORE, 100)
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
			Price.StoreVendorPrice(itemId, 10 * need)
		end
		local total, priced, count = Price.CraftCost(171, 2330, 3)

		local expected = 0
		for _, need in pairs(reagents) do expected = expected + (10 * need) * need * 3 end
		assert.equal(expected, total)
		assert.equal(n, priced)
		assert.equal(n, count)
	end)

	it("returns zeroes for a recipe the library has never heard of", function()
		local total, priced, count, stale = Price.CraftCost(99999, 99999, 1)
		assert.equal(0, total); assert.equal(0, priced)
		assert.equal(0, count); assert.is_false(stale)
	end)
end)

describe("Money", function()
	it("uses the client's coin string when there is one", function()
		_G.GetCoinTextureString = function(c) return "COIN:" .. c end
		assert.equal("COIN:1234", Price.Money(1234))
	end)

	it("falls back to plain text", function()
		assert.equal("1g 23s 45c", Price.Money(12345))
	end)

	it("returns empty for a non-number", function()
		assert.equal("", Price.Money(nil))
		assert.equal("", Price.Money("lots"))
	end)
end)

describe("merchant capture", function()
	it("caches unlimited-stock wares at their per-item price", function()
		_G.GetMerchantNumItems = function() return 2 end
		_G.GetMerchantItemInfo = function(i)
			if i == 1 then return "Coarse Thread", nil, 500, 5, -1 end
			return "Limited Recipe", nil, 10000, 1, 3   -- finite stock: skipped
		end
		_G.GetMerchantItemLink = function(i)
			return "|cffffffff|Hitem:" .. (i == 1 and THREAD or 4567) .. "|h[x]|h|r"
		end
		ns.callbacks:Fire("__no_such_event__")   -- keep the bus warm; harmless
		-- Drive the real MERCHANT_SHOW registration through AceEvent's frame.
		local AceEvent = LibStub("AceEvent-3.0")
		AceEvent.frame:Fire("OnEvent", "MERCHANT_SHOW")
		assert.equal(100, Ace.db.factionrealm.vendorPrices[THREAD])
		assert.is_nil(Ace.db.factionrealm.vendorPrices[4567])
	end)
end)

describe("AH scan results", function()
	it("persists every lowest buyout the scanner reports", function()
		ns.callbacks:Fire("AH_SCAN_COMPLETE", { [ORE] = { lowestBuyout = 321 } })
		assert.equal(321, Ace.db.factionrealm.ahPrices[ORE].p)
	end)

	it("ignores a malformed result set", function()
		ns.callbacks:Fire("AH_SCAN_COMPLETE", "nope")
		ns.callbacks:Fire("AH_SCAN_COMPLETE", { [ORE] = {} })
		assert.is_nil(Ace.db.factionrealm.ahPrices[ORE])
	end)
end)

describe("vendor base price from LibItemDB", function()
	-- Tier 2c IS LibItemDB now. TOGPM's own Data/VendorPrices.lua was deleted on
	-- 2026-08-07 when `GetVendorBasePrice` landed at MINOR 21 (ItemDB's
	-- docs/DEPENDENCY_CONTRACTS.md §7), so there is no local table behind this
	-- any more and no fallthrough to test — that was the point of the move.
	local VIAL = 3371

	--- A hand-made object, used ONLY where the real library cannot be made to
	--- do the thing under test — a method that raises, or a build old enough to
	--- lack the API. Those cases test OUR defensive wrapper, not the
	--- integration, and that distinction is why they are allowed a fake while
	--- every shape/behaviour case above uses the real library.
	local function brokenItemDB(stub)
		ns._itemDB = stub or false
	end

	before_each(function() ns._itemDB = nil end)
	after_each(function() ns._itemDB = nil end)

	it("uses the library's price when it answers", function()
		realVendorPrices({ [VIAL] = 25 })
		local price, source = ns.Price.Get(VIAL)
		assert.equal(25, price)
		assert.equal("vendor-static", source)
	end)

	it("keeps the source key, so no new label is needed downstream", function()
		-- "vendor-static" has a display name, a colour and a CraftingTab
		-- abbreviation. Introducing a fourth vendor key would need all three and
		-- would tell the player nothing extra.
		realVendorPrices({ [VIAL] = 999 })
		assert.equal("vendor-static", select(2, ns.Price.Get(VIAL)))
	end)

	it("answers nothing for an item with no vendor record", function()
		-- `nil` means "no vendor RECORD", not "no vendor sells this" — ItemDB
		-- retracted the stronger claim on 2026-08-07 (their
		-- docs/DEPENDENCY_CONTRACTS.md §7), because the vendor gate comes from
		-- Wrath/Cata dumps that cannot see a Vanilla-only vendor. Omitting the
		-- price is right; asserting "no vendor sells this" from it would not be.
		realVendorPrices({})
		assert.is_nil(ns.Price.Get(VIAL))
	end)

	it("ignores a zero price, because the library refuses to store one", function()
		-- Driven through the real LoadVendorPrices, which rejects 0 and
		-- negatives outright — so this asserts the two layers agree rather than
		-- asserting our guard against an imagined input.
		realVendorPrices({ [VIAL] = 0, [4306] = -5 })
		assert.is_nil(ns.Price.Get(VIAL))
		assert.is_nil(ns.Price.Get(4306))
	end)

	it("still ranks BELOW the live vendor sources, which know the player's discount", function()
		-- The tier order is the correctness argument: the library ships the
		-- Neutral BASE price, while TOGPM's own MERCHANT_SHOW capture recorded
		-- what this player was actually charged. Promoting 2c above 2b would
		-- quietly overwrite a real observed price with a worse estimate.
		realVendorPrices({ [VIAL] = 25 })
		ns.Price.StoreVendorPrice(VIAL, 20)
		local price, source = ns.Price.Get(VIAL)
		assert.equal(20, price)
		assert.equal("togpm-vendor", source)
	end)

	it("degrades quietly against a LibItemDB that predates the API", function()
		-- The whole tier goes silent rather than erroring. Correct for a
		-- last-resort source, and the reason the detection is on the METHOD
		-- rather than on a MINOR. The installed library HAS the method, so this
		-- is one of the cases that genuinely needs a stand-in.
		brokenItemDB({ GetLink = function() end })
		assert.is_nil(ns.Price.Get(VIAL))
	end)

	it("degrades quietly when ItemDB is not installed at all", function()
		brokenItemDB(nil)
		assert.is_nil(ns.Price.Get(VIAL))
	end)

	it("survives the library raising, rather than taking the tooltip down", function()
		-- A cross-addon call on a surface this addon does not own. The real
		-- library cannot be made to throw here, so this one is a stand-in too.
		brokenItemDB({ GetVendorBasePrice = function() error("boom") end })
		assert.is_nil(ns.Price.Get(VIAL))
	end)
end)
