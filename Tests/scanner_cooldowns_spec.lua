-- Scanner's own-character cooldown scan.
--
-- This is the only place a cooldown is MINTED — everyone else adopts what this
-- produces — so the rules here are load-bearing:
--   * every transmute shares one bucket, and a known-but-idle transmute is
--     seeded "Ready" (a past timestamp) rather than left absent;
--   * a value is stored as an ABSOLUTE server-time expiry;
--   * a fired GCD (remaining <= 0) must not clobber an existing Ready state;
--   * the UI refresh fires only when something actually changed, because a local
--     scan raises no sync signal to piggyback on and re-runs constantly while
--     the player crafts.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, gdb, data
local ME  = "Testchar-Testrealm"
local NOW = 1000000

-- Cooldowns the client reports as running: [spellId] = secondsRemaining.
local running = {}

-- Client uptime in seconds — what GetTime() reports.
local UPTIME = 5000

-- The (start, duration) pair the WoW API would return for a cooldown with
-- `remaining` seconds left: it STARTED in the past, at a GetTime() stamp.
local function cooldownPair(remaining)
	local start = UPTIME - 10
	return start, remaining + 10
end

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	S = env.loadModule("Scanner.lua").Scanner
end)

before_each(function()
	env.install()
	env.serverTime = NOW
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	env.setRecipeDB({})
	running = {}
	S.DS = nil

	-- GetTime is monotonic seconds since client start, and a cooldown's `start` is
	-- a GetTime() stamp from the PAST. That ordering matters: the addon treats
	-- start >= now as a post-2^32ms-rollover timestamp and takes a completely
	-- different branch, so a naive `start = 1, GetTime() = 0` stub silently tests
	-- the rollover path instead of the ordinary one.
	_G.GetTime = function() return UPTIME end
	_G.GetSpellCooldown = function(spellId)
		local remaining = running[spellId]
		if not remaining then return 0, 0 end
		return cooldownPair(remaining)
	end
	_G.IsSpellKnown = function() return false end
	_G.GetContainerNumSlots = function() return 0 end
	_G.GetContainerItemInfo = function() return nil end
	_G.C_Container = nil
	data = ns:GetCooldownData()
end)

local function anyTransmute()
	for spellId in pairs(data.transmutes) do return spellId end
end

local function plainCooldown()
	for spellId in pairs(data.cooldowns) do
		if not data.transmutes[spellId] then return spellId end
	end
end

