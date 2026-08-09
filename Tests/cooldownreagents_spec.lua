-- Every reagent Data/CooldownIds.lua still writes down by hand, cross-checked
-- against ProfessionDB's actual shipped SpellReagents data.
--
-- THIS SPEC EXISTS BECAUSE NINE OF FORTY-NINE HAND-WRITTEN REAGENT IDS WERE
-- WRONG, and every one of them had a correct comment sitting next to it:
--
--   17187 Transmute: Arcanite      -> 12364 "Huge Emerald"   (Arcane Crystal is 12363)
--   11480 Mithril to Truesilver    -> 3859  "Steel Bar"      (Mithril Bar is 3860)
--   17559/60/61/62 elemental       -> 7067-7070 "Elemental X" (recipes take "Essence of X")
--   28569 / 28581 Primal Water     -> 22454   <- NOT A REAL ITEM ID
--   28584 Primal Life              -> 22455   <- NOT A REAL ITEM ID
--
-- The Cooldowns tab's reagent count, its [AH] price lookup, its [Bank] button
-- and its shopping-list add all read that id. For six of them the player was
-- shown the wrong item; for three the id resolves to nothing at all.
--
-- Nothing caught it because the numbers were only ever compared against the
-- comment beside them, and ProfessionDB has carried Blizzard's own reagent list
-- the whole time. The bulk of the data is now DERIVED from the library, so what
-- is left to guard is the small residue that still cannot be:
--
--   FEATURED_REAGENT  which of several reagents to show on a collapsed row.
--                     A display choice, so no DBC field expresses it — but the
--                     id must still be one the recipe genuinely uses.
--   REAGENT_FALLBACK  what to show when ProfessionDB is absent. Unverifiable at
--                     runtime by definition, which is exactly why it is
--                     verified here.
--
-- Read from SOURCE because both are file-locals. Same technique as
-- Tests/recipegate_spec.lua's structural guard, and for the same reason: the
-- thing worth pinning is not reachable through the public surface.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

--- Parse `local <NAME> = { [k] = { id = N, qty = M }, ... }` out of the source.
local function parseIdQty(src, name)
	local block = src:match("\nlocal " .. name .. " = %{(.-)\n%}")
	assert(block, name .. " not found in Data/CooldownIds.lua — the guard is "
		.. "reading source, so a rename silently disarms it")
	local out = {}
	for key, id, qty in block:gmatch("%[(%d+)%]%s*=%s*{%s*id%s*=%s*(%d+),%s*qty%s*=%s*(%d+)") do
		out[tonumber(key)] = { id = tonumber(id), qty = tonumber(qty) }
	end
	return out
end

--- Parse `local <NAME> = { [k] = N, ... }` out of the source.
local function parseIdMap(src, name)
	local block = src:match("\nlocal " .. name .. " = %{(.-)\n%}")
	assert(block, name .. " not found in Data/CooldownIds.lua")
	local out = {}
	for key, id in block:gmatch("%[(%d+)%]%s*=%s*(%d+),") do
		out[tonumber(key)] = tonumber(id)
	end
	return out
end

--- The real library with the _core files these cooldowns live in. Loaded by
--- path, as env.professionDB does — the libs manifest deliberately excludes the
--- Data trees, which are hundreds of files of addon payload.
-- EVERY profession core, every version — enumerated rather than hand-listed.
--
-- A curated list was the first attempt and it was the wrong instinct: it became
-- a third place to keep in sync with the tables it is supposed to be checking,
-- and it was already wrong (Titansteel Bar ships in Cata Blacksmithing as well
-- as Wrath, so a cooldown went unverified). Absent combinations are normal —
-- Vanilla has no Inscription — and are skipped without complaint. What must not
-- be silent is a hand-maintained entry that no core covers, and the "covers
-- every entry" case below is what fails on that.
local VERSIONS = { "Vanilla", "TBC", "Wrath", "Cata", "Mists" }
local PROFESSIONS = {
	"Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
	"Firstaid", "Fishing", "Inscription", "Jewelcrafting", "Leatherworking",
	"Mining", "Tailoring",
}

