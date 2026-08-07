-- Can the Professions tab show the REAL recipe tooltip on hover?
--
-- Feasibility proof, written before anything is swapped. The list keeps showing
-- the crafted item's name and icon ("Barbaric Shoulders", not "Plans: Barbaric
-- Shoulders") — that display is not in question. What the tooltip could become
-- is the genuine teaching-item tooltip, which natively embeds the crafted item
-- AND lets other addons' tooltip hooks contribute.
--
-- That only works where a teaching item exists, so this pins the resolver:
-- addon.ItemLink.TeachingItem. Nothing here changes what a player sees.
--
-- Measured coverage, from ItemDB's DBC join (LibItemDB-1.0 MINOR 17):
--   Vanilla 1.15.9   1,073 of 1,645 recipes have one   (572 do not)
--   TBC     2.5.6    1,453 of 2,267                    (814 do not)
-- So roughly a third are trainer-taught and will ALWAYS need the hand-built
-- tooltip. A design that assumes otherwise is designing for data that does not
-- exist.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, IL
local ALCHEMY = 171
local TRANSMUTE_SPELL, SCROLL_ITEM = 17187, 12656   -- Arcanite Bar + its plans
local TRAINER_SPELL = 2259                          -- Apprentice Alchemy: no scroll
local RANK_BOOK_SPELL, RANK_BOOK_ITEM = 7732, 16083 -- Expert Fishing book

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	IL = ns.ItemLink
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	ns._profDB = nil          -- clear the lazy LibStub cache between tests
	env.setRecipeDB({})
end)

-- AND after. `_itemDB` is cached on the addon for the session, so a stub left
-- behind by the last test in this file is inherited by every LATER spec file --
-- which showed up as `attempt to call method 'IsReady'` inside gui_draw_spec,
-- nowhere near the cause. Same discipline the env follows for globals.
after_each(function() ns._profDB = nil end)

--- Stand in for LibProfessionDB, which owns the recipe-scroll data as of
--- MINOR 8. (It was LibItemDB until 2026-08-06.) The harness loads the library but NOT its bulk Data
--- trees (env/libs.lua says so explicitly), so the mapping has to be seeded. What
--- is under test is our resolver's PREFERENCE ORDER, not ItemDB's data.
local function itemDBWith(map, rankBooks)
	ns._profDB = {
		GetRecipeItem = function(_, spellID)
			local id = map[spellID]
			if not id then return nil, false end
			return id, (rankBooks or {})[spellID] == true
		end,
	}
end

local function professionDBWith(recipeId, fields, profId)
	env.setRecipeDB({ [profId or ALCHEMY] = { [recipeId] = fields } })
end

-- ---------------------------------------------------------------------------

describe("TeachingItem — where the answer comes from", function()
	it("uses ItemDB's DBC-derived mapping when it has one", function()
		itemDBWith({ [TRANSMUTE_SPELL] = SCROLL_ITEM })
		assert.equal(SCROLL_ITEM, (IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)))
	end)

	it("keys on the recipe's SPELL id, which is how ProfessionDB keys recipes", function()
		-- Documented in docs/DEPENDENCY_CONTRACTS.md §3 and load-bearing: pass an
		-- item id here and you resolve whatever unrelated item shares the number.
		local asked = {}
		ns._profDB = { GetRecipeItem = function(_, id) asked[#asked + 1] = id end }
		IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)
		assert.same({ TRANSMUTE_SPELL }, asked)
	end)

	it("falls back to ProfessionDB where ItemDB has no data for the flavour", function()
		-- ItemDB ships Vanilla and TBC only. On Wrath / Cata / Mists every lookup
		-- misses, and without this fallback the feature would silently do nothing
		-- on three of the five flavours this addon supports.
		itemDBWith({})
		professionDBWith(TRANSMUTE_SPELL, { name = "Transmute", itemId = SCROLL_ITEM })
		assert.equal(SCROLL_ITEM, (IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)))
	end)

	it("prefers ItemDB over ProfessionDB when the two disagree", function()
		-- ItemDB's is a DBC join; ProfessionDB's came from a name-match linker
		-- that its own generator documents as ~97% accurate. When they differ,
		-- the authoritative one wins.
		itemDBWith({ [TRANSMUTE_SPELL] = SCROLL_ITEM })
		professionDBWith(TRANSMUTE_SPELL, { name = "Transmute", itemId = 99999 })
		assert.equal(SCROLL_ITEM, (IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)))
	end)

	it("works with no ItemDB installed at all", function()
		-- It is an optional standalone addon, resolved through a silent LibStub.
		ns._profDB = false
		professionDBWith(TRANSMUTE_SPELL, { name = "Transmute", itemId = SCROLL_ITEM })
		assert.equal(SCROLL_ITEM, (IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)))
	end)

	it("survives an older ItemDB without GetRecipeItem", function()
		ns._profDB = {}   -- MINOR < 17
		professionDBWith(TRANSMUTE_SPELL, { name = "Transmute", itemId = SCROLL_ITEM })
		assert.equal(SCROLL_ITEM, (IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)))
	end)
