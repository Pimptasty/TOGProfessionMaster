-- The Missing Recipes tab's set computation.
--
-- "Missing" is a subtraction: the shipped recipe universe for a profession minus
-- what the character (personal scope) or anyone in the guild (guild scope)
-- already knows. Both halves of that subtraction have been wrong in shipped
-- versions — the known-set because scanned recipes could be keyed by crafted
-- item id rather than spell id, and the guild half because a cross-guild alt's
-- recipe counted as "the guild has it".

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, M, gdb, L
local ME   = "Testchar-Testrealm"
local MATE = "Bob-Testrealm"
local ALCHEMY = 171

-- Three Alchemy recipes at different learn skills.
local A, B, C = 2330, 2331, 2332

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	M = env.loadModule("GUI/MissingRecipesTab.lua").MissingRecipesTab
	-- The locale table is a file-local in every addon file; fetch our own the
	-- same way they do rather than reaching for a namespace field that isn't there.
	L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({
		[ALCHEMY] = {
			[A] = { name = "Minor Healing Potion", craftedItemId = 118, requiredSkill = 1 },
			[B] = { name = "Elixir of Lion's Strength", craftedItemId = 2454, requiredSkill = 100 },
			[C] = { name = "Greater Healing Potion", craftedItemId = 1710, requiredSkill = 200 },
		},
	})
	ns.sourceDB = { [ALCHEMY] = {} }
	gdb.skills[ME] = { [ALCHEMY] = { skillRank = 150, skillMax = 300 } }
	gdb.accountChars[ME] = true
	_G.GetItemInfo = function() return nil end
	_G.GetItemIcon = function() return nil end
end)

