-- The revision-2 hash rollout.
--
-- Revision 1 renders a number and its string form identically — `{v = 1}` and
-- `{v = "1"}` hash the same — so a real difference between two clients can be
-- invisible and the sync is simply skipped. Revision 2 types each scalar.
--
-- Both ship side by side and every comparison picks the highest revision BOTH
-- ends advertise. That is what makes the rollout coordination-free, and it is
-- also the whole risk: get the fallback wrong and a mixed-version guild sees
-- phantom differences and re-syncs the same leaf forever. These specs pin the
-- rules in both directions, including the roll-up composition, which is the one
-- place a half-upgraded set of children could produce an incomparable value.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, HM, S, gdb, DS
local ME    = "Testchar-Testrealm"
local OWNER = "Bob-Testrealm"
local ALCHEMY = 171
local NOW = 1000000

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	HM = env.loadModule("Modules/HashManager.lua").HashManager
	S  = env.loadModule("Scanner.lua").Scanner
end)

before_each(function()
	env.install()
	env.serverTime = NOW
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({ [ALCHEMY] = { [2330] = { name = "Minor Healing Potion", craftedItemId = 118 } } })
	DS = env.deltaSync()
	S.DS = DS
end)

describe("the collision revision 2 exists to fix", function()
	it("is real: revision 1 cannot tell 1 from \"1\"", function()
		assert.equal(DS:ComputeHash({ v = 1 }), DS:ComputeHash({ v = "1" }))
	end)

	it("revision 2 can", function()
		assert.is_true(DS:ComputeHashV2({ v = 1 }) ~= DS:ComputeHashV2({ v = "1" }))
	end)
end)

describe("minting", function()
	it("stamps both revisions on a leaf", function()
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		HM:InvalidateCharCooldowns(DS, gdb, ME)
		local e = gdb.hashes["cooldown:" .. ME]
		assert.is_true(e.hash ~= nil)
		assert.is_true(e.hashV2 ~= nil)
	end)

	it("stamps both on every leaf family", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		gdb.altClaims[OWNER] = { OWNER }
		gdb.skills[OWNER]    = { [182] = { skillRank = 1, skillMax = 300 },
		                         [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { [OWNER] = ns:GetCurrentGuildTag() } } }
		HM:InvalidateCharCooldowns(DS, gdb, OWNER)
		HM:InvalidateAccountChars(DS, gdb, OWNER)
		HM:InvalidateCharSkills(DS, gdb, OWNER)
		HM:InvalidateCharProfessions(DS, gdb, OWNER)
		HM:InvalidateProfession(DS, gdb, ALCHEMY)
		for _, key in ipairs({ "cooldown:" .. OWNER, "accountchars:" .. OWNER,
		                       "skills:" .. OWNER, "professions:" .. OWNER,
		                       "crafters:" .. ALCHEMY }) do
			assert.is_true(gdb.hashes[key].hashV2 ~= nil, key .. " carries no hashV2")
		end
	end)

	it("keeps revision 1 byte-identical, so old peers still agree", function()
		-- Revision 1 is frozen and compared against clients we will never update.
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		HM:InvalidateCharCooldowns(DS, gdb, ME)
		assert.equal(DS:ComputeHash(gdb.cooldowns[ME]), gdb.hashes["cooldown:" .. ME].hash)
	end)

	it("falls back to revision 1 alone on a DeltaSync without MakeHashEntry", function()
		local old = { ComputeHash = function(_, t) return DS:ComputeHash(t) end,
		              ComputeStructuredHash = function(_, t) return DS:ComputeStructuredHash(t) end }
		gdb.cooldowns[ME] = { [17187] = NOW + 60 }
		HM:InvalidateCharCooldowns(old, gdb, ME)
		local e = gdb.hashes["cooldown:" .. ME]
		assert.is_true(e.hash ~= nil)
		assert.is_nil(e.hashV2)
	end)
end)

describe("roll-up composition", function()
	local function twoOwners()
		gdb.cooldowns.A = { [17187] = NOW + 1 }
		gdb.cooldowns.B = { [17187] = NOW + 2 }
		HM:InvalidateCharCooldowns(DS, gdb, "A")
		HM:InvalidateCharCooldowns(DS, gdb, "B")
	end

	it("carries a V2 roll-up when every child has one", function()
		twoOwners()
		assert.is_true(gdb.hashes["guild:cooldowns"].hashV2 ~= nil)
	end)

	it("drops to V1-only the moment ANY child is V1-only", function()
		-- A roll-up mixing V2 tokens with V1 fallbacks is not comparable to
		-- another client's mix: two clients holding identical data would compute
		-- different V2 roll-ups and re-sync forever. Advertising no V2 makes both
		-- ends fall back to revision 1, which they agree on.
		twoOwners()
		HM:StoreDeliveredCooldownLeaf(DS, gdb, "C", 4242, 500, true, nil)  -- old peer
		assert.is_nil(gdb.hashes["guild:cooldowns"].hashV2)
		assert.is_true(gdb.hashes["guild:cooldowns"].hash ~= nil)
	end)

	it("upgrades itself once the V1-only child is replaced", function()
		twoOwners()
		HM:StoreDeliveredCooldownLeaf(DS, gdb, "C", 4242, 500, true, nil)
		assert.is_nil(gdb.hashes["guild:cooldowns"].hashV2)
		-- The owner upgrades and re-mints, carrying a V2 token this time.
		HM:StoreDeliveredCooldownLeaf(DS, gdb, "C", 5555, 600, true, 7777)
		assert.is_true(gdb.hashes["guild:cooldowns"].hashV2 ~= nil)
	end)

	it("composes the roll-up from STORED child tokens, never by re-hashing", function()
		-- The owner-authoritative rule: an adopted token must reach the roll-up
		-- exactly as its owner minted it.
		gdb.cooldowns.A = { [17187] = 999999 }         -- our copy differs
		HM:StoreDeliveredCooldownLeaf(DS, gdb, "A", 1234, 500, true, 5678)
		local mine = gdb.hashes["guild:cooldowns"]

		local other = env.newGdb()
		other.cooldowns.A = { [17187] = 111111 }        -- a different local copy
		HM:StoreDeliveredCooldownLeaf(DS, other, "A", 1234, 500, true, 5678)
		assert.equal(mine.hash,   other.hashes["guild:cooldowns"].hash)
		assert.equal(mine.hashV2, other.hashes["guild:cooldowns"].hashV2)
	end)
end)