end)

describe("TeachingItem — nil is an answer, not a failure", function()
	it("returns nil for a trainer-taught recipe", function()
		-- 572 of 1,645 Vanilla recipes. The caller must fall back to the
		-- hand-built tooltip, not treat this as missing data.
		itemDBWith({})
		professionDBWith(TRAINER_SPELL, { name = "Apprentice Alchemy" })
		assert.is_nil((IL.TeachingItem(ALCHEMY, TRAINER_SPELL)))
	end)

	it("returns nil rather than raising without a recipe id", function()
		assert.is_nil((IL.TeachingItem(ALCHEMY, nil)))
	end)

	it("treats a zero itemId in ProfessionDB as absent", function()
		itemDBWith({})
		professionDBWith(TRANSMUTE_SPELL, { name = "Transmute", itemId = 0 })
		assert.is_nil((IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)))
	end)

	it("does not need a profession id to use ItemDB", function()
		-- ItemDB is keyed by spell alone, so a caller that has the recipe id but
		-- not its profession still resolves.
		itemDBWith({ [TRANSMUTE_SPELL] = SCROLL_ITEM })
		assert.equal(SCROLL_ITEM, (IL.TeachingItem(nil, TRANSMUTE_SPELL)))
	end)
end)

describe("TeachingItem — skill-rank books", function()
	it("flags a rank book so a recipe list can exclude it", function()
		-- "Expert Fishing - The Bass and You" genuinely teaches spell 7732, so the
		-- DBC join is right to resolve it — but it is not a recipe. ItemDB
		-- classifies these from data, so we never string-match on titles.
		itemDBWith({ [RANK_BOOK_SPELL] = RANK_BOOK_ITEM }, { [RANK_BOOK_SPELL] = true })
		local itemId, isRankBook = IL.TeachingItem(ALCHEMY, RANK_BOOK_SPELL)
		assert.equal(RANK_BOOK_ITEM, itemId)
		assert.is_true(isRankBook)
	end)

	it("reports false for an ordinary recipe scroll", function()
		itemDBWith({ [TRANSMUTE_SPELL] = SCROLL_ITEM })
		local _, isRankBook = IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)
		assert.is_false(isRankBook)
	end)

	it("reports false, never nil, on the ProfessionDB fallback", function()
		-- ProfessionDB carries no rank-book classification, so the fallback path
		-- has to answer the second return anyway — a nil there would read as
		-- "unknown" and callers branch on a boolean.
		itemDBWith({})
		professionDBWith(TRANSMUTE_SPELL, { name = "Transmute", itemId = SCROLL_ITEM })
		local _, isRankBook = IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)
		assert.is_false(isRankBook)
	end)
end)

describe("what this means for the tooltip swap", function()
	it("resolves a link for the scroll, never for the crafted item", function()
		-- The distinction the whole feature rests on. entry.itemLink is the
		-- CRAFTED product; the teaching item is a different item entirely, and
		-- showing the wrong one gives you gear stats where a recipe was wanted.
		itemDBWith({ [TRANSMUTE_SPELL] = SCROLL_ITEM })
		professionDBWith(TRANSMUTE_SPELL, {
			name = "Transmute: Arcanite", itemId = SCROLL_ITEM, craftedItemId = 12360,
		})
		local teaching = IL.TeachingItem(ALCHEMY, TRANSMUTE_SPELL)
		local crafted  = ns:GetRecipeCraftedItemId(ALCHEMY, TRANSMUTE_SPELL)
		assert.equal(SCROLL_ITEM, teaching)
		assert.is_not.equal(teaching, crafted)
	end)
end)

