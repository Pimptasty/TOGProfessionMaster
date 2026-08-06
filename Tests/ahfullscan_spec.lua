-- Modules/AHScanner.lua — the full scan that builds the local price DB.
--
-- Every cost-to-craft figure in the addon comes from here, and the arithmetic
-- has one property that makes it dangerous: it is wrong SILENTLY and by a
-- plausible-looking factor. An auction is a stack, so the price that matters is
-- `ceil(buyout / count)`. Forget the division and a stack of 20 prices the item
-- at twenty times its worth — every craft in the Profit Planner then looks like
-- a loss, and nothing errors.
--
-- The corollary is the case worth stating out loud: **the cheapest listing is
-- not the cheapest item.** A single bar at 60 is dearer per unit than a stack
-- of 20 at 1000, and a scanner that compares raw buyouts picks the wrong one.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, AH, saved, stored

local THORIUM, FELCLOTH = 12359, 14256

setup(function()
	ns = env.initDb()
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/AHScanner.lua")
	AH = ns.AH
end)

--- Feed the legacy auction list. Each listing is { itemId, buyout, count }.
local function listings(rows)
	_G.GetNumAuctionItems = function() return #rows end
	_G.GetAuctionItemInfo = function(_which, i)
		local r = rows[i]
		if not r then return nil end
		-- Positional, as the client returns it: count is 3, buyout 10, id 17.
		local out = {}
		out[3], out[10], out[17] = r.count, r.buyout, r.itemId
		return unpack(out, 1, 17)
	end
end

before_each(function()
	env.installFrames()
	env.resetDb()

	saved = {
		GetNumAuctionItems = _G.GetNumAuctionItems,
		GetAuctionItemInfo = _G.GetAuctionItemInfo,
		FrameUtil          = _G.FrameUtil,
		Print              = ns.Print,
		Debug              = ns.DebugPrint,
		StoreAHPrice       = ns.Price and ns.Price.StoreAHPrice,
		UpdateScanButton   = AH.UpdateScanButtonState,
	}
	ns.Print       = function() end
	ns.DebugPrint  = function() end
	AH.UpdateScanButtonState = function() end
	-- FrameUtil comes from the harness now (delivered 2026-08-05).

	stored = {}
	ns.Price = ns.Price or {}
	ns.Price.StoreAHPrice = function(itemId, price) stored[itemId] = price end

	AH._fullSeen     = nil
	AH._fullScanning = true
	listings({})
end)

after_each(function()
	_G.GetNumAuctionItems = saved.GetNumAuctionItems
	_G.GetAuctionItemInfo = saved.GetAuctionItemInfo
	_G.FrameUtil          = saved.FrameUtil
	ns.Print              = saved.Print
	ns.DebugPrint         = saved.Debug
	AH.UpdateScanButtonState = saved.UpdateScanButton
	if saved.StoreAHPrice then ns.Price.StoreAHPrice = saved.StoreAHPrice end
	AH._fullScanning = false
end)

local function scan(rows)
	listings(rows)
	AH._fullScanning = true
	AH._fullProcessLegacy()
	return AH._fullSeen or {}
end

describe("full scan — price per item, not per auction", function()
	it("divides a stack's buyout by its size", function()
		-- 20 bars for 1000 is 50 a bar. This single division is the difference
		-- between a usable price DB and one that is wrong by the stack size.
		local seen = scan({ { itemId = THORIUM, buyout = 1000, count = 20 } })
		assert.equal(50, seen[THORIUM].lowestBuyout)
	end)

	it("rounds a part-copper unit price up", function()
		-- 1000 across 3 is 333.33; rounding down would undercut the real cost.
		local seen = scan({ { itemId = THORIUM, buyout = 1000, count = 3 } })
		assert.equal(334, seen[THORIUM].lowestBuyout)
	end)

	it("prices a single item at its buyout", function()
		local seen = scan({ { itemId = THORIUM, buyout = 750, count = 1 } })
		assert.equal(750, seen[THORIUM].lowestBuyout)
	end)

	it("picks the cheapest UNIT, not the cheapest listing", function()
		-- The whole point. The 60 listing is the cheaper auction and the dearer
		-- bar; a scanner comparing raw buyouts stores 60 and every craft using
		-- Thorium is then mispriced.
		local seen = scan({
			{ itemId = THORIUM, buyout = 60,   count = 1  },   -- 60 a bar
			{ itemId = THORIUM, buyout = 1000, count = 20 },   -- 50 a bar
		})
		assert.equal(50, seen[THORIUM].lowestBuyout)
	end)

	it("keeps items apart", function()
		local seen = scan({
			{ itemId = THORIUM,  buyout = 1000, count = 20 },
			{ itemId = FELCLOTH, buyout = 300,  count = 2  },
		})
		assert.equal(50,  seen[THORIUM].lowestBuyout)
		assert.equal(150, seen[FELCLOTH].lowestBuyout)
	end)

	it("counts how many listings it saw for an item", function()
		local seen = scan({
			{ itemId = THORIUM, buyout = 1000, count = 20 },
			{ itemId = THORIUM, buyout = 900,  count = 20 },
			{ itemId = THORIUM, buyout = 800,  count = 20 },
		})
		assert.equal(3, seen[THORIUM].count)
	end)
end)

