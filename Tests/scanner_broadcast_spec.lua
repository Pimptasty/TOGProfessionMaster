-- Scanner's send side, and the cross-guild roster persistence.
--
-- Every broadcast here is GUILD-WIDE, which is what makes the coalescing rules
-- load-bearing: a leaf many peers want gets one request per peer, and without
-- suppression the same bytes go to everyone once per requester. The rules are
-- deliberately asymmetric — a repeat of the SAME version is swallowed, a CHANGED
-- one always goes out immediately, because swallowing that is exactly the update
-- peers are waiting for (it once stalled two-client cooldown sync outright).

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, gdb, DS
local ME  = "Testchar-Testrealm"
local OWNER = "Bob-Testrealm"
local ALCHEMY = 171
local NOW = 1000000

-- Records every broadcast while delegating hashing to the real library.
local function recorder()
	local real = env.deltaSync()
	local r = { hashCasts = {}, dataCasts = {}, completed = {} }
	r.BroadcastItemHashes = function(_, map, prio)
		r.hashCasts[#r.hashCasts + 1] = { map = map, prio = prio }
		return true, 100
	end
	r.BroadcastData = function(_, payload, dist, prio)
		r.dataCasts[#r.dataCasts + 1] = { payload = payload, dist = dist, prio = prio }
		return true, 200
	end
	r.p2p = { OnItemCompleted = function(_, key, who)
		r.completed[#r.completed + 1] = { key = key, who = who }
	end }
	r.ComputeHash           = function(_, t) return real:ComputeHash(t) end
	r.ComputeStructuredHash = function(_, t) return real:ComputeStructuredHash(t) end
	return r
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
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({ [ALCHEMY] = { [2330] = { name = "Minor Healing Potion", craftedItemId = 118 } } })
	DS = recorder()
	S.DS = DS
	S.GuildRoster = ns.Scanner and ns.Scanner.GuildRoster
	S._lastBroadcastHashes = nil
	S._lastBroadcastAt     = 0
	S._lastLeafBroadcast   = nil
	S._lastSubhashBroadcast = nil
	S._broadcastSeconds    = S._broadcastSeconds or 30
end)

describe("BroadcastHashes", function()
	it("does nothing without a sync host or a guild", function()
		S.DS = nil
		S:BroadcastHashes()
		S.DS = DS
		env.guildName = nil
		S:BroadcastHashes()
		env.guildName = "Testguild"
		assert.equal(0, #DS.hashCasts)
	end)

	it("sends the leaf hashes we hold", function()
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		ns.HashManager:InvalidateCharCooldowns(DS, gdb, ME)
		S:BroadcastHashes()
		assert.equal(1, #DS.hashCasts)
		assert.is_true(DS.hashCasts[1].map["guild:cooldowns"] ~= nil)
	end)

	it("pads a placeholder for professions we hold nothing for", function()
		-- Without the placeholder the OFFER protocol never fires for a key absent
		-- from our list, so a peer would never offer us that profession's data.
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		ns.HashManager:InvalidateCharCooldowns(DS, gdb, ME)
		S:BroadcastHashes()
		assert.is_true(DS.hashCasts[1].map["crafters:" .. ALCHEMY] ~= nil)
	end)

	it("sends only what changed since the last broadcast", function()
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		ns.HashManager:InvalidateCharCooldowns(DS, gdb, ME)
		S:BroadcastHashes()

		env.serverTime = NOW + 100
		S._lastBroadcastAt = 0        -- past the debounce
		gdb.cooldowns[OWNER] = { [17187] = NOW + 999 }
		ns.HashManager:InvalidateCharCooldowns(DS, gdb, OWNER)
		S:BroadcastHashes()
		assert.equal(2, #DS.hashCasts)
		-- The second send carries the changed roll-up, not the untouched placeholders.
		assert.is_true(DS.hashCasts[2].map["guild:cooldowns"] ~= nil)
		assert.is_nil(DS.hashCasts[2].map["crafters:" .. ALCHEMY])
	end)

	it("skips the send entirely when nothing changed", function()
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		ns.HashManager:InvalidateCharCooldowns(DS, gdb, ME)
		S:BroadcastHashes()
		S._lastBroadcastAt = 0
		S:BroadcastHashes()
		assert.equal(1, #DS.hashCasts)
	end)

	it("respects the debounce window", function()
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		ns.HashManager:InvalidateCharCooldowns(DS, gdb, ME)
		S._lastBroadcastAt = NOW - 1
		S:BroadcastHashes()
		assert.equal(0, #DS.hashCasts)
	end)
end)

describe("BroadcastLeafToGuild", function()
	before_each(function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		gdb.hashes["cooldown:" .. OWNER] = { hash = 111, updatedAt = 50, abs = true }
	end)

	it("broadcasts the leaf and completes its session", function()
		S:BroadcastLeafToGuild("cooldown:" .. OWNER)
		assert.equal(1, #DS.dataCasts)
		assert.equal("GUILD", DS.dataCasts[1].dist)
		assert.equal("cooldown:" .. OWNER, DS.completed[1].key)
	end)

	it("swallows a repeat of the SAME version within the window", function()
		S:BroadcastLeafToGuild("cooldown:" .. OWNER)
		S:BroadcastLeafToGuild("cooldown:" .. OWNER)
		assert.equal(1, #DS.dataCasts)
	end)

	it("always sends a CHANGED version immediately", function()
		-- Coalescing a new hash would swallow the very update peers are waiting
		-- for; this is what stalled two-client cooldown sync.
		S:BroadcastLeafToGuild("cooldown:" .. OWNER)
		gdb.hashes["cooldown:" .. OWNER].hash = 222
		S:BroadcastLeafToGuild("cooldown:" .. OWNER)
		assert.equal(2, #DS.dataCasts)
	end)

	it("re-sends the same version once the window has passed", function()
		S:BroadcastLeafToGuild("cooldown:" .. OWNER)
		env.serverTime = NOW + 11
		S:BroadcastLeafToGuild("cooldown:" .. OWNER)
		assert.equal(2, #DS.dataCasts)
	end)

	it("exempts a scoped crafters reply, which varies by who was asked", function()
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { [OWNER] = ns:GetCurrentGuildTag() } } }
		S:BroadcastLeafToGuild("crafters:" .. ALCHEMY, { [OWNER] = true })
		S:BroadcastLeafToGuild("crafters:" .. ALCHEMY, { [OWNER] = true })
		assert.equal(2, #DS.dataCasts)
	end)

	it("drops an orphan hash when asked for a leaf we hold no data for", function()
		-- We advertised it (it gossiped in via subhashes) but hold nothing; left
		-- alone, peers request it forever and our inflated stamp keeps the real
		-- owner silent.
		gdb.hashes["cooldown:Ghost-Testrealm"] = { hash = 9, updatedAt = 5, abs = true }
		S:BroadcastLeafToGuild("cooldown:Ghost-Testrealm")
		assert.equal(0, #DS.dataCasts)
		assert.is_nil(gdb.hashes["cooldown:Ghost-Testrealm"])
	end)

	it("does NOT drop the hash on an empty SCOPED reply", function()
		-- A scoped crafters reply can legitimately have nothing for the players
		-- asked without the whole leaf being orphaned.
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { [OWNER] = ns:GetCurrentGuildTag() } } }
		gdb.hashes["crafters:" .. ALCHEMY] = { hash = 5, updatedAt = 5 }
		S:BroadcastLeafToGuild("crafters:" .. ALCHEMY, { ["Nobody-Testrealm"] = true })
		assert.is_true(gdb.hashes["crafters:" .. ALCHEMY] ~= nil)
	end)

	it("stays quiet without a guild", function()
		env.guildName = nil
		S:BroadcastLeafToGuild("cooldown:" .. OWNER)
		env.guildName = "Testguild"
		assert.equal(0, #DS.dataCasts)
	end)
end)

describe("BroadcastSubhashesToGuild", function()
	before_each(function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		ns.HashManager:InvalidateCharCooldowns(DS, gdb, OWNER)
	end)

	it("sends the per-character list for a roll-up it knows", function()
		S:BroadcastSubhashesToGuild("guild:cooldowns")
		assert.equal(1, #DS.dataCasts)
		local p = DS.dataCasts[1].payload
		assert.equal("subhashes", p.type)
		assert.equal("guild:cooldowns", p.parent)
		assert.is_true(p.subhashes["cooldown:" .. OWNER] ~= nil)
		assert.equal(1, p.subsync)
	end)

	it("serves every roll-up family", function()
		gdb.altClaims[OWNER] = { OWNER }
		gdb.skills[OWNER] = { [182] = { skillRank = 1, skillMax = 300 } }
		ns.HashManager:RebuildOnFirstLoad(DS, gdb)
		for _, parent in ipairs({ "guild:accountchars", "guild:skills", "guild:professions" }) do
			S._lastSubhashBroadcast = nil
			S:BroadcastSubhashesToGuild(parent)
		end
		assert.equal(3, #DS.dataCasts)
	end)

	it("refuses a parent it does not know", function()
		S:BroadcastSubhashesToGuild("guild:bananas")
		assert.equal(0, #DS.dataCasts)
	end)

	it("coalesces a burst for an unchanged roll-up", function()
		S:BroadcastSubhashesToGuild("guild:cooldowns")
		S:BroadcastSubhashesToGuild("guild:cooldowns")
		assert.equal(1, #DS.dataCasts)
	end)

	it("sends again once the roll-up has changed", function()
		S:BroadcastSubhashesToGuild("guild:cooldowns")
		gdb.cooldowns["Third-Testrealm"] = { [17187] = NOW + 5 }
		ns.HashManager:InvalidateCharCooldowns(DS, gdb, "Third-Testrealm")
		S:BroadcastSubhashesToGuild("guild:cooldowns")
		assert.equal(2, #DS.dataCasts)
	end)
end)

describe("BroadcastPlayerSubhashes", function()
	it("sends a per-player hash list for the profession", function()
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { [OWNER] = ns:GetCurrentGuildTag() } } }
		S:BroadcastPlayerSubhashes(ALCHEMY)
		local p = DS.dataCasts[1].payload
		assert.equal("player-subhashes", p.type)
		assert.equal(ALCHEMY, p.profId)
		assert.is_true(p.players[OWNER] ~= nil)
	end)

	it("sends nothing for a profession with no crafters", function()
		S:BroadcastPlayerSubhashes(ALCHEMY)
		assert.equal(0, #DS.dataCasts)
	end)
end)

describe("PeerSupportsSubSync", function()
	it("normalises the peer name before looking it up", function()
		S._subsyncPeers = { [OWNER] = true }
		assert.is_true(S:PeerSupportsSubSync("Bob"))
		assert.is_false(S:PeerSupportsSubSync("Someone"))
		S._subsyncPeers = nil
	end)

	it("is false before any beacon and for a nil peer", function()
		assert.is_false(S:PeerSupportsSubSync(nil))
		assert.is_false(S:PeerSupportsSubSync(OWNER))
	end)
end)

describe("sister rosters", function()
	local SISTER = "Horde-Sisterguild"

	local function fakeRosterLib(rosters)
		return {
			GetRoster = function(_, key) return rosters[key] end,
			RemoveSisterRoster = function(_, key) rosters[key] = nil end,
			SetSisterRoster = function(_, key, members) rosters.fed = rosters.fed or {}; rosters.fed[key] = members end,
			NormalizeName = function(_, n) return n end,
			IsOnline = function() return true end,
		}
	end

	before_each(function()
		-- env.install() resets the settings database, so the allied-guild list has
		-- to be re-declared per test rather than once.
		ns.lib.db.profile.sisterGuilds = { "Sisterguild" }
	end)

	it("persists a fed roster with its members", function()
		local rosters = { [SISTER] = { ["Sis-Testrealm"] = { class = "MAGE", level = 60, rank = 2 } } }
		S.GuildRoster = fakeRosterLib(rosters)
		S:PersistSisterRoster(SISTER)
		local stored = gdb.sisterRosters[SISTER]
		assert.equal(1, #stored.members)
		assert.equal("Sis-Testrealm", stored.members[1].name)
		assert.equal(NOW, stored.fedAt)
	end)

	it("does nothing without a roster library or a roster", function()
		S.GuildRoster = nil
		S:PersistSisterRoster(SISTER)
		S.GuildRoster = fakeRosterLib({})
		S:PersistSisterRoster(SISTER)
		assert.is_nil(gdb.sisterRosters and gdb.sisterRosters[SISTER])
	end)

	it("rejects and removes a roster for a guild we have not allied with", function()
		local rosters = { ["Horde-Strangers"] = { ["X-Testrealm"] = {} } }
		S.GuildRoster = fakeRosterLib(rosters)
		S:OnSisterRosterUpdated("Horde-Strangers")
		assert.is_nil(rosters["Horde-Strangers"])
		assert.is_nil(gdb.sisterRosters and gdb.sisterRosters["Horde-Strangers"])
	end)

	it("accepts a roster for a configured ally", function()
		local rosters = { [SISTER] = { ["Sis-Testrealm"] = {} } }
		S.GuildRoster = fakeRosterLib(rosters)
		S:OnSisterRosterUpdated(SISTER)
		assert.is_true(gdb.sisterRosters[SISTER] ~= nil)
	end)

	it("re-feeds persisted rosters on login", function()
		local rosters = {}
		S.GuildRoster = fakeRosterLib(rosters)
		gdb.sisterRosters = { [SISTER] = { members = { { name = "Sis-Testrealm" } } } }
		S:RefeedSisterRosters()
		assert.is_true(rosters.fed[SISTER] ~= nil)
	end)

	it("forgets a persisted roster whose guild is no longer allied", function()
		local rosters = {}
		S.GuildRoster = fakeRosterLib(rosters)
		gdb.sisterRosters = { ["Horde-Strangers"] = { members = { { name = "X-Testrealm" } } } }
		S:RefeedSisterRosters()
		assert.is_nil(gdb.sisterRosters["Horde-Strangers"])
		assert.is_nil(rosters.fed)
	end)

	it("does nothing without a roster library", function()
		S.GuildRoster = nil
		gdb.sisterRosters = { [SISTER] = { members = {} } }
		S:RefeedSisterRosters()
		assert.is_true(gdb.sisterRosters[SISTER] ~= nil)
	end)
end)
