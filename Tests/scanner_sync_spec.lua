-- Scanner's wire half: what we put on the wire, and what we do with what
-- arrives.
--
-- The rules being pinned here are the ones the sync protocol lives or dies by:
--   * A cooldown leaf ships ABSOLUTE expiry plus the owner's minted token, and a
--     receiver adopts both VERBATIM. Reconstructing "now + remaining" on each hop
--     inflated the value by the transmission latency, changed the hash, and kept
--     guild:cooldowns from ever converging.
--   * Nobody may overwrite our OWN cooldowns; we mint those locally.
--   * A leaf we hold no DATA for must advertise a stamp of -1, not the timestamp
--     of a leftover orphan hash — otherwise the owner's real copy isn't "strictly
--     newer", it stays silent, and the data can never reach us.
--
-- DeltaSync is represented here by a recorder: what is under test is Scanner's
-- DECISION (which keys to request, with which stamps), not the library's
-- delivery, which has its own suite.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, gdb, DS
local ME    = "Testchar-Testrealm"
local OWNER = "Bob-Testrealm"
local ALCHEMY = 171
local NOW = 1000000

-- A DeltaSync stand-in that RECORDS what Scanner asks for while delegating the
-- hashing to the REAL library — the receive path recomposes roll-ups through
-- HashManager, and faking those hashes would let a convergence bug pass.
local function recorder()
	local real = env.deltaSync()
	local r = { requests = {}, completed = {} }
	r.RequestData = function(_, peer, req) r.requests[#r.requests + 1] = { peer = peer, req = req } end
	r.p2p = { OnItemCompleted = function(_, key, peer)
		r.completed[#r.completed + 1] = { key = key, peer = peer }
	end }
	r.ComputeHash           = function(_, t) return real:ComputeHash(t) end
	r.ComputeStructuredHash = function(_, t) return real:ComputeStructuredHash(t) end
	return r
end

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	-- Loaded for its side effect: Scanner reaches HashManager through the addon
	-- namespace, so it has to exist before Scanner runs.
	env.loadModule("Modules/HashManager.lua")
	S  = env.loadModule("Scanner.lua").Scanner
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
	Scanner_subsyncReset()
end)

function Scanner_subsyncReset()
	S._subsyncPeers = nil
end

describe("BuildLeafPayload — cooldowns", function()
	it("ships absolute expiry, flagged as the absolute format", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 3600 }
		local p = S:BuildLeafPayload("cooldown:" .. OWNER)
		local leaf = p.leaves["cooldown:" .. OWNER]
		assert.equal(1, leaf.abs)
		assert.equal(NOW + 3600, leaf.data[17187])
	end)

	it("ships the owner's minted token, not a recomputed one", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 3600 }
		gdb.hashes["cooldown:" .. OWNER] = { hash = 4242, updatedAt = 77, abs = true }
		local leaf = S:BuildLeafPayload("cooldown:" .. OWNER).leaves["cooldown:" .. OWNER]
		assert.equal(4242, leaf.hash)
		assert.equal(77, leaf.updatedAt)
	end)

	it("piggybacks the owner's scan time", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		gdb.lastScan[OWNER] = { cooldowns = 555, skills = 999 }
		local p = S:BuildLeafPayload("cooldown:" .. OWNER)
		assert.same({ [OWNER] = { cooldowns = 555 } }, p.lastScan)
	end)

	it("refuses to build a payload for a bucket we do not hold", function()
		assert.is_nil(S:BuildLeafPayload("cooldown:Nobody-Testrealm"))
		gdb.cooldowns[OWNER] = {}
		assert.is_nil(S:BuildLeafPayload("cooldown:" .. OWNER))
	end)

	it("drops a non-numeric expiry rather than shipping it", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60, [999] = "soon" }
		local leaf = S:BuildLeafPayload("cooldown:" .. OWNER).leaves["cooldown:" .. OWNER]
		assert.is_nil(leaf.data[999])
	end)

	it("carries the presence beacon so peers know we speak drill-down", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		assert.equal(1, S:BuildLeafPayload("cooldown:" .. OWNER).subsync)
	end)
end)