-- Rows are keyed by the recipe's SPELL id.
local function ids(list)
	local out = {}
	for _, row in ipairs(list) do out[#out + 1] = assert(row.spellId, "row carried no spellId") end
	table.sort(out)
	return out
end

local function knows(charKey, recipeId, key)
	gdb.recipes[ALCHEMY] = gdb.recipes[ALCHEMY] or {}
	local k = key or recipeId
	gdb.recipes[ALCHEMY][k] = gdb.recipes[ALCHEMY][k] or { crafters = {} }
	gdb.recipes[ALCHEMY][k].crafters[charKey] = ns:GetCurrentGuildTag()
end

describe("BuildMissingList — personal scope", function()
	it("lists the whole universe when the character knows nothing", function()
		assert.same({ A, B, C }, ids(M._BuildMissingList(ME, ALCHEMY, true, false, false, "char")))
	end)

	it("drops the recipes the character already crafts", function()
		knows(ME, A)
		assert.same({ B, C }, ids(M._BuildMissingList(ME, ALCHEMY, true, false, false, "char")))
	end)

	it("ignores what OTHER characters know", function()
		knows(MATE, A)
		assert.same({ A, B, C }, ids(M._BuildMissingList(ME, ALCHEMY, true, false, false, "char")))
	end)

	it("recognises a recipe stored under its crafted-item id", function()
		-- Vanilla/Hardcore scans key by crafted item; the recipe universe is
		-- keyed by spell. A direct lookup missed every non-Enchanting recipe and
		-- the tab told players they were missing things they had.
		knows(ME, A, 118)
		assert.same({ B, C }, ids(M._BuildMissingList(ME, ALCHEMY, true, false, false, "char")))
	end)

	it("recognises a recipe whose row carries the spell id as a field", function()
		gdb.recipes[ALCHEMY] = { [999] = { spellId = A, crafters = { [ME] = ns:GetCurrentGuildTag() } } }
		assert.same({ B, C }, ids(M._BuildMissingList(ME, ALCHEMY, true, false, false, "char")))
	end)

	it("can learn now hides recipes above the character's rank", function()
		-- Rank 150: the 200-skill recipe is out of reach.
		assert.same({ A, B }, ids(M._BuildMissingList(ME, ALCHEMY, true, true, false, "char")))
	end)

	it("can learn now keeps everything when the rank is high enough", function()
		gdb.skills[ME][ALCHEMY].skillRank = 300
		assert.same({ A, B, C }, ids(M._BuildMissingList(ME, ALCHEMY, true, true, false, "char")))
	end)

	it("show all ignores what is already known", function()
		knows(ME, A)
		assert.same({ A, B, C }, ids(M._BuildMissingList(ME, ALCHEMY, true, false, true, "char")))
	end)

	it("returns nothing without a character or a profession", function()
		assert.same({}, M._BuildMissingList(nil, ALCHEMY, true, false, false, "char"))
		assert.same({}, M._BuildMissingList(ME, nil, true, false, false, "char"))
		assert.same({}, M._BuildMissingList(ME, 0, true, false, false, "char"))
	end)

	it("returns nothing for a profession we ship no data for", function()
		assert.same({}, M._BuildMissingList(ME, 999, true, false, false, "char"))
	end)
end)

describe("BuildMissingList — guild scope", function()
	it("counts a recipe as present when ANY guild member has it", function()
		knows(MATE, A)
		assert.same({ B, C }, ids(M._BuildMissingList(nil, ALCHEMY, true, false, false, "guild")))
	end)

	it("still counts a recipe as missing when only a cross-guild alt knows it", function()
		-- The guild view answers "what can nobody HERE make?" — an alt parked in
		-- another guild doesn't cover the gap.
		knows("Away-Testrealm", A)
		assert.same({ A, B, C }, ids(M._BuildMissingList(nil, ALCHEMY, true, false, false, "guild")))
	end)

	it("ignores the can-learn filter, which is meaningless guild-wide", function()
		assert.same({ A, B, C }, ids(M._BuildMissingList(nil, ALCHEMY, true, true, false, "guild")))
	end)

	it("needs no character key at all", function()
		assert.equal(3, #M._BuildMissingList(nil, ALCHEMY, true, false, false, "guild"))
	end)
end)

describe("row contents", function()
	it("carries what the row renders and whether it is known", function()
		knows(ME, A)
		local list = M._BuildMissingList(ME, ALCHEMY, true, false, true, "char")
		local row
		for _, r in ipairs(list) do if r.spellId == A then row = r end end
		assert.equal(118, row.craftedItemId)
		assert.equal(1, row.requiredSkill)
		assert.is_true(row.known)
	end)

	it("sorts by learn skill, with unknown skills last", function()
		env.setRecipeDB({
			[ALCHEMY] = {
				[A] = { name = "a", requiredSkill = 200 },
				[B] = { name = "b" },                      -- no learn skill shipped
				[C] = { name = "c", requiredSkill = 1 },
			},
		})
		local list = M._BuildMissingList(ME, ALCHEMY, true, false, false, "char")
		assert.equal(C, list[1].spellId)
		assert.equal(A, list[2].spellId)
		assert.equal(B, list[3].spellId)
	end)
end)

describe("source formatting", function()
	it("says Unknown when we ship no source for the recipe", function()
		assert.equal(L["MissingSrcUnknown"], M._FormatSources(nil, true))
	end)

	it("lists the sources it knows", function()
		local out = M._FormatSources({ drop = true, vendor = true }, true)
		assert.is_true(out ~= L["MissingSrcUnknown"])
		assert.is_true(out:find(",", 1, true) ~= nil)
	end)

	it("omits trainer sources when the toggle is off", function()
		local withTrainer = M._FormatSources({ trainer = true, drop = true }, true)
		local without     = M._FormatSources({ trainer = true, drop = true }, false)
		assert.is_true(#withTrainer > #without)
	end)

	it("falls back to Unknown when filtering removes everything", function()
		assert.equal(L["MissingSrcUnknown"], M._FormatSources({ trainer = true }, false))
	end)

	it("summarises a source kind it has never seen as Other", function()
		assert.equal(L["MissingSrcOther"], M._FormatSources({ somethingnew = true }, true))
	end)

	it("knows whether a recipe is obtainable without a trainer", function()
		assert.is_false(M._HasNonTrainerSource(nil))
		assert.is_false(M._HasNonTrainerSource({ trainer = true }))
		assert.is_true(M._HasNonTrainerSource({ trainer = true, drop = true }))
	end)
end)

describe("character and profession pickers", function()
	it("shortens a character key to its name", function()
		assert.equal("Testchar", M._CharShortName(ME))
		assert.equal("Plain", M._CharShortName("Plain"))
	end)

	it("lists own characters that have profession data, current one first", function()
		gdb.skills["Alt-Testrealm"] = { [ALCHEMY] = { skillRank = 1, skillMax = 300 } }
		gdb.accountChars["Alt-Testrealm"] = true
		gdb.skills[MATE] = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
		local list = M._GetCharactersWithProfessions()
		assert.equal(ME, list[1])
		local seen = {}
		for _, ck in ipairs(list) do seen[ck] = true end
		assert.is_true(seen["Alt-Testrealm"])
		assert.is_nil(seen[MATE])      -- not one of ours
	end)

	it("always includes the logged-in character, even with no scan yet", function()
		gdb.skills = {}
		assert.same({ ME }, M._GetCharactersWithProfessions())
	end)

	it("lists a character's professions we ship data for, by name", function()
		gdb.skills[ME][999] = { skillRank = 1, skillMax = 1 }   -- no recipe data
		assert.same({ ALCHEMY }, M._GetProfessionsForCharacter(ME))
	end)

	it("returns nothing for a character with no skills", function()
		assert.same({}, M._GetProfessionsForCharacter("Nobody-Testrealm"))
	end)

	it("lists professions the guild practises", function()
		gdb.skills[MATE] = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
		assert.same({ ALCHEMY }, M._GetGuildProfessions())
	end)

	it("omits a profession this client version cannot have", function()
		local prev = ns.IsProfessionAvailable
		ns.IsProfessionAvailable = function() return false end
		local out = M._GetProfessionsForCharacter(ME)
		ns.IsProfessionAvailable = prev
		assert.same({}, out)
	end)
end)
