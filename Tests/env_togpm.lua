-- env_togpm — the offline environment TOGProfessionMaster's own modules run in.
--
-- Layers three things on top of the shared WoWAPITesting harness (`Tests/wowapi`):
--
--   1. The globals the addon reads at LOAD time that the harness does not own
--      (GetCurrentRegion, C_AddOns, the FrameXML stdlib aliases, StaticPopup…).
--   2. A BOOT of the real addon core: the real Ace3 chain (via `env.ace`) and
--      the real AceCommQueue-1.0 / DeltaSync-1.0 (via `env.libs`), then
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

local wow    = require("env.wow")
local ace    = require("env.ace")
local libs   = require("env.libs")
local frames = require("env.frames")
-- The shared guild-API model (roster iteration, chat format strings, the guild
-- info APIs). Copied from GuildRoster/Tests — see the banner in env_guild.lua.
local guild = require("env_guild")

local M = { wow = wow, guild = guild, ace = ace, libs = libs, frames = frames }

-- `bit` (LuaBitOp, signed 32-bit) used to be hand-rolled here. The harness owns
-- it as of 2026-08-03 — a local copy would now shadow it and drift.

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
		return M.guildName, guild.model.guildRankName, guild.model.guildRankIndex
	end
	_G.UnitName            = function() return M.playerName end
	_G.GetRealmName        = function() return M.realmName end
	_G.GetNormalizedRealmName = function() return M.realmName end
	_G.UnitFactionGroup    = function() return M.faction end
	_G.GetServerTime       = function() return M.serverTime end
end
M.installIdentity = installIdentity

-- Tooltip minimum width was a stand-in here for about an hour on 2026-08-07 and
-- is now the harness's, delivered at 0fffb49 on the GameTooltip CLASS — so it
-- covers `TOGPMMissingRecipeTip` too, which the instance-level stand-in could
-- not. `SetMinimumWidth` also came out of the frames NOOPS table, which is what
-- had been swallowing the call. Steer it through `_G.GameTooltip` directly;
-- `Tests/tooltipminwidth_spec.lua` is the consumer.

function M.install()
	for k, v in pairs(M.DEFAULTS) do M[k] = v end
	-- The base env first: it owns C_ChatInfo, Enum, geterrorhandler, GetTime,
	-- hooksecurefunc, xpcall, bit and the rest of the plumbing Ace3 and
	-- ChatThrottleLib read. It must run BEFORE the guild model, which replaces
	-- some of the same names.
	--
	-- `frames.reset()` rather than `wow.reset()`, for the WHOLE suite rather
	-- than per-spec, and that is forced rather than chosen: every AceGUI widget
	-- file opens with `local CreateFrame, UIParent = CreateFrame, UIParent`, so
	-- AceGUI binds whichever model is installed when it loads and keeps it for
	-- the rest of the run. Ace3 is loaded once, in boot(), so the widget layer
	-- has to be in place before that or no AceGUI widget is ever testable.
	-- (frames.reset() calls wow.reset() itself, first — never the other way
	-- round, which would silently put the hollow frame back.)
	--
	-- The rich model is also the more faithful one: an absent method answers
	-- nil, as in the client, instead of the hollow model's truthy no-op that
	-- makes every `if frame.SetResizeBounds then` feature test true.
	frames.reset()
	-- Then the guild model: it owns the roster iteration APIs, the chat format
	-- strings, and a clean member list per test. resetState() also reinstalls
	-- every global it owns, which is what keeps one spec from corrupting a later
	-- spec FILE through a stub it reassigned.
	guild.resetState()
	guild.model.realm     = M.realmName
	guild.model.guildName = M.guildName
	guild.model.inGuild   = M.guildName ~= nil

	-- Identity AFTER the guild model, since they share several names.
	installIdentity()

	-- Everything env.wow owns has been deleted from here rather than redefined.
	-- The list, because it is long and each one was a shadow: hooksecurefunc,
	-- SlashCmdList, DEFAULT_CHAT_FRAME, Enum, bit (2026-08-03); SendChatMessage,
	-- C_BattleNet.SendGameData, C_Timer, StaticPopup*, print, time,
	-- GetAddOnMetadata, GetCurrentRegion (2026-08-04). Shadowing any of them
	-- silently swaps a faithful model for a stub — the hooksecurefunc no-op this
	-- file used to carry meant ChatThrottleLib's Init had never once run here.
	--
	-- FrameXML aliases the Lua stdlib into globals; addon code uses the bare
	-- names (`floor(x)`, `date()`), which stock Lua 5.1 does not have. `time` is
	-- deliberately absent — env.wow installs it, and it is a DIFFERENT clock from
	-- GetTime().
	_G.floor               = math.floor
	_G.ceil                = math.ceil
	_G.abs                 = math.abs
	_G.date                = os.date
	-- `IsAddOnLoaded` used to be stubbed here. It is NOT — the bare global does
	-- not exist on Classic Era (zero call sites under Interface/, and the harness
	-- asserts its absence), so stubbing it pointed Compat's optional-dependency
	-- check at a branch the client never takes. `C_AddOns.IsAddOnLoaded` is what
	-- runs, and env.wow ships it.

	-- Items, bags, spell cooldowns and spell knowledge were stubbed here until the
	-- harness shipped them at 616c914. All four are gone now; steer the real ones
	-- through `env.wow.items` / `.bags` / `.spellCooldowns` / `.knownSpells`, each
	-- of which starts EMPTY for the reason this env argued for and the harness
	-- then adopted as a general rule.
	--
	-- One deliberate difference from what was asked for, and it matters here: the
	-- harness installs the container API under **C_Container only**, and specs an
	-- assertion that the bare `GetContainerNumSlots` / `GetContainerItemInfo` /
	-- `GetContainerItemLink` globals are ABSENT. Classic Era documents them only
	-- under the namespace, has zero bare call sites, and — unlike the Item and
	-- SpellBook families — Blizzard wrote no deprecation fallback for them. So
	-- `Compat.lua` now takes its C_Container branch offline, which is the branch
	-- it takes in game on every flavour this addon supports. The stub here had
	-- been driving the other one.

	-- `GetSpellTexture` and `Item`/`ItemMixin` were stand-ins here until the
	-- harness shipped them at 41fdefe. Both deleted; steer the real ones
	-- through `env.wow.spells` (an undeclared spell has no icon) and
	-- `env.wow.items` + the harness's own item-load fixture.


	-- ADD to C_AddOns, never assign it: env.wow owns C_AddOns.GetAddOnMetadata,
	-- and a wholesale `_G.C_AddOns = { … }` would drop it. That is the same
	-- hazard as the wholesale C_ChatInfo assignment in the Adoption log — it
	-- fails several layers away from the line that causes it.
	_G.C_AddOns = _G.C_AddOns or {}
	-- `IsAddOnLoaded` is env.wow's now; only LoadAddOn is still ours.
	_G.C_AddOns.LoadAddOn = function() end

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

	-- `Enum` was a permissive stand-in here until the 2026-08-03 harness update.
	-- env.wow now ships Enum.SendAddonMessageResult with Blizzard's REAL values,
	-- which is what makes a delivery-verdict spec mean anything — keeping the
	-- stand-in would shadow it and make every result compare equal to 0.