describe("full scan — listings it must ignore", function()
	it("skips a bid-only auction", function()
		-- buyoutPrice 0 means "no buyout"; treated as a price it would report
		-- the item as free and poison every craft that uses it.
		local seen = scan({
			{ itemId = THORIUM, buyout = 0,   count = 20 },
			{ itemId = THORIUM, buyout = 400, count = 20 },
		})
		assert.equal(20, seen[THORIUM].lowestBuyout)
		assert.equal(1, seen[THORIUM].count)
	end)

	it("records nothing for an item that is only ever bid-only", function()
		local seen = scan({ { itemId = THORIUM, buyout = 0, count = 5 } })
		assert.is_nil(seen[THORIUM])
	end)

	it("skips a listing with no item id", function()
		local seen = scan({ { itemId = nil, buyout = 500, count = 1 } })
		assert.same({}, seen)
	end)

	it("skips a listing claiming a stack of zero", function()
		-- Would divide by zero and store inf.
		local seen = scan({ { itemId = THORIUM, buyout = 500, count = 0 } })
		assert.is_nil(seen[THORIUM])
	end)

	it("handles an empty auction list", function()
		assert.same({}, scan({}))
	end)
end)

-- The Cata / MoP path. Same arithmetic, different API — and that API is
-- **0-indexed** while the loop is 1-based. This addon ships to Cata and MoP as
-- well as Classic Era, so the branch a Classic Era player never runs still has
-- to be right, and it is the one nobody would notice breaking.
describe("full scan — the modern (Cata/MoP) auction API", function()
	--- Feed C_AuctionHouse's replicate list. Deliberately indexed from ZERO, as
	--- the real API is: a spec that mirrored the 1-based loop would agree with
	--- an off-by-one instead of catching it.
	local function replicate(rows)
		_G.C_AuctionHouse = {
			GetNumReplicateItems = function() return #rows end,
			GetReplicateItemInfo = function(i)
				local r = rows[i + 1]
				if not r then return nil end
				local out = {}
				out[3], out[10], out[17] = r.count, r.buyout, r.itemId
				return unpack(out, 1, 17)
			end,
		}
	end

	local savedAH
	before_each(function() savedAH = _G.C_AuctionHouse end)
	after_each(function() _G.C_AuctionHouse = savedAH end)

	local function scanModern(rows)
		replicate(rows)
		AH._fullSeen     = nil
		AH._fullScanning = true
		AH._fullProcessModern()
		return AH._fullSeen or {}
	end

	it("reads the very first listing, which lives at index zero", function()
		-- Drop the `- 1` and this item disappears from every scan while the
		-- rest of the DB looks perfectly healthy.
		local seen = scanModern({ { itemId = THORIUM, buyout = 500, count = 1 } })
		assert.is_truthy(seen[THORIUM])
		assert.equal(500, seen[THORIUM].lowestBuyout)
	end)

	it("reads every listing exactly once", function()
		local seen = scanModern({
			{ itemId = THORIUM, buyout = 500, count = 1 },
			{ itemId = THORIUM, buyout = 400, count = 1 },
			{ itemId = THORIUM, buyout = 300, count = 1 },
		})
		assert.equal(3, seen[THORIUM].count)
		assert.equal(300, seen[THORIUM].lowestBuyout)
	end)

	it("prices a stack per unit, as the legacy path does", function()
		local seen = scanModern({ { itemId = THORIUM, buyout = 1000, count = 20 } })
		assert.equal(50, seen[THORIUM].lowestBuyout)
	end)

	it("skips a bid-only auction here too", function()
		local seen = scanModern({ { itemId = THORIUM, buyout = 0, count = 5 } })
		assert.is_nil(seen[THORIUM])
	end)

	it("handles an empty replicate list", function()
		assert.same({}, scanModern({}))
	end)
end)

describe("full scan — what reaches the price DB", function()
	it("stores the lowest unit price for each item", function()
		scan({
			{ itemId = THORIUM,  buyout = 1000, count = 20 },
			{ itemId = THORIUM,  buyout = 60,   count = 1  },
			{ itemId = FELCLOTH, buyout = 300,  count = 2  },
		})
		assert.equal(50,  stored[THORIUM])
		assert.equal(150, stored[FELCLOTH])
	end)

	it("stores nothing for an item with no buyable listing", function()
		scan({ { itemId = THORIUM, buyout = 0, count = 5 } })
		assert.is_nil(stored[THORIUM])
	end)

	it("clears the scanning flags when it finishes", function()
		scan({ { itemId = THORIUM, buyout = 100, count = 1 } })
		assert.is_false(AH.IsFullScanning())
	end)

	it("keeps the scan results for the rest of the session", function()
		-- GetListingsFor falls back to them, which is what lights up the [AH]
		-- buttons on every tab without a second targeted scan.
		scan({ { itemId = THORIUM, buyout = 100, count = 1 } })
		assert.is_truthy(AH._fullSeen[THORIUM])
	end)
end)
