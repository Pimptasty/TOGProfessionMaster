-- env_togpm — the offline environment TOGProfessionMaster's own modules run in.
--
-- Layers three things on top of the shared WoWAPITesting harness (`Tests/wowapi`):
--
--   1. The globals Ace3 and the addon read at LOAD time (bit, GetTime,
--      GetCurrentRegion, C_AddOns, Enum, …) — the harness covers the stat/unit
--      surface, not this one.
--   2. A BOOT of the real addon core: the real Ace3 chain and the real
--      AceCommQueue-1.0 / DeltaSync-1.0 from the sibling AddOns folders, then
--      `TOGProfessionMaster.lua` itself. That is the exact code that ships, so
--      an integration bug can't hide behind a stub — and it means specs read
--      real tables (`addon.CRAFTING_PROFS`, the real AceDB defaults) instead of
--      hand-copied ones that silently drift from the source.
--   3. `newGdb()` — an empty guild DB in the shape AceDB hands the addon, so a
--      spec starts from the same blank slate a fresh install does.
--
-- WHY THE REAL DeltaSync: HashManager's whole job is producing hashes that two
-- clients agree on. Stubbing ComputeHash with `return 1` would make every
-- convergence assertion pass without testing anything. The library is loaded
-- standalone (DeltaSync.lua only) because the hash functions are pure — the
-- comms files aren't needed to hash a table.
--
-- ISOLATION: the whole suite runs in ONE Lua state and specs reassign globals
-- freely, so every global this env owns is reinstalled by M.install(), which
-- specs call in before_each. A partial reset lets one spec corrupt LATER SPEC
-- FILES — invisible in a single-file run, only reproducible in a full-suite run.
-- The BOOT is deliberately once-only and cached: AceAddon:NewAddon errors on a
-- second call for the same addon name, and LibStub libraries are singletons.

-- This env deliberately REPLACES some stubs the base harness installs
-- (GetServerTime, UnitName, …) with versions a spec can steer. That is the point.
---@diagnostic disable: duplicate-set-field

package.path = "./Tests/?.lua;" .. package.path

local wow   = require("env.wow")
-- The shared guild-API model (roster iteration, chat format strings, the guild
-- info APIs). Copied from GuildRoster/Tests — see the banner in env_guild.lua.
local guild = require("env_guild")

local M = { wow = wow, guild = guild }

-- ---------------------------------------------------------------------------
-- 0. One-time setup — genuinely global, not per-test state
-- ---------------------------------------------------------------------------

-- WoW ships LuaBitOp as the global `bit`; stock Lua 5.1 has none. Prefer a real
-- one, else fall back to a pure-Lua implementation returning SIGNED 32-bit
-- results exactly like LuaBitOp — code that normalises with `% 4294967296` is
-- normalising for a reason, and an unsigned stub would leave that untested.
-- (Copied from GuildRoster/Tests/env_guild.lua; see Tests/HARNESS_CONTRACT.md
-- there — it belongs in the harness, not in five addons.)
if not _G.bit then
	local ok, real = pcall(require, "bit")
	if ok and type(real) == "table" and real.bxor then
		_G.bit = real
	else
		local function toSigned(n)
			n = n % 4294967296
			if n >= 2147483648 then n = n - 4294967296 end
			return n
		end
		local function bitwise(a, b, op)
			a, b = a % 4294967296, b % 4294967296
			local result, place = 0, 1
			for _ = 1, 32 do
				local x, y = a % 2, b % 2
				local v
				if op == "xor" then v = (x ~= y) and 1 or 0
				elseif op == "and" then v = (x == 1 and y == 1) and 1 or 0
				else v = (x == 1 or y == 1) and 1 or 0 end
				result = result + v * place
				a, b, place = (a - x) / 2, (b - y) / 2, place * 2
			end
			return toSigned(result)
		end
		_G.bit = {
			bxor = function(a, b) return bitwise(a, b, "xor") end,
			band = function(a, b) return bitwise(a, b, "and") end,
			bor  = function(a, b) return bitwise(a, b, "or") end,
			bnot = function(a) return toSigned(4294967295 - (a % 4294967296)) end,
			lshift = function(a, n) return toSigned(a * (2 ^ n)) end,
			rshift = function(a, n) return toSigned(math.floor((a % 4294967296) / (2 ^ n))) end,
		}
	end
end

-- ---------------------------------------------------------------------------
-- 1. Globals this env owns — reinstalled on every reset
-- ---------------------------------------------------------------------------