end

M.install()

-- ---------------------------------------------------------------------------
-- 2. Boot the real addon core (once)
-- ---------------------------------------------------------------------------

-- Ace3 modules the addon core needs at load. `ace.load` derives the order from
-- verified file-scope dependency edges (CallbackHandler before AceEvent,
-- ChatThrottleLib before AceComm) — this list is what we USE, not an order.
--
-- AceGUI is here rather than per-spec because it must be loaded exactly once:
-- unlike AceLocale it does not bail when LibStub:NewLibrary returns nil for an
-- already-registered version — it indexes the nil and errors.
M.ACE = {
	"AceLocale-3.0", "AceAddon-3.0", "AceEvent-3.0", "AceTimer-3.0",
	"AceSerializer-3.0", "AceHook-3.0", "AceConsole-3.0", "AceComm-3.0",
	"AceDB-3.0", "AceGUI-3.0",
}

-- Suite libraries, from the sibling installs — the exact files that ship.
M.LIBS = { "AceCommQueue-1.0", "DeltaSync-1.0" }

-- Addon files loaded into the shared namespace, in .toc order. Only the ones
-- that load cleanly without a UI are here; GUI files are loaded per-spec.
M.CORE = {
	"Locale/_init.lua",
	"Locale/enUS.lua",
	"TOGProfessionMaster.lua",
	"Compat.lua",
	"Modules/RecipeGate.lua",
}

--- Load the real libraries + addon core once and return the addon namespace.
--- Repeat calls return the same namespace: AceAddon:NewAddon errors on a second
--- NewAddon for the same name, and every LibStub library is a singleton.
function M.boot()
	if booted then return booted end
	M.install()

	ace.load(unpack(M.ACE))
	for _, name in ipairs(M.LIBS) do
		if not libs.available(name) then
			error("env_togpm: required library not installed: " .. libs.pathsOf(name)[1] ..
				"\nEvery TOG addon test env loads real libraries from the sibling AddOns" ..
				" folder — check the install rather than stubbing it.")
		end
		libs.load(name)
	end

	local ns = {}
	for _, path in ipairs(M.CORE) do
		wow.loadAddonFile(path, "TOGProfessionMaster", ns)
	end

	booted = ns
	return ns
end