local CORE_FILES = {}
for _, version in ipairs(VERSIONS) do
	for _, prof in ipairs(PROFESSIONS) do
		CORE_FILES[#CORE_FILES + 1] = ("Data/%s/_core/%s.lua"):format(version, prof)
	end
end

local lib, src, missing, index

--- Reagents from EVERY version's `_core` file, keyed by spell alone.
---
--- Collected through a capture stub rather than the real library, and that is
--- load-bearing. Each shipped data file opens with
--- `if not lib:IsGameVersion("Wrath") then return end`, and this env runs as
--- Classic Era — so loading all 23 files against the real library registers
--- only the Vanilla ones and every other check quietly verifies nothing.
---
--- That is not hypothetical: this spec passed with exactly that hole until
--- mutation-testing it showed a reintroduced TBC defect going undetected. The
--- flavour gate is correct behaviour for the CLIENT; here the question is
--- whether an id is right in the shipped data, which has no flavour.
local function collectReagents()
	local out = {}
	local capture = {}
	function capture:IsGameVersion() return true end
	function capture:LoadCore(_profId, core)
		for spellId, entry in pairs(core) do
			local id = tonumber(spellId)
			if id and type(entry) == "table" and type(entry.reagents) == "table"
			   and next(entry.reagents) then
				local r = {}
				for itemId, qty in pairs(entry.reagents) do
					r[tonumber(itemId) or itemId] = tonumber(qty) or qty
				end
				out[id] = r
			end
		end
	end
	-- Anything else a _core file may call (LoadEnchantsCore, ...) is irrelevant
	-- here; swallow it rather than erroring on a file that grows a new call.
	setmetatable(capture, { __index = function() return function() end end })

	local realStub = _G.LibStub
	_G.LibStub = setmetatable({}, { __call = function(_, major)
		return major == "LibProfessionDB-1.0" and capture or realStub(major, true)
	end })

	missing = {}
	for _, file in ipairs(CORE_FILES) do
		local path  = env.libs.pathOf("LibProfessionDB-1.0", file)
		local chunk = loadfile(path)
		if chunk then chunk("ProfessionDB", {}) else missing[#missing + 1] = file end
	end

	_G.LibStub = realStub
	return out
end

setup(function()
	env.boot()
	src = assert(io.open("Data/CooldownIds.lua")):read("*a")
	if not env.libs.available("LibProfessionDB-1.0") then return end
	env.libs.load("LibProfessionDB-1.0")
	lib   = LibStub("LibProfessionDB-1.0", true)
	index = collectReagents()
end)

local function reagentIndex() return index end

describe("hand-maintained cooldown reagents agree with ProfessionDB", function()
	it("built a populated reagent index across every version", function()
		-- Without this the checks below would walk an empty index and pass while
		-- verifying nothing — the exact shape of silently-passing test the
		-- harness rules forbid, and the shape this spec was in until the flavour
		-- gate was noticed.
		--
		-- `missing` is NOT asserted empty: the file list is a full cross-product
		-- and absent combinations are correct (Vanilla has no Inscription). The
		-- floor is on the RESULT instead, which cannot be satisfied by accident.
		if not lib then return pending("ProfessionDB is not installed alongside") end
		local n = 0
		for _ in pairs(reagentIndex()) do n = n + 1 end
		assert.is_true(n > 2000, "expected a populated cross-version reagent index, got " .. n)
		assert.is_true(#missing < #CORE_FILES,
			"no core file loaded at all — the path helper is probably wrong")
	end)

	it("covers every hand-maintained entry, rather than skipping the unloaded", function()
		-- The hazard this closes, found by mutation-testing the guard itself:
		-- both checks below skip a spell the index does not know, so an entry
		-- for a profession missing from CORE_FILES was verified by nothing and
		-- still reported green. Reintroducing a real shipped defect (28569 ->
		-- item 22454, which does not exist) did NOT fail, because TBC Alchemy
		-- was not loaded. A guard with a silent hole is worse than none.
		if not lib then return pending("ProfessionDB is not installed alongside") end
		local index = reagentIndex()
		local uncovered = {}
		for spellId in pairs(parseIdMap(src, "FEATURED_REAGENT")) do
			if not index[spellId] then uncovered[#uncovered + 1] = "FEATURED " .. spellId end
		end
		for spellId in pairs(parseIdQty(src, "REAGENT_FALLBACK")) do
			if not index[spellId] then uncovered[#uncovered + 1] = "FALLBACK " .. spellId end
		end
		assert.same({}, uncovered)
	end)

	it("features only a reagent the recipe actually uses", function()
		if not lib then return pending("ProfessionDB is not installed alongside") end
		local index = reagentIndex()
		local bad = {}
		for spellId, itemId in pairs(parseIdMap(src, "FEATURED_REAGENT")) do
			local real = index[spellId]
			if real and not real[itemId] then
				local have = {}
				for i in pairs(real) do have[#have + 1] = i end
				table.sort(have)
				bad[#bad + 1] = ("spell %d features item %d; recipe uses %s")
					:format(spellId, itemId, table.concat(have, ", "))
			end
		end
		assert.same({}, bad)
	end)

	it("keeps no fallback that contradicts the shipped data", function()
		-- Both halves matter. A wrong ID shows the player the wrong item; a
		-- wrong QUANTITY shows the right item and the wrong number, which is
		-- harder to notice and just as wrong on a shopping list.
		if not lib then return pending("ProfessionDB is not installed alongside") end
		local index = reagentIndex()
		local bad = {}
		for spellId, rg in pairs(parseIdQty(src, "REAGENT_FALLBACK")) do
			local real = index[spellId]
			if real then
				if not real[spellId] and not real[rg.id] then
					bad[#bad + 1] = ("spell %d falls back to item %d, which the recipe does not use")
						:format(spellId, rg.id)
				elseif real[rg.id] and real[rg.id] ~= rg.qty then
					bad[#bad + 1] = ("spell %d falls back to %dx item %d; recipe needs %d")
						:format(spellId, rg.qty, rg.id, real[rg.id])
				end
			end
		end
		assert.same({}, bad)
	end)

	it("no longer carries the tables the wrong ids lived in", function()
		-- REAGENTS / TRANSMUTE_REAGENTS / MULTI_REAGENTS were the hand-written
		-- copies of data ProfessionDB already ships. Re-adding one would
		-- reintroduce the whole class of defect, so fail if a name comes back.
		for _, name in ipairs({ "REAGENTS", "TRANSMUTE_REAGENTS", "MULTI_REAGENTS" }) do
			assert.is_nil(src:match("\nlocal " .. name .. " = %{"),
				name .. " is back in Data/CooldownIds.lua — reagents are derived "
				.. "from ProfessionDB now; a second copy is what shipped nine wrong ids")
		end
	end)
end)