-- Player identity the addon builds character keys and guild tags from. A spec
-- may reassign any of these mid-test (`env.guildName = nil` to go guildless is
-- the common one); install() restores the defaults, so a spec that dies before
-- putting a value back cannot leak it into later tests — which otherwise shows
-- up as a cascade of unrelated failures in the NEXT describe block.
M.DEFAULTS = {
	playerName = "Testchar",
	realmName  = "Testrealm",
	faction    = "Horde",
	guildName  = "Testguild",
	serverTime = 1000,
}

-- Set once the addon core has been loaded (see M.boot). Declared up here so
-- install() can tell "before boot" from "between tests" — nothing derived from
-- the namespace exists to reset until the core is in.
local booted

-- The identity globals must be (re)installed after ANYTHING that reloads the
-- guild model, because guild.install() owns some of the same names. Reading
-- M.<field> at call time is what lets a spec flip identity without a reinstall.
local function installIdentity()
	_G.IsInGuild    = function() return M.guildName ~= nil end
	_G.GetGuildInfo = function()
		if not M.guildName then return nil end
		return M.guildName, guild.state.rankName, guild.state.rankIndex
	end
	_G.UnitName            = function() return M.playerName end
	_G.GetRealmName        = function() return M.realmName end
	_G.GetNormalizedRealmName = function() return M.realmName end
	_G.UnitFactionGroup    = function() return M.faction end
	_G.GetServerTime       = function() return M.serverTime end
end
M.installIdentity = installIdentity

function M.install()
	for k, v in pairs(M.DEFAULTS) do M[k] = v end
	-- The guild model first: it owns the roster iteration APIs, the chat format
	-- strings, and a clean member list per test. resetState() also reinstalls
	-- every global it owns, which is what keeps one spec from corrupting a later
	-- spec FILE through a stub it reassigned.
	guild.resetState()
	guild.state.playerName = M.playerName
	guild.state.realm      = M.realmName
	guild.state.faction    = M.faction
	guild.state.guildName  = M.guildName
	guild.state.inGuild    = M.guildName ~= nil

	-- Identity AFTER the guild model, since they share several names.
	installIdentity()

	_G.hooksecurefunc      = function() end
	_G.GetCurrentRegion    = function() return 1 end
	-- FrameXML aliases the Lua stdlib into globals; addon code uses the bare
	-- names (`floor(x)`, `time()`), which stock Lua 5.1 does not have.
	_G.floor               = math.floor
	_G.ceil                = math.ceil
	_G.abs                 = math.abs
	_G.time                = os.time
	_G.date                = os.date
	_G.IsAddOnLoaded       = function() return false end
	_G.SlashCmdList        = _G.SlashCmdList or {}
	_G.DEFAULT_CHAT_FRAME  = { AddMessage = function() end }
	-- FrameXML tables that addon files index at LOAD time (registering a static
	-- popup, adding a frame to the ESC-closes list). Created once and kept, not
	-- replaced: an addon that registered into them at load would otherwise lose
	-- its entry on the next reset.
	_G.StaticPopupDialogs  = _G.StaticPopupDialogs or {}
	_G.UISpecialFrames     = _G.UISpecialFrames or {}
	_G.StaticPopup_Show    = function() end
	_G.StaticPopup_Hide    = function() end

	-- C_Timer: After returns NOTHING (only NewTimer/NewTicker hand back a
	-- cancellable handle). Faithful on purpose — a fake handle from After would
	-- make every `timer:Cancel()` "work" offline and silently no-op in game.
	_G.C_Timer = {
		After    = function() end,
		NewTimer = function() return { Cancel = function() end } end,
		NewTicker = function() return { Cancel = function() end } end,
	}

	_G.C_AddOns = {
		GetAddOnMetadata = function() return "test" end,
		IsAddOnLoaded    = function() return false end,
		LoadAddOn        = function() end,
	}

	-- Blank recipe universe (and its derived indexes) unless a spec installs one.
	if booted then
		M.setRecipeDB(nil)
		-- Settings back to AceDB defaults. Specs flip profile toggles freely (a
		-- price source, an allied guild, the crafting takeover) and a leftover
		-- one changes behaviour in a LATER spec file, which shows up as a failure
		-- nowhere near the spec that caused it. ResetDB covers profile, char and
		-- factionrealm in one call; the guild database is a separate AceDB and is
		-- reset by resetDb().
		if booted.lib and booted.lib.db and booted.lib.db.ResetDB then
			booted.lib.db:ResetDB()
		end
	end

	-- ChatThrottleLib indexes Enum at load; nothing under test reads a real
	-- value from it, so a permissive stand-in is enough.
	_G.Enum = setmetatable({}, { __index = function()
		return setmetatable({}, { __index = function() return 0 end })
	end })
end

M.install()

-- ---------------------------------------------------------------------------
-- 2. Boot the real addon core (once)
-- ---------------------------------------------------------------------------

