-- What opening the Professions tab COSTS, measured against a real guild database.
--
-- Reported from Discord, 2026-09-11: "getting a lag on open of about 3-5
-- seconds". The Professions tab is the default tab, and on a cache miss it runs
-- BrowserTab's BuildFullList(0, "guild") SYNCHRONOUSLY -- every recipe in every
-- profession, every crafter under each, the visibility gate per crafter. The
-- background warm that should make the open a cache hit starts 8 s after login
-- at 4 ms per frame, so whether the open is a hit depends on how long the build
-- takes; a build that is slow makes the warm slow, which makes a miss likely,
-- which makes the open slow. One number decides all of that, and this spec
-- measures it rather than reasoning about it.
--
-- THE DATA IS REAL. The operator's own SavedVariables file for this addon (2.4 MB,
-- ~99k lines, ~45k recipe-crafter pairs) is loaded straight into the harness's
-- AceDB, with the full shipped Vanilla recipe database from ProfessionDB. The
-- roster is every character that has ever broadcast (gdb.lastScan), so the
-- crafters who never did -- alts, departed members -- take the alt-group gate,
-- which is the path this spec suspects.
--
-- WHAT THIS CANNOT MEASURE, said up front: the harness's item API is empty, so
-- the per-crafted-item tooltip scrape in BuildFullList (GetItemTooltipSearchText
-- -> SetItemByID) returns before doing any work. In the client that is one
-- C-side tooltip render per recipe with a crafted item. Everything else --
-- the Lua the build spends its time in -- runs as it does in game, on the same
-- Lua 5.1.
--
-- The SV path is the operator's account by default; set TOGPM_SV to point at
-- another. When the file is absent every case is `pending`, never silently
-- green.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env  = require("env_togpm")
local libs = require("env.libs")

local SV_PATH = os.getenv("TOGPM_SV")
	or ("C:/Program Files (x86)/World of Warcraft/_classic_era_/WTF/Account/IANPLAMONDON/"
	    .. "SavedVariables/TOGProfessionMaster.lua")

-- The guild the SV's crafters are tagged for (guildRegistry["8e5c20"]).
local GUILD, FACTION = "The Old Gods", "Horde"

-- Budgets. A frame at 60 fps is 16.7 ms; a synchronous build the player waits
-- for is a hitch above ~100 ms and a "lag" at the reported 3-5 s. The budget is
-- what the code should hold, not what it does: a red here is the report.
local BUILD_BUDGET_MS      = 250
local ALT_GATE_BUDGET_US   = 50     -- per IsAltOfInRosterCharacter call, microseconds

-- THE TIMER. On Windows os.clock is WALL time (Microsoft's CRT clock() "doesn't
-- strictly conform to ISO C"), so one sample measures machine load as well: the
-- same build read 233 ms in one run and 671 ms in the next while other suites
-- ran (inbox 0822420a). Load only ever ADDS wall time, so a budget gates on the
-- FASTEST of a few runs (wow.bestTime, WoWAPITesting 953768d). Only repeatable
-- work is timed this way; the login stages mutate the database and run once.
-- Five, the harness's own default: three still lost all its samples to one
-- busy stretch with four other suites running (BuildFullList 327 ms against
-- 64 ms one run earlier, 2026-10-04).
local BEST_OF = 5
local function bestMs(fn)
	return (env.wow.bestTime(fn, BEST_OF)) * 1000
end

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = deepCopy(x) end
	return out
end

local ns, B, gdb, sv
local stats = {}

local VANILLA_PROFS = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
                        "Firstaid", "Fishing", "Leatherworking", "Mining", "Tailoring" }

--- Read the SavedVariables file as the client does: it is a Lua chunk that
--- assigns two globals. Run it in a private environment and take them.
local function loadSavedVariables(path)
	local chunk = loadfile(path)
	if not chunk then return nil end
	local sandbox = {}
	setfenv(chunk, sandbox)
	chunk()
	return sandbox.TOGPM_GuildDB and sandbox.TOGPM_GuildDB.global
end