describe("ScrollHeader — the hand-built tooltip opens like a real scroll", function()
	local LEATHER, PROFNAME = 165, "Leatherworking"

	it("uses LibItemDB's localized prefix, never a hardcoded one", function()
		ns._profDB = {
			GetSyntheticRecipeScroll = function(_, id)
				if id ~= TRAINER_SPELL then return nil end
				return { prefix = "Plans: ", professionID = LEATHER, requiredSkill = 200 }
			end,
		}
		local title = IL.ScrollHeader(LEATHER, TRAINER_SPELL, "Barbaric Shoulders", PROFNAME)
		assert.equal("Plans: Barbaric Shoulders", title)
	end)

	it("honours a locale whose prefix is not 'Word: '", function()
		-- frFR puts a space BEFORE the colon and zhCN uses a full-width one. A
		-- hardcoded English table would render both wrong, which is exactly why
		-- the prefix is derived upstream rather than transcribed.
		ns._profDB = {
			GetSyntheticRecipeScroll = function()
				return { prefix = "Plans : ", professionID = LEATHER }
			end,
		}
		local title = IL.ScrollHeader(LEATHER, TRAINER_SPELL, "Épaulières", PROFNAME)
		assert.equal("Plans : Épaulières", title)
	end)

	it("takes the required skill from ProfessionDB, not from ItemDB", function()
		-- LibItemDB MINOR 18 ships requiredSkill = 1 for every recipe on 8 of 12
		-- skill lines, which printed "Requires Mining (1)" on Smelt Truesilver
		-- (really 230). ProfessionDB has the real per-recipe value, so that is
		-- what this reads — and it must keep reading it even when the synthetic
		-- record offers a number of its own.
		ns._profDB = {
			GetSyntheticRecipeScroll = function()
				return { prefix = "Plans: ", professionID = LEATHER, requiredSkill = 1 }
			end,
		}
		professionDBWith(TRAINER_SPELL, { name = "Barbaric Shoulders", requiredSkill = 200 }, LEATHER)
		local _, requires = IL.ScrollHeader(LEATHER, TRAINER_SPELL, "Barbaric Shoulders", PROFNAME)
		assert.equal("Requires Leatherworking (200)", requires)
	end)

	it("omits the line entirely rather than printing a skill of 1", function()
		-- The wrong-data case. A recipe genuinely requiring 1 loses a line that
		-- said nothing; a recipe whose data is missing does not get a fabricated
		-- "(1)". Both are better than the number being wrong.
		ns._profDB = {
			GetSyntheticRecipeScroll = function()
				return { prefix = "Plans: ", professionID = LEATHER, requiredSkill = 1 }
			end,
		}
		professionDBWith(TRAINER_SPELL, { name = "Thing", requiredSkill = 1 }, LEATHER)
		local _, requires = IL.ScrollHeader(LEATHER, TRAINER_SPELL, "Thing", PROFNAME)
		assert.is_nil(requires)
	end)

	it("omits the line when ProfessionDB has no skill for the recipe", function()
		ns._profDB = {
			GetSyntheticRecipeScroll = function()
				return { prefix = "Plans: ", professionID = LEATHER, requiredSkill = 200 }
			end,
		}
		professionDBWith(TRAINER_SPELL, { name = "Thing" }, LEATHER)
		local _, requires = IL.ScrollHeader(LEATHER, TRAINER_SPELL, "Thing", PROFNAME)
		assert.is_nil(requires)
	end)

	it("falls back to the old Profession: Name form with no prefix available", function()
		-- Gathering lines have no real scroll to derive a prefix from, and
		-- Wrath/Cata/Mists have no ItemDB data at all yet. Those keep the shape
		-- this addon has always used rather than losing their header.
		ns._profDB = false
		local title = IL.ScrollHeader(LEATHER, TRAINER_SPELL, "Barbaric Shoulders", PROFNAME)
		assert.equal("Leatherworking: Barbaric Shoulders", title)
	end)

	it("falls back again to the bare name when there is no profession either", function()
		ns._profDB = false
		local title = IL.ScrollHeader(nil, TRAINER_SPELL, "Barbaric Shoulders", nil)
		assert.equal("Barbaric Shoulders", title)
	end)

	it("returns nothing without a recipe name", function()
		local title, requires = IL.ScrollHeader(LEATHER, TRAINER_SPELL, nil, PROFNAME)
		assert.is_nil(title)
		assert.is_nil(requires)
	end)

	it("uses the profession-wide prefix for a recipe with no synthetic record", function()
		-- A recipe that HAS a real scroll still needs a header if we end up on
		-- the hand-built path (uncached link), so the prefix lookup falls back
		-- to the profession's own rather than giving up.
		ns._profDB = {
			GetSyntheticRecipeScroll = function() return nil end,
			GetRecipeScrollPrefix    = function(_, id) return id == LEATHER and "Pattern: " or nil end,
		}
		local title = IL.ScrollHeader(LEATHER, TRANSMUTE_SPELL, "Thing", PROFNAME)
		assert.equal("Pattern: Thing", title)
	end)
end)
