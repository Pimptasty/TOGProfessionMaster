-- Modules/AHScanner.lua — the parts that decide what gets scanned and what
-- price comes out of it.
--
-- The scan machinery itself needs an auction house; these do not. What is
-- covered here is the queue the scan is built from (which has already crashed
-- once in the field), the guards that refuse to start, and the lowest-buyout
-- selection that every cost-to-craft figure in the addon rests on.
--
-- A wrong lowest-buyout is invisible: it produces a plausible number that is
-- simply not the cheapest listing, and nobody notices until they undercut
-- themselves. That is the case for testing it rather than eyeballing it.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, AH, saved

local THORIUM, FELCLOTH = 12359, 14256

setup(function()
	ns = env.initDb()
	env.loadModule("Modules/AHScanner.lua")
	AH = ns.AH
end)

before_each(function()
	env.installFrames()
	env.resetDb()

	saved = {
		IsOpen    = AH.IsOpen,
		_scanNext = AH._scanNext,
		Print     = ns.Print,
		Debug     = ns.DebugPrint,
	}
	ns.Print      = function() end
	ns.DebugPrint = function() end
	AH.IsOpen     = function() return true end
	-- The query step needs a live auction house. What is under test here is the
	-- queue StartScan builds before it, so stop at that boundary.
	AH._scanNext  = function() end

	AH.CancelScan()
	AH.ClearResults()
	AH._isScanning   = false
	AH._fullScanning = false
	AH._currentItem  = nil
	AH._scannedItems = 0
end)

after_each(function()
	AH.IsOpen    = saved.IsOpen
	AH._scanNext = saved._scanNext
	ns.Print     = saved.Print
	ns.DebugPrint = saved.Debug
	AH._isScanning = false
end)

describe("GetEffectiveScanDelay", function()
	it("uses this client's default when nothing is configured", function()
		ns.lib.db.profile.ahScanDelay = nil
		-- Classic Era's server throttle is the loose one.
		assert.equal(1.5, AH.GetEffectiveScanDelay())
	end)

	it("honours a configured delay", function()
		ns.lib.db.profile.ahScanDelay = 4
		assert.equal(4, AH.GetEffectiveScanDelay())
	end)

	it("ignores a zero or negative delay rather than hammering the server", function()
		-- A 0 here would mean no gap between queries at all, which is how you
		-- get disconnected.
		ns.lib.db.profile.ahScanDelay = 0
		assert.equal(1.5, AH.GetEffectiveScanDelay())
		ns.lib.db.profile.ahScanDelay = -5
		assert.equal(1.5, AH.GetEffectiveScanDelay())
	end)

	it("ignores a non-numeric delay", function()
		ns.lib.db.profile.ahScanDelay = "fast"
		assert.equal(1.5, AH.GetEffectiveScanDelay())
	end)
end)

describe("StartScan — when it refuses", function()
	it("refuses with the auction house closed", function()
		AH.IsOpen = function() return false end
		local ok, why = AH.StartScan({ { itemId = THORIUM, itemName = "Thorium Bar" } })
		assert.is_false(ok)
		assert.equal("ah-closed", why)
	end)

	it("refuses an empty list", function()
		local ok, why = AH.StartScan({})
		assert.is_false(ok)
		assert.equal("no-items", why)
	end)

	it("refuses something that is not a list at all", function()
		local ok, why = AH.StartScan(nil)
		assert.is_false(ok)
		assert.equal("no-items", why)
	end)

	it("refuses while a scan is already running", function()
		AH._isScanning = true
		local ok, why = AH.StartScan({ { itemId = THORIUM, itemName = "Thorium Bar" } })
		assert.is_false(ok)
		assert.equal("scan-in-progress", why)
	end)

	it("refuses while a full scan is running", function()
		AH._fullScanning = true
		local ok, why = AH.StartScan({ { itemId = THORIUM, itemName = "Thorium Bar" } })
		assert.is_false(ok)
		assert.equal("full-scan-in-progress", why)
	end)

	it("clears the scanning flag when every item was unusable", function()
		-- Otherwise the addon believes a scan is running forever and every later
		-- StartScan returns "scan-in-progress" for the rest of the session.
		local ok, why = AH.StartScan({ { itemId = THORIUM, itemName = 12359 } })
		assert.is_false(ok)
		assert.equal("no-items", why)
		assert.is_false(AH.IsScanning())
	end)
end)

