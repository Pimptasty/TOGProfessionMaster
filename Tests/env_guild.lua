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
function M.resetState()
	guild.reset()
	return M
end

--- Load a FRESH copy of a LibStub library, discarding any previously registered
--- one. Required because the whole suite runs in one Lua state and
--- LibStub:NewLibrary returns nil for an already-registered version — a second
--- plain load would bail at `if not lib then return end` and hand back a stale
--- library carrying the previous test's roster.
function M.freshLib(path, major)
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
