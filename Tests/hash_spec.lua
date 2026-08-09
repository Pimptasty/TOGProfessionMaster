-- HashManager — the leaf-hash cache behind the hash-then-fetch sync protocol.
--
-- The invariant this module exists to hold, and that these specs are really
-- about: a leaf hash is MINTED BY ITS OWNER and ADOPTED VERBATIM by everyone
-- else. A receiver that recomputes a hash from its own copy of the data
-- computes a different number (its clock, its merge order), the roll-up never
-- converges, and peers re-request the same leaf forever. That is the cooldown
-- drift disaster; `StoreDelivered*` vs `Invalidate*` is the line between the
-- two, and the roll-up composing STORED hashes (never re-hashing data) is what
-- keeps an adopted token intact through a relay.
--
-- Hashing uses the REAL DeltaSync-1.0 from the sibling addon — stubbing it
-- would make every convergence assertion pass without testing anything.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local HashManager, DS

setup(function()
	env.boot()
	HashManager = env.loadModule("Modules/HashManager.lua").HashManager
	DS = env.deltaSync()
end)

before_each(function()
	env.install()
end)

-- A gdb with one character's data across every leaf type.
local function populated()
	local gdb = env.newGdb()
	gdb.cooldowns["Alice-Realm"] = { [17187] = 5000 }
	gdb.altClaims["Alice-Realm"] = { "Alice-Realm", "Alt-Realm" }
	gdb.skills["Alice-Realm"] = {
		[171] = { skillRank = 300, skillMax = 300 },   -- Alchemy   (crafting)
		[182] = { skillRank = 225, skillMax = 300 },   -- Herbalism (gathering)
	}
	gdb.recipes[171] = { [2330] = { crafters = { ["Alice-Realm"] = true } } }
	gdb.lastScan["Alice-Realm"] = {
		cooldowns = 100, accountchars = 110, skills = 120, professions = 130, [171] = 140,
	}
	return gdb
end