describe("StartFullScan — every way it refuses", function()
	-- This function had NO test of any kind, so none of its four refusals had
	-- ever executed. Found by applying the harness's review check "which of this
	-- function's early returns has a test ever taken?" — coverage cannot answer
	-- it, because a refusal line is evaluated on every run whichever way it goes.
	--
	-- It matters more than the count suggests: the throttle refusals are the ones
	-- standing between this addon and firing `getAll` more than once per 15
	-- minutes, which is a server-side rate limit, not a local nicety.

	before_each(function()
		AH._fullScanning   = false
		AH._isScanning     = false
		AH._lastFullScanAt = nil
	end)

	it("refuses while a full scan is already running", function()
		AH._fullScanning = true
		local ok, why = AH.StartFullScan()
		assert.is_false(ok)
		assert.equal("busy", why)
	end)

	it("refuses while a TARGETED scan is running", function()
		-- Same reason, different flag. Both are checked on one line, so a test
		-- taking only the first leaves the second unproven.
		AH._isScanning = true
		local ok, why = AH.StartFullScan()
		assert.is_false(ok)
		assert.equal("busy", why)
	end)

	it("refuses with the auction house closed", function()
		AH.IsOpen = function() return false end
		local ok, why = AH.StartFullScan()
		assert.is_false(ok)
		assert.equal("ah-closed", why)
	end)

	it("refuses on a modern client with no ReplicateItems", function()
		AH._isModernAH = true
		local savedAH = _G.C_AuctionHouse
		_G.C_AuctionHouse = nil
		local ok, why = AH.StartFullScan()
		_G.C_AuctionHouse = savedAH
		AH._isModernAH = false
		assert.is_false(ok)
		assert.equal("no-api", why)
	end)

	it("throttles a modern rescan inside the 15-minute window", function()
		AH._isModernAH = true
		local fired = false
		local savedAH = _G.C_AuctionHouse
		_G.C_AuctionHouse = { ReplicateItems = function() fired = true end }
		AH._lastFullScanAt = ((_G.GetServerTime and _G.GetServerTime()) or os.time()) - 60

		local ok, why = AH.StartFullScan(true)

		_G.C_AuctionHouse = savedAH
		AH._isModernAH = false
		assert.is_false(ok)
		assert.equal("throttled", why)
		-- The point of the refusal: it must not reach the API.
		assert.is_false(fired)
	end)

	it("throttles the legacy path when the server says getAll is on cooldown", function()
		-- `CanSendAuctionQuery`'s SECOND return is "can do a getAll right now".
		-- Reading the first by mistake would send a getAll the server refuses.
		local savedCanSend = _G.CanSendAuctionQuery
		_G.CanSendAuctionQuery = function() return true, false end
		local queried = false
		local savedQuery = _G.QueryAuctionItems
		_G.QueryAuctionItems = function() queried = true end

		local ok, why = AH.StartFullScan(true)

		_G.CanSendAuctionQuery = savedCanSend
		_G.QueryAuctionItems   = savedQuery
		assert.is_false(ok)
		assert.equal("throttled", why)
		assert.is_false(queried)
		-- and it did not leave the addon believing a scan is in flight
		assert.is_false(AH.IsFullScanning())
	end)
end)