describe("BuildLeafPayload — other leaves", function()
	it("ships an alt-group claim", function()
		gdb.altClaims[OWNER] = { OWNER, "Alt-Testrealm" }
		local leaf = S:BuildLeafPayload("accountchars:" .. OWNER).leaves["accountchars:" .. OWNER]
		assert.same({ OWNER, "Alt-Testrealm" }, leaf.data)
	end)

	it("refuses an empty alt-group claim", function()
		gdb.altClaims[OWNER] = {}
		assert.is_nil(S:BuildLeafPayload("accountchars:" .. OWNER))
	end)

	it("ships the full profession snapshot", function()
		gdb.skills[OWNER] = {
			[ALCHEMY] = { skillRank = 300, skillMax = 300 },
			[182]     = { skillRank = 150, skillMax = 300 },
		}
		local leaf = S:BuildLeafPayload("professions:" .. OWNER).leaves["professions:" .. OWNER]
		assert.same({ ["171"] = { r = 300, m = 300 }, ["182"] = { r = 150, m = 300 } }, leaf.data)
	end)

	it("ships only GATHERING skills on the legacy skills leaf", function()
		gdb.skills[OWNER] = {
			[ALCHEMY] = { skillRank = 300, skillMax = 300 },
			[182]     = { skillRank = 150, skillMax = 300 },
		}
		local leaf = S:BuildLeafPayload("skills:" .. OWNER).leaves["skills:" .. OWNER]
		assert.same({ ["182"] = { r = 150, m = 300 } }, leaf.data)
	end)

	it("refuses a skills leaf for a character with only crafting skills", function()
		gdb.skills[OWNER] = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
		assert.is_nil(S:BuildLeafPayload("skills:" .. OWNER))
		assert.is_nil(S:BuildLeafPayload("professions:Nobody-Testrealm"))
	end)

	it("refuses a leaf key it does not recognise", function()
		assert.is_nil(S:BuildLeafPayload("banana:1"))
	end)
end)

describe("BuildLeafPayload — crafters", function()
	local TAG
	before_each(function()
		TAG = ns:GetCurrentGuildTag()
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { [OWNER] = TAG } } }
	end)

	it("ships each crafter's ORIGIN tag so attribution survives a relay", function()
		local leaf = S:BuildLeafPayload("crafters:" .. ALCHEMY).leaves["crafters:" .. ALCHEMY]
		assert.equal(TAG, leaf.data[2330][OWNER])
	end)

	it("piggybacks skill ranks and specialisations for that profession", function()
		gdb.skills[OWNER] = { [ALCHEMY] = { skillRank = 275, skillMax = 300 } }
		gdb.specializations[OWNER] = { [ALCHEMY] = 28672 }
		local p = S:BuildLeafPayload("crafters:" .. ALCHEMY)
		assert.same({ skillRank = 275, skillMax = 300 }, p.skills[ALCHEMY][OWNER])
		assert.equal(28672, p.specializations[ALCHEMY][OWNER])
	end)

	it("narrows to the requested players when the peer asked for a subset", function()
		gdb.recipes[ALCHEMY][2331] = { crafters = { ["Other-Testrealm"] = TAG } }
		gdb.skills["Other-Testrealm"] = { [ALCHEMY] = { skillRank = 1, skillMax = 300 } }
		local p = S:BuildLeafPayload("crafters:" .. ALCHEMY, { [OWNER] = true })
		assert.is_true(p.leaves["crafters:" .. ALCHEMY].data[2330] ~= nil)
		assert.is_nil(p.leaves["crafters:" .. ALCHEMY].data[2331])
		assert.is_nil(p.skills and p.skills[ALCHEMY] and p.skills[ALCHEMY]["Other-Testrealm"])
	end)

	it("refuses a profession with no crafters at all", function()
		gdb.recipes[ALCHEMY][2330].crafters = {}
		assert.is_nil(S:BuildLeafPayload("crafters:" .. ALCHEMY))
		assert.is_nil(S:BuildLeafPayload("crafters:999"))
		assert.is_nil(S:BuildLeafPayload("crafters:notanumber"))
	end)
end)

