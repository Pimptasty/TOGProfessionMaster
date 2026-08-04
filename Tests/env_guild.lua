-- env_guild — the offline guild-API model LibGuildRoster-1.0 runs against.
--
-- ============================================================================
-- THIS FILE IS A COPY, not an original. It is maintained upstream as
-- GuildRoster/Tests/env_guild.lua, which is itself a staging copy of a proposed
-- WoWAPITesting addition (see GuildRoster/Tests/HARNESS_CONTRACT.md). DeltaSync
-- carries the same copy. Nothing in it is addon-specific: every TOG addon that
-- reads the guild roster needs exactly this model.
--
-- DO NOT diverge from the upstream file. If TOGPM needs something more from it,
-- raise it in docs/DEPENDENCY_CONTRACTS.md and change it upstream — the whole
-- point of the shared harness is that five addons see one faithful model of the
-- guild API, not five drifting ones. The only local addition is `M.libPath`,
-- because TOGPM consumes the library from the sibling GuildRoster install
-- rather than from its own repo root.
-- ============================================================================
--
-- Design follows the harness's convention: everything is a plain global you may
-- REASSIGN per test, and stubs honour the real API CONTRACT wherever the
-- contract is what bites (positional return order, the flavour-dependent shape
-- of GetNumGuildMembers).

---@diagnostic disable: duplicate-set-field

local wow = require("env.wow")

local M = { wow = wow }

--- Where LibGuildRoster-1.0 lives, relative to the addon root. TOGPM declares it
--- as a dependency (`## Dependencies: GuildRoster`) rather than embedding it, so
--- the real shipped file is loaded from the sibling install.
M.libPath = "../GuildRoster/LibGuildRoster-1.0.lua"

-- ---------------------------------------------------------------------------
-- 1. The guild model — plain state a spec mutates directly
-- ---------------------------------------------------------------------------
M.state = {}

--- Replace the roster. Each entry may set any documented field; the rest default.
function M.setMembers(list)
	local out = {}
	for i, m in ipairs(list or {}) do
		out[i] = {
			name          = m.name,
			rankName      = m.rankName or "Member",
			rankIndex     = m.rankIndex or 2,
			level         = m.level or 60,
			classDisplay  = m.classDisplay or "Warrior",
			zone          = m.zone or "Orgrimmar",
			publicNote    = m.publicNote,
			officerNote   = m.officerNote,
			isOnline      = m.isOnline or false,
			status        = m.status or 0,
			classFileName = m.classFileName or "WARRIOR",
			isMobile      = m.isMobile,
			lastOnline    = m.lastOnline,
		}
	end
	M.state.members = out
	return M
end

-- The slice of the roster the iteration APIs expose. On retail, iteration is
-- filtered by the guild panel's show-offline toggle; on Classic whether the
-- underlying list is re-filtered is unresolved, so the default models Classic as
-- unfiltered and a spec probing the other reading sets classicFiltersIteration
-- explicitly rather than having the harness quietly pick a side.
local function visible()
	local filtered = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) or M.state.classicFiltersIteration
	if filtered and not M.state.showOffline then
		local out = {}
		for _, m in ipairs(M.state.members) do
			if m.isOnline then out[#out + 1] = m end
		end
		return out
	end
	return M.state.members
end
M.visible = visible

-- ---------------------------------------------------------------------------
-- 2. Install every global this env owns (idempotent; called per test)
-- ---------------------------------------------------------------------------
function M.install()
	local S = M.state

	_G.securecallfunction = function(fn, ...) return fn(...) end
	_G.wipe = function(t)
		for k in pairs(t) do t[k] = nil end
		return t
	end

	-- Real Blizzard enUS format strings. The ONLINE form carries chat-hyperlink
	-- markup and a bracketed display name, which is what exercises a consumer's
	-- markup-stripping and optional-bracket logic — keep it rather than simplify.
	_G.ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online."
	_G.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
	_G.ERR_GUILD_JOIN_S     = "%s has joined the guild."
	_G.ERR_GUILD_LEAVE_S    = "%s has left the guild."
	_G.ERR_GUILD_REMOVE_SS  = "%s has been kicked out of the guild by %s."

	_G.IsInGuild = function() return S.inGuild end

	-- Classic returns (totalMembers, onlineMembers); retail returns a single
	-- already-filtered count. Consumers reading only the first return therefore
	-- see different things per flavour — the point of modelling it faithfully.
	_G.GetNumGuildMembers = function()
		local list = visible()
		local online = 0
		for _, m in ipairs(S.members) do
			if m.isOnline then online = online + 1 end
		end
		if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then return #list end
		return #list, online
	end

	-- Full 17-value positional contract, mirroring Blizzard's order exactly:
	-- getting it wrong here would make a consumer's decode bug invisible.
	_G.GetGuildRosterInfo = function(i)
		local m = visible()[i]
		if not m then return nil end
		return m.name, m.rankName, m.rankIndex, m.level, m.classDisplay, m.zone,
		       m.publicNote, m.officerNote, m.isOnline, m.status, m.classFileName,
		       0, 0, m.isMobile, nil, 0, "Player-4711-00000001"
	end

	_G.GetGuildRosterLastOnline = function(i)
		local m = visible()[i]
		if not m or not m.lastOnline then return nil end
		local l = m.lastOnline
		return l.years, l.months, l.days, l.hours
	end

	_G.GetGuildInfo = function()
		if not S.inGuild then return nil end
		return S.guildName, S.rankName, S.rankIndex
	end

	_G.GetNormalizedRealmName = function() return S.realm end
	_G.GetRealmName           = function() return S.realm end
	_G.UnitName               = function() return S.playerName end
	_G.UnitFactionGroup       = function() return S.faction end
	_G.GetTime                = function() return S.clock end

	_G.SetGuildRosterShowOffline = function(v) S.showOffline = v and true or false end
	_G.GetGuildRosterShowOffline = function() return S.showOffline end

	_G.C_GuildInfo = { GuildRoster = function() S.requests = S.requests + 1 end }
	_G.C_ChatInfo  = { InChatMessagingLockdown = function() return S.lockdown end }

	-- The deprecated bare global is ABSENT by default: it is gone on every
	-- current client, so a consumer that still calls it must be exercising its
	-- feature-detect. A spec opts in by assigning _G.GuildRoster itself.
	_G.GuildRoster = nil
end

--- Advance the fake clock (GetTime is monotonic seconds in-game).
function M.advance(seconds)
	M.state.clock = M.state.clock + seconds
	return M
end

-- ---------------------------------------------------------------------------
-- 3. Loading the library under test
-- ---------------------------------------------------------------------------

--- Reset model AND globals to a known baseline. Does not reload the library.
function M.resetState()
	M.state.inGuild     = true
	M.state.guildName   = "Testguild"
	M.state.faction     = "Horde"
	M.state.realm       = "Testrealm"
	M.state.playerName  = "Testchar"
	M.state.rankName    = "Officer"
	M.state.rankIndex   = 1
	M.state.showOffline = true
	M.state.lockdown    = false
	M.state.clock       = 1000
	M.state.requests    = 0
	M.state.classicFiltersIteration = nil
	M.state.members     = {}
	M.install()
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