describe("StartScan — building the queue", function()
	local function queueAfter(items)
		AH.StartScan(items)
		local out = {}
		for _, q in ipairs(AH._queue) do out[#out + 1] = q.itemId end
		return out
	end

	it("queues the items it was given", function()
		assert.same({ THORIUM, FELCLOTH }, queueAfter({
			{ itemId = THORIUM,  itemName = "Thorium Bar" },
			{ itemId = FELCLOTH, itemName = "Felcloth" },
		}))
	end)

	it("skips an item whose name arrived as a NUMBER", function()
		-- This shipped: a call site passed GetItemInfoInstant's first return,
		-- which is the item id, and the scanner died on the first :lower().
		assert.same({ FELCLOTH }, queueAfter({
			{ itemId = THORIUM,  itemName = 12359 },
			{ itemId = FELCLOTH, itemName = "Felcloth" },
		}))
	end)

	it("skips an empty name, which queries nothing useful", function()
		assert.same({ FELCLOTH }, queueAfter({
			{ itemId = THORIUM,  itemName = "" },
			{ itemId = FELCLOTH, itemName = "Felcloth" },
		}))
	end)

	it("skips an item with no id", function()
		assert.same({ FELCLOTH }, queueAfter({
			{ itemName = "Nameless" },
			{ itemId = FELCLOTH, itemName = "Felcloth" },
		}))
	end)

	it("queries a repeated item once", function()
		-- Several rows can reference the same reagent; querying it twice is a
		-- wasted round trip against a rate-limited server.
		assert.same({ THORIUM }, queueAfter({
			{ itemId = THORIUM, itemName = "Thorium Bar" },
			{ itemId = THORIUM, itemName = "Thorium Bar" },
			{ itemId = THORIUM, itemName = "Thorium Bar" },
		}))
	end)

	it("reports the deduped total, not the number handed in", function()
		AH.StartScan({
			{ itemId = THORIUM,  itemName = "Thorium Bar" },
			{ itemId = THORIUM,  itemName = "Thorium Bar" },
			{ itemId = FELCLOTH, itemName = "Felcloth" },
		})
		local _, total = AH.GetScanProgress()
		assert.equal(2, total)
	end)
end)

describe("_completeCurrentItem — the price that comes out", function()
	local function complete(listings)
		AH._isScanning  = true
		AH._currentItem = { itemId = THORIUM, itemName = "Thorium Bar" }
		AH._completeCurrentItem(listings)
		return AH.GetListingsFor(THORIUM)
	end

	it("takes the cheapest buyout, not the first or the last", function()
		local r = complete({
			{ buyoutPrice = 5000 },
			{ buyoutPrice = 1200 },
			{ buyoutPrice = 9900 },
		})
		assert.equal(1200, r.lowestBuyout)
	end)

	it("ignores a listing with no buyout, which is bid-only", function()
		-- A bid-only auction has buyoutPrice 0. Treating that as the cheapest
		-- price would report every item as free.
		local r = complete({
			{ buyoutPrice = 0 },
			{ buyoutPrice = 3000 },
		})
		assert.equal(3000, r.lowestBuyout)
	end)

	it("ignores a listing whose buyout is missing entirely", function()
		local r = complete({
			{ bidAmount = 500 },
			{ buyoutPrice = 2500 },
		})
		assert.equal(2500, r.lowestBuyout)
	end)

	it("reports no price at all when nothing is buyable", function()
		local r = complete({ { buyoutPrice = 0 }, { bidAmount = 100 } })
		assert.is_nil(r.lowestBuyout)
		assert.equal(2, r.count)
	end)

	it("records an empty result rather than nothing for an unlisted item", function()
		-- "Nobody is selling it" and "we never looked" must not be the same
		-- answer to a caller pricing a craft.
		local r = complete({})
		assert.is_truthy(r)
		assert.equal(0, r.count)
		assert.is_nil(r.lowestBuyout)
	end)

	it("counts the item as scanned", function()
		complete({ { buyoutPrice = 100 } })
		local scanned = AH.GetScanProgress()
		assert.equal(1, scanned)
	end)

	it("does nothing when no scan is running", function()
		AH._isScanning  = false
		AH._currentItem = { itemId = THORIUM, itemName = "Thorium Bar" }
		AH._completeCurrentItem({ { buyoutPrice = 100 } })
		assert.is_nil(AH.GetListingsFor(THORIUM))
	end)
end)

describe("ClearResults", function()
	it("forgets previous prices so a stale figure cannot be served", function()
		AH._isScanning  = true
		AH._currentItem = { itemId = THORIUM, itemName = "Thorium Bar" }
		AH._completeCurrentItem({ { buyoutPrice = 100 } })
		assert.is_truthy(AH.GetListingsFor(THORIUM))

		AH.ClearResults()
		assert.is_nil(AH.GetListingsFor(THORIUM))
	end)
end)
