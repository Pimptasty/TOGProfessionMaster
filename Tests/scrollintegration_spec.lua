-- The recipe-scroll tooltip, end to end against the REAL shipped data.
--
-- Every other spec in this suite hands ItemLink a fake ProfessionDB. That
-- proves the branching is right and proves nothing about whether the library
-- actually answers on a live client — and the difference is not academic. The
-- 26 shipped data files sat in ProfessionDB registering against
-- `LibStub("LibItemDB-1.0")`, the handle they were generated with before the
-- move. ItemDB still had the loaders, so the data loaded into ITEMDB's tables,
-- every ProfessionDB query returned nil, and the recipe browser silently drew
-- its old fallback tooltip for every recipe in the game. Nothing errored, the
-- fixture-based specs stayed green, and it took a screenshot to find.
--
-- So this file loads the real library, executes the real data files off disk,
-- and drives the real resolvers. No fixture ProfessionDB is permitted here.
--
-- It reaches across to the sibling ProfessionDB install and skips — loudly, via
-- a pending — when that is absent, rather than passing vacuously.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ENGINEERING = 202

-- Core Marksman Rifle: an Engineering recipe with a REAL teaching scroll.
-- (18290 is the Accurascope's schematic; 18292 is this one. An earlier version
-- of this file named the constant after the wrong item while asserting the
-- right id -- correct test, misleading name.)
local RIFLE_SPELL, RIFLE_SCROLL = 22795, 18292

local ns, IL, lib, realGetProfessionDB

--- The real library with Engineering's core data, the recipe→scroll map and the
--- enUS prefixes loaded, exactly as a client loads them.
local function loadRealProfessionDB()
	local libs = env.libs
	if not libs.available("LibProfessionDB-1.0") then return nil end
	libs.load("LibProfessionDB-1.0")
	for _, file in ipairs({
		"Data/Vanilla/_core/Engineering.lua",
		"Data/Vanilla/_core/RecipeItems.lua",
		"Data/Vanilla/enUS/Engineering.lua",
		"Data/Vanilla/enUS/RecipeScrollPrefixes.lua",
	}) do
		local chunk = loadfile(libs.pathOf("LibProfessionDB-1.0", file))
		if not chunk then return nil end
		chunk("ProfessionDB", {})
	end
	return LibStub("LibProfessionDB-1.0", true)
end

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	IL = ns.ItemLink
	realGetProfessionDB = ns.GetProfessionDB
	lib = loadRealProfessionDB()
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	if lib then
		ns.GetProfessionDB = function() return lib end
		env.setRecipeDB(lib.recipes)
	end
end)

-- AND restore it. `ns` is the one addon table the whole suite shares, so a
-- method left overwritten here is inherited by every LATER spec file. This
-- file's stub returns the REAL library, which is exactly what a fixture-based
-- spec is trying not to talk to: it silently took over 15 assertions in
-- teachingitem_spec, which then read shipped data (item 12958, prefix
-- "Recipe: ") instead of their own fixtures. Invisible in a single-file run —
-- only a whole-suite run reproduces it. Same discipline env/ follows for
-- globals, and the same one teachingitem_spec already follows for `_profDB`.
after_each(function() ns.GetProfessionDB = realGetProfessionDB end)

describe("the shipped data actually reaches this addon", function()
	it("has a ProfessionDB to talk to at all", function()
		assert.is_truthy(lib, "sibling ProfessionDB install not found — this "
			.. "spec cannot verify the integration and must not pass quietly")
	end)

	it("loaded recipe→scroll rows, not an empty table", function()
		-- The regression, stated as the addon experiences it. With the wrong
		-- LibStub handle this table is empty and everything below still
		-- "works" by falling back, which is why the assertion is on the data.
		local n = 0
		for _ in pairs(lib:GetRecipeItems()) do n = n + 1 end
		assert.is_true(n > 0, "ProfessionDB loaded ZERO recipe items — the "
			.. "shipped data files are registering against another library")
	end)

	it("loaded the localized scroll prefixes", function()
		assert.equal("Schematic: ", lib:GetRecipeScrollPrefix(ENGINEERING))
	end)
end)

