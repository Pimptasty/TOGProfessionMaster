-- The seams between this addon and ItemDB's price API (v1.1.0):
--
--   * `addon.AH` -- the facade Modules/AHScanner.lua now IS. The per-row [AH]
--     buttons gate on `GetListingsFor` and search through `SearchFor`, the
--     shared Scan AH button drives `StartScan` / `CancelScan` / the progress
--     reads, and every tab subscribes to two addon events this file re-fires
--     from the library's callbacks. Installed only when the ItemDB in play
--     carries the scanner, which is what every caller's `if addon.AH` was
--     written for.
--   * `addon:MigratePriceSettingsToItemDB` -- the one-shot carry-over of a
--     player's price-source choices from this addon's profile into ItemDB's
--     per-account settings.
--   * The Settings button that replaced nine toggles, and the Profit Planner's
--     source filter, both of which read the library's registry instead of
--     deciding anything themselves.
--
-- Driven against the REAL library and its REAL Price/ files (env.priceDB);
-- the one stand-in is the "older ItemDB" case, which the real library cannot
-- be made to be.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")
local ace = require("env.ace")

local ns, Ace, DB

local ORE = 2770

setup(function()
	ns  = env.initDb()
	Ace = ns.lib
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	DB = env.priceDB()
	-- The facade binds the ItemDB in play at LOAD, so it is loaded per example
	-- against whichever library the example wants.
	ns.AH = nil
end)

after_each(function()
	ns.AH = nil
	ns._itemDB = nil
end)

local function loadFacade()
	env.loadModule("Modules/AHScanner.lua")
	return ns.AH
end