describe("leaf hashes", function()
	it("hash the same data to the same number on any client", function()
		local a, b = populated(), populated()
		assert.equal(HashManager:ComputeCharCooldownHash(DS, a, "Alice-Realm"),
			HashManager:ComputeCharCooldownHash(DS, b, "Alice-Realm"))
		assert.equal(HashManager:ComputeCraftersHash(DS, a, 171),
			HashManager:ComputeCraftersHash(DS, b, 171))
	end)

	it("change when the data changes", function()
		local gdb = populated()
		local before = HashManager:ComputeCharCooldownHash(DS, gdb, "Alice-Realm")
		gdb.cooldowns["Alice-Realm"][28596] = 6000
		assert.is_true(before ~= HashManager:ComputeCharCooldownHash(DS, gdb, "Alice-Realm"))
	end)

	it("treat an unknown character as empty rather than erroring", function()
		local gdb = env.newGdb()
		assert.equal(DS:ComputeHash({}), HashManager:ComputeCharCooldownHash(DS, gdb, "Nobody-Realm"))
		assert.equal(DS:ComputeHash({}), HashManager:ComputeAccountCharsHash(DS, gdb, "Nobody-Realm"))
	end)

	it("split skills: the gathering leaf excludes crafting professions", function()
		local gdb = populated()
		local gathering = HashManager:GetGatheringSkills(gdb, "Alice-Realm")
		assert.same({ ["182"] = { r = 225, m = 300 } }, gathering)
	end)

	it("split skills: the professions leaf carries EVERY profession", function()
		local gdb = populated()
		assert.same({
			["171"] = { r = 300, m = 300 },
			["182"] = { r = 225, m = 300 },
		}, HashManager:GetProfessionSnapshot(gdb, "Alice-Realm"))
	end)

	it("normalise missing ranks to 0 so a partial scan still hashes deterministically", function()
		local gdb = env.newGdb()
		gdb.skills["Alice-Realm"] = { [182] = {} }
		assert.same({ ["182"] = { r = 0, m = 0 } }, HashManager:GetGatheringSkills(gdb, "Alice-Realm"))
	end)

	it("ignore non-table skill rows left by older schemas", function()
		local gdb = env.newGdb()
		gdb.skills["Alice-Realm"] = { [182] = 225 }
		assert.same({}, HashManager:GetGatheringSkills(gdb, "Alice-Realm"))
		assert.same({}, HashManager:GetProfessionSnapshot(gdb, "Alice-Realm"))
	end)

	it("exclude crafterless recipes from the crafters hash", function()
		-- An empty crafter set drifts between peers (one pruned it, one hasn't),
		-- so including it would move the hash without the data differing.
		local withEmpty = populated()
		withEmpty.recipes[171][2331] = { crafters = {} }
		assert.equal(HashManager:ComputeCraftersHash(DS, populated(), 171),
			HashManager:ComputeCraftersHash(DS, withEmpty, 171))
	end)

	it("ignore falsy crafter entries", function()
		local gdb = populated()
		gdb.recipes[171][2330].crafters["Ghost-Realm"] = false
		assert.equal(HashManager:ComputeCraftersHash(DS, populated(), 171),
			HashManager:ComputeCraftersHash(DS, gdb, 171))
	end)

	it("hash an absent profession as empty", function()
		assert.equal(DS:ComputeHash({}), HashManager:ComputeCraftersHash(DS, env.newGdb(), 999))
	end)
end)

describe("GetProfessionPlayerSubhashes", function()
	it("buckets a profession's recipes by crafter and stamps each with that player's scan time", function()
		local gdb = populated()
		gdb.recipes[171][2331] = { crafters = { ["Bob-Realm"] = true } }
		gdb.lastScan["Bob-Realm"] = { [171] = 200 }

		local subs = HashManager:GetProfessionPlayerSubhashes(DS, gdb, 171)
		assert.equal(140, subs["Alice-Realm"].ts)
		assert.equal(200, subs["Bob-Realm"].ts)
		-- Different recipe sets → different hashes.
		assert.is_true(subs["Alice-Realm"].h ~= subs["Bob-Realm"].h)
	end)

	it("stamps 0 when the crafter has no recorded scan for the profession", function()
		local gdb = populated()
		gdb.lastScan["Alice-Realm"] = nil
		assert.equal(0, HashManager:GetProfessionPlayerSubhashes(DS, gdb, 171)["Alice-Realm"].ts)
	end)

	it("skips falsy crafters and returns empty for an unknown profession", function()
		local gdb = populated()
		gdb.recipes[171][2330].crafters["Ghost-Realm"] = false
		assert.is_nil(HashManager:GetProfessionPlayerSubhashes(DS, gdb, 171)["Ghost-Realm"])
		assert.same({}, HashManager:GetProfessionPlayerSubhashes(DS, gdb, 999))
	end)
end)

describe("targeted invalidation", function()
	it("writes the leaf and refreshes its roll-up", function()
		local gdb = populated()
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		assert.equal(100, gdb.hashes["cooldown:Alice-Realm"].updatedAt)
		assert.is_true(gdb.hashes["guild:cooldowns"] ~= nil)
	end)

	it("is a no-op on recompute, so an unchanged leaf never re-broadcasts", function()
		local gdb = populated()
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		local entry = gdb.hashes["cooldown:Alice-Realm"]
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		-- Same TABLE, not merely an equal one: setEntry must not rewrite.
		assert.is_true(entry == gdb.hashes["cooldown:Alice-Realm"])
	end)

	it("stamps each leaf from its own content-derived scan time, never the clock", function()
		local gdb = populated()
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		HashManager:InvalidateAccountChars(DS, gdb, "Alice-Realm")
		HashManager:InvalidateCharSkills(DS, gdb, "Alice-Realm")
		HashManager:InvalidateCharProfessions(DS, gdb, "Alice-Realm")
		assert.equal(100, gdb.hashes["cooldown:Alice-Realm"].updatedAt)
		assert.equal(110, gdb.hashes["accountchars:Alice-Realm"].updatedAt)
		assert.equal(120, gdb.hashes["skills:Alice-Realm"].updatedAt)
		assert.equal(130, gdb.hashes["professions:Alice-Realm"].updatedAt)
	end)

	it("falls back to 0 when no scan time is recorded", function()
		local gdb = populated()
		gdb.lastScan = nil
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		assert.equal(0, gdb.hashes["cooldown:Alice-Realm"].updatedAt)
	end)

	it("stamps crafters: with the freshest contributing scan", function()
		local gdb = populated()
		gdb.recipes[171][2331] = { crafters = { ["Bob-Realm"] = true } }
		gdb.lastScan["Bob-Realm"] = { [171] = 400 }
		HashManager:InvalidateProfession(DS, gdb, 171)
		assert.equal(400, gdb.hashes["crafters:171"].updatedAt)
	end)

	it("stamps crafters: 0 for a profession nobody has scanned", function()
		local gdb = env.newGdb()
		HashManager:InvalidateProfession(DS, gdb, 202)
		assert.equal(0, gdb.hashes["crafters:202"].updatedAt)
	end)

	it("creates gdb.hashes when it is missing", function()
		local gdb = populated()
		gdb.hashes = nil
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		assert.is_true(gdb.hashes["cooldown:Alice-Realm"] ~= nil)
	end)
end)

describe("owner-authoritative adoption", function()
	it("adopts a delivered cooldown token VERBATIM instead of recomputing it", function()
		local gdb = populated()
		-- The owner's token; our own data differs (a relay's copy always can).
		assert.is_true(HashManager:StoreDeliveredCooldownLeaf(DS, gdb, "Alice-Realm", 424242, 900, true))
		assert.equal(424242, gdb.hashes["cooldown:Alice-Realm"].hash)
		assert.equal(900, gdb.hashes["cooldown:Alice-Realm"].updatedAt)
		assert.is_true(gdb.hashes["cooldown:Alice-Realm"].abs)
	end)

	it("records the legacy/absolute format flag even when the write is a no-op", function()
		local gdb = populated()
		HashManager:StoreDeliveredCooldownLeaf(DS, gdb, "Alice-Realm", 424242, 900, true)
		assert.is_false(HashManager:StoreDeliveredCooldownLeaf(DS, gdb, "Alice-Realm", 424242, 900, false))
		assert.is_nil(gdb.hashes["cooldown:Alice-Realm"].abs)
	end)

	it("defaults a missing delivered timestamp to 0", function()
		local gdb = populated()
		HashManager:StoreDeliveredCooldownLeaf(DS, gdb, "Alice-Realm", 1, nil, false)
		assert.equal(0, gdb.hashes["cooldown:Alice-Realm"].updatedAt)
		HashManager:StoreDeliveredAccountCharsLeaf(DS, gdb, "Alice-Realm", 2, nil)
		assert.equal(0, gdb.hashes["accountchars:Alice-Realm"].updatedAt)
		HashManager:StoreDeliveredProfessionsLeaf(DS, gdb, "Alice-Realm", 3, nil)
		assert.equal(0, gdb.hashes["professions:Alice-Realm"].updatedAt)
	end)

	it("adopts accountchars and professions tokens verbatim too", function()
		local gdb = populated()
		assert.is_true(HashManager:StoreDeliveredAccountCharsLeaf(DS, gdb, "Alice-Realm", 111, 900))
		assert.is_true(HashManager:StoreDeliveredProfessionsLeaf(DS, gdb, "Alice-Realm", 222, 901))
		assert.equal(111, gdb.hashes["accountchars:Alice-Realm"].hash)
		assert.equal(222, gdb.hashes["professions:Alice-Realm"].hash)
		-- Re-adopting the same token is a no-op, so a relay can't churn.
		assert.is_false(HashManager:StoreDeliveredAccountCharsLeaf(DS, gdb, "Alice-Realm", 111, 900))
		assert.is_false(HashManager:StoreDeliveredProfessionsLeaf(DS, gdb, "Alice-Realm", 222, 901))
	end)

	it("gives a relay the SAME roll-up as the owner — the convergence invariant", function()
		-- Owner mints from its own data.
		local owner = populated()
		HashManager:InvalidateCharCooldowns(DS, owner, "Alice-Realm")
		local token = owner.hashes["cooldown:Alice-Realm"].hash
		local ts    = owner.hashes["cooldown:Alice-Realm"].updatedAt

		-- Relay holds a DIFFERENT local copy of the same character's cooldowns
		-- (mid-merge, or reconstructed against its own clock) and adopts.
		local relay = env.newGdb()
		relay.cooldowns["Alice-Realm"] = { [17187] = 999999 }
		HashManager:StoreDeliveredCooldownLeaf(DS, relay, "Alice-Realm", token, ts, true)

		assert.equal(owner.hashes["guild:cooldowns"].hash, relay.hashes["guild:cooldowns"].hash)
		assert.equal(owner.hashes["guild:cooldowns"].updatedAt, relay.hashes["guild:cooldowns"].updatedAt)
	end)
end)