describe("ScanCooldowns", function()
	it("stores an active cooldown as an absolute expiry", function()
		local spellId = plainCooldown()
		running[spellId] = 3600
		S:ScanCooldowns()
		assert.equal(NOW + 3600, gdb.cooldowns[ME][spellId])
	end)

	it("seeds a known idle cooldown as Ready", function()
		local spellId = plainCooldown()
		_G.IsSpellKnown = function(id) return id == spellId end
		S:ScanCooldowns()
		assert.equal(NOW - 1, gdb.cooldowns[ME][spellId])
	end)

	it("does not invent cooldowns for spells the character doesn't know", function()
		S:ScanCooldowns()
		assert.same({}, gdb.cooldowns[ME])
	end)

	it("leaves an existing Ready state alone when the GCD fires", function()
		local spellId = plainCooldown()
		gdb.cooldowns[ME] = { [spellId] = NOW - 5 }
		S:ScanCooldowns()
		assert.equal(NOW - 5, gdb.cooldowns[ME][spellId])
	end)

	it("ignores an implausible remaining time", function()
		local spellId = plainCooldown()
		running[spellId] = 60 * 60 * 24 * 400   -- over a year
		S:ScanCooldowns()
		assert.is_nil(gdb.cooldowns[ME][spellId])
	end)

	it("shares one expiry across every transmute the character knows", function()
		local active = anyTransmute()
		running[active] = 7200
		-- A second transmute known through the recipe database.
		local other
		for spellId in pairs(data.transmutes) do
			if spellId ~= active then other = spellId; break end
		end
		gdb.recipes[171] = { [1] = { spellId = other, crafters = { [ME] = "tag" } } }
		S:ScanCooldowns()
		assert.equal(NOW + 7200, gdb.cooldowns[ME][active])
		assert.equal(NOW + 7200, gdb.cooldowns[ME][other])
	end)

	it("seeds a known transmute as Ready when none is running", function()
		local known = anyTransmute()
		gdb.recipes[171] = { [1] = { spellId = known, crafters = { [ME] = "tag" } } }
		S:ScanCooldowns()
		assert.equal(NOW - 1, gdb.cooldowns[ME][known])
	end)

	it("shows the running transmute even before any trade-skill scan", function()
		-- IsSpellKnown returns false for transmutes on Classic Era, so the spell
		-- found on cooldown has to count as known by itself.
		local active = anyTransmute()
		running[active] = 100
		S:ScanCooldowns()
		assert.equal(NOW + 100, gdb.cooldowns[ME][active])
	end)

	it("stamps the scan time the hash layer reads", function()
		S:ScanCooldowns()
		assert.equal(NOW, gdb.lastScan[ME].cooldowns)
		assert.equal(NOW, gdb.syncTimes[ME])
	end)

	it("mints the leaf hash when a sync host is present", function()
		local spellId = plainCooldown()
		running[spellId] = 60
		S.DS = env.deltaSync()
		S:ScanCooldowns()
		S.DS = nil
		assert.is_true(gdb.hashes["cooldown:" .. ME] ~= nil)
		assert.is_true(gdb.hashes["guild:cooldowns"] ~= nil)
	end)

	it("fires a cooldowns-scoped refresh only when something changed", function()
		local fired = {}
		ns.RegisterCallback({}, "GUILD_DATA_UPDATED", function(_e, charKey, scopes)
			fired[#fired + 1] = { charKey = charKey, scopes = scopes }
		end)
		local spellId = plainCooldown()
		running[spellId] = 60
		S:ScanCooldowns()
		assert.equal(1, #fired)
		assert.is_true(fired[1].scopes.cooldowns)

		-- Re-scanning with identical state must not redraw.
		S:ScanCooldowns()
		assert.equal(1, #fired)
	end)

	it("copes with no database at all", function()
		local saved = ns.guildDb
		ns.guildDb = { global = nil }
		local ok, err = pcall(function() S:ScanCooldowns() end)
		ns.guildDb = saved          -- restore BEFORE asserting, so a failure here
		assert.is_true(ok, tostring(err))   -- cannot leak into every later test
	end)
end)

describe("ScanSaltShaker", function()
	local SHAKER = 15846

	before_each(function()
		_G.C_Container = nil
		_G.GetItemCooldown = function() return 0, 0 end
		_G.GetItemCount = function() return 0 end
	end)

	it("records the item's cooldown as an absolute expiry", function()
		_G.GetItemCooldown = function() return cooldownPair(3600) end
		local stored = {}
		S:ScanSaltShaker(stored, NOW, SHAKER)
		assert.equal(NOW + 3600, stored[SHAKER])
	end)

	it("prefers the namespaced API where the client has it", function()
		_G.C_Container = { GetItemCooldown = function() return cooldownPair(1800) end }
		_G.GetItemCooldown = function() return cooldownPair(9999) end
		local stored = {}
		S:ScanSaltShaker(stored, NOW, SHAKER)
		assert.equal(NOW + 1800, stored[SHAKER])
	end)

	it("falls back to the global when the namespaced one answers nothing", function()
		-- Some Classic Era builds ship one but not the other; falling back on the
		-- RESULT (not just existence) is what covers both failure modes.
		_G.C_Container = { GetItemCooldown = function() return 0, 0 end }
		_G.GetItemCooldown = function() return cooldownPair(600) end
		local stored = {}
		S:ScanSaltShaker(stored, NOW, SHAKER)
		assert.equal(NOW + 600, stored[SHAKER])
	end)

	it("seeds Ready when the item is owned but off cooldown", function()
		_G.GetItemCount = function() return 1 end
		local stored = {}
		S:ScanSaltShaker(stored, NOW, SHAKER)
		assert.equal(NOW - 1, stored[SHAKER])
	end)

	it("records nothing when the item isn't owned", function()
		local stored = {}
		S:ScanSaltShaker(stored, NOW, SHAKER)
		assert.same({}, stored)
	end)

	it("does nothing without an item id", function()
		local stored = {}
		S:ScanSaltShaker(stored, NOW, nil)
		assert.same({}, stored)
	end)
end)

describe("BackfillReagentItemIds", function()
	it("resolves a missing item id from the reagent's link", function()
		gdb.recipes[171] = { [2330] = { reagents = {
			{ name = "Peacebloom", itemLink = "|cffffffff|Hitem:2447|h[Peacebloom]|h|r" },
		} } }
		_G.GetItemInfoInstant = function() return nil end
		S:BackfillReagentItemIds()
		assert.equal(2447, gdb.recipes[171][2330].reagents[1].itemId)
	end)

	it("falls back to a name lookup", function()
		gdb.recipes[171] = { [2330] = { reagents = { { name = "Peacebloom" } } } }
		_G.GetItemInfoInstant = function(name) return name == "Peacebloom" and 2447 or nil end
		S:BackfillReagentItemIds()
		assert.equal(2447, gdb.recipes[171][2330].reagents[1].itemId)
	end)

	it("leaves an already-resolved reagent alone", function()
		gdb.recipes[171] = { [2330] = { reagents = { { name = "x", itemId = 99 } } } }
		_G.GetItemInfoInstant = function() return 2447 end
		S:BackfillReagentItemIds()
		assert.equal(99, gdb.recipes[171][2330].reagents[1].itemId)
	end)

	it("does nothing without the instant lookup API", function()
		_G.GetItemInfoInstant = nil
		local ok, err = pcall(function() S:BackfillReagentItemIds() end)
		assert.is_true(ok, tostring(err))
	end)
end)

describe("_ProfSuffix", function()
	it("names a profession for the sync log", function()
		assert.is_true(S:_ProfSuffix(171):find("Alchemy", 1, true) ~= nil)
	end)

	it("says nothing for an id it cannot name", function()
		assert.equal("", S:_ProfSuffix(999999))
	end)
end)

describe("PeerSupportsSubSync", function()
	it("is false until a peer's payload has announced it", function()
		S._subsyncPeers = nil
		assert.is_false(S:PeerSupportsSubSync("Bob-Testrealm") or false)
	end)

	it("is true once the beacon has been seen", function()
		S._subsyncPeers = { ["Bob-Testrealm"] = true }
		assert.is_true(S:PeerSupportsSubSync("Bob-Testrealm"))
		S._subsyncPeers = nil
	end)
end)
