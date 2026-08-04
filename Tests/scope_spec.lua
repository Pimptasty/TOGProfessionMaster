-- The display-time visibility gates.
--
-- These decide who appears in every guild-scoped view, and — for one of them —
-- who gets queued for deletion. Three separate releases fixed bugs in here:
--   * v1.0.3: "own alts are always visible, regardless of guild" leaked a second
--     guild's alts (and their recipes and cooldowns) into whichever guild you
--     were logged into.
--   * v1.0.4: an early-login refresh, before the roster library had built,
--     queued legitimate guildmates for the purge sweep.
--   * v1.0.1: a sister-guild crafter was purged as "stale" because the tag
--     didn't match home.
-- Every one of those is a question about what to do when the roster CANNOT yet
-- answer — so the specs run against the REAL LibGuildRoster, driven to ready or
-- deliberately left mid-build, rather than a stub that would just agree with
-- whatever we assumed those states meant.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, gdb
local ME       = "Testchar-Testrealm"
local MATE     = "Bob-Testrealm"
local STRANGER = "Nobody-Testrealm"
local FOREIGN  = "ffffff"

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
end)

local function ownAccount(...)
	for _, ck in ipairs({ ... }) do gdb.accountChars[ck] = true end
end

local function purged(ck)
	return (gdb.pendingPurge or {})[ck] == true
end

describe("IsMyCharacter", function()
	it("recognises characters from this account and nobody else", function()
		ownAccount(ME)
		assert.is_true(ns:IsMyCharacter(ME))
		assert.is_false(ns:IsMyCharacter(MATE))
	end)
end)

describe("GetAllowedGuildTagSet", function()
	it("always permits our own alts and our home guild", function()
		local set = ns:GetAllowedGuildTagSet()
		assert.is_true(set[ns.PersonalTag])
		assert.is_true(set[ns:GetCurrentGuildTag()])
	end)

	it("collapses to personal-only when guildless — purely local operation", function()
		env.guildName = nil
		local set = ns:GetAllowedGuildTagSet()
		env.guildName = "Testguild"
		assert.same({ [ns.PersonalTag] = true }, set)
	end)

	it("never permits a guild we have not federated with", function()
		assert.is_nil(ns:GetAllowedGuildTagSet()[FOREIGN])
	end)
end)

describe("IsInCurrentGuildScope", function()
	it("rejects a nil character", function()
		assert.is_false(ns:IsInCurrentGuildScope(nil))
	end)

	it("always accepts the logged-in character", function()
		assert.is_true(ns:IsInCurrentGuildScope(ME))
	end)

	it("accepts a guildmate the roster confirms", function()
		assert.is_true(ns:IsInCurrentGuildScope(MATE))
	end)

	it("rejects someone the roster does not list", function()
		assert.is_false(ns:IsInCurrentGuildScope(STRANGER))
	end)

	it("hides nobody while the roster is still building", function()
		-- Cold start: we cannot judge membership yet, and blanking a legitimate
		-- list is far worse than briefly over-showing one.
		env.roster({ { name = "Testchar" } }, false)
		assert.is_true(ns:IsInCurrentGuildScope(STRANGER))
	end)

	it("hides nobody when the roster library is not installed", function()
		env.noRoster()
		assert.is_true(ns:IsInCurrentGuildScope(STRANGER))
	end)

	it("falls back to own-account membership when guildless", function()
		env.guildName = nil
		ownAccount("Alt-Testrealm")
		assert.is_true(ns:IsInCurrentGuildScope("Alt-Testrealm"))
		assert.is_false(ns:IsInCurrentGuildScope(STRANGER))
		env.guildName = "Testguild"
	end)

	it("is READ-ONLY — a hidden character is never queued for deletion", function()
		-- A cross-guild alt must stay hidden here but keep its data, for when you
		-- log into that guild or open the "Mine" view.
		assert.is_false(ns:IsInCurrentGuildScope(STRANGER))
		assert.is_false(purged(STRANGER))
	end)
end)