describe("roll-ups", function()
	it("take the newest child timestamp", function()
		local gdb = populated()
		gdb.cooldowns["Bob-Realm"] = { [17187] = 7000 }
		gdb.lastScan["Bob-Realm"] = { cooldowns = 500 }
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		HashManager:InvalidateCharCooldowns(DS, gdb, "Bob-Realm")
		assert.equal(500, gdb.hashes["guild:cooldowns"].updatedAt)
	end)

	it("cover each leaf family", function()
		local gdb = populated()
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		HashManager:InvalidateAccountChars(DS, gdb, "Alice-Realm")
		HashManager:InvalidateCharSkills(DS, gdb, "Alice-Realm")
		HashManager:InvalidateCharProfessions(DS, gdb, "Alice-Realm")
		-- Driven from the addon's OWN prefix→key map rather than a copy of it, so
		-- adding a fifth leaf family cannot leave this assertion behind. Audit
		-- finding 5: the four hardcoded prefixes that used to live in
		-- HashManager were a second copy of exactly this list.
		local families = HashManager:RollupFamilies()
		local checked  = 0
		for prefix, rollupKey in pairs(families) do
			assert.equal(HashManager:ComposeRollup(DS, gdb, prefix),
				gdb.hashes[rollupKey].hash,
				"stored roll-up differs from a fresh composition for " .. prefix)
			checked = checked + 1
		end
		-- A loop over an empty table is a test that asserts nothing.
		assert.equal(4, checked)
	end)

	it("rejects a prefix that is not a known leaf family", function()
		-- The typo case. Four hardcoded wrappers could not have caught this;
		-- one function driven by the map returns an error instead of nil.
		assert.has_error(function()
			HashManager:ComposeRollup(DS, populated(), "cooldowns:")
		end)
	end)

	it("do not confuse one prefix with another", function()
		-- "cooldown:" must not sweep up "cooldowns-of-something-else" style keys.
		local gdb = env.newGdb()
		gdb.hashes["cooldown:A"]     = { hash = 1, updatedAt = 10 }
		gdb.hashes["accountchars:A"] = { hash = 2, updatedAt = 20 }
		gdb.hashes["skills:A"]       = { hash = 3, updatedAt = 30 }
		gdb.hashes["professions:A"]  = { hash = 4, updatedAt = 40 }
		local cd = HashManager:ComposeRollup(DS, gdb, "cooldown:")
		assert.equal(DS:ComputeStructuredHash({ ["cooldown:A"] = 1 }), cd)
	end)
end)

