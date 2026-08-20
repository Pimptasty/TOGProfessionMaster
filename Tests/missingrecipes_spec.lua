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
	-- SharedWidgets before the tab, mirroring the TOC. MissingRecipesTab reads
	-- addon.ItemLink.SOURCE_LABELS at FILE scope, so loading it first is not
	-- optional — without this the file errors on load. It passed for a while
	-- anyway, because in a whole-suite run an earlier spec had already put
	-- ItemLink on the shared namespace; only a single-file run showed it.
	env.loadModule("GUI/SharedWidgets.lua")
	M = env.loadModule("GUI/MissingRecipesTab.lua").MissingRecipesTab
	-- The locale table is a file-local in every addon file; fetch our own the
	-- same way they do rather than reaching for a namespace field that isn't there.
	L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
end)

before_each(function()
	env.install()
	-- See browserlist_spec: recipes have to exist on the simulated client or
	-- the Vanilla spell-existence filter drops them.
	env.spellsExist(A, B, C)
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
	-- Both spellings -- the code reads through addon.Item.*, which prefers
	-- C_Item exactly as the client does. See env.itemAPI.
	env.itemAPI("GetItemInfo", function() return nil end)
	env.itemAPI("GetItemIcon", function() return nil end)
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

-- Skill-RANK books (audit finding 24). A rank book raises the profession CAP; it
-- is not a recipe and must vanish once the character has read it, while staying
-- listed for a character who has not. The filter that used to be here never ran
-- once -- it tested `type(data.teaches) == "string"` against a table keyed by
-- rank NAME, and `teaches` is a spell id -- so a maxed character was told
-- forever to go and buy books they had already consumed.
describe("BuildMissingList -- skill-rank books", function()
	-- Two of the three fixture recipes stand in for rank books: B requires 100,
	-- C requires 200. Classification is addon.ItemLink.TeachingItem's second
	-- return in production; stubbed here so this spec measures the SKILL GATE
	-- and not ProfessionDB's classifier, which has its own specs upstream.
	local savedTeachingItem

	before_each(function()
		savedTeachingItem = ns.ItemLink.TeachingItem
	end)

	after_each(function()
		ns.ItemLink.TeachingItem = savedTeachingItem
	end)

	-- Mark the given recipe ids as rank books.
	local function rankBooks(...)
		local flagged = {}
		for _, id in ipairs({ ... }) do flagged[id] = true end
		ns.ItemLink.TeachingItem = function(_, recipeId)
			if flagged[recipeId] then return 16084, true end
			return nil, false
		end
	end

	local function listAt(skillMax)
		gdb.skills[ME] = { [ALCHEMY] = { skillRank = 1, skillMax = skillMax } }
		return ids(M._BuildMissingList(ME, ALCHEMY, true, false, false, "char"))
	end

	it("derives the cap a rank book grants from every requiredSkill that ships", function()
		-- 125 / 200 / 275 / 300 are the ONLY values carried by any rank book in
		-- ProfessionDB, across all five flavours (measured against the shipped
		-- _core data, 2026-08-18). Note the last two: a flat requiredSkill + 100
		-- would put Master First Aid at 400 and never hide it.
		assert.equal(225, M._RankBookGrantedCap(125))   -- Expert
		assert.equal(300, M._RankBookGrantedCap(200))   -- Artisan
		assert.equal(375, M._RankBookGrantedCap(275))   -- Master Fishing
		assert.equal(375, M._RankBookGrantedCap(300))   -- Master First Aid
		assert.equal(600, M._RankBookGrantedCap(600))   -- clamped at the ceiling
		assert.is_nil(M._RankBookGrantedCap(nil))
		assert.is_nil(M._RankBookGrantedCap("Expert"))  -- the old key type
	end)

	it("hides a rank book once the cap it grants has been reached", function()
		rankBooks(B)                       -- requiredSkill 100 -> grants 225
		assert.same({ A, C }, listAt(225))
	end)

	it("still lists a rank book the character has not read", function()
		rankBooks(B)
		assert.same({ A, B, C }, listAt(150))
	end)

	it("hides only the ranks already taken, not every rank book", function()
		-- The reviewer's own acceptance test, and the half that a blanket
		-- "hide all rank books" fix would get wrong: at cap 300 the Expert-tier
		-- book (grants 225) is gone and the Artisan-tier one (grants 375) stays.
		rankBooks(B, C)                    -- B grants 225, C (200) grants 300
		assert.same({ A }, listAt(300))
		assert.same({ A, C }, listAt(225))
	end)

	it("leaves ordinary recipes alone at any skill", function()
		rankBooks()                        -- nothing is a rank book
		assert.same({ A, B, C }, listAt(600))
	end)

	it("keeps listing a rank book when its requiredSkill is missing", function()
		-- No requiredSkill means no derivable cap, so there is nothing to compare
		-- against. Show it rather than hide it: a false positive costs a wasted
		-- vendor trip, a false negative hides the only route past a cap.
		ns.recipeDB[ALCHEMY][B].requiredSkill = nil
		rankBooks(B)
		assert.same({ A, B, C }, listAt(600))
	end)
end)
