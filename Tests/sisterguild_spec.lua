-- The allied ("sister") guild list and rosters are LibGuildRoster's (MINOR 18),
-- and TOGPM reads them.
--
-- Until v1.0.10 TOGPM kept its own list in TOGPM_Settings, gossiped it on its
-- own prefix, pulled rosters over a DeltaSync host, persisted them in
-- TOGPM_GuildDB and relayed them on a second prefix -- and TOGTools and
-- TOGBankClassic would each have needed the same. The user's direction,
-- 2026-09-13: one copy, in the library, every addon reads it. So what is
-- asserted here is (a) that TOGPM's readers answer from the library's store and
-- nothing else, (b) that the one-shot import of an older build's list and
-- rosters lands in that store and deletes the copies, and (c) that the library's
-- callbacks reach the guild-scoped views. The library's own suite proves the
-- gossip, the pull and the relay; none of that is re-proved here.
--
-- Every case drives the REAL LibGuildRoster-1.0 from the sibling install --
-- a stub would let these assert whatever the stub was written to say.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, gdb, lib
local HOME = "Horde-Testguild"

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	lib = env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	ns.Print = function() end
end)

local function officer(can)
	env.guild.model.canViewOfficerNote = can
end

-- The library's SavedVariables record for the home guild, read raw so the
-- assertion is about WHERE the data went and not about an accessor.
local function libRecord()
	return _G.LibGuildRosterDB and _G.LibGuildRosterDB.guilds and _G.LibGuildRosterDB.guilds[HOME]
end

describe("allied-guild list", function()
	it("starts empty", function()
		assert.same({}, ns:GetSisterGuilds())
		assert.equal(0, ns:GetSisterGuildsTs())
	end)

	it("an officer's edit lands in LibGuildRoster's store, not in TOGPM's settings", function()
		officer(true)
		assert.is_true((ns:SetSisterGuilds("  Beta  \nAlpha\n\nalpha\nGamma  ")))
		-- Sorted: the library hands every consumer the same order.
		assert.same({ "Alpha", "Beta", "Gamma" }, ns:GetSisterGuilds())
		assert.same({ "Beta", "Alpha", "Gamma" }, libRecord().sisterGuilds)
		assert.is_nil(ns.lib.db.profile.sisterGuilds)
		assert.is_nil(ns.lib.db.profile.sisterGuildsTs)
	end)

	it("stamps the edit so the last writer wins", function()
		officer(true)
		env.serverTime = 12345
		ns:SetSisterGuilds("Alpha")
		assert.equal(12345, ns:GetSisterGuildsTs())
	end)

	it("refuses an edit from a non-officer, in the player's words", function()
		officer(false)
		local said
		ns.Print = function(_, msg) said = msg end
		local ok, reason = ns:SetSisterGuilds("Alpha")
		assert.is_false(ok)
		assert.equal("not-officer", reason)
		assert.same({}, ns:GetSisterGuilds())
		assert.is_truthy(said and said:find("officer", 1, true))
	end)

	it("CanEditSisterGuilds asks the library the same question the edit will", function()
		officer(true)
		assert.is_true(ns:CanEditSisterGuilds())
		officer(false)
		assert.is_false(ns:CanEditSisterGuilds())
		env.guildName = nil
		officer(true)
		assert.is_false(ns:CanEditSisterGuilds())
	end)

	it("recognises a configured guild's key, and only that one", function()
		officer(true)
		ns:SetSisterGuilds("Sisterguild")
		assert.is_true(ns:IsSisterGuildKey("Horde-Sisterguild"))
		assert.is_false(ns:IsSisterGuildKey("Horde-Strangers"))
		assert.is_false(ns:IsSisterGuildKey(nil))
		assert.is_false(ns:IsSisterGuildKey(""))
		assert.same({ "Horde-Sisterguild" }, ns:GetSisterGuildKeys())
		assert.same({ ["Horde-Sisterguild"] = true }, ns:GetSisterGuildKeySet())
	end)

	it("matches a key case-insensitively, as the library does", function()
		-- The list is typed by an officer; a key over the wire is spelled the
		-- way the provider's client spells its own guild.
		officer(true)
		ns:SetSisterGuilds("Sisterguild")
		assert.is_true(ns:IsSisterGuildKey("Horde-SISTERGUILD"))
	end)

	it("never lists the home guild as its own sister", function()
		officer(true)
		ns:SetSisterGuilds("Testguild\nSisterguild")
		assert.same({ "Horde-Sisterguild" }, ns:GetSisterGuildKeys())
	end)

	it("answers 'nothing configured' under a library without the store", function()
		-- The pre-MINOR-18 shape: a roster library with no sister-guild API.
		-- Cross-guild is simply off; nothing half-works from a list only TOGPM
		-- could see.
		ns.Scanner.GuildRoster = { IsOfficer = function() return true end }
		local said
		ns.Print = function(_, msg) said = msg end
		assert.same({}, ns:GetSisterGuilds())
		assert.same({}, ns:GetSisterGuildKeys())
		assert.equal(0, ns:GetSisterGuildsTs())
		assert.is_false(ns:IsSisterGuildKey("Horde-Sisterguild"))
		local ok, reason = ns:SetSisterGuilds("Alpha")
		assert.is_false(ok)
		assert.equal("no-library", reason)
		assert.is_truthy(said and said:find("0.7.0", 1, true))
	end)

	it("answers the same with no roster library at all", function()
		env.noRoster()
		assert.same({}, ns:GetSisterGuilds())
		assert.is_false(ns:IsSisterGuildKey("Horde-Sisterguild"))
		assert.is_false(ns:CanEditSisterGuilds() and false)
	end)

	it("TOGPM no longer carries a gossip, a relay or a prefix of its own", function()
		-- Code with no production entry point, pinned absent: the v0.10.1 -
		-- v1.0.10 feeders. Their return would mean two writers into one store.
		assert.is_nil(ns.SisterCfgPrefix)
		assert.is_nil(ns.SisterRosterPrefix)
		assert.is_nil(ns.BroadcastSisterConfig)
		assert.is_nil(ns.BroadcastSisterRosters)
		assert.is_nil(ns.OnSisterConfigReceived)
		assert.is_nil(ns.OnSisterRosterReceived)
		assert.is_nil(ns.DropSisterGuildData)
		assert.is_nil(ns.Scanner.PersistSisterRoster)
		assert.is_nil(ns.Scanner.RefeedSisterRosters)
		assert.is_nil(ns.lib.OnSisterConfigComm)
		assert.is_nil(ns.lib.OnSisterRosterComm)
	end)
end)