--- `install()`, plus the frames module handed back so a GUI spec can reach
--- `find` / `dump` / `contains` without a second require.
---
--- There is no opt-in/opt-out here: `install()` always installs the widget
--- layer, because AceGUI captures `CreateFrame` at load and Ace3 loads once for
--- the whole suite. This exists for readability at a GUI spec's call site.
function M.installFrames()
	M.install()
	return frames
end

--- Declare that these spell ids EXIST on the simulated client, so
--- `GetSpellInfo(id)` returns a name for them.
---
--- This is load-bearing, not decoration. On Vanilla the recipe browser drops
--- any recipe whose spell the client does not have
--- (`GetSpellInfo and not GetSpellInfo(recipeId)` — GUI/BrowserTab.lua), which
--- is how recipes from later expansions are kept out of a Classic Era list.
--- Until the harness installed `GetSpellInfo` that guard short-circuited and the
--- filter had NEVER run offline; every spec was passing with it inert. A spec
--- that puts a recipe in the DB and expects to see it must now say the spell
--- exists, exactly as it would on a real client.
---
--- Call AFTER install()/installFrames(): `wow.reset()` empties `wow.spells`.
function M.spellsExist(...)
	for i = 1, select("#", ...) do
		local id = (select(i, ...))
		wow.spells[id] = wow.spells[id] or { name = "Spell " .. tostring(id) }
	end
	return M
end

-- `M.loadItem` lived here until the harness shipped `wow.loadItem(id, fields)`
-- at 41fdefe, with the same two-call design this env asked for: writing
-- `wow.items[id]` models an item already cached when the frame drew, and
-- `wow.loadItem` models the data arriving afterwards and flushing the parked
-- ContinueOnItemLoad callbacks. Use `env.wow.loadItem`.

--- The real AceGUI-3.0, with all 27 stock widget types registered.
--- Loading is idempotent, so calling this per test is fine.
function M.aceGUI()
	M.boot()
	ace.load("AceGUI-3.0")
	return LibStub("AceGUI-3.0")
end