-- Ace3's own load order. Every entry is the REAL file from the sibling install —
-- the same code that ships to players. ChatThrottleLib lives inside AceComm-3.0's
-- folder, and AceComm asserts on it at load, so it must precede AceComm.
M.LIBS = {
	"../Ace3/LibStub/LibStub.lua",
	"../Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua",
	"../Ace3/AceLocale-3.0/AceLocale-3.0.lua",
	"../Ace3/AceAddon-3.0/AceAddon-3.0.lua",
	"../Ace3/AceEvent-3.0/AceEvent-3.0.lua",
	"../Ace3/AceTimer-3.0/AceTimer-3.0.lua",
	"../Ace3/AceSerializer-3.0/AceSerializer-3.0.lua",
	"../Ace3/AceHook-3.0/AceHook-3.0.lua",
	"../Ace3/AceConsole-3.0/AceConsole-3.0.lua",
	"../Ace3/AceComm-3.0/ChatThrottleLib.lua",
	"../Ace3/AceComm-3.0/AceComm-3.0.lua",
	"../Ace3/AceDB-3.0/AceDB-3.0.lua",
	-- AceGUI is needed to LOAD any GUI/ file (they grab it at file scope). It
	-- must be loaded exactly once: unlike AceLocale, AceGUI-3.0 does not bail
	-- when LibStub:NewLibrary returns nil for an already-registered version — it
	-- indexes the nil and errors. Hence here, once, rather than per-spec.
	"../Ace3/AceGUI-3.0/AceGUI-3.0.lua",
	"../AceCommQueue-1.0/AceCommQueue-1.0.lua",
	"../DeltaSync/DeltaSync.lua",
}

-- Addon files loaded into the shared namespace, in .toc order. Only the ones
-- that load cleanly without a UI are here; GUI files are loaded per-spec.
M.CORE = {
	"Locale/_init.lua",
	"Locale/enUS.lua",
	"TOGProfessionMaster.lua",
	"Compat.lua",
}

--- Load the real libraries + addon core once and return the addon namespace.
--- Repeat calls return the same namespace: AceAddon:NewAddon errors on a second
--- NewAddon for the same name, and every LibStub library is a singleton.
function M.boot()
	if booted then return booted end
	M.install()

	-- The harness vendors LibStub already; skip a second copy if it's loaded.
	for _, path in ipairs(M.LIBS) do
		if not (path:find("LibStub") and _G.LibStub) then
			local chunk = loadfile(path)
			if not chunk then
				error("env_togpm: required library not found: " .. path ..
					"\nEvery TOG addon test env loads real libraries from the sibling AddOns" ..
					" folder — check the install rather than stubbing it.")
			end
			chunk(path:match("([^/]+)%.lua$"), {})
		end
	end

	local ns = {}
	for _, path in ipairs(M.CORE) do
		wow.loadAddonFile(path, "TOGProfessionMaster", ns)
	end

	booted = ns
	return ns
end

--- Load one more addon file into the booted namespace (e.g. a Module under test).
function M.loadModule(path)
	return wow.loadAddonFile(path, "TOGProfessionMaster", M.boot())
end

local dbInit

--- Run the addon's REAL `Ace:OnInitialize()` once — the AceDB SavedVariables,
--- the schema migrations, the guild-tag registry. Anything that reads
--- `addon:GetGuildDb()` or computes a guild tag needs it (tags are an FNV-1a of
--- the guild key and get registered in the DB on first use, so faking one would
--- test nothing). Once-only: AceDB:New on the same SV name twice is not the
--- same object, and the migrations are written to run at login.
function M.initDb()
	local ns = M.boot()
	if not dbInit then
		ns.lib:OnInitialize()
		dbInit = true
	end
	return ns
end

--- The real DeltaSync-1.0 handle — what the addon passes around as `DS`. Its
--- ComputeHash / ComputeStructuredHash are pure, which is the whole reason a
--- hash spec can be meaningful offline.
function M.deltaSync()
	M.boot()
	return LibStub("DeltaSync-1.0")
end

-- ---------------------------------------------------------------------------
-- 3. Guild roster
-- ---------------------------------------------------------------------------