describe("on the wire", function()
	it("ships the V2 token with the leaf", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		HM:InvalidateCharCooldowns(DS, gdb, OWNER)
		local leaf = S:BuildLeafPayload("cooldown:" .. OWNER).leaves["cooldown:" .. OWNER]
		assert.equal(gdb.hashes["cooldown:" .. OWNER].hashV2, leaf.hashV2)
	end)

	it("ships no V2 for a leaf that has none", function()
		HM:StoreDeliveredCooldownLeaf(DS, gdb, OWNER, 4242, 500, true, nil)
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		local leaf = S:BuildLeafPayload("cooldown:" .. OWNER).leaves["cooldown:" .. OWNER]
		assert.is_nil(leaf.hashV2)
	end)

	it("adopts a delivered V2 token verbatim", function()
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER,
			leaves = { ["cooldown:" .. OWNER] = {
				data = { [17187] = NOW + 60 }, abs = 1,
				hash = 1234, hashV2 = 5678, updatedAt = 500,
			} },
		})
		local e = gdb.hashes["cooldown:" .. OWNER]
		assert.equal(1234, e.hash)
		assert.equal(5678, e.hashV2)
	end)

	it("carries both revisions in the broadcast maps", function()
		gdb.cooldowns[OWNER] = { [17187] = NOW + 60 }
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { [OWNER] = ns:GetCurrentGuildTag() } } }
		HM:InvalidateCharCooldowns(DS, gdb, OWNER)
		HM:InvalidateProfession(DS, gdb, ALCHEMY)
		assert.is_true(HM:GetCooldownLevelMap(gdb)["cooldown:" .. OWNER].hashV2 ~= nil)
		local l0 = HM:GetL0BroadcastMap(gdb)
		assert.is_true(l0["crafters:" .. ALCHEMY].hashV2 ~= nil)
		assert.is_true(l0["guild:cooldowns"].hashV2 ~= nil)
	end)

	it("gives the profession placeholder both revisions too", function()
		local map = {}
		HM:PadMissingProfessionPlaceholders(DS, map)
		local ph = map["crafters:" .. ALCHEMY]
		assert.equal(DS:ComputeHash({}), ph.hash)
		assert.equal(DS:ComputeHashV2({}), ph.hashV2)
	end)
end)

describe("comparison picks the highest revision both ends advertise", function()
	local requested

	local function subhashes(peerEntry)
		requested = nil
		S.DS = {
			RequestData = function(_, _, req) requested = req.keys end,
			p2p = { OnItemCompleted = function() end },
			ComputeHash = function(_, t) return DS:ComputeHash(t) end,
			ComputeStructuredHash = function(_, t) return DS:ComputeStructuredHash(t) end,
			MakeHashEntry = function(_, t, u) return DS:MakeHashEntry(t, u) end,
			ComputeHashV2 = function(_, t) return DS:ComputeHashV2(t) end,
		}
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER, type = "subhashes", parent = "guild:cooldowns",
			subhashes = { ["cooldown:X"] = peerEntry },
		})
		return requested or {}
	end

	before_each(function()
		gdb.cooldowns.X = { [17187] = NOW }
		gdb.hashes["cooldown:X"] = { hash = 100, hashV2 = 200, updatedAt = 10, abs = true }
	end)

	it("two updated peers compare on revision 2", function()
		-- V1 agrees but V2 differs — a real difference revision 1 cannot see.
		assert.same({ "cooldown:X" }, subhashes({ hash = 100, hashV2 = 999, updatedAt = 20 }))
	end)

	it("and stay silent when revision 2 agrees", function()
		-- V1 differs but V2 agrees: revision 2 is the authority for this pair, so
		-- a stale V1 value must NOT trigger a fetch.
		assert.same({}, subhashes({ hash = 999, hashV2 = 200, updatedAt = 20 }))
	end)

	it("falls back to revision 1 against a peer that sends no V2", function()
		assert.same({ "cooldown:X" }, subhashes({ hash = 999, updatedAt = 20 }))
		assert.same({}, subhashes({ hash = 100, updatedAt = 20 }))
	end)

	it("falls back to revision 1 when WE are the V1-only side", function()
		gdb.hashes["cooldown:X"] = { hash = 100, updatedAt = 10, abs = true }
		assert.same({}, subhashes({ hash = 100, hashV2 = 999, updatedAt = 20 }))
	end)

	it("a mixed-version pair holding the same data sees no phantom difference", function()
		-- The failure this rollout has to avoid: an old peer and a new one
		-- offering each other the same leaf forever.
		assert.same({}, subhashes({ hash = 100, updatedAt = 5 }))
	end)
end)