--- The full shipped Vanilla recipe database, wired exactly as Data/RecipeDB.lua
--- does in game: addon.recipeDB[profId] = lib:GetRecipes(profId).
local function loadRecipeDB()
	if not libs.available("LibProfessionDB-1.0") then return nil end
	libs.load("LibProfessionDB-1.0")
	for _, prof in ipairs(VANILLA_PROFS) do
		for _, dir in ipairs({ "_core", "enUS" }) do
			local chunk = loadfile(libs.pathOf("LibProfessionDB-1.0", "Data/Vanilla/" .. dir .. "/" .. prof .. ".lua"))
			if chunk then chunk("ProfessionDB", {}) end
		end
	end
	local lib = LibStub("LibProfessionDB-1.0", true)
	if not lib then return nil end
	local db = {}
	for _, profId in ipairs(lib:GetProfessions()) do db[profId] = lib:GetRecipes(profId) end
	return db
end

local function ms(seconds) return seconds * 1000 end

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/SyncLog.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/ReagentWatch.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Crafting/CraftQueue.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	B = env.loadModule("GUI/BrowserTab.lua").BrowserTab
	env.loadModule("GUI/CooldownsTab.lua")
	env.loadModule("GUI/MissingRecipesTab.lua")
	env.loadModule("GUI/GuildTab.lua")
	env.loadModule("GUI/AHProfitTab.lua")
	env.loadModule("GUI/ReagentTracker.lua")
end)

before_each(function()
	-- Loaded PER TEST, not once: env.resetDb() wipes the AceDB tables in place,
	-- and the SV's tables are installed into it by reference below, so a copy
	-- loaded once would be emptied by the second test's reset. (That happened;
	-- the fixture guards in each case caught it as "the fixture is wrong".)
	sv = loadSavedVariables(SV_PATH)
	if not sv then return end
	env.install()
	env.installFrames()
	env.guildName, env.faction = GUILD, FACTION
	gdb = env.resetDb()
	ns.Print = function() end

	-- The real database, wholesale. Every top-level table the SV holds.
	for k, v in pairs(sv) do gdb[k] = v end

	-- Roster: everyone who has ever broadcast is a member. WoW hands the roster
	-- "Name-Realm" for a connected-realm cluster, and these keys already are.
	local members = {}
	for charKey in pairs(sv.lastScan or {}) do
		members[#members + 1] = { name = charKey, isOnline = false }
	end
	env.roster(members)

	local db = loadRecipeDB()
	env.setRecipeDB(db)
	-- Every shipped recipe spell exists on this client, or the Vanilla
	-- "spell not on this client" gate drops the whole list.
	for _, recipes in pairs(db or {}) do
		for spellId in pairs(recipes) do env.spellsExist(spellId) end
	end
	-- Keep the client item API silent: its cost is the client's, not Lua's.
	env.itemAPI("GetItemInfo", function() return nil end)
	env.itemAPI("GetItemIcon", function() return nil end)
	_G.GetSpellTexture = function(_spell) return nil end
end)

describe("the real database, described", function()
	it("is the reporter's scale, so the numbers below mean something", function()
		if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
		local pairsN, uniqueCrafters, recipesN = 0, {}, 0
		for _, prof in pairs(gdb.recipes or {}) do
			for _, rd in pairs(prof) do
				recipesN = recipesN + 1
				for ck in pairs(rd.crafters or {}) do
					pairsN = pairsN + 1
					uniqueCrafters[ck] = true
				end
			end
		end
		local altEntries = 0
		for _, arr in pairs(gdb.altGroups or {}) do altEntries = altEntries + #arr end
		local claimEntries = 0
		for _, arr in pairs(gdb.altClaims or {}) do claimEntries = claimEntries + #arr end
		stats.recipes, stats.pairs, stats.crafters = recipesN, pairsN, count(uniqueCrafters)
		stats.altKeys, stats.altEntries, stats.claimEntries = count(gdb.altGroups), altEntries, claimEntries
		stats.roster = count(sv.lastScan)
		io.write(("  [openperf] recipes with crafters %d | recipe-crafter pairs %d | unique crafters %d | roster %d\n")
			:format(recipesN, pairsN, stats.crafters, stats.roster))
		io.write(("  [openperf] altGroups: %d keys, %d entries serialized | altClaims: %d keys, %d entries (the source)\n")
			:format(stats.altKeys, altEntries, count(gdb.altClaims), claimEntries))
		assert.is_true(pairsN > 10000, "expected a large guild; got " .. pairsN .. " pairs")
	end)
end)