describe("OnGuildDataReceived — gates", function()
	it("ignores a malformed payload", function()
		S:OnGuildDataReceived("Bob", nil)
		S:OnGuildDataReceived("Bob", "not a table")
		S:OnGuildDataReceived("Bob", {})                    -- no charKey
		S:OnGuildDataReceived("Bob", { charKey = 42 })      -- charKey not a string
		assert.equal(0, #DS.requests)
	end)

	it("ignores the echo of our own broadcast", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		S:OnGuildDataReceived("Testchar", {
			charKey = ME,
			leaves = { ["cooldown:" .. OWNER] = { data = { [17187] = NOW + 999 }, abs = 1, hash = 1, updatedAt = 9 } },
		})
		assert.equal(NOW + 60, gdb.cooldowns[OWNER][17187])
	end)

	it("ignores everything while guildless", function()
		env.guildName = nil
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER,
			leaves = { ["cooldown:" .. OWNER] = { data = { [17187] = NOW + 60 }, abs = 1, hash = 1, updatedAt = 9 } },
		})
		env.guildName = "Testguild"
		assert.is_nil(gdb.cooldowns[OWNER])
	end)

	it("drops a payload from a guild we do not federate with", function()
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER,
			guildKey = "Horde-Strangers",
			leaves = { ["cooldown:" .. OWNER] = { data = { [17187] = NOW + 60 }, abs = 1, hash = 1, updatedAt = 9 } },
		})
		assert.is_nil(gdb.cooldowns[OWNER])
	end)

	it("records a peer as drill-down capable from its beacon", function()
		S:OnGuildDataReceived("Bob", { charKey = OWNER, subsync = 1, leaves = {} })
		assert.is_true(S._subsyncPeers[OWNER])
	end)

	it("merges incoming scan times, newest wins", function()
		gdb.lastScan[OWNER] = { cooldowns = 500 }
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER,
			leaves  = {},
			lastScan = { [OWNER] = { cooldowns = 400, skills = 900 } },
		})
		assert.equal(500, gdb.lastScan[OWNER].cooldowns)   -- ours was newer
		assert.equal(900, gdb.lastScan[OWNER].skills)
	end)
end)

describe("OnGuildDataReceived — cooldown adoption", function()
	local function deliver(token, ts, expiry, owner)
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER,
			leaves = { ["cooldown:" .. (owner or OWNER)] = {
				data = { [17187] = expiry }, abs = 1, hash = token, updatedAt = ts,
			} },
		})
	end

	it("adopts a leaf we hold nothing for, verbatim", function()
		deliver(1234, 500, NOW + 7200)
		assert.equal(NOW + 7200, gdb.cooldowns[OWNER][17187])
		assert.equal(1234, gdb.hashes["cooldown:" .. OWNER].hash)
		assert.equal(500, gdb.hashes["cooldown:" .. OWNER].updatedAt)
	end)

	it("ignores a re-send of the same token", function()
		deliver(1234, 500, NOW + 7200)
		deliver(1234, 500, NOW + 1)
		assert.equal(NOW + 7200, gdb.cooldowns[OWNER][17187])
	end)

	it("takes a strictly newer version", function()
		deliver(1234, 500, NOW + 7200)
		deliver(5678, 600, NOW + 9999)
		assert.equal(NOW + 9999, gdb.cooldowns[OWNER][17187])
	end)

	it("refuses an equally-aged different token, so two peers cannot ping-pong", function()
		-- Mixed-version rollout: two upgraded clients can hold different drifted
		-- tokens with the same owner timestamp. `>=` would let them adopt each
		-- other's copy forever and churn the Cooldowns tab.
		deliver(1234, 500, NOW + 7200)
		deliver(9999, 500, NOW + 1)
		assert.equal(NOW + 7200, gdb.cooldowns[OWNER][17187])
	end)

	it("upgrades a legacy copy to the authoritative absolute one", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 10 }
		gdb.hashes["cooldown:" .. OWNER] = { hash = 111, updatedAt = 900 }  -- no .abs
		deliver(222, 1, NOW + 7200)
		assert.equal(NOW + 7200, gdb.cooldowns[OWNER][17187])
	end)

	it("never lets a peer overwrite our OWN cooldowns", function()
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		deliver(4321, 99999, NOW + 99999, ME)
		assert.equal(NOW + 60, gdb.cooldowns[ME][17187])
	end)
end)