describe("DropOrphanLeaf", function()
	it("removes the leaf and refreshes the matching roll-up", function()
		local gdb = populated()
		HashManager:InvalidateCharCooldowns(DS, gdb, "Alice-Realm")
		local before = gdb.hashes["guild:cooldowns"].hash
		assert.is_true(HashManager:DropOrphanLeaf(DS, gdb, "cooldown:Alice-Realm"))
		assert.is_nil(gdb.hashes["cooldown:Alice-Realm"])
		assert.is_true(before ~= gdb.hashes["guild:cooldowns"].hash)
	end)

	it("handles every leaf family that has a roll-up", function()
		local gdb = populated()
		HashManager:InvalidateAccountChars(DS, gdb, "Alice-Realm")
		HashManager:InvalidateCharSkills(DS, gdb, "Alice-Realm")
		HashManager:InvalidateCharProfessions(DS, gdb, "Alice-Realm")
		assert.is_true(HashManager:DropOrphanLeaf(DS, gdb, "accountchars:Alice-Realm"))
		assert.is_true(HashManager:DropOrphanLeaf(DS, gdb, "skills:Alice-Realm"))
		assert.is_true(HashManager:DropOrphanLeaf(DS, gdb, "professions:Alice-Realm"))
		assert.is_nil(gdb.hashes["accountchars:Alice-Realm"])
		assert.is_nil(gdb.hashes["skills:Alice-Realm"])
		assert.is_nil(gdb.hashes["professions:Alice-Realm"])
	end)

	it("drops a crafters leaf, which has no roll-up", function()
		local gdb = populated()
		HashManager:InvalidateProfession(DS, gdb, 171)
		assert.is_true(HashManager:DropOrphanLeaf(DS, gdb, "crafters:171"))
		assert.is_nil(gdb.hashes["crafters:171"])
	end)

	it("reports false for a leaf we do not hold", function()
		local gdb = populated()
		assert.is_false(HashManager:DropOrphanLeaf(DS, gdb, "cooldown:Nobody-Realm"))
		gdb.hashes = nil
		assert.is_false(HashManager:DropOrphanLeaf(DS, gdb, "cooldown:Alice-Realm"))
	end)
end)

