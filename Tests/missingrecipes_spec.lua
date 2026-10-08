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

-- [Where]: the row button that opens LibItemDB's "Where to get it" window on the
-- recipe scroll (Discord request 2026-09-29, "lead you to where patterns are
-- sold/dropped"). LibItemDB is stubbed: the window and its Questbook hand-off
-- are ItemDB's, specced there; this pins when TOGPM offers the button and what
-- it hands over.
describe("the [Where] button", function()
	local SCROLL = 6663
	local savedIdb, opened, built

	-- A LibItemDB that knows `nRows` places for SCROLL and records what it opens.
	local function itemDB(nRows, opts)
		opts = opts or {}
		built = 0
		local idb = {
			GetName = function() return "Recipe: Elixir of Lion's Strength" end,
			GetLink = function() return nil end,
			GetQuality = function() return nil end,
		}
		if not opts.old then
			idb.BuildWhereRows = function(_, id)
				built = built + 1
				local rows = {}
				for i = 1, (id == SCROLL and nRows or 0) do rows[i] = { kind = "Vendor" } end
				return rows
			end
			idb.OpenWhereWindow = function(_, id) opened[#opened + 1] = id end
		end
		ns._itemDB = idb
	end

	local function whereColumn()
		assert.is_truthy(ns.W and ns.W.RowList, "LibAceGUIWidgets RowList is not loaded in this env")
		local list = M:BuildRowList(CreateFrame("Frame", nil, UIParent))
		for _, col in ipairs(list.columns) do
			if col.key == "whereBtn" then return col end
		end
		error("the Missing Recipes list has no [Where] column")
	end

	before_each(function()
		savedIdb, opened = ns._itemDB, {}
	end)

	after_each(function()
		ns._itemDB = savedIdb
	end)

	it("is offered for a recipe scroll LibItemDB knows a source for", function()
		itemDB(2)
		assert.is_true(whereColumn().show({ spellId = B, itemId = SCROLL }))
	end)

	it("is not offered for a trainer-taught recipe, which has no scroll", function()
		itemDB(2)
		assert.is_false(whereColumn().show({ spellId = A }))
	end)

	it("is not offered when LibItemDB knows no source for the scroll", function()
		-- WoW Forever's ItemDB ships no places data; a button that opens
		-- "No known source" is a dead end.
		itemDB(0)
		assert.is_false(whereColumn().show({ spellId = B, itemId = SCROLL }))
	end)

	it("is not offered by a LibItemDB without the window, or with no LibItemDB", function()
		itemDB(2, { old = true })
		assert.is_false(whereColumn().show({ spellId = B, itemId = SCROLL }))
		ns._itemDB = false
		assert.is_false(whereColumn().show({ spellId = B, itemId = SCROLL }))
	end)

	it("counts sources with the window's own faction filter", function()
		-- The window hides the other faction's vendors by default; a scroll only
		-- they sell must not get a button that opens an empty list.
		itemDB(2)
		local idb, asked = ns._itemDB, "unset"
		idb.GetWhereOwnFactionOnly = function() return true end
		idb.BuildWhereRows = function(_, _, faction) asked = faction; return {} end
		-- The env's faction seam (reset to its default at every install).
		env.faction = "Alliance"
		assert.is_false(whereColumn().show({ spellId = B, itemId = SCROLL }))
		assert.equal("Alliance", asked)
	end)

	it("asks LibItemDB once per row, not on every paint", function()
		itemDB(2)
		local col, entry = whereColumn(), { spellId = B, itemId = SCROLL }
		col.show(entry)
		col.show(entry)
		col.show(entry)
		assert.equal(1, built)
	end)

	-- Operator, 2026-10-04 (Retail, which ships no ProfessionDB sources): "itemdb
	-- has a lot of the drop info, and you're showing it as unkown".
	describe("the Sources cell falls back to LibItemDB's places", function()
		local function srcColumn()
			local list = M:BuildRowList(CreateFrame("Frame", nil, UIParent))
			for _, col in ipairs(list.columns) do
				if col.key == "source" then return col end
			end
			error("the Missing Recipes list has no Sources column")
		end

		it("names the kinds of place, in the usual order, when ProfessionDB has no sources", function()
			itemDB(0)
			ns._itemDB.BuildWhereRows = function()
				return { { kind = "Quest" }, { kind = "Vendor" }, { kind = "Boss" } }
			end
			local text = srcColumn().format(nil, { spellId = B, itemId = SCROLL, sourcesText = L["MissingSrcUnknown"] })
			assert.is_truthy(text:find(L["MissingSrcVendor"] .. ", " .. L["MissingSrcDrop"] .. ", "
				.. L["MissingSrcQuest"], 1, true))
		end)

		it("keeps ProfessionDB's sources when it has them", function()
			itemDB(2)
			local text = srcColumn().format(nil, { spellId = B, itemId = SCROLL,
				sources = { quest = { 1 } }, sourcesText = L["MissingSrcQuest"] })
			assert.is_nil(text:find(L["MissingSrcVendor"], 1, true))
		end)

		it("stays Unknown when LibItemDB knows no place either", function()
			itemDB(0)
			local text = srcColumn().format(nil, { spellId = B, itemId = SCROLL, sourcesText = L["MissingSrcUnknown"] })
			assert.is_truthy(text:find(L["MissingSrcUnknown"], 1, true))
		end)
	end)

	it("opens LibItemDB's window on the scroll item, not the recipe spell", function()
		itemDB(2)
		whereColumn().onClick({ spellId = B, itemId = SCROLL })
		assert.same({ SCROLL }, opened)
	end)

	it("carries its own tooltip", function()
		local title, body = whereColumn().tip({ spellId = B, itemId = SCROLL })
		assert.equal(L["TooltipWhereTitle"], title)
		assert.equal(L["TooltipWhereDescScroll"], body)
	end)
end)

-- [Guide]: one click hands the best place for the scroll to Questbook through
-- LibItemDB:WhereTrack (Discord request 2026-09-29; operator 2026-10-01: "give
-- us the guide route/cancel route inside TOGPM too"). Questbook is optional:
-- without it there is no route, so no button.
describe("the [Guide] button", function()
	local SCROLL = 6663
	local AceAddon = LibStub("AceAddon-3.0")
	local savedIdb, savedPrint, savedMap, tracked, printed

	local function place(kind, mapID, chance, name)
		return { kind = kind, name = name or kind, zone = "Zone " .. mapID, chance = chance,
		         uiMapID = mapID, points = { { x = 50, y = 50 } } }
	end

	local function itemDB(rows, trackResult)
		ns._itemDB = {
			GetName = function() return "Recipe" end,
			GetLink = function() return nil end,
			GetQuality = function() return nil end,
			BuildWhereRows = function(_, id) return id == SCROLL and rows or {} end,
			OpenWhereWindow = function() end,
			WhereTrack = function(_, row) tracked[#tracked + 1] = row; return trackResult ~= false end,
			WhereStopTracking = function() return true end,
		}
	end

	local function guideColumn()
		local list = M:BuildRowList(CreateFrame("Frame", nil, UIParent))
		for _, col in ipairs(list.columns) do
			if col.key == "guideBtn" then return col end
		end
		error("the Missing Recipes list has no [Guide] column")
	end

	before_each(function()
		savedIdb, savedPrint, savedMap = ns._itemDB, ns.Print, _G.C_Map
		tracked, printed = {}, {}
		ns.Print = function(_, msg) printed[#printed + 1] = msg end
		AceAddon.addons["Questbook"] = { TrackPlace = function() end }
		_G.C_Map = { GetBestMapForUnit = function() return 1429 end }
	end)

	after_each(function()
		ns._itemDB, ns.Print, _G.C_Map = savedIdb, savedPrint, savedMap
		AceAddon.addons["Questbook"] = nil
	end)

	it("is offered with Questbook and a place that has coordinates", function()
		itemDB({ place("Vendor", 1411) })
		assert.is_true(guideColumn().show({ spellId = B, itemId = SCROLL }))
	end)

	it("is not offered without Questbook", function()
		AceAddon.addons["Questbook"] = nil
		itemDB({ place("Vendor", 1411) })
		assert.is_false(guideColumn().show({ spellId = B, itemId = SCROLL }))
	end)

	it("is not offered when no place has coordinates", function()
		-- A quest or crafted source has a zone name but no point to route to.
		itemDB({ { kind = "Quest", name = "", zone = "Elwynn Forest" } })
		assert.is_false(guideColumn().show({ spellId = B, itemId = SCROLL }))
	end)

	it("prefers a place in the player's zone, then a vendor, then the best drop", function()
		local far, vendor, here = place("Drop", 1411, 5), place("Vendor", 1412), place("Drop", 1429, 1)
		assert.equal(here, M:PickGuideRow({ far, vendor, here }))
		assert.equal(vendor, M:PickGuideRow({ far, vendor }))
		local better = place("Drop", 1413, 9)
		assert.equal(better, M:PickGuideRow({ far, better }))
	end)

	it("hands the chosen place to LibItemDB and says where", function()
		local vendor = place("Vendor", 1412, nil, "Kendor Kabonka")
		itemDB({ place("Drop", 1411, 5), vendor })
		guideColumn().onClick({ spellId = B, itemId = SCROLL })
		assert.same({ vendor }, tracked)
		assert.equal(L["GuideStartedFormat"]:format("Kendor Kabonka, Zone 1412"), printed[1])
	end)

	it("says so when Questbook refuses the place", function()
		itemDB({ place("Vendor", 1412) }, false)
		assert.is_false(M:Guide({ spellId = B, itemId = SCROLL }))
		assert.equal(L["GuideFailed"], printed[1])
	end)

	it("stops the route through LibItemDB", function()
		itemDB({})
		assert.is_true(M:StopGuide())
		assert.equal(L["GuideStopped"], printed[1])
	end)
end)

-- Discord report, 2026-10-07: "I cannot read what the recipe is without
-- scrolling over it and there is no way to move columns to the right to read
-- it." The window was locked at 720 and Sources took a fixed 180 px for a
-- word like "Drop", leaving the Recipe column about ten characters wide.
describe("the Recipe column gets the room", function()
	local function columns()
		local list = M:BuildRowList(CreateFrame("Frame", nil, UIParent))
		local byKey = {}
		for _, col in ipairs(list.columns) do byKey[col.key] = col end
		return byKey
	end

	it("lets the player widen the window", function()
		-- The whole spec, so a `locked` (or a fixed width) coming back fails here.
		assert.same({ minWidth = 720, minHeight = 500 }, M.WINDOW_SIZE)
	end)

	it("keeps Recipe as the auto-width column, which takes every pixel the others leave", function()
		local recipe = columns().recipe
		assert.is_nil(recipe.width)
		assert.is_falsy(recipe.autoFit)
	end)

	it("sizes Sources to its own text rather than a fixed width", function()
		local source = columns().source
		assert.is_nil(source.width)
		assert.is_true(source.autoFit)
	end)
end)