--- What `addon:Print` is handed while `fn` runs. Recorded at the addon's own
--- seam rather than read back from `env.wow.chat`, because several GUI spec
--- files replace `ns.Print` with a no-op and never put it back -- in a
--- full-suite run the chat frame sees nothing from this addon by the time this
--- file runs. Restored afterwards whatever `fn` does.
local function chatDuring(fn)
	local lines, saved = {}, ns.Print
	ns.Print = function(_, ...) lines[#lines + 1] = table.concat({ ... }, " ") end
	local ok, err = pcall(fn)
	ns.Print = saved
	if not ok then error(err, 0) end
	return lines
end

describe("addon.AH -- installed only over an ItemDB that carries the scanner", function()
	it("is installed over the real library", function()
		assert.is_table(loadFacade())
	end)

	it("is NOT installed over an ItemDB that predates the scanner", function()
		-- The [AH] buttons then never draw and the Scan AH button stays
		-- disabled: the degrade every caller's `if addon.AH` guard exists for.
		ns._itemDB = { GetPrice = function() return nil end }
		assert.is_nil(loadFacade())
	end)

	it("is NOT installed with no ItemDB at all", function()
		ns._itemDB = false
		assert.is_nil(loadFacade())
	end)
end)

describe("addon.AH -- the reads the tabs make", function()
	it("reports the auction house closed until the library says otherwise", function()
		local AH = loadFacade()
		assert.is_false(AH.IsOpen())
		DB.scan.isOpen = true
		assert.is_true(AH.IsOpen())
	end)

	it("hands back the library's scan record for an item -- the [AH] button's gate", function()
		local AH = loadFacade()
		assert.is_nil(AH.GetListingsFor(ORE))
		DB.scan.results[ORE] = { lowestBuyout = 123, count = 2, scannedAt = 1000 }
		assert.equal(123, AH.GetListingsFor(ORE).lowestBuyout)
	end)

	it("reports no scan running and no progress at rest", function()
		local AH = loadFacade()
		assert.is_false(AH.IsScanning())
		assert.is_false(AH.IsFullScanning())
		local scanned, total = AH.GetScanProgress()
		assert.equal(0, scanned)
		assert.equal(0, total)
	end)

	it("reads the library's progress while a scan runs", function()
		local AH = loadFacade()
		DB.scan.scanning, DB.scan.scannedItems, DB.scan.totalItems = true, 3, 7
		assert.is_true(AH.IsScanning())
		local scanned, total = AH.GetScanProgress()
		assert.equal(3, scanned)
		assert.equal(7, total)
	end)
end)

describe("addon.AH -- the actions", function()
	it("SearchFor says so in chat and does nothing when the AH is closed", function()
		local AH = loadFacade()
		local fired
		local lines = chatDuring(function() fired = AH.SearchFor("Copper Ore") end)
		assert.is_false(fired)
		assert.equal(1, #lines)
		local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
		assert.is_truthy(lines[1]:find(L["AHScannerOpenAH"], 1, true))
	end)

	it("SearchFor refuses a non-name without a word in chat", function()
		local AH = loadFacade()
		local lines = chatDuring(function()
			assert.is_false(AH.SearchFor(nil))
			assert.is_false(AH.SearchFor(""))
			assert.is_false(AH.SearchFor(42))
		end)
		assert.same({}, lines)
	end)

	it("SearchFor runs the library's search when the AH is open", function()
		local AH = loadFacade()
		DB.scan.isOpen = true
		local searched
		DB.AuctionHouseSearch = function(_, name) searched = name return true end
		assert.is_true(AH.SearchFor("Copper Ore"))
		assert.equal("Copper Ore", searched)
	end)

	it("StartScan passes the library's refusal through, reason and all", function()
		local AH = loadFacade()
		local started, reason = AH.StartScan({ { ORE, "Copper Ore" } })
		assert.is_false(started)
		assert.equal("ah-closed", reason)
	end)

	it("StartFullScan passes the library's refusal through too", function()
		local AH = loadFacade()
		local started, reason = AH.StartFullScan(true)
		assert.is_false(started)
		assert.equal("ah-closed", reason)
	end)

	it("CancelScan reaches the library", function()
		local AH = loadFacade()
		local cancelled = false
		DB.CancelScan = function() cancelled = true end
		AH.CancelScan()
		assert.is_true(cancelled)
	end)
end)

describe("addon.AH -- the two addon events, fed from the library's callbacks", function()
	it("re-fires AH_OPEN_STATE_CHANGED with the open flag", function()
		loadFacade()
		local got, owner = {}, {}
		ns.RegisterCallback(owner, "AH_OPEN_STATE_CHANGED", function(_, isOpen)
			got[#got + 1] = isOpen
		end)
		DB:_PriceFire("LibItemDB_AuctionHouse", true)
		DB:_PriceFire("LibItemDB_AuctionHouse", false)
		ns.UnregisterCallback(owner, "AH_OPEN_STATE_CHANGED")
		assert.same({ true, false }, got)
	end)

	it("re-fires AH_SCAN_COMPLETE as (results, reason), never a nil result set", function()
		loadFacade()
		local got, owner = {}, {}
		ns.RegisterCallback(owner, "AH_SCAN_COMPLETE", function(_, results, reason)
			got[#got + 1] = { results = results, reason = reason }
		end)
		local results = { [ORE] = { lowestBuyout = 5 } }
		DB:_PriceFire("LibItemDB_ScanComplete", "targeted", "complete", results)
		DB:_PriceFire("LibItemDB_ScanComplete", "full", "complete", nil)
		ns.UnregisterCallback(owner, "AH_SCAN_COMPLETE")
		assert.equal(2, #got)
		assert.equal(results, got[1].results)
		assert.equal("complete", got[1].reason)
		assert.same({}, got[2].results)
	end)
end)

describe("MigratePriceSettingsToItemDB -- a player's choices follow the ladder", function()
	local function profile() return Ace.db.profile end

	it("carries every value that DIFFERS from ItemDB's default, under its new name", function()
		local p = profile()
		p.useTOGPMAH, p.autoScanAH, p.ahScanDelay = false, true, 2.5
		p.useAuctionator, p.useAuctionatorHistorical = true, false
		assert.equal(5, ns:MigratePriceSettingsToItemDB())
		assert.is_false(DB:GetPriceSetting("useOwnScan"))
		assert.is_true(DB:GetPriceSetting("autoScan"))
		assert.equal(2.5, DB:GetPriceSetting("scanDelay"))
		assert.is_true(DB:GetPriceSetting("useAuctionator"))
		assert.is_false(DB:GetPriceSetting("useAuctionatorHistorical"))
	end)

	it("clears the profile's copies once they are carried over", function()
		local p = profile()
		p.useAuctionator, p.useTSM, p.useAuctioneer = true, true, false
		ns:MigratePriceSettingsToItemDB()
		assert.is_nil(p.useAuctionator)
		assert.is_nil(p.useTSM)
		assert.is_nil(p.useAuctioneer)
	end)

	it("writes nothing for a value that already matches, so no settings-changed event fires", function()
		local p = profile()
		p.useAuctioneer, p.useTSM, p.useTOGPMAH = false, false, true   -- ItemDB's defaults
		local fired = 0
		DB.RegisterCallback("pricefacade_spec", "LibItemDB_PriceSettingsChanged", function() fired = fired + 1 end)
		local written = ns:MigratePriceSettingsToItemDB()
		DB.UnregisterCallback("pricefacade_spec", "LibItemDB_PriceSettingsChanged")
		assert.equal(0, written)
		assert.equal(0, fired)
		assert.is_nil(p.useAuctioneer)
	end)

	it("writes a parent before its fallback, so the parent's cascade cannot undo the fallback", function()
		-- ItemDB turns a fallback off with its parent. Another consumer had
		-- Auctionator ON; this profile says parent OFF, fallback ON. Written
		-- child-first the parent's cascade would then switch the fallback off.
		DB:SetPriceSetting("useAuctionator", true)
		local p = profile()
		p.useAuctionator, p.useAuctionatorHistorical = false, true
		ns:MigratePriceSettingsToItemDB()
		assert.is_false(DB:GetPriceSetting("useAuctionator"))
		assert.is_true(DB:GetPriceSetting("useAuctionatorHistorical"))
	end)

	it("never switches TSM's App Helper (region) data OFF from this addon's old default", function()
		-- ItemDB defaults it ON and it gates the one complete picture of the
		-- AH; this addon's default was OFF, so a stored false is the old
		-- default, not a choice (ItemDB's reply on thread 6b52f51f).
		local p = profile()
		p.useTSMAppHelper = false
		assert.equal(0, ns:MigratePriceSettingsToItemDB())
		assert.is_true(DB:GetPriceSetting("useTSMAppHelper"))
		assert.is_nil(p.useTSMAppHelper)
	end)

	it("does carry an explicit App Helper opt-in", function()
		DB:SetPriceSetting("useTSMAppHelper", false)
		profile().useTSMAppHelper = true
		assert.equal(1, ns:MigratePriceSettingsToItemDB())
		assert.is_true(DB:GetPriceSetting("useTSMAppHelper"))
	end)

	it("drops the orphaned scan store this addon kept under factionrealm", function()
		local fr = Ace.db.factionrealm
		fr.ahPrices, fr.vendorPrices = { [ORE] = { p = 1, at = 1 } }, { [ORE] = 5 }
		ns:MigratePriceSettingsToItemDB()
		assert.is_nil(fr.ahPrices)
		assert.is_nil(fr.vendorPrices)
	end)

	it("keeps the profile's values against an older ItemDB, for a later login with a newer one", function()
		ns._itemDB = { GetVendorBasePrice = function() return nil end }
		local p = profile()
		p.useAuctionator = true
		assert.equal(0, ns:MigratePriceSettingsToItemDB())
		assert.is_true(p.useAuctionator)
		-- The orphaned store still goes: nothing reads it whichever ItemDB is in.
		assert.is_nil(Ace.db.factionrealm.ahPrices)
	end)

	it("is a no-op with nothing to carry", function()
		assert.equal(0, ns:MigratePriceSettingsToItemDB())
	end)

	it("runs ONCE PER ACCOUNT: the first character's choices carry, a later profile's are only cleared", function()
		-- ItemDB's settings are per account and this addon's were per profile
		-- (ItemDB's contract 5bb73440): stamped per profile, the second
		-- character to log in would overwrite the first's import.
		local p = profile()
		p.useAuctionator = true
		assert.equal(1, ns:MigratePriceSettingsToItemDB())
		assert.is_true(Ace.db.global.priceSettingsMigrated)
		-- A second profile, with the opposite choice, logs in later.
		p.useAuctionator = false
		p.useTSM = true
		assert.equal(0, ns:MigratePriceSettingsToItemDB())
		assert.is_true(DB:GetPriceSetting("useAuctionator"))
		assert.is_false(DB:GetPriceSetting("useTSM"))
		assert.is_nil(p.useAuctionator)
		assert.is_nil(p.useTSM)
	end)

	it("stamps the account even when there was nothing to carry, so a later profile cannot import", function()
		assert.equal(0, ns:MigratePriceSettingsToItemDB())
		assert.is_true(Ace.db.global.priceSettingsMigrated)
	end)

	it("does not stamp the account against an older ItemDB, so a newer one still imports", function()
		ns._itemDB = { GetVendorBasePrice = function() return nil end }
		ns:MigratePriceSettingsToItemDB()
		assert.is_nil(Ace.db.global.priceSettingsMigrated)
	end)
end)

describe("the Profit Planner's source filter reads ItemDB's registry", function()
	local PT

	setup(function()
		env.loadModule("GUI/SharedWidgets.lua")
		PT = env.loadModule("GUI/AHProfitTab.lua").AHProfitTab
	end)

	it("offers exactly the sources that are present AND on, in the library's precedence", function()
		-- Out of the box: only the own scan (the third parties are off, and
		-- not installed here anyway).
		assert.same({ scan = true }, PT._enabledSourcesForMode("live"))
		_G.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 1 end } } }
		DB:SetPriceSetting("useAuctionator", true)
		assert.same({ scan = true, auctionator = true }, PT._enabledSourcesForMode("live"))
		local opts = PT.BuildFilterOptions({ _mode = "live" }, {})
		assert.same({ "auctionator", "scan" }, opts.sources)
	end)

	it("offers only history-carrying sources on the Historical subtab", function()
		-- The own scan has a minimum buyout and nothing else, so it can never
		-- answer a historical row; pre-ticking it would promise rows that
		-- cannot come.
		_G.Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function() return 1 end } } }
		DB:SetPriceSetting("useAuctionator", true)
		assert.same({ auctionator = true }, PT._enabledSourcesForMode("history"))
	end)

	it("skips a source that is on but not installed", function()
		DB:SetPriceSetting("useTSM", true)
		assert.same({ scan = true }, PT._enabledSourcesForMode("live"))
	end)

	it("offers nothing against an ItemDB without the price API, and still lists what the rows carry", function()
		ns._itemDB = { GetVendorBasePrice = function() return nil end }
		assert.same({}, PT._enabledSourcesForMode("live"))
		local opts = PT.BuildFilterOptions({ _mode = "live" }, { { source = "scan" } })
		assert.same({ "scan" }, opts.sources)
	end)

	it("folds a filter saved by an older build onto the provider ids", function()
		local filter = { sources = {
			["togpm-ah"] = true, ["auctioneer-live"] = false, ["auctioneer-cached"] = true,
			["tsm-history"] = false, ["auctionator-history"] = false,
		} }
		PT:SyncSourceSelection(filter, { sources = {}, enabledSources = {} })
		-- A provider is ticked if ANY of its old keys was; every old key is gone.
		assert.is_true(filter.sources["scan"])
		assert.is_true(filter.sources["auctioneer"])
		assert.is_false(filter.sources["tsm"])
		assert.is_false(filter.sources["auctionator"])
		for old in pairs({ ["togpm-ah"] = 1, ["auctioneer-live"] = 1, ["auctioneer-cached"] = 1,
		                   ["tsm-history"] = 1, ["auctionator-history"] = 1 }) do
			assert.is_nil(filter.sources[old], old .. " survived")
		end
	end)
end)

describe("the Settings button that replaced the toggles", function()
	local options, savedDb

	--- Find an option by key anywhere in the tree.
	local function opt(key, node)
		for k, v in pairs(node.args or {}) do
			if k == key then return v end
			if type(v) == "table" and v.args then
				local found = opt(key, v)
				if found then return found end
			end
		end
		return nil
	end

	setup(function()
		ace.load("AceConfig-3.0", "AceConfigDialog-3.0")
		env.loadModule("GUI/SharedWidgets.lua")
		env.loadModule("GUI/MainWindow.lua")
		env.loadModule("GUI/Settings.lua")
		-- Registration is hooked onto OnInitialize (already run by initDb), so
		-- it runs once more -- guarded, as settings_spec does, because
		-- AddToBlizOptions raises on a second registration of the same path.
		local registry = LibStub("AceConfigRegistry-3.0")
		if not registry:GetOptionsTable("TOGProfessionMaster") then
			savedDb = ns.lib.db
			ns.lib:OnInitialize()
		end
		options = registry:GetOptionsTable("TOGProfessionMaster")("dialog", "AceConfigDialog-3.0")
	end)

	teardown(function()
		if savedDb then ns.lib.db = savedDb end
	end)

	it("is one button, and the nine toggles are gone", function()
		assert.equal("execute", opt("ahPriceSources", options).type)
		for _, key in ipairs({ "useTOGPMAH", "autoScanAH", "ahScanDelay", "useAuctionator",
		                       "useAuctionatorHistorical", "useAuctioneer", "useAuctioneerCached",
		                       "useTSM", "useTSMAppHelper" }) do
			assert.is_nil(opt(key, options), key .. " is still in the options table")
		end
	end)

	it("opens ItemDB's price window", function()
		local opened = false
		DB.OpenPriceWindow = function() opened = true end
		local button = opt("ahPriceSources", options)
		assert.is_false(button.disabled())
		button.func()
		assert.is_true(opened)
	end)

	it("is disabled against an ItemDB with no window to open", function()
		ns._itemDB = { GetVendorBasePrice = function() return nil end }
		local button = opt("ahPriceSources", options)
		assert.is_true(button.disabled())
		button.func()   -- and pressing it anyway does nothing
	end)
end)