describe("RebuildOnFirstLoad", function()
	it("strips leaf keys from retired schema versions", function()
		local gdb = populated()
		gdb.hashes["recipes:171"]    = { hash = 1, updatedAt = 1 }
		gdb.hashes["recipemeta:171"] = { hash = 2, updatedAt = 2 }
		gdb.hashes["guild:recipes"]  = { hash = 3, updatedAt = 3 }
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_nil(gdb.hashes["recipes:171"])
		assert.is_nil(gdb.hashes["recipemeta:171"])
		assert.is_nil(gdb.hashes["guild:recipes"])
	end)

	it("builds the leaves the data implies", function()
		local gdb = populated()
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_true(gdb.hashes["cooldown:Alice-Realm"] ~= nil)
		assert.is_true(gdb.hashes["accountchars:Alice-Realm"] ~= nil)
		assert.is_true(gdb.hashes["crafters:171"] ~= nil)
		assert.is_true(gdb.hashes["skills:Alice-Realm"] ~= nil)
		assert.is_true(gdb.hashes["professions:Alice-Realm"] ~= nil)
	end)

	it("does not fabricate a skills leaf for a character with only crafting skills", function()
		local gdb = env.newGdb()
		gdb.skills["Crafter-Realm"] = { [171] = { skillRank = 300, skillMax = 300 } }
		gdb.lastScan["Crafter-Realm"] = { professions = 50 }
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_nil(gdb.hashes["skills:Crafter-Realm"])
	end)

	it("does NOT mint a professions leaf for a character we only relayed skills for", function()
		-- No authoritative snapshot time → no leaf. Minting one advertises an
		-- orphan hash we can't serve, and once adopted elsewhere its truthy
		-- lastScan.professions makes peers ignore that character's real data.
		local gdb = env.newGdb()
		gdb.skills["Relayed-Realm"] = { [171] = { skillRank = 300, skillMax = 300 } }
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_nil(gdb.hashes["professions:Relayed-Realm"])
	end)

	it("purges the fabricated updatedAt-0 professions leaves an earlier build wrote", function()
		local gdb = populated()
		gdb.hashes["professions:Ghost-Realm"] = { hash = 7, updatedAt = 0 }
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_nil(gdb.hashes["professions:Ghost-Realm"])
	end)

	it("clears the bogus lastScan.professions == 0 those leaves left behind", function()
		-- 0 is truthy in Lua, so it read as "we have an authoritative snapshot".
		local gdb = populated()
		gdb.lastScan["Ghost-Realm"] = { professions = 0 }
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_nil(gdb.lastScan["Ghost-Realm"].professions)
	end)

	it("sweeps orphan hashes we hold no data for", function()
		local gdb = populated()
		gdb.hashes["cooldown:Ghost-Realm"]     = { hash = 1, updatedAt = 10 }
		gdb.hashes["skills:Ghost-Realm"]       = { hash = 2, updatedAt = 10 }
		gdb.hashes["accountchars:Ghost-Realm"] = { hash = 3, updatedAt = 10 }
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_nil(gdb.hashes["cooldown:Ghost-Realm"])
		assert.is_nil(gdb.hashes["skills:Ghost-Realm"])
		assert.is_nil(gdb.hashes["accountchars:Ghost-Realm"])
	end)

	it("always leaves all four roll-ups present", function()
		local gdb = populated()
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_true(gdb.hashes["guild:cooldowns"] ~= nil)
		assert.is_true(gdb.hashes["guild:accountchars"] ~= nil)
		assert.is_true(gdb.hashes["guild:skills"] ~= nil)
		assert.is_true(gdb.hashes["guild:professions"] ~= nil)
	end)

	it("is idempotent — a second pass changes nothing", function()
		local gdb = populated()
		HashManager:RebuildOnFirstLoad(DS, gdb)
		local snapshot = {}
		for k, e in pairs(gdb.hashes) do snapshot[k] = { e.hash, e.updatedAt } end
		HashManager:RebuildOnFirstLoad(DS, gdb)
		for k, e in pairs(gdb.hashes) do
			assert.same(snapshot[k], { e.hash, e.updatedAt })
		end
	end)

	it("copes with an empty database", function()
		local gdb = env.newGdb()
		gdb.cooldowns, gdb.altClaims, gdb.recipes, gdb.skills, gdb.lastScan = nil, nil, nil, nil, nil
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_true(gdb.hashes["guild:cooldowns"] ~= nil)
	end)
end)