describe("IsVisibleCrafter", function()
	local HOME

	before_each(function() HOME = ns:GetCurrentGuildTag() end)

	it("rejects a nil character", function()
		assert.is_false(ns:IsVisibleCrafter(nil, HOME))
	end)

	it("shows an own alt that is in this guild", function()
		ownAccount(MATE)
		assert.is_true(ns:IsVisibleCrafter(MATE, HOME))
	end)

	it("hides a cross-guild own alt WITHOUT queueing it for deletion", function()
		-- The v1.0.3 leak: this used to return true unconditionally. It must now
		-- hide — but the data has to survive for that alt's own guild.
		ownAccount(STRANGER)
		assert.is_false(ns:IsVisibleCrafter(STRANGER, HOME))
		assert.is_false(purged(STRANGER))
	end)

	it("shows a guildmate whose tag matches and whom the roster confirms", function()
		assert.is_true(ns:IsVisibleCrafter(MATE, HOME))
		assert.is_false(purged(MATE))
	end)

	it("queues a tag-matching character the roster has never heard of", function()
		assert.is_false(ns:IsVisibleCrafter(STRANGER, HOME))
		assert.is_true(purged(STRANGER))
	end)

	it("shows — and does NOT queue — a tag-matching character while the roster builds", function()
		-- The v1.0.4 bug: an early-login refresh flagged legitimate members for
		-- the purge sweep, which then silently deleted their data.
		env.roster({ { name = "Testchar" } }, false)
		assert.is_true(ns:IsVisibleCrafter(STRANGER, HOME))
		assert.is_false(purged(STRANGER))
	end)

	it("shows — and does NOT queue — anyone when the roster library is absent", function()
		env.noRoster()
		assert.is_true(ns:IsVisibleCrafter(STRANGER, HOME))
		assert.is_false(purged(STRANGER))
	end)

	it("keeps a bank alt of an in-guild main", function()
		gdb.altGroups["Bank-Testrealm"] = { "Bob", MATE, "Bank-Testrealm" }
		assert.is_true(ns:IsVisibleCrafter("Bank-Testrealm", HOME))
		assert.is_false(purged("Bank-Testrealm"))
	end)

	it("queues a foreign-tagged crafter the roster cannot vouch for", function()
		assert.is_false(ns:IsVisibleCrafter(STRANGER, FOREIGN))
		assert.is_true(purged(STRANGER))
	end)

	it("keeps a foreign-tagged crafter while the roster is still building", function()
		-- A sister roster may not have been re-fed yet; purging here would delete
		-- a legitimate cross-guild crafter.
		env.roster({ { name = "Testchar" } }, false)
		assert.is_true(ns:IsVisibleCrafter(STRANGER, FOREIGN))
		assert.is_false(purged(STRANGER))
	end)

	it("queues a personal-tagged crafter who is not one of ours", function()
		assert.is_false(ns:IsVisibleCrafter(STRANGER, ns.PersonalTag))
		assert.is_true(purged(STRANGER))
	end)
end)

describe("IsAltOfInRosterCharacter", function()
	it("accepts an alt whose group OWNER is in the roster", function()
		gdb.altGroups["Bank-Testrealm"] = { MATE, "Bank-Testrealm" }
		gdb.altGroups[MATE] = gdb.altGroups["Bank-Testrealm"]
		assert.is_true(ns:IsAltOfInRosterCharacter("Bank-Testrealm"))
	end)

	it("accepts an alt whose SIBLING is in the roster", function()
		gdb.altGroups["Owner-Testrealm"] = { "Bank-Testrealm", MATE }
		assert.is_true(ns:IsAltOfInRosterCharacter("Bank-Testrealm"))
	end)

	it("rejects an alt group with nobody in the roster", function()
		gdb.altGroups["Owner-Testrealm"] = { "Bank-Testrealm", STRANGER }
		assert.is_false(ns:IsAltOfInRosterCharacter("Bank-Testrealm"))
	end)

	it("rejects a character in no alt group at all", function()
		assert.is_false(ns:IsAltOfInRosterCharacter("Bank-Testrealm"))
	end)

	it("rejects everything when the roster library is absent", function()
		env.noRoster()
		gdb.altGroups["Owner-Testrealm"] = { "Bank-Testrealm", MATE }
		assert.is_false(ns:IsAltOfInRosterCharacter("Bank-Testrealm"))
	end)
end)

describe("IsCooldownProfessionDropped", function()
	-- Pick a real profession-gated cooldown out of the shipped data rather than
	-- hard-coding a spell id that could be re-tagged later.
	local SPELL, PROF
	setup(function()
		for spellId, profId in pairs(ns:GetCooldownData().professionOf) do
			SPELL, PROF = spellId, profId
			break
		end
	end)

	it("only ever judges our OWN characters", function()
		-- A guildmate's profession snapshot is best-effort sync; hiding a cooldown
		-- that genuinely synced because their leaf lagged is the "your view
		-- depends on your own tradeskill" behaviour we refuse.
		gdb.lastScan[MATE] = { professions = 500 }
		gdb.skills[MATE]   = {}
		assert.is_false(ns:IsCooldownProfessionDropped(MATE, SPELL))
	end)

	it("says dropped when our own complete snapshot lacks the profession", function()
		ownAccount(ME)
		gdb.lastScan[ME] = { professions = 500 }
		gdb.skills[ME]   = {}
		assert.is_true(ns:IsCooldownProfessionDropped(ME, SPELL))
	end)

	it("says not dropped while we still hold the profession", function()
		ownAccount(ME)
		gdb.lastScan[ME] = { professions = 500 }
		gdb.skills[ME]   = { [PROF] = { skillRank = 300, skillMax = 300 } }
		assert.is_false(ns:IsCooldownProfessionDropped(ME, SPELL))
	end)

	it("never guesses without an authoritative snapshot", function()
		ownAccount(ME)
		gdb.skills[ME] = {}
		assert.is_false(ns:IsCooldownProfessionDropped(ME, SPELL))
	end)

	it("leaves cooldowns that belong to no profession alone", function()
		-- The Salt Shaker has no professionOf entry — it is an item, not a craft.
		ownAccount(ME)
		gdb.lastScan[ME] = { professions = 500 }
		gdb.skills[ME]   = {}
		assert.is_false(ns:IsCooldownProfessionDropped(ME, 99999999))
	end)

	it("rejects missing arguments", function()
		assert.is_false(ns:IsCooldownProfessionDropped(nil, SPELL))
		assert.is_false(ns:IsCooldownProfessionDropped(ME, nil))
	end)
end)
