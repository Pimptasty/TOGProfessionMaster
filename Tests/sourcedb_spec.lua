-- Data/SourceDB.lua — the shim that replaced Data/Sources/*.lua.
--
-- WHY A METATABLE RATHER THAN A REWRITE OF THE CALL SITES. The library keys
-- sources by SPELL alone (a craft spell belongs to exactly one skill line, so
-- the profession key never added information), but both production consumers
-- index `addon.sourceDB[profId][recipeId]`:
--
--   * GUI/SharedWidgets.lua's ItemLink.RecipeDetails
--   * GUI/MissingRecipesTab.lua's BuildMissingList
--
-- The shim preserves that shape so neither had to move. What this spec is
-- guarding is that the preserved shape is genuinely equivalent — the failure
-- mode is silent: a shim that answered nil everywhere would show "Unknown" on
-- every recipe, which is indistinguishable from a data gap and is exactly what
-- the old all-expansion tree looked like on a Vanilla client.
--
-- The profession scoping is the subtle half. The library's store is NOT
-- partitioned by profession, so a naive view would answer
-- sourceDB[ALCHEMY][someTailoringSpell]. Nothing would error; the Missing tab
-- would just quietly attribute a Tailoring source to an Alchemy recipe.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ALCHEMY, TAILORING = 171, 197
local TRANSMUTE  = 17187      -- Alchemy
local MOONCLOTH  = 18560      -- Tailoring
local GRINDSTONE = 2158       -- the truncated-drop case

local ns

--- A stand-in LibProfessionDB carrying just the source surface the shim uses.
--- Deliberately NOT the real library: this spec is about the shim's mapping, and
--- driving it from a fixture is the only way to assert the profession scoping
--- (the shipped data has no spell that belongs to two professions to test with).
local function installLib(sources, names)
	local lib = {
		sources = sources or {},
		names   = names or {},
	}
	function lib:GetRecipeSourceKinds(spellID)
		local raw = self.sources[spellID]
		if not raw then return nil end
		local out, any = {}, false
		for kind, ids in pairs(raw) do
			if type(ids) == "table" and #ids > 0 then out[kind], any = true, true end
		end
		if not any then return nil end
		return out
	end
	function lib:GetRecipeSources(spellID)
		local raw = self.sources[spellID]
		if not raw then return nil end
		local out, any = {}, false
		for kind, ids in pairs(raw) do
			if type(ids) == "table" and #ids > 0 then
				local list = {}
				for i = 1, #ids do list[i] = { id = ids[i], name = self.names[ids[i]] } end
				list.total = raw[kind .. "Total"] or #ids
				out[kind], any = list, true
			end
		end
		if not any then return nil end
		return out
	end
	-- Installed straight into LibStub's registry rather than through
	-- env.libs.register, which loads library FILES and cannot take an instance.
	-- Both tables have to be written: LibStub:GetLibrary reads `libs`, and a
	-- later NewLibrary compares against `minors`.
	local LibStub = _G.LibStub
	LibStub.libs["LibProfessionDB-1.0"]   = lib
	LibStub.minors["LibProfessionDB-1.0"] = 10
	return lib
end

--- Remove the library entirely, so the shim takes its no-library path.
local function forgetLib()
	local LibStub = _G.LibStub
	LibStub.libs["LibProfessionDB-1.0"]   = nil
	LibStub.minors["LibProfessionDB-1.0"] = nil
end

--- Load the shim against the current namespace. Returns the namespace.
local function loadShim()
	assert(loadfile("Data/SourceDB.lua"))("TOGProfessionMaster", ns)
	return ns
end

--- The REAL library, with a fixture loaded through its own LoadSources — not a
--- stand-in. Used by the seam tests below, where the whole point is that the
--- value shape the library actually produces is the shape consumers can eat.
local function realLibWith(sources, names)
	-- FORGET then LOAD. `libs.load` is idempotent by flag, so on its own it is a
	-- no-op once anything has loaded the library — and the describes above swap
	-- a fake into LibStub, so a bare load() hands the fake straight back. That
	-- passed in a single-file run and failed 5 ways in a whole-suite run, which
	-- is the shared-state trap the per-file sweep exists to expose from the
	-- other direction.
	env.libs.forget("LibProfessionDB-1.0")
	env.libs.load("LibProfessionDB-1.0")
	local lib = assert(LibStub("LibProfessionDB-1.0", true),
		"the real LibProfessionDB did not load; this spec must not silently fall back to a stub")
	lib.sources, lib.sourceNames = {}, {}
	lib:LoadSources(sources)
	if names then lib:LoadSourceNames(names) end
	return lib
end

before_each(function()
	ns = env.initDb()
	-- env.initDb resets the DB but hands back the SHARED addon namespace, so
	-- both of these survive from the previous test. Left alone, the no-library
	-- cases read `sourceDBFromLib = true` set by an earlier one and pass or fail
	-- for the wrong reason — the same shared-namespace hazard that made five
	-- other specs pass only in a whole-suite run.
	ns.sourceDB        = {}
	ns.sourceDBFromLib = nil
	-- The shim scopes each profession view to that profession's own recipes, so
	-- recipeDB has to be populated for the scoping to have anything to check.
	ns.recipeDB = {
		[ALCHEMY]  = { [TRANSMUTE] = {}, [GRINDSTONE] = {} },
		[TAILORING] = { [MOONCLOTH] = {} },
	}
end)

describe("SourceDB shim", function()
	it("answers the [profId][recipeId] shape both consumers already use", function()
		installLib({ [TRANSMUTE] = { trainer = { 1385 } } })
		loadShim()
		local entry = ns.sourceDB[ALCHEMY][TRANSMUTE]
		assert.is_table(entry)
		-- A non-empty TABLE per kind, not a boolean. RecipeDetails calls
		-- `next()` on this value; see the SEAM describe at the end of the file
		-- for the live error a boolean caused.
		assert.is_table(entry.trainer)
		assert.equal(1385, entry.trainer[1].id)
	end)

	it("returns nil for a recipe with no source, not an empty table", function()
		-- GUI/MissingRecipesTab.lua's FormatSources branches on `not srcEntry` to
		-- print "Unknown". An empty table is truthy and would print nothing at all.
		installLib({})
		loadShim()
		assert.is_nil(ns.sourceDB[ALCHEMY][TRANSMUTE])
	end)

	it("does NOT leak another profession's recipe through a profession view", function()
		-- The failure the scoping exists to stop. Mooncloth is Tailoring; asking
		-- for it under Alchemy must answer nil even though the library knows it.
		installLib({ [MOONCLOTH] = { trainer = { 1385 } } })
		loadShim()
		assert.is_table(ns.sourceDB[TAILORING][MOONCLOTH])
		assert.is_nil(ns.sourceDB[ALCHEMY][MOONCLOTH])
	end)

	it("survives a profession that has no recipes at all", function()
		installLib({ [TRANSMUTE] = { trainer = { 1385 } } })
		loadShim()
		assert.has_no.errors(function() return ns.sourceDB[999][TRANSMUTE] end)
	end)

	it("caches a profession view rather than rebuilding it per lookup", function()
		-- BuildMissingList hoists sourceDB[profId] out of its per-recipe loop, so
		-- this must resolve once per list build and not once per row.
		installLib({ [TRANSMUTE] = { trainer = { 1385 } } })
		loadShim()
		assert.equal(ns.sourceDB[ALCHEMY], ns.sourceDB[ALCHEMY])
	end)

	it("exposes the full detail — ids and names — via GetRecipeSourceDetail", function()
		-- The half the old data could not do at all. "Trainer" becomes "Brawn".
		installLib({ [TRANSMUTE] = { trainer = { 1385 } } }, { [1385] = "Brawn" })
		loadShim()
		local detail = ns:GetRecipeSourceDetail(TRANSMUTE)
		assert.equal(1385, detail.trainer[1].id)
		assert.equal("Brawn", detail.trainer[1].name)
	end)

	it("passes the TRUE total through, not the truncated length", function()
		installLib({ [GRINDSTONE] = { drop = { 30, 36, 40 }, dropTotal = 951 } })
		loadShim()
		local detail = ns:GetRecipeSourceDetail(GRINDSTONE)
		assert.equal(3, #detail.drop)
		assert.equal(951, detail.drop.total)
	end)

	it("answers nil from GetRecipeSourceDetail for a nil or unknown recipe", function()
		installLib({})
		loadShim()
		assert.is_nil(ns:GetRecipeSourceDetail(nil))
		assert.is_nil(ns:GetRecipeSourceDetail(TRANSMUTE))
	end)

	it("marks that the data came from the library", function()
		installLib({})
		loadShim()
		assert.is_true(ns.sourceDBFromLib)
	end)
end)

describe("SourceDB shim without the library", function()
	before_each(forgetLib)

	it("leaves sourceDB a plain empty table instead of raising", function()
		-- ProfessionDB is a required dependency so this should not happen on a
		-- normal install — but every consumer guards with
		-- `addon.sourceDB and addon.sourceDB[profId]`, and that guard has to keep
		-- behaving rather than indexing a nil.
		assert.has_no.errors(loadShim)
		assert.is_table(ns.sourceDB)
		assert.is_nil(ns.sourceDBFromLib)
		assert.is_nil(ns.sourceDB[ALCHEMY])
	end)

	it("degrades the same way against a ProfessionDB older than MINOR 10", function()
		-- Feature-detected on the METHOD, not the MINOR, so a partial rollback
		-- degrades to "Unknown sources" rather than erroring on every tooltip.
		local LibStub = _G.LibStub
		LibStub.libs["LibProfessionDB-1.0"]   = { GetRecipes = function() return {} end }
		LibStub.minors["LibProfessionDB-1.0"] = 9
		assert.has_no.errors(loadShim)
		assert.is_nil(ns.sourceDBFromLib)
	end)
end)

describe("the SEAM: what the shim yields is what consumers can eat", function()
	-- THE GAP THAT SHIPPED A LIVE ERROR, and the reason this describe exists
	-- separately from everything above.
	--
	-- Both sides were tested and the JOIN between them was not. The shim's own
	-- specs drove a stand-in library; RecipeDetails' specs hand-built
	-- `{ trainer = { [1234] = "" } }` tables. Neither ever fed the shim's REAL
	-- output into the real consumer — so nobody noticed the shim was handing
	-- back `{ trainer = true }` while RecipeDetails does `next(npcs)` on each
	-- kind's value. In game that was:
	--
	--   112x SharedWidgets.lua:429: bad argument #1 to 'next'
	--        (table expected, got boolean)
	--
	-- once per drawn row of the Missing Recipes tab.
	--
	-- So these tests use the REAL library and the REAL consumer, and assert the
	-- value SHAPE the old sourceDB guaranteed: every kind present is a non-empty
	-- table. A cheaper representation is only allowed if it still satisfies that.
	local ALCH_RECIPES = { [TRANSMUTE] = {}, [GRINDSTONE] = {} }

	before_each(function()
		ns.recipeDB = { [ALCHEMY] = ALCH_RECIPES }
		env.loadModule("GUI/SharedWidgets.lua")
	end)

	it("gives every present kind a NON-EMPTY TABLE, never a boolean", function()
		realLibWith({ [TRANSMUTE] = { t = { 1385 }, d = { 30, 36 } } })
		loadShim()
		local entry = ns.sourceDB[ALCHEMY][TRANSMUTE]
		assert.is_table(entry)
		for kind, value in pairs(entry) do
			assert.is_table(value, ("kind %q must be a table, got %s"):format(kind, type(value)))
			assert.is_not_nil(next(value), ("kind %q must be non-empty"):format(kind))
		end
	end)

	it("survives the exact call RecipeDetails makes, without raising", function()
		-- next(entry[kind]) is the line that blew up. Drive the real function.
		realLibWith({ [TRANSMUTE] = { t = { 1385 } } })
		loadShim()
		assert.has_no.errors(function()
			ns.ItemLink.RecipeDetails(ALCHEMY, TRANSMUTE)
		end)
	end)

	it("produces source LABELS through the real consumer", function()
		realLibWith({ [TRANSMUTE] = { t = { 1385 }, v = { 42 } } })
		loadShim()
		local _, sources = ns.ItemLink.RecipeDetails(ALCHEMY, TRANSMUTE)
		assert.is_table(sources)
		assert.is_true(#sources >= 2, "expected both kinds to yield a label")
	end)

	it("yields no labels for a recipe the library has no sources for", function()
		realLibWith({})
		loadShim()
		local _, sources = ns.ItemLink.RecipeDetails(ALCHEMY, TRANSMUTE)
		assert.is_nil(sources)
	end)

	it("still answers on the SECOND read, when the cache is serving it", function()
		-- The metatable rawsets its answer. A cached value of the wrong shape
		-- would raise on the second row rather than the first, which is a nastier
		-- failure to reproduce than a consistent one.
		realLibWith({ [TRANSMUTE] = { t = { 1385 } } })
		loadShim()
		ns.ItemLink.RecipeDetails(ALCHEMY, TRANSMUTE)
		assert.has_no.errors(function()
			ns.ItemLink.RecipeDetails(ALCHEMY, TRANSMUTE)
		end)
	end)
end)