describe("the synchronous open path", function()
	it("BuildFullList(0, 'guild') -- what a cache miss on open costs the player", function()
		if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
		local list
		local elapsed = bestMs(function() list = B._BuildFullList(0, "guild", { showAll = false }) end)
		stats.buildMs, stats.rows = elapsed, #list
		io.write(("  [openperf] BuildFullList(All) synchronous: %.0f ms for %d rows (budget %d ms)\n")
			:format(elapsed, #list, BUILD_BUDGET_MS))
		assert.is_true(#list > 500, "the build produced almost nothing; the fixture is wrong, not fast")
		assert.is_true(elapsed <= BUILD_BUDGET_MS,
			("synchronous All-professions build took %.0f ms; budget is %d ms"):format(elapsed, BUILD_BUDGET_MS))
	end)

	it("the warm rebuilds every profession on top of All -- the total the 4 ms/frame budget has to absorb", function()
		if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
		local t0 = os.clock()
		local rows = 0
		for profId in pairs(gdb.recipes or {}) do
			rows = rows + #B._BuildFullList(profId, "guild", { showAll = false })
		end
		local perProf = ms(os.clock() - t0)
		local total = perProf + (stats.buildMs or 0)
		-- At 4 ms of work per 16.7 ms frame the wall-clock is ~4x the CPU time.
		io.write(("  [openperf] per-profession builds: %.0f ms (%d rows); whole warm ~%.0f ms CPU, "
			.. "~%.1f s wall at 4 ms/frame\n"):format(perProf, rows, total, total * (16.7 / 4) / 1000))
		assert.is_true(perProf > 0)
	end)
end)

-- The window remembers its last tab, so "on open" can be any of these. Each is
-- drawn for real against real AceGUI and the real database, cold (no cache),
-- and timed. Text metrics are not faithful offline, so what is measured is the
-- Lua the tab spends building its rows -- the same Lua that runs in game.
describe("each tab drawn cold on the real database", function()
	local TAB_BUDGET_MS = 250
	-- Cold every time: `prep` empties the tab's cache before each timed draw.
	local function timeDraw(tab, prep)
		return bestMs(function()
			if prep then prep() end
			env.drawTab(tab)
		end)
	end

	local tabs = {
		{ "Professions (Browser)", "BrowserTab",        function() B._listCache = {} end },
		{ "Cooldowns",             "CooldownsTab" },
		{ "Missing Recipes",       "MissingRecipesTab" },
		{ "Guild",                 "GuildTab" },
		{ "Profit Planner",        "AHProfitTab" },
	}
	for _, spec in ipairs(tabs) do
		local label, field, prep = spec[1], spec[2], spec[3]
		it(label .. " draws inside the budget", function()
			if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
			local elapsed = timeDraw(ns[field], prep)
			io.write(("  [openperf] %s Draw (cold): %.0f ms (budget %d ms)\n"):format(label, elapsed, TAB_BUDGET_MS))
			assert.is_true(elapsed <= TAB_BUDGET_MS,
				("%s cold draw took %.0f ms; budget %d ms"):format(label, elapsed, TAB_BUDGET_MS))
		end)
	end
end)

describe("the alt-group visibility gate", function()
	it("IsAltOfInRosterCharacter walks the WHOLE altGroups table per call", function()
		if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
		-- The crafters the memo cannot save: each unique crafter NOT in the
		-- roster reaches this gate once per build.
		local GC = ns.Scanner.GuildRoster
		local probes = {}
		for _, prof in pairs(gdb.recipes or {}) do
			for _, rd in pairs(prof) do
				for ck in pairs(rd.crafters or {}) do
					if not probes[ck] and not GC:IsInGuild(ck) then probes[ck] = true end
				end
			end
		end
		local n = count(probes)
		local hits
		local elapsed = bestMs(function()
			hits = 0
			for ck in pairs(probes) do
				if ns:IsAltOfInRosterCharacter(ck) then hits = hits + 1 end
			end
		end)
		local perCallUs = n > 0 and (elapsed * 1000 / n) or 0
		io.write(("  [openperf] alt gate: %d not-in-roster crafters, %d kept as alts, %.0f ms total, "
			.. "%.1f us/call (budget %d us)\n"):format(n, hits, elapsed, perCallUs, ALT_GATE_BUDGET_US))
		assert.is_true(n > 0, "no crafter was outside the roster; the roster fixture is wrong")
		assert.is_true(perCallUs <= ALT_GATE_BUDGET_US,
			("%.1f us per IsAltOfInRosterCharacter call; budget %d us"):format(perCallUs, ALT_GATE_BUDGET_US))
	end)
end)

-- The LOGIN path, 2026-09-11 evening: "it 'glitched' on login. i told you,
-- this happens ON LOGIN". The client's profiler charges everything an Ace
-- addon does at login to whichever addon loaded Ace3 (an OnEvent script is
-- blamed on the frame's creator, and AceEvent/AceAddon/AceTimer own one frame
-- each), so it cannot say what TOGPM's share of the login frame is. This can:
-- each synchronous stage of the login path, run in the order the client runs
-- it, against the real database, timed. The budget is per stage: a stage over
-- ~100 ms is a hitch on its own, and the stages run back to back.
describe("the login path on the real database", function()
	local STAGE_BUDGET_MS = 100

	it("REPORT + budget: every synchronous login stage, in order", function()
		if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
		local S  = ns.Scanner
		-- The real library's hashing under a recorder for the sends: the wire is
		-- DeltaSync's cost and has its own suite; the Lua that builds what goes on
		-- it is ours and is what is timed here.
		local real = env.deltaSync()
		local DS = {
			BroadcastItemHashes = function() return true, 0 end,
			BroadcastData       = function() return true, 0 end,
			p2p = { OnItemCompleted = function() end },
			ComputeHash           = function(_, t) return real:ComputeHash(t) end,
			ComputeStructuredHash = function(_, t) return real:ComputeStructuredHash(t) end,
		}
		S.DS = DS
		S._lastBroadcastHashes, S._lastBroadcastAt = nil, 0
		local stages = {
			-- OnInitialize
			{ "OnInitialize: MigrateGuildDb",          function() ns:MigrateGuildDb() end },
			{ "OnInitialize: RemapItemKeysToSpellIds", function() ns:RemapItemKeysToSpellIds() end },
			{ "OnInitialize: RemoveBogusCooldowns",    function() ns:RemoveBogusCooldowns() end },
			-- OnEnable -> Scanner:Init
			{ "Scanner:Init: RebuildAltGroups",        function() S:RebuildAltGroups(gdb) end },
			-- PLAYER_ENTERING_WORLD -> InitDeltaSync's first-load hash rebuild + scrub
			-- `fresh`: it only does its work once (later calls find every leaf and
			-- no-op), so each timed run gets a fresh copy of the two tables it
			-- writes and the budget gates on the fastest; the last run's tables
			-- are kept, as one real call would leave them.
			{ "PEW: HashManager:RebuildOnFirstLoad",   function() ns.HashManager:RebuildOnFirstLoad(DS, gdb) end,
			  fresh = { "hashes", "lastScan" } },
			{ "PEW: ScrubObsoleteRecipeNames",         function() S:ScrubObsoleteRecipeNames() end },
			-- +2 s timer
			{ "+2s: ScanCooldowns",                    function() S:ScanCooldowns() end },
			{ "+2s: ScanGatheringProfessions",         function() S:ScanGatheringProfessions() end },
			{ "+2s: BroadcastHashes (payload build)",  function() S:BroadcastHashes() end },
			-- +3 s / +4 s timers
			-- Guarded on the BARE global (audit finding 30, site 4), which the
			-- harness does not install -- so without this the stage measures the
			-- bail, not the walk. Installed for the stage and removed after.
			{ "+3s: BackfillReagentItemIds",           function()
				_G.GetItemInfoInstant = function() return nil end
				S:BackfillReagentItemIds()
				_G.GetItemInfoInstant = nil
			end },
			{ "+4s: BackfillBogusRecipeNames",         function() S:BackfillBogusRecipeNames() end },
			-- What a peer's first contact after our login makes us build, in one go.
			{ "on request: BuildFullGuildPayload",     function() S:BuildFullGuildPayload() end },
		}
		local total, worst, worstMs = 0, nil, 0
		for _, stage in ipairs(stages) do
			local label, fn = stage[1], stage[2]
			local elapsed
			if stage.fresh then
				local saved = {}
				for _, f in ipairs(stage.fresh) do saved[f] = gdb[f] end
				elapsed = math.huge
				for _ = 1, BEST_OF do
					for _, f in ipairs(stage.fresh) do gdb[f] = deepCopy(saved[f]) end
					local t0 = os.clock()
					fn()
					elapsed = math.min(elapsed, ms(os.clock() - t0))
				end
			else
				local t0 = os.clock()
				fn()
				elapsed = ms(os.clock() - t0)
			end
			total = total + elapsed
			if elapsed > worstMs then worst, worstMs = label, elapsed end
			io.write(("  [openperf] login %-40s %6.0f ms\n"):format(label, elapsed))
		end
		io.write(("  [openperf] login stages total: %.0f ms of Lua; worst: %s at %.0f ms (budget %d ms per stage)\n")
			:format(total, tostring(worst), worstMs, STAGE_BUDGET_MS))
		assert.is_true(worstMs <= STAGE_BUDGET_MS,
			("login stage '%s' took %.0f ms; budget %d ms"):format(tostring(worst), worstMs, STAGE_BUDGET_MS))
	end)

	-- The login hash broadcast makes every online peer compare and then send
	-- us the leaves we differ on, and serve them ours. Each leaf crosses the
	-- wire through DeltaSync's SerializeWithChecksum (AceSerializer plus a
	-- byte-by-byte Lua checksum over the whole string) and back through
	-- DeserializeWithChecksum. That is Lua running on the receiving client's
	-- main thread, charged to Ace3 by the profiler, and this is what it costs
	-- for the largest leaf in the real database.
	it("REPORT + budget: the wire cost of each crafters leaf, serialized and deserialized", function()
		if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
		local S    = ns.Scanner
		local real = env.deltaSync()
		S.DS = real
		local WIRE_BUDGET_MS = 100
		local worst, worstMs, worstBytes, worstWire = nil, 0, 0, nil
		for profId in pairs(gdb.recipes or {}) do
			local key = "crafters:" .. profId
			local t0 = os.clock()
			local payload = S:BuildLeafPayload(key)
			local buildMs = ms(os.clock() - t0)
			if payload then
				t0 = os.clock()
				local wire = real:SerializeWithChecksum(payload)
				local serMs = ms(os.clock() - t0)
				-- Once per leaf here; the budget re-times only the worst one below,
				-- best of BEST_OF -- five passes over every leaf ran this file past
				-- the runner's 60 s limit under load (2026-10-04).
				t0 = os.clock()
				local ok = real:DeserializeWithChecksum(wire)
				local deserMs = ms(os.clock() - t0)
				assert.is_true(ok, "round trip failed for " .. key)
				local pairsN = 0
				for _, set in pairs(payload.leaves[key].data or {}) do pairsN = pairsN + count(set) end
				io.write(("  [openperf] wire %-16s %6d pairs %8d bytes  build %4.0f ms  serialize+checksum %4.0f ms  "
					.. "checksum+deserialize %4.0f ms\n"):format(key, pairsN, #wire, buildMs, serMs, deserMs))
				if deserMs > worstMs then worst, worstMs, worstBytes, worstWire = key, deserMs, #wire, wire end
			end
		end
		assert.is_truthy(worst, "no crafters leaf was built; the fixture is wrong")
		-- The gate: the worst leaf again, fastest of BEST_OF.
		worstMs = bestMs(function() real:DeserializeWithChecksum(worstWire) end)
		io.write(("  [openperf] wire worst receive: %s at %.0f ms for %d bytes (budget %d ms)\n")
			:format(tostring(worst), worstMs, worstBytes, WIRE_BUDGET_MS))
		assert.is_true(worstMs <= WIRE_BUDGET_MS,
			("receiving %s costs %.0f ms of Lua; budget %d ms"):format(tostring(worst), worstMs, WIRE_BUDGET_MS))
	end)
end)

--- Lines the client's SV writer would emit for a value: one per scalar, and
--- for a table one open, one close, plus its contents.
local function svLines(v)
	if type(v) ~= "table" then return 1 end
	local n = 2
	for _, x in pairs(v) do n = n + svLines(x) end
	return n
end

describe("what the SavedVariables carry", function()
	it("REPORT: lines per section, and what each recipe entry stores besides its crafters", function()
		if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
		local total = svLines(sv)
		local rows = {}
		for k, v in pairs(sv) do rows[#rows + 1] = { k, svLines(v) } end
		table.sort(rows, function(a, b) return a[2] > b[2] end)
		io.write(("  [openperf] TOGPM_GuildDB.global: %d serialized lines\n"):format(total))
		for _, r in ipairs(rows) do
			if r[2] >= 50 then
				io.write(("  [openperf]   %-20s %7d lines  %5.1f%%\n"):format(r[1], r[2], 100 * r[2] / total))
			end
		end
		-- Recipe entries: the crafter map is the data; anything else is metadata
		-- the shipped recipe DB also holds, or a leftover from the recipemeta era.
		local fields, recipesN, crafterLines = {}, 0, 0
		for _, prof in pairs(sv.recipes or {}) do
			for _, rd in pairs(prof) do
				recipesN = recipesN + 1
				crafterLines = crafterLines + svLines(rd.crafters or {})
				for k, v in pairs(rd) do
					if k ~= "crafters" then
						fields[k] = fields[k] or { n = 0, lines = 0 }
						fields[k].n = fields[k].n + 1
						fields[k].lines = fields[k].lines + svLines(v) + 0   -- key line included in svLines(scalar)=1
					end
				end
			end
		end
		io.write(("  [openperf] recipes: %d entries; crafter maps %d lines; other fields:\n"):format(recipesN, crafterLines))
		for k, f in pairs(fields) do
			io.write(("  [openperf]   %-12s on %4d recipes, %5d lines\n"):format(k, f.n, f.lines))
		end
		-- Characters: how many distinct keys each per-character section holds,
		-- against the roster of everyone who has ever broadcast.
		local function keys(t) return count(t) end
		io.write(("  [openperf] per-character keys: skills %d | cooldowns %d | lastScan %d | specializations %d "
			.. "| altClaims %d\n"):format(keys(sv.skills), keys(sv.cooldowns), keys(sv.lastScan),
			                              keys(sv.specializations), keys(sv.altClaims)))
		io.write(("  [openperf] hashes %d leaves | syncLog %d entries | pendingPurge %d | sisterRosters %d\n")
			:format(keys(sv.hashes), keys(sv.syncLog), keys(sv.pendingPurge), keys(sv.sisterRosters)))
		assert.is_true(total > 0)
	end)

	it("altGroups is a derived view and is serialized LARGER than its source", function()
		if not sv then return pending("SavedVariables not found at " .. SV_PATH) end
		-- altGroups is rebuilt wholesale from altClaims (Scanner:RebuildAltGroups)
		-- and keyed per MEMBER, so an account of N characters is written N times
		-- over -- O(N^2) in the file for data that is O(N) in altClaims.
		local altEntries, claimEntries = 0, 0
		for _, arr in pairs(sv.altGroups or {}) do altEntries = altEntries + #arr end
		for _, arr in pairs(sv.altClaims or {}) do claimEntries = claimEntries + #arr end
		local ratio = claimEntries > 0 and altEntries / claimEntries or 0
		io.write(("  [openperf] SV altGroups entries %d vs altClaims entries %d (%.1fx)\n")
			:format(altEntries, claimEntries, ratio))
		-- A file written BEFORE the fix carries the view, and larger than its
		-- source (measured 14,095 vs 5,637 on 2026-09-11). A file written by a
		-- client running the fix carries none -- the operator's did, the same
		-- evening -- so its absence is the fix landed on disk, not a broken
		-- premise.
		if sv.altGroups ~= nil then
			assert.is_true(altEntries > claimEntries,
				("altGroups (%d) is not larger than altClaims (%d); the premise is wrong"):format(altEntries, claimEntries))
		else
			io.write("  [openperf] altGroups is absent from the file: written by a client with the fix\n")
		end

		-- The issue, stated as an assertion on the MECHANISM rather than on the
		-- file (the file only changes after a play session): the client writes
		-- SavedVariables from a table's raw contents. After the rebuild the view
		-- must still answer through gdb.altGroups, and must NOT be a raw field.
		ns.Scanner:RebuildAltGroups(gdb)
		assert.is_truthy(gdb.altGroups, "altGroups no longer answers at all after a rebuild")
		assert.is_true(count(gdb.altGroups) > 0, "altGroups rebuilt empty from a populated altClaims")
		assert.is_nil(rawget(gdb, "altGroups"),
			("altGroups is a raw field of the database, so %d entries (%.1fx altClaims) are written to disk")
				:format(altEntries, ratio))
	end)
end)
