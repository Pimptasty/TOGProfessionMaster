-- The deferred purge sweep.
--
-- The purge is the only code that DELETES another player's data, so its guards
-- matter more than its deletions: it never runs against an unconfirmed roster,
-- and it re-validates every flag at sweep time, because a character can be
-- flagged during an early-login refresh and still be a perfectly real member.
-- It also has to remove the character's leaf HASHES along with the data —
-- leaving one behind re-mints it from surviving data on the next rebuild and
-- resurrects the character.
--
-- The allied-guild list that drives cross-guild federation used to be pinned
-- here too (22 cases: the list, DropSisterGuildData, and the delivery verdicts
-- on TOGPM's two GUILD broadcasts). writ-cannot: that feature was removed on
-- purpose in v1.0.10 -- the list, its gossip, the roster relay and the two
-- prefixes are LibGuildRoster's now and TOGPM makes no AceComm send of its
-- own, so there is no config to broadcast, no roster to relay and no verdict
-- to record. What TOGPM still does with the list (read it, edit it through
-- the library, import an older build's copy, react to the library's
-- callbacks) is pinned in Tests/sisterguild_spec.lua.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, gdb, DS
local MATE   = "Bob-Testrealm"
local GONE   = "Leaver-Testrealm"
local ALCHEMY = 171

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	DS = env.deltaSync()
end)

-- Give a character data in every table the purge is meant to clear.
local function populate(charKey)
	gdb.recipes[ALCHEMY] = gdb.recipes[ALCHEMY] or { [2330] = { crafters = {} } }
	gdb.recipes[ALCHEMY][2330].crafters[charKey] = ns:GetCurrentGuildTag()
	gdb.cooldowns[charKey]       = { [17187] = 1 }
	gdb.skills[charKey]          = { [ALCHEMY] = { skillRank = 1, skillMax = 300 } }
	gdb.specializations[charKey] = { [ALCHEMY] = 28672 }
	gdb.altClaims[charKey]       = { charKey }
	gdb.altGroups[charKey]       = { charKey }
	gdb.lastScan[charKey]        = { cooldowns = 5 }
	ns.HashManager:InvalidateCharCooldowns(DS, gdb, charKey)
end

local function stillHasData(charKey)
	return gdb.cooldowns[charKey] ~= nil
	    or gdb.skills[charKey] ~= nil
	    or gdb.recipes[ALCHEMY][2330].crafters[charKey] ~= nil
end

describe("RunPendingPurge", function()
	it("does nothing with nothing flagged", function()
		assert.equal(0, ns:RunPendingPurge())
	end)

	it("refuses to delete while the roster cannot be confirmed", function()
		-- Flags accumulate during early login and while the roster library is
		-- unavailable; sweeping then would destroy real members' data.
		populate(GONE)
		ns:FlagForPurge(GONE)
		env.roster({ { name = "Testchar" } }, false)   -- still building
		assert.equal(0, ns:RunPendingPurge())
		assert.is_true(stillHasData(GONE))
	end)

	it("refuses to delete with no roster library at all", function()
		populate(GONE)
		ns:FlagForPurge(GONE)
		env.noRoster()
		assert.equal(0, ns:RunPendingPurge())
		assert.is_true(stillHasData(GONE))
	end)

	it("deletes a character the ready roster confirms is gone", function()
		populate(GONE)
		ns:FlagForPurge(GONE)
		assert.equal(1, ns:RunPendingPurge())
		assert.is_false(stillHasData(GONE))
		assert.is_nil(gdb.altClaims[GONE])
		assert.is_nil(gdb.lastScan[GONE])
		assert.is_nil(gdb.specializations[GONE])
	end)

	it("drops the departed character's leaf hashes too", function()
		-- A surviving hash is re-minted from surviving data on the next rebuild,
		-- which resurrects the character.
		populate(GONE)
		ns:FlagForPurge(GONE)
		ns:RunPendingPurge()
		assert.is_nil(gdb.hashes["cooldown:" .. GONE])
	end)

	it("keeps a flagged character the roster still vouches for", function()
		populate(MATE)
		ns:FlagForPurge(MATE)
		ns:RunPendingPurge()
		assert.is_true(stillHasData(MATE))
	end)

	it("keeps one of our own characters however it got flagged", function()
		populate(GONE)
		gdb.accountChars[GONE] = true
		ns:FlagForPurge(GONE)
		ns:RunPendingPurge()
		assert.is_true(stillHasData(GONE))
	end)

	it("keeps a bank alt of somebody still in the roster", function()
		populate("Bank-Testrealm")
		gdb.altGroups["Bank-Testrealm"] = { "Bank-Testrealm", MATE }
		ns:FlagForPurge("Bank-Testrealm")
		ns:RunPendingPurge()
		assert.is_true(stillHasData("Bank-Testrealm"))
	end)

	it("clears the flag list whether or not it deleted anything", function()
		populate(MATE)
		ns:FlagForPurge(MATE)
		ns:RunPendingPurge()
		assert.is_nil(next(gdb.pendingPurge or {}))
	end)

	it("strips the departed character from other players' alt arrays", function()
		-- The other member has to be gone too: sharing an alt group with someone
		-- still in the roster is itself a reason to KEEP the character.
		populate(GONE)
		gdb.altGroups["Ghost-Testrealm"] = { "Ghost-Testrealm", GONE }
		ns:FlagForPurge(GONE)
		ns:RunPendingPurge()
		assert.same({ "Ghost-Testrealm" }, gdb.altGroups["Ghost-Testrealm"])
	end)

	it("protects a character sharing an alt group with a current member", function()
		-- Through altClaims and the real rebuild, so altGroups is keyed per
		-- MEMBER as production keys it; a fixture keyed by MATE alone modelled
		-- a shape RebuildAltGroups never produces. Both accounts' claims list
		-- the same characters, as two broadcasts from one account do --
		-- populate()'s singleton self-claim contradicting MATE's claim left
		-- GONE keyed by whichever claim `pairs` visited last.
		populate(GONE)
		gdb.altClaims[GONE] = { MATE, GONE }
		gdb.altClaims[MATE] = { MATE, GONE }
		ns.Scanner:RebuildAltGroups(gdb)
		ns:FlagForPurge(GONE)
		ns:RunPendingPurge()
		assert.is_true(stillHasData(GONE))
	end)

	it("a character purged from ANOTHER owner's claim does not come back on rebuild (finding 35)", function()
		-- The purge strips the name from the alt arrays through altGroups, and
		-- those arrays ARE altClaims' arrays (one table, filed under every
		-- member). That aliasing is what keeps the character purged: a rebuild
		-- re-derives altGroups from altClaims, so if the strip had reached only a
		-- copy, altClaims would still hold GONE and the rebuild would re-mint it.
		-- This is the case the fixture above cannot reach, and the one an
		-- innocent "store a copy" hardening would break.
		populate(GONE)
		gdb.altClaims["Ghost-Testrealm"] = { "Ghost-Testrealm", GONE }   -- Ghost is not in the roster
		ns.Scanner:RebuildAltGroups(gdb)
		ns:FlagForPurge(GONE)
		ns:RunPendingPurge()
		assert.is_false(stillHasData(GONE))
		ns.Scanner:RebuildAltGroups(gdb)
		assert.is_nil(gdb.altGroups[GONE])
		assert.same({ "Ghost-Testrealm" }, gdb.altClaims["Ghost-Testrealm"])
	end)

	it("ignores a flag for nothing", function()
		ns:FlagForPurge(nil)
		assert.equal(0, ns:RunPendingPurge())
	end)
end)