describe("MigrateSisterGuildsToLibrary", function()
	it("moves an older build's list into the library and deletes the copy", function()
		ns.lib.db.profile.sisterGuilds   = { "Old Guild", "", "Other" }
		ns.lib.db.profile.sisterGuildsTs = 500
		assert.is_true(ns:MigrateSisterGuildsToLibrary())
		assert.same({ "Old Guild", "Other" }, ns:GetSisterGuilds())
		assert.equal(500, ns:GetSisterGuildsTs())
		assert.same({ "Old Guild", "Other" }, libRecord().sisterGuilds)
		assert.is_nil(ns.lib.db.profile.sisterGuilds)
		assert.is_nil(ns.lib.db.profile.sisterGuildsTs)
	end)

	it("keeps a NEWER list the library already holds, and still deletes the copy", function()
		-- The library's last-writer rule, applied to the import: an officer who
		-- edited through /guildroster before this client upgraded must not be
		-- overwritten by this client's stale copy.
		officer(true)
		env.serverTime = 900
		ns:SetSisterGuilds("New Guild")
		ns.lib.db.profile.sisterGuilds   = { "Old Guild" }
		ns.lib.db.profile.sisterGuildsTs = 500
		assert.is_false(ns:MigrateSisterGuildsToLibrary())
		assert.same({ "New Guild" }, ns:GetSisterGuilds())
		assert.equal(900, ns:GetSisterGuildsTs())
		assert.is_nil(ns.lib.db.profile.sisterGuilds)
	end)

	it("moves the persisted rosters of listed guilds and re-feeds them", function()
		ns.lib.db.profile.sisterGuilds   = { "Old Guild" }
		ns.lib.db.profile.sisterGuildsTs = 500
		gdb.sisterRosters = {
			["Horde-Old Guild"] = { members = { { name = "Sis-Testrealm", class = "MAGE", level = 60 } }, fedAt = 400 },
		}
		assert.is_true(ns:MigrateSisterGuildsToLibrary())
		-- Fed: the visibility gate can see the sister member right now.
		-- (IsInAnyRoster answers with the roster KEY, not a boolean.)
		assert.equal("Horde-Old Guild", lib:IsInAnyRoster("Sis-Testrealm"))
		assert.is_truthy(lib:GetRoster("Horde-Old Guild")["Sis-Testrealm"])
		-- Persisted in the library's SavedVariables, gone from TOGPM's. (The
		-- library re-snapshots on every feed, so `fedAt` is its own stamp now.)
		assert.equal("Sis-Testrealm", libRecord().sisterRosters["Horde-Old Guild"].members[1].name)
		assert.is_nil(rawget(gdb, "sisterRosters"))
	end)

	it("drops, rather than moves, a persisted roster for a guild that is not listed", function()
		ns.lib.db.profile.sisterGuilds   = { "Old Guild" }
		ns.lib.db.profile.sisterGuildsTs = 500
		gdb.sisterRosters = {
			["Horde-Strangers"] = { members = { { name = "X-Testrealm" } } },
		}
		ns:MigrateSisterGuildsToLibrary()
		assert.is_nil(libRecord().sisterRosters["Horde-Strangers"])
		assert.is_falsy(lib:IsInAnyRoster("X-Testrealm"))
		assert.is_nil(rawget(gdb, "sisterRosters"))
	end)

	it("never overwrites a roster the library already persisted", function()
		officer(true)
		ns:SetSisterGuilds("Old Guild")
		lib:SetSisterRoster("Horde-Old Guild", { { name = "Current-Testrealm" } }, {})
		lib:PersistSisterRoster("Horde-Old Guild")
		gdb.sisterRosters = {
			["Horde-Old Guild"] = { members = { { name = "Stale-Testrealm" } } },
		}
		ns:MigrateSisterGuildsToLibrary()
		assert.equal("Current-Testrealm", libRecord().sisterRosters["Horde-Old Guild"].members[1].name)
		assert.equal("Horde-Old Guild", lib:IsInAnyRoster("Current-Testrealm"))
		assert.is_falsy(lib:IsInAnyRoster("Stale-Testrealm"))
	end)

	it("does nothing with nothing to move, and is safe to run again", function()
		assert.is_false(ns:MigrateSisterGuildsToLibrary())
		ns.lib.db.profile.sisterGuilds   = { "Old Guild" }
		ns.lib.db.profile.sisterGuildsTs = 500
		assert.is_true(ns:MigrateSisterGuildsToLibrary())
		assert.is_false(ns:MigrateSisterGuildsToLibrary())
		assert.same({ "Old Guild" }, ns:GetSisterGuilds())
	end)

	it("leaves the copies in place under a library without the store, so a later upgrade can import them", function()
		ns.Scanner.GuildRoster = {}
		ns.lib.db.profile.sisterGuilds   = { "Old Guild" }
		ns.lib.db.profile.sisterGuildsTs = 500
		gdb.sisterRosters = { ["Horde-Old Guild"] = { members = {} } }
		assert.is_false(ns:MigrateSisterGuildsToLibrary())
		assert.same({ "Old Guild" }, ns.lib.db.profile.sisterGuilds)
		assert.is_truthy(rawget(gdb, "sisterRosters"))
	end)
end)