--- Install a live trade-skill session: the profession window being open, with
--- `recipes` in it. This is the state the whole Crafting tab is built on, and
--- on Classic there is exactly one way to get it in game — cast the profession
--- — so nothing in that tab is reachable offline without faking the session.
---
--- Each recipe: { name=, difficulty=, available=, reagents={ {name=,need=,have=} } }.
--- Returns a `crafted` list that DoTradeSkill appends to, so a spec can assert
--- what was actually crafted rather than only what was queued.
---
--- Faithful shapes, because they are what bites: GetTradeSkillInfo returns
--- (name, type, numAvailable, isExpanded) and a HEADER row returns type
--- "header" with no reagents — code that forgets headers walks off the end of
--- the list, which is a real Classic-scan bug class.
function M.tradeSkillSession(profName, recipes, opts)
	recipes = recipes or {}
	opts    = opts or {}
	local crafted = {}

	-- The character has to KNOW the profession, not just have its window open:
	-- the Crafting tab asks the engine for known professions first and renders
	-- "you have no professions" if the list is empty — which is how a whole tab
	-- can draw, pass a smoke test, and cover almost nothing. On Classic that
	-- list comes from the skill-line API, so the session installs it.
	--
	-- A HEADER row is included because the real skill list has them, and
	-- `isHeader` is the flag consumers must skip on — a fake with no headers
	-- lets a missing check pass here and fail in game.
	local skills = { { name = "Professions", isHeader = true } }
	for _, p in ipairs(opts.knows or { { name = profName or "Alchemy", rank = 300, max = 300 } }) do
		skills[#skills + 1] = p
	end
	_G.GetNumSkillLines = function() return #skills end
	_G.GetSkillLineInfo = function(i)
		local s = skills[i]
		if not s then return nil end
		-- name, isHeader, isExpanded, rank, numTempPoints, modifier, maxRank
		return s.name, s.isHeader or false, true, s.rank or 0, 0, 0, s.max or 0
	end
	_G.ExpandSkillHeader = function() end

	_G.GetTradeSkillLine        = function() return profName or "Alchemy", 300, 300 end
	_G.GetNumTradeSkills        = function() return #recipes end
	_G.GetTradeSkillInfo        = function(i)
		local r = recipes[i]
		if not r then return nil end
		return r.name, r.difficulty or "optimal", r.available or 1, r.isExpanded
	end
	_G.GetTradeSkillIcon        = function(i) return recipes[i] and (recipes[i].icon or 1) or nil end
	_G.GetTradeSkillItemLink    = function(i) return recipes[i] and recipes[i].link or nil end
	_G.GetTradeSkillNumReagents = function(i) return #((recipes[i] or {}).reagents or {}) end
	_G.GetTradeSkillReagentInfo = function(i, j)
		local r = ((recipes[i] or {}).reagents or {})[j]
		if not r then return nil end
		return r.name, r.texture or 1, r.need or 1, r.have or 0
	end
	_G.GetTradeSkillReagentItemLink = function(i, j)
		local r = ((recipes[i] or {}).reagents or {})[j]
		return r and r.link or nil
	end
	_G.DoTradeSkill = function(i, n) crafted[#crafted + 1] = { index = i, count = n or 1 } end
	_G.CloseTradeSkill = function() end

	-- The Craft window (Enchanting on Vanilla/TBC) is a SEPARATE API returning
	-- the same shape. Wired to the same data so a spec can flip between them.
	_G.GetNumCrafts             = function() return #recipes end
	_G.GetCraftInfo             = function(i)
		local r = recipes[i]
		if not r then return nil end
		return r.name, r.subSpellName or "", r.difficulty or "optimal", r.available or 1
	end
	_G.GetCraftIcon             = function(i) return recipes[i] and (recipes[i].icon or 1) or nil end
	_G.GetCraftItemLink         = function(i) return recipes[i] and recipes[i].link or nil end
	_G.GetCraftNumReagents      = function(i) return #((recipes[i] or {}).reagents or {}) end
	_G.GetCraftReagentInfo      = function(i, j)
		local r = ((recipes[i] or {}).reagents or {})[j]
		if not r then return nil end
		return r.name, r.texture or 1, r.need or 1, r.have or 0
	end
	_G.GetCraftReagentItemLink  = function(i, j)
		local r = ((recipes[i] or {}).reagents or {})[j]
		return r and r.link or nil
	end
	_G.GetCraftDisplaySkillLine = function() return profName or "Enchanting" end
	_G.GetCraftedItemStatText   = function() return "" end
	_G.DoCraft = function(i) crafted[#crafted + 1] = { index = i, count = 1 } end

	-- Tell the engine the window is OPEN, through the handler the client's
	-- TRADE_SKILL_SHOW drives — not by setting the flag, so the real
	-- session-open path runs. Without this the engine reports no session and
	-- the Crafting tab renders its "open a profession" state instead: the tab
	-- draws, a smoke test passes, and almost nothing is covered.
	local Engine = booted and booted.CraftingEngine
	if Engine and Engine.OnProfessionShow and not opts.closed then
		pcall(function() Engine:OnProfessionShow() end)
	end

	return crafted
end

--- Draw a tab into a REAL AceGUI container and hand back the container.
---
--- Every tab exposes `Draw(container)` and builds its entire UI from there, so
--- this one call executes the construction path a player triggers by clicking
--- the tab — several hundred lines per tab, none of it reachable before the
--- harness had a widget layer. It is a smoke fixture on purpose: what it proves
--- is "the constructor still runs against real AceGUI and real data", which is
--- the failure that otherwise only shows up in game.
---
--- The container is a plain SimpleGroup rather than the real TabGroup child:
--- tabs only ever call container methods (SetLayout/AddChild/ReleaseChildren),
--- and using the TabGroup would drag in MainWindow's whole lifecycle.
function M.drawTab(tab, opts)
	opts = opts or {}
	local GUI = M.aceGUI()
	local container = GUI:Create(opts.widget or "SimpleGroup")
	container:SetLayout(opts.layout or "List")
	container:SetWidth(opts.width or 700)
	container:SetHeight(opts.height or 480)
	tab:Draw(container)
	return container, GUI
end

--- Count the AceGUI children a draw produced, at any depth. A tab that "drew"
--- but built nothing is the failure mode a bare pcall would miss.
function M.countWidgets(container)
	local n = 0
	local function walk(w)
		for _, child in ipairs(w.children or {}) do
			n = n + 1
			walk(child)
		end
	end
	walk(container)
	return n
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
	guild.model.realm     = M.realmName
	guild.model.guildName = M.guildName
	guild.model.inGuild   = M.guildName ~= nil
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
	if not libs.available("LibProfessionDB-1.0") then profDB = false; return nil end
	libs.load("LibProfessionDB-1.0")
	-- The manifest deliberately excludes the Data/ trees (hundreds of files of
	-- addon payload), so reach for the one profession this env needs by path.
	for _, file in ipairs({ "Data/Vanilla/_core/Alchemy.lua", "Data/Vanilla/enUS/Alchemy.lua" }) do
		local chunk = loadfile(libs.pathOf("LibProfessionDB-1.0", file))
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
	ns.recipeDB          = db or {}
	ns._craftedItemMap   = nil
	-- Tooltip.lua's item -> recipe index is derived from recipeDB and cached for
	-- the session (in game recipeDB is built once at load). A spec swapping
	-- recipeDB must drop it too, or every later case reads the first one's data.
	ns._recipeItemIndex  = nil
	-- Same reasoning for ItemLink.ProfessionForRecipe's spell -> profession map.
	ns._recipeProfIndex  = nil
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