describe("broadcast maps", function()
	it("copy entries per family without leaking the stored tables", function()
		local gdb = populated()
		HashManager:RebuildOnFirstLoad(DS, gdb)
		local map = HashManager:GetCooldownLevelMap(gdb)
		assert.is_true(map["cooldown:Alice-Realm"] ~= nil)
		assert.is_true(map["cooldown:Alice-Realm"] ~= gdb.hashes["cooldown:Alice-Realm"])
		map["cooldown:Alice-Realm"].hash = -1
		assert.is_true(gdb.hashes["cooldown:Alice-Realm"].hash ~= -1)
	end)

	it("expose one map per leaf family", function()
		local gdb = populated()
		HashManager:RebuildOnFirstLoad(DS, gdb)
		assert.is_true(HashManager:GetAccountCharsLevelMap(gdb)["accountchars:Alice-Realm"] ~= nil)
		assert.is_true(HashManager:GetSkillsLevelMap(gdb)["skills:Alice-Realm"] ~= nil)
		assert.is_true(HashManager:GetProfessionsLevelMap(gdb)["professions:Alice-Realm"] ~= nil)
		assert.is_true(HashManager:GetCraftersLevelMap(gdb)["crafters:171"] ~= nil)
	end)

	it("keep per-character leaves OUT of the L0 broadcast", function()
		-- L0 carries crafters + roll-ups only; per-character leaves are drilled
		-- down to on a roll-up mismatch, which is what keeps the broadcast small.
		local gdb = populated()
		HashManager:RebuildOnFirstLoad(DS, gdb)
		local l0 = HashManager:GetL0BroadcastMap(gdb)
		assert.is_true(l0["crafters:171"] ~= nil)
		assert.is_true(l0["guild:cooldowns"] ~= nil)
		assert.is_true(l0["guild:accountchars"] ~= nil)
		assert.is_true(l0["guild:skills"] ~= nil)
		assert.is_true(l0["guild:professions"] ~= nil)
		assert.is_nil(l0["cooldown:Alice-Realm"])
		assert.is_nil(l0["skills:Alice-Realm"])
	end)

	it("omit roll-ups that have not been computed yet", function()
		assert.same({}, HashManager:GetL0BroadcastMap(env.newGdb()))
	end)
end)

describe("PadMissingProfessionPlaceholders", function()
	it("adds an empty-hash placeholder for every craftable profession we hold nothing for", function()
		-- Without the placeholder the OFFER protocol never fires for a key absent
		-- from our hash list, so a player with no Engineering data would never be
		-- offered any by a guildmate.
		local map = {}
		HashManager:PadMissingProfessionPlaceholders(DS, map)
		local ns = env.boot()
		for profId in pairs(ns.CRAFTING_PROFS) do
			local available = (not ns.IsProfessionAvailable) or ns.IsProfessionAvailable(profId)
			if available then
				assert.equal(DS:ComputeHash({}), map["crafters:" .. profId].hash)
				assert.equal(0, map["crafters:" .. profId].updatedAt)
			end
		end
	end)

	it("never overwrites a real hash with a placeholder", function()
		local map = { ["crafters:171"] = { hash = 999, updatedAt = 50 } }
		HashManager:PadMissingProfessionPlaceholders(DS, map)
		assert.equal(999, map["crafters:171"].hash)
		assert.equal(50, map["crafters:171"].updatedAt)
	end)

	it("skips professions this client version cannot have", function()
		local ns = env.boot()
		local prev = ns.IsProfessionAvailable
		ns.IsProfessionAvailable = function(profId) return profId ~= 755 end   -- no Jewelcrafting
		local map = {}
		HashManager:PadMissingProfessionPlaceholders(DS, map)
		ns.IsProfessionAvailable = prev
		assert.is_nil(map["crafters:755"])
		assert.is_true(map["crafters:171"] ~= nil)
	end)

	it("does nothing without a sync host", function()
		local map = {}
		HashManager:PadMissingProfessionPlaceholders(nil, map)
		assert.same({}, map)
	end)
end)