describe("OnGuildDataReceived — subhashes diff", function()
	local function subhashes(map, parent)
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER, type = "subhashes", parent = parent or "guild:cooldowns",
			subhashes = map,
		})
	end

	it("asks only for the leaves whose hash differs", function()
		gdb.hashes["cooldown:A"] = { hash = 1, updatedAt = 10, abs = true }
		gdb.cooldowns.A = { [17187] = NOW }
		subhashes({
			["cooldown:A"] = { hash = 1, updatedAt = 10 },   -- same
			["cooldown:B"] = { hash = 2, updatedAt = 10 },   -- new to us
		})
		assert.equal(1, #DS.requests)
		assert.same({ "cooldown:B" }, DS.requests[1].req.keys)
	end)

	it("stamps -1 for a cooldown we hold NO data for", function()
		-- An orphan hash with a real timestamp would make the owner think our copy
		-- is current, so it stays silent and we never receive the data.
		gdb.hashes["cooldown:B"] = { hash = 7, updatedAt = 5000, abs = true }
		subhashes({ ["cooldown:B"] = { hash = 9, updatedAt = 10 } })
		assert.equal(-1, DS.requests[1].req.stamps["cooldown:B"])
	end)

	it("stamps our own updatedAt when we DO hold an authoritative copy", function()
		gdb.cooldowns.B = { [17187] = NOW }
		gdb.hashes["cooldown:B"] = { hash = 7, updatedAt = 5000, abs = true }
		subhashes({ ["cooldown:B"] = { hash = 9, updatedAt = 9000 } })
		assert.equal(5000, DS.requests[1].req.stamps["cooldown:B"])
	end)

	it("does not chase a cooldown copy that is no newer than ours", function()
		gdb.cooldowns.B = { [17187] = NOW }
		gdb.hashes["cooldown:B"] = { hash = 7, updatedAt = 5000, abs = true }
		subhashes({ ["cooldown:B"] = { hash = 9, updatedAt = 4000 } })
		assert.equal(0, #DS.requests)
	end)

	it("does not chase an equal-or-older professions snapshot", function()
		gdb.hashes["professions:B"] = { hash = 7, updatedAt = 5000 }
		subhashes({ ["professions:B"] = { hash = 9, updatedAt = 5000 } }, "guild:professions")
		assert.equal(0, #DS.requests)
	end)

	it("ignores a legacy skills leaf once we hold the owner's professions snapshot", function()
		gdb.lastScan.B = { professions = 4000 }
		subhashes({ ["skills:B"] = { hash = 9, updatedAt = 9000 } }, "guild:skills")
		assert.equal(0, #DS.requests)
	end)

	it("completes the parent session so the P2P slot frees up", function()
		subhashes({}, "guild:cooldowns")
		assert.equal("guild:cooldowns", DS.completed[1].key)
	end)

	it("stays silent when the peer has gone offline mid-exchange", function()
		env.roster({ { name = "Testchar", isOnline = true } })
		S.GuildRoster = ns.Scanner.GuildRoster
		subhashes({ ["cooldown:B"] = { hash = 2, updatedAt = 10 } })
		assert.equal(0, #DS.requests)
	end)
end)

describe("OnGuildDataReceived — player subhashes", function()
	it("pulls the differing players, newest scan first", function()
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { [OWNER] = ns:GetCurrentGuildTag() } } }
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER, type = "player-subhashes", profId = ALCHEMY,
			players = {
				[OWNER]            = { h = 999999, ts = 100 },   -- differs
				["Late-Testrealm"] = { h = 888888, ts = 900 },   -- differs, newer
			},
		})
		assert.equal(1, #DS.requests)
		assert.same({ "Late-Testrealm", OWNER }, DS.requests[1].req.players)
	end)

	it("completes the profession's parent session", function()
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER, type = "player-subhashes", profId = ALCHEMY, players = {},
		})
		assert.equal("crafters:" .. ALCHEMY, DS.completed[1].key)
	end)

	it("stays silent when the peer has gone offline mid-exchange", function()
		-- The third copy of the online gate. It had never executed: only the
		-- leaf-data site above was asserted, and this one and onSyncAccepted
		-- were taken on faith because they read the same. They are now ONE
		-- function, and this is the spec that says so for this site.
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { [OWNER] = ns:GetCurrentGuildTag() } } }
		env.roster({ { name = "Testchar", isOnline = true } })
		S.GuildRoster = ns.Scanner.GuildRoster
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER, type = "player-subhashes", profId = ALCHEMY,
			players = { [OWNER] = { h = 999999, ts = 100 } },
		})
		assert.equal(0, #DS.requests)
	end)
end)

--- The gate itself, because it now has one implementation and three call sites.
--- Every outbound RequestData is behind it, so a wrong answer here is either
--- "sync stops working" or "we send to someone who left".
describe("Scanner:PeerIsOffline", function()
	it("is true for a guildmate the roster reports offline", function()
		env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = false } })
		S.GuildRoster = ns.Scanner.GuildRoster
		assert.is_true(S:PeerIsOffline("Bob"))
	end)

	it("is false for one it reports online", function()
		env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
		S.GuildRoster = ns.Scanner.GuildRoster
		assert.is_false(S:PeerIsOffline("Bob"))
	end)

	it("is FALSE with no roster library, which is the load-bearing case", function()
		-- Knowing nothing about who is online must not be read as "everyone is
		-- offline": that would refuse every send and disable sync entirely,
		-- rather than protect it. This is why the gate is a named function and
		-- not an inline `and` -- the nil case is a decision, not an accident.
		S.GuildRoster = nil
		assert.is_false(S:PeerIsOffline("Bob"))
	end)

	it("answers a boolean, never a nil, so a caller can assert on it", function()
		S.GuildRoster = nil
		assert.equal("boolean", type(S:PeerIsOffline("Bob")))
	end)
end)