--- Load a fresh REAL LibGuildRoster-1.0 from the sibling GuildRoster install,
--- populate it with `members`, drive it to READY, and hand it to the addon the
--- way the live code does (`Scanner.GuildRoster`).
---
--- Real library, not a stub, because the display gates are all ABOUT its
--- semantics — `IsInGuild` is a strict membership check, `IsReady` is false
--- until two consecutive rebuilds agree on the member count, and the gates
--- deliberately fail OPEN during that window rather than blank a legitimate
--- list. A hand-written stub would let us assert whatever we assumed those
--- meant. Pass `ready = false` to stop before the roster stabilises and test
--- the cold-start window itself.
--- @param members table   array of { name=, isOnline= } (realm-less, as WoW gives)
--- @param ready   boolean|nil  default true
function M.roster(members, ready)
	local lib = guild.freshRoster()
	guild.setMembers(members or {})
	guild.state.playerName = M.playerName
	guild.state.realm      = M.realmName
	guild.state.faction    = M.faction
	guild.state.guildName  = M.guildName
	guild.state.inGuild    = M.guildName ~= nil
	-- freshRoster reinstalls the guild model's globals, which overlap ours.
	installIdentity()

	guild.fire(lib, "PLAYER_LOGIN")
	if ready ~= false then
		-- STABLE_THRESHOLD consecutive rebuilds with a matching member total is
		-- what flips the library to ready; +1 for the initial build.
		for _ = 1, (lib.STABLE_THRESHOLD or 2) + 1 do
			guild.fire(lib, "GUILD_ROSTER_UPDATE")
		end
	end

	local ns = M.boot()
	ns.Scanner = ns.Scanner or {}
	ns.Scanner.GuildRoster = lib
	return lib
end

--- Detach the roster library — models "GuildRoster isn't installed", which the
--- gates must survive without hiding anybody.
function M.noRoster()
	local ns = M.boot()
	if ns.Scanner then ns.Scanner.GuildRoster = nil end
end

-- ---------------------------------------------------------------------------
-- 4. Fixtures
-- ---------------------------------------------------------------------------

local profDB

--- The REAL LibProfessionDB-1.0 with one profession's shipped data loaded
--- (Vanilla Alchemy — the env runs as Classic Era / enUS, which is what those
--- data files guard on). Enough for anything that asks the library for reagents
--- or difficulty without loading all fourteen professions on every suite run.
--- Returns nil if the sibling ProfessionDB install is missing.
function M.professionDB()
	if profDB ~= nil then return profDB or nil end
	M.boot()
	local files = {
		"../ProfessionDB/LibProfessionDB-1.0.lua",
		"../ProfessionDB/Data/Vanilla/_core/Alchemy.lua",
		"../ProfessionDB/Data/Vanilla/enUS/Alchemy.lua",
	}
	for _, path in ipairs(files) do
		local chunk = loadfile(path)
		if not chunk then profDB = false; return nil end
		chunk("ProfessionDB", {})
	end
	profDB = LibStub("LibProfessionDB-1.0", true) or false
	return profDB or nil
end

--- Install a recipe universe for the test, dropping every index derived from it.
---
--- In the game `addon.recipeDB` is set ONCE at load (Data/RecipeDB.lua points it
--- at LibProfessionDB), so the addon builds lazy reverse indexes off it —
--- `_craftedItemMap`, the item stat/tooltip text caches — and never invalidates
--- them. That is correct in production. Offline it is a trap: a spec that swaps
--- in its own fixture leaves the FIRST fixture's index answering for every later
--- spec FILE, which shows up only in a full-suite run. Dropping the caches here
--- rather than in each spec means it cannot be forgotten.
function M.setRecipeDB(db)
	local ns = M.boot()
	ns.recipeDB        = db or {}
	ns._craftedItemMap = nil
	ns._itemStatText   = nil
	ns._itemTTText     = nil
	return ns.recipeDB
end

--- Wipe the REAL AceDB guild database back to empty and hand it back. The DB is
--- a singleton for the whole suite (AceDB:New once, at boot), so a spec that
--- leaves rows behind corrupts later spec FILES — this is the reset for anything
--- that goes through `addon:GetGuildDb()` rather than a passed-in table.
function M.resetDb()
	local ns = M.initDb()
	local g  = ns.guildDb.global
	for key, value in pairs(g) do
		if type(value) == "table" then
			for k in pairs(value) do value[k] = nil end
		else
			g[key] = nil
		end
	end
	-- Re-create the skeleton. A spec is entitled to nil a whole sub-table (to
	-- model "this client has never scanned"), and AceDB does not put it back —
	-- so without this the NEXT test inherits a missing table and fails somewhere
	-- unrelated to what it is testing.
	for _, key in ipairs({ "recipes", "skills", "cooldowns", "specializations",
	                       "altGroups", "altClaims", "accountChars", "lastScan",
	                       "hashes", "pendingPurge", "guildRegistry" }) do
		if type(g[key]) ~= "table" then g[key] = {} end
	end
	return g
end

--- An empty guild DB in the shape the addon's AceDB defaults produce. Every
--- sub-table the code indexes without a nil-guard belongs here.
function M.newGdb()
	return {
		recipes         = {},
		skills          = {},
		cooldowns       = {},
		specializations = {},
		altGroups       = {},
		altClaims       = {},
		accountChars    = {},
		lastScan        = {},
		hashes          = {},
	}
end

return M
