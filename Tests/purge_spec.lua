-- The deferred purge sweep, and the allied-guild list that drives cross-guild
-- federation.
--
-- The purge is the only code that DELETES another player's data, so its guards
-- matter more than its deletions: it never runs against an unconfirmed roster,
-- and it re-validates every flag at sweep time, because a character can be
-- flagged during an early-login refresh and still be a perfectly real member.
-- It also has to remove the character's leaf HASHES along with the data —
-- leaving one behind re-mints it from surviving data on the next rebuild and
-- resurrects the character.

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
	-- The cross-guild send verdicts land here, so the real module has to be in.
	env.loadModule("Modules/SyncLog.lua")
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
		populate(GONE)
		gdb.altGroups[MATE] = { MATE, GONE }
		ns:FlagForPurge(GONE)
		ns:RunPendingPurge()
		assert.is_true(stillHasData(GONE))
	end)

	it("ignores a flag for nothing", function()
		ns:FlagForPurge(nil)
		assert.equal(0, ns:RunPendingPurge())
	end)
end)

describe("allied-guild list", function()
	local function officer(can)
		ns.CanEditSisterGuilds = function() return can end
	end

	local realCanEdit
	before_each(function()
		realCanEdit = ns.CanEditSisterGuilds
		ns.Print = function() end
	end)
	after_each(function()
		ns.CanEditSisterGuilds = realCanEdit
	end)

	it("starts empty", function()
		assert.same({}, ns:GetSisterGuilds())
	end)

	it("parses a newline-separated list, trimming and de-duplicating", function()
		officer(true)
		ns:SetSisterGuilds("  Alpha  \nBeta\n\nalpha\nGamma  ")
		assert.same({ "Alpha", "Beta", "Gamma" }, ns:GetSisterGuilds())
	end)

	it("stamps the edit so the last writer wins", function()
		officer(true)
		env.serverTime = 12345
		ns:SetSisterGuilds("Alpha")
		assert.equal(12345, ns:GetSisterGuildsTs())
	end)

	it("refuses an edit from a non-officer", function()
		officer(false)
		ns:SetSisterGuilds("Alpha")
		assert.same({}, ns:GetSisterGuilds())
	end)

	it("recognises a configured guild's key, and only that one", function()
		officer(true)
		ns:SetSisterGuilds("Sisterguild")
		assert.is_true(ns:IsSisterGuildKey("Horde-Sisterguild"))
		assert.is_false(ns:IsSisterGuildKey("Horde-Strangers") or false)
	end)

	it("tears down a guild dropped from the list", function()
		officer(true)
		ns:SetSisterGuilds("Sisterguild")
		gdb.sisterRosters = { ["Horde-Sisterguild"] = { members = {} } }
		ns:SetSisterGuilds("")
		assert.is_nil(gdb.sisterRosters["Horde-Sisterguild"])
	end)

	it("never broadcasts a config it does not hold", function()
		local sent = 0
		local realSend = ns.lib.SendCommMessage
		ns.lib.SendCommMessage = function() sent = sent + 1 end
		ns:BroadcastSisterConfig()             -- ts is 0
		ns.lib.SendCommMessage = realSend
		assert.equal(0, sent)
	end)

	it("never broadcasts on GUILD while guildless", function()
		-- The client refuses such a send, and since AceCommQueue MINOR 5 a
		-- refusal with no delivery callback reaches the player's bug catcher.
		officer(true)
		ns:SetSisterGuilds("Sisterguild")
		local sent = 0
		local realSend = ns.lib.SendCommMessage
		ns.lib.SendCommMessage = function() sent = sent + 1 end
		env.guildName = nil
		ns:BroadcastSisterConfig()
		ns:BroadcastSisterRosters()
		env.guildName = "Testguild"
		ns.lib.SendCommMessage = realSend
		assert.equal(0, sent)
	end)
end)

describe("DropSisterGuildData", function()
	it("removes the persisted roster and tells the roster library", function()
		local removed
		ns.Scanner.GuildRoster = { RemoveSisterRoster = function(_, key) removed = key end }
		gdb.sisterRosters = { ["Horde-Sisterguild"] = { members = {} } }
		ns:DropSisterGuildData("Horde-Sisterguild")
		assert.equal("Horde-Sisterguild", removed)
		assert.is_nil(gdb.sisterRosters["Horde-Sisterguild"])
	end)

	it("ignores a nil key", function()
		local ok = pcall(function() ns:DropSisterGuildData(nil) end)
		assert.is_true(ok)
	end)
end)