describe("HasContent", function()
	it("serves a roll-up when any underlying data exists", function()
		local gdb = populated()
		assert.is_true(HashManager:HasContent(gdb, "guild:cooldowns"))
		assert.is_true(HashManager:HasContent(gdb, "guild:accountchars"))
		assert.is_true(HashManager:HasContent(gdb, "guild:skills"))
		assert.is_true(HashManager:HasContent(gdb, "guild:professions"))
	end)

	it("refuses a roll-up with nothing behind it", function()
		local gdb = env.newGdb()
		assert.is_false(HashManager:HasContent(gdb, "guild:cooldowns"))
		assert.is_false(HashManager:HasContent(gdb, "guild:accountchars"))
		assert.is_false(HashManager:HasContent(gdb, "guild:skills"))
		assert.is_false(HashManager:HasContent(gdb, "guild:professions"))
	end)

	it("answers with a real boolean, never nil, whichever table is absent", function()
		-- `a and b ~= nil` returns NIL when `a` is nil. A predicate that answers
		-- "no" as false in one branch and nil in another breaks any caller
		-- comparing against false, and serialises differently over the wire.
		local bare = {}
		for _, key in ipairs({ "guild:cooldowns", "guild:accountchars", "guild:skills",
		                       "guild:professions", "cooldown:X", "accountchars:X",
		                       "professions:X", "skills:X", "crafters:171" }) do
			assert.equal("boolean", type(HashManager:HasContent(bare, key)))
		end
	end)

	it("refuses a roll-up it does not know", function()
		assert.is_false(HashManager:HasContent(populated(), "guild:somethingelse"))
	end)

	it("serves per-character leaves it holds data for", function()
		local gdb = populated()
		assert.is_true(HashManager:HasContent(gdb, "cooldown:Alice-Realm"))
		assert.is_true(HashManager:HasContent(gdb, "accountchars:Alice-Realm"))
		assert.is_true(HashManager:HasContent(gdb, "professions:Alice-Realm"))
		assert.is_true(HashManager:HasContent(gdb, "skills:Alice-Realm"))
		assert.is_true(HashManager:HasContent(gdb, "crafters:171"))
	end)

	it("refuses per-character leaves it holds nothing for", function()
		local gdb = populated()
		assert.is_false(HashManager:HasContent(gdb, "cooldown:Nobody-Realm"))
		assert.is_false(HashManager:HasContent(gdb, "accountchars:Nobody-Realm"))
		assert.is_false(HashManager:HasContent(gdb, "professions:Nobody-Realm"))
		assert.is_false(HashManager:HasContent(gdb, "skills:Nobody-Realm"))
		assert.is_false(HashManager:HasContent(gdb, "crafters:202"))
	end)

	it("refuses a crafters leaf whose recipes all lost their crafters", function()
		local gdb = populated()
		gdb.recipes[171][2330].crafters = {}
		assert.is_false(HashManager:HasContent(gdb, "crafters:171"))
	end)

	it("refuses a malformed crafters key", function()
		assert.is_false(HashManager:HasContent(populated(), "crafters:notanumber"))
	end)

	it("refuses an empty alt claim", function()
		local gdb = populated()
		gdb.altClaims["Alice-Realm"] = {}
		assert.is_false(HashManager:HasContent(gdb, "accountchars:Alice-Realm"))
	end)

	it("refuses the retired recipemeta leaf so peers stop asking", function()
		assert.is_false(HashManager:HasContent(populated(), "recipemeta:171"))
	end)

	it("refuses anything it does not recognise", function()
		assert.is_false(HashManager:HasContent(populated(), "banana:171"))
	end)
end)
