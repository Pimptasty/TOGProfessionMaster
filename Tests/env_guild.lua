-- env_guild — loading LibGuildRoster-1.0 offline, on top of the harness's guild model.
--
-- ============================================================================
-- THE GUILD API SURFACE LIVES IN THE HARNESS NOW.
--
-- This file used to carry a copy of it — GetGuildRosterInfo's seventeen
-- positional values, the flavour-dependent GetNumGuildMembers, the roster
-- request counter, the enUS event format strings — duplicated across
-- GuildRoster, DeltaSync and TOGPM. The harness took it over on 2026-08-03 as
-- `env.guild`, so the copy is gone and `M.model` IS the harness's table: set
-- `env.guild.model.showOffline`, read `env.guild.model.rosterUpdates`.
--
-- What stays here is the part that is genuinely TOGPM's and belongs in no
-- shared harness: WHERE LibGuildRoster is (a sibling addon, because TOGPM
-- declares it as a dependency rather than embedding it), how a fresh copy is
-- loaded into a suite that shares one Lua state, and how its event frame is
-- driven.
-- ============================================================================

local wow   = require("env.wow")
local guild = require("env.guild")

local M = { wow = wow, model = guild }

--- Where LibGuildRoster-1.0 lives, relative to the addon root. TOGPM declares it
--- as a dependency (`## Dependencies: GuildRoster`) rather than embedding it, so
--- the real shipped file is loaded from the sibling install.
M.libPath = "../GuildRoster/LibGuildRoster-1.0.lua"

--- Replace the roster. Partial member tables; the harness fills the rest.
function M.setMembers(list)
	guild.setMembers(list)
	return M
end

--- Reset the guild model and reinstall every global it owns.
---
--- Order matters and is the harness's documented one: `wow.reset()` FIRST (it
--- replaces C_ChatInfo wholesale), then the guild model. env_togpm.install()
--- already calls wow.reset() before this, so this only owns the guild half.
---
--- Two MINOR-18 resets, copied from GuildRoster/Tests/env_guild.lua (the
--- maintained copy) because the library now brings its sister-guild sync up
--- inside the login build every spec drives:
---   * `LibGuildRosterDB` is the library's SavedVariables and ONE global for the
---     suite. Left alone, a list or roster one spec put there is re-fed by the
---     next spec's login build and looks like a real roster there. Absent by
---     default, exactly as a first login sees it. env.roster() runs this
---     reset too, so a spec modelling a returning player fills the store
---     AFTER env.roster() (through lib:GetSisterDb()) and calls
---     lib:RefeedSisterRosters() itself -- the login build's own re-feed has
---     already run by then, against an empty store.
---   * ChatThrottleLib is one global too and QUEUES what it has no bandwidth
---     for, draining on later ticks -- so a gossip the previous spec's library
---     queued lands in THIS spec's wow.sent the first time it advances the
---     clock. Its queues are thrown away and the gauge set to a full burst;
---     `BlockedQueuesDelay` cleared because Init() only builds the Blocked
---     rings while it is nil, and `HardThrottlingBeginTime` pushed into the
---     past because Init() stamps it now and caps the gauge for five seconds.
function M.resetState()
	local CTL = _G.ChatThrottleLib
	if CTL and CTL.Init then
		CTL.Prio, CTL.avail, CTL.bQueueing, CTL.BlockedQueuesDelay = nil, nil, false, nil
		CTL:Init()
		CTL.avail = CTL.BURST
		CTL.HardThrottlingBeginTime = GetTime() - 60
	end
	guild.reset()
	_G.LibGuildRosterDB = nil
	return M
end

--- Load a FRESH copy of a LibStub library, discarding any previously registered
--- one. Required because the whole suite runs in one Lua state and
--- LibStub:NewLibrary returns nil for an already-registered version — a second
--- plain load would bail at `if not lib then return end` and hand back a stale
--- library carrying the previous test's roster.
---
--- MINOR 18: a library instance that reached roster-ready registered its three
--- sister-guild prefixes on AceComm-3.0, which is loaded ONCE for the suite. Left
--- there, every previous instance still receives each replayed message and
--- writes into the one shared SavedVariables global. Stale instances are found
--- by the `owner` tag the library puts on its comm object and evicted first.
function M.freshLib(path, major)
	local AceComm = LibStub("AceComm-3.0", true)
	local events = AceComm and AceComm.callbacks and AceComm.callbacks.events
	if events then
		local stale = {}
		for _, handlers in pairs(events) do
			for obj in pairs(handlers) do
				if type(obj) == "table" and obj.owner == major then stale[obj] = true end
			end
		end
		for obj in pairs(stale) do AceComm.UnregisterAllComm(obj) end
	end
	LibStub.libs[major], LibStub.minors[major] = nil, nil
	local ns = wow.loadAddonFile(path, "GuildRoster")
	local lib = LibStub(major)
	return lib, ns
end

--- Full per-test reset: baseline model/globals + a freshly loaded LibGuildRoster.
--- The flavour is selected HERE because the library captures IS_RETAIL at load
--- time and the suite shares one Lua state — a retail test that forgot to switch
--- back would silently make every later spec file run as retail.
function M.freshRoster(flavour)
	if flavour == "mainline" then wow.useMainline() else wow.useClassicEra() end
	M.resetState()
	local lib = M.freshLib(M.libPath, "LibGuildRoster-1.0")
	M.lib = lib
	return lib
end

--- Drive the library's event frame the way the client would.
function M.fire(lib, event, ...)
	return lib.frame:Fire("OnEvent", event, ...)
end

return M