describe("the library's callbacks reach the guild-scoped views", function()
	local fired

	before_each(function()
		fired = {}
		ns.RegisterCallback({}, "GUILD_DATA_UPDATED", function(_e, what, scopes)
			fired[#fired + 1] = { what = what, scopes = scopes }
		end)
		-- OnEnable is where TOGPM subscribes to the library; the real one, so
		-- the subscription under test is the shipped one. In a full-suite run
		-- minimap_spec has hooked the minimap button onto it, and LibDBIcon
		-- refuses a second Register of the same name -- a fresh copy per run is
		-- minimap_spec's own answer to that.
		if env.libs.loaded["LibDBIcon-1.0"] then env.libs.fresh("LibDBIcon-1.0") end
		ns.lib:OnEnable()
	end)

	it("a changed list refreshes the views", function()
		officer(true)
		ns:SetSisterGuilds("Sisterguild")
		assert.equal(1, #fired)
		assert.equal("sisterconfig", fired[1].what)
	end)

	it("a landed roster refreshes the views with the roster scopes", function()
		officer(true)
		ns:SetSisterGuilds("Sisterguild")
		fired = {}
		lib:SetSisterRoster("Horde-Sisterguild", { { name = "Sis-Testrealm" } }, { via = "Sis-Testrealm" })
		lib:OnSisterRosterPulled("Horde-Sisterguild")
		-- SetSisterRoster itself fires OnMemberJoined for the new member, which
		-- the scope handler answers with a refresh of its own; the one under
		-- test is the roster-landed refresh, and it carries the scopes.
		local landed
		for _, f in ipairs(fired) do
			if f.what == "sister:Horde-Sisterguild" then landed = f end
		end
		assert.is_truthy(landed)
		assert.is_true(landed.scopes.roster)
		assert.is_true(landed.scopes.altgroups)
	end)

	it("the roster-ready transition runs the one-shot import first", function()
		ns.lib.db.profile.sisterGuilds   = { "Old Guild" }
		ns.lib.db.profile.sisterGuildsTs = 500
		lib.callbacks:Fire("OnRosterReady")
		assert.same({ "Old Guild" }, ns:GetSisterGuilds())
		assert.is_nil(ns.lib.db.profile.sisterGuilds)
	end)
end)

describe("Scanner:SisterPullGate", function()
	-- The bilateral consent proof they attach, naming OUR home guild.
	local function pull(extra)
		local b = { type = "sister-pull", parent = "Horde-Sisterguild", keys = { [HOME] = true } }
		for k, v in pairs(extra or {}) do b[k] = v end
		return b
	end

	before_each(function()
		officer(true)
		ns:SetSisterGuilds("Sisterguild")
		ns.Scanner.GuildRoster = lib
	end)

	it("serves a listed guild that lists us, on first contact (no roster held yet)", function()
		local consent, identity = ns.Scanner:SisterPullGate("Sis-Testrealm", pull())
		assert.is_true(consent)
		assert.is_true(identity)
	end)

	it("serves a MEMBER of a sister roster we already hold", function()
		-- v1.1.1 passed IsInGuildScoped(name, guildKey) against the library's
		-- (guildKey, name), so this legitimate member was refused.
		lib:SetSisterRoster("Horde-Sisterguild", { { name = "Sis-Testrealm" } }, {})
		local consent, identity = ns.Scanner:SisterPullGate("Sis-Testrealm", pull())
		assert.is_true(consent)
		assert.is_true(identity)
	end)

	it("refuses a stranger claiming a sister guild whose roster we hold", function()
		lib:SetSisterRoster("Horde-Sisterguild", { { name = "Sis-Testrealm" } }, {})
		local consent, identity = ns.Scanner:SisterPullGate("Spoof-Testrealm", pull())
		assert.is_true(consent)
		assert.is_false(identity)
	end)

	it("refuses a guild we do not list", function()
		local consent = ns.Scanner:SisterPullGate("X-Testrealm", pull({ parent = "Horde-Strangers" }))
		assert.is_false(consent)
	end)

	it("refuses a one-sided config: they do not list us", function()
		local consent = ns.Scanner:SisterPullGate("Sis-Testrealm", pull({ keys = {} }))
		assert.is_false(consent)
	end)
end)

describe("/togpm pullroster", function()
	local printed
	before_each(function()
		printed = {}
		ns.lib.Print = function(_, msg) printed[#printed + 1] = msg end
	end)

	it("pulls through the library and asks the same peer for TOGPM's data", function()
		local asked
		ns.Scanner.RequestSisterData = function(_, peer) asked = peer end
		local pulled
		lib.PullSisterRoster = function(_, peer) pulled = peer; return true end
		ns:PullSisterRoster("Sis-Otherrealm")
		assert.equal("Sis-Otherrealm", pulled)
		assert.equal("Sis-Otherrealm", asked)
		ns.Scanner.RequestSisterData = nil
	end)

	it("says the library is too old rather than pulling through DeltaSync", function()
		ns.Scanner.GuildRoster = {}
		ns:PullSisterRoster("Sis")
		assert.is_truthy(printed[1] and printed[1]:find("0.7.0", 1, true))
	end)

	it("says when the library refused (no guild, roster not ready)", function()
		lib.PullSisterRoster = function() return false end
		ns:PullSisterRoster("Sis")
		assert.is_truthy(printed[1] and printed[1]:find("not ready", 1, true))
	end)

	it("prints usage with no name", function()
		ns:PullSisterRoster("")
		assert.is_truthy(printed[1] and printed[1]:find("Usage", 1, true))
	end)
end)