-- The delivery verdict on TOGPM's OWN sends (AceCommQueue-1.0 MINOR 5).
--
-- These two broadcasts are the only places TOGPM calls SendCommMessage itself;
-- everything else rides DeltaSync, which runs its own OnSendResult. Until
-- v1.0.6 they passed no callback, so a refusal went to the player's bug catcher
-- from inside the comm layer and TOGPM learned nothing about its own federation
-- traffic failing.
--
-- Scope: the library's suite proves it PRODUCES the verdict. What is ours is
-- that we ask for one and read its five outcomes correctly — in particular that
-- "suppressed" is not an error, since a wrapper dropping a send deliberately is
-- the addon working as designed.
describe("cross-guild send verdicts", function()
	local realSend, realCanEdit, realPrint, calls

	-- Stand in for the queue and hand back the verdict under test. Driving a
	-- real refusal through the booted AceCommQueue would mean driving
	-- ChatThrottleLib's bandwidth model as well, which is that library's own
	-- suite's job; the contract is what is being asserted here.
	local function sendYielding(delivered, reason)
		ns.lib.SendCommMessage = function(_, prefix, _text, dist, _target, _prio, cb, arg)
			calls[#calls + 1] = { prefix = prefix, dist = dist, cb = cb, arg = arg }
			if cb then cb(arg, 0, 0, delivered, reason) end
		end
	end

	local function failures()
		local out = {}
		for _, e in ipairs(ns.SyncLog:GetEntries()) do
			if e.event == "failed" then out[#out + 1] = e end
		end
		return out
	end

	before_each(function()
		realSend, realCanEdit, realPrint = ns.lib.SendCommMessage, ns.CanEditSisterGuilds, ns.Print
		-- Quiet during setup: SetSisterGuilds broadcasts on change, and that send
		-- is not the one under test.
		ns.lib.SendCommMessage = function() end
		ns.Print               = function() end
		ns.CanEditSisterGuilds = function() return true end
		ns:SetSisterGuilds("Sisterguild")
		ns._seenSisterRoster = {}
		ns.Scanner.GuildRoster = {
			GetKnownRosters = function() return { "Horde-Testguild", "Horde-Sisterguild" } end,
			GetRosterHash   = function() return 42 end,
			GetRoster       = function() return { ["Bob-Testrealm"] = { class = "MAGE", level = 60 } } end,
		}
		ns.SyncLog:Clear()
		calls = {}
	end)

	after_each(function()
		ns.lib.SendCommMessage = realSend
		ns.CanEditSisterGuilds = realCanEdit
		ns.Print               = realPrint
	end)

	it("asks for a delivery verdict on the sister-config broadcast", function()
		sendYielding(true, nil)
		ns:BroadcastSisterConfig()
		assert.equal(1, #calls)
		assert.equal(ns.SisterCfgPrefix, calls[1].prefix)
		assert.equal("GUILD", calls[1].dist)
		assert.is_function(calls[1].cb)
	end)

	it("asks for a delivery verdict on the sister-roster broadcast", function()
		sendYielding(true, nil)
		ns:BroadcastSisterRosters()
		assert.equal(1, #calls)
		assert.equal(ns.SisterRosterPrefix, calls[1].prefix)
		assert.is_function(calls[1].cb)
	end)

	it("records nothing when the message was delivered", function()
		sendYielding(true, nil)
		ns:BroadcastSisterConfig()
		assert.equal(0, #failures())
	end)

	it("records a refusal to the Sync Log, naming what did not arrive", function()
		sendYielding(false, "refused")
		ns:BroadcastSisterConfig()
		local f = failures()
		assert.equal(1, #f)
		assert.equal("guild", f[1].peer)
		assert.is_true(f[1].detail:find("sister config", 1, true) ~= nil)
		assert.is_true(f[1].detail:find("refused", 1, true) ~= nil)
	end)

	it("treats a deliberate suppression as success, not failure", function()
		-- delivered == nil with reason "suppressed" is one of our own wrappers
		-- dropping the send on purpose. Logging it would train the user to
		-- ignore the log.
		sendYielding(nil, "suppressed")
		ns:BroadcastSisterConfig()
		assert.equal(0, #failures())
	end)

	it("records the three nil verdicts that DO mean the message was lost", function()
		-- "lost" is AceCommQueue MINOR 6's terminal verdict on a stall it could
		-- not recover from, and it arrives as delivered == NIL — so the original
		-- `delivered == false` test walked straight past it. It is also the one
		-- that matters most: a send reported "lost" has already been released
		-- and re-sent under the retry budget and failed again, so unlike a
		-- refusal it will NOT heal itself on the next periodic pass.
		for _, reason in ipairs({ "rejected", "error", "lost" }) do
			ns.SyncLog:Clear()
			sendYielding(nil, reason)
			ns:BroadcastSisterConfig()
			local f = failures()
			assert.equal(1, #f)
			assert.is_true(f[1].detail:find(reason, 1, true) ~= nil)
		end
	end)

	it("keeps telling suppression apart from lost, though both arrive as nil", function()
		-- The whole reason `reason` exists. Collapsing them would either spam the
		-- log with deliberate drops or hide a dead cross-guild link.
		ns.SyncLog:Clear()
		sendYielding(nil, "suppressed")
		ns:BroadcastSisterConfig()
		assert.equal(0, #failures())

		ns.SyncLog:Clear()
		sendYielding(nil, "lost")
		ns:BroadcastSisterConfig()
		assert.equal(1, #failures())
	end)

	it("names the guild whose roster failed, not just 'a roster'", function()
		-- One broadcast pass can send several rosters; a bare "roster failed"
		-- would not say which allied guild stopped propagating.
		sendYielding(false, "refused")
		ns:BroadcastSisterRosters()
		local f = failures()
		assert.equal(1, #f)
		assert.is_true(f[1].detail:find("Horde-Sisterguild", 1, true) ~= nil)
	end)

	it("survives a verdict arriving before the guild DB exists", function()
		-- The callback is the one path that can run at an arbitrary later time.
		local saved = ns.guildDb
		ns.guildDb = nil
		sendYielding(false, "refused")
		local ok = pcall(function() ns:BroadcastSisterConfig() end)
		ns.guildDb = saved
		assert.is_true(ok)
	end)
end)