describe("a recipe with a real scroll", function()
	it("resolves to the scroll item, not a synthetic record", function()
		-- kind == "item" is what sends BrowserTab down SetHyperlink(scrollLink)
		-- — the real game tooltip, which other addons' OnTooltipSetItem hooks
		-- can contribute to. "synthetic" or nil means the hand-built fallback.
		local kind, itemId = IL.RecipeTooltipSource(ENGINEERING, RIFLE_SPELL)
		assert.equal("item", kind)
		assert.equal(RIFLE_SCROLL, itemId)
	end)

	it("resolves through the library even with no recipeDB fallback", function()
		-- TeachingItem has two sources: the library first, then the recipe's
		-- own meta.itemId. Both currently answer for this recipe, which means
		-- a broken library is invisible here unless the fallback is removed.
		env.setRecipeDB({})
		local itemId, isRankBook = IL.TeachingItem(ENGINEERING, RIFLE_SPELL)
		assert.equal(RIFLE_SCROLL, itemId)
		assert.is_false(isRankBook)
	end)

	it("resolves through recipeDB even with no library", function()
		-- The other half of the same pair, so neither source can rot unnoticed.
		-- This is the path Wrath / Cata / Mists rely on entirely: no
		-- recipe-scroll data is generated for those flavours yet.
		ns.GetProfessionDB = function() return nil end
		local itemId = IL.TeachingItem(ENGINEERING, RIFLE_SPELL)
		assert.equal(RIFLE_SCROLL, itemId,
			"the meta.itemId fallback is dead — Wrath/Cata/Mists have nothing")
	end)
end)

-- `profId` on browser rows IS covered -- in `browserlist_spec.lua`, which drives
-- the real `_BuildFullList` and has for a long time. A commented-out attempt sat
-- here claiming the guild-db fixture could not drive the builder; that was simply
-- wrong, and the note it left behind read as a known coverage hole for a feature
-- that now depends on the field. Removed rather than left to mislead again.
--
-- The version there also asserts the case a single-profession build cannot: an
-- all-professions build must stamp each row's OWN profession, not the one that
-- was requested. Those are the same number whenever one profession is asked for,
-- so the obvious test passes against the wrong variable.

describe("a recipe with no scroll", function()
	local trainerSpell

	setup(function()
		-- Chosen from the shipped data rather than hard-coded, so a data
		-- refresh cannot leave this asserting a recipe that gained a scroll.
		if not lib then return end
		for spellID in pairs(lib.recipes[ENGINEERING] or {}) do
			if not lib:GetRecipeItem(spellID) then trainerSpell = spellID break end
		end
	end)

	it("gets a scroll-SHAPED header with the real localized prefix", function()
		assert.is_truthy(trainerSpell, "no scroll-less Engineering recipe in the shipped data")
		local header = IL.ScrollHeader(ENGINEERING, trainerSpell, "Test Recipe", "Engineering")
		-- "Schematic: Test Recipe", not "Engineering: Test Recipe". The latter
		-- is the pre-move fallback and is exactly what the screenshots showed.
		assert.equal("Schematic: Test Recipe", header)
	end)

	it("takes requiredSkill from the recipe, never from the scroll record", function()
		-- ProfessionDB carries the correct per-recipe skill. The synthetic
		-- descriptor deliberately does not, because ItemDB's copy was a floor
		-- of 1 on eight of twelve skill lines and rendered "Requires Mining (1)"
		-- on a recipe needing 230.
		local scroll = lib:GetSyntheticRecipeScroll(trainerSpell)
		assert.is_truthy(scroll)
		assert.is_nil(scroll.requiredSkill)

		local _, requires = IL.ScrollHeader(ENGINEERING, trainerSpell, "Test Recipe", "Engineering")
		local skill = lib.recipes[ENGINEERING][trainerSpell].requiredSkill
		if skill and skill > 1 then
			assert.is_truthy(requires)
			assert.is_truthy(tostring(requires):find(tostring(skill), 1, true),
				"the Requires line must carry the recipe's own skill")
		else
			-- No trustworthy number: omit the line rather than print "(1)".
			assert.is_nil(requires)
		end
	end)
end)
