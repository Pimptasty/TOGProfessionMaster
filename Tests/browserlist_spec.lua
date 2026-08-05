-- The recipe-list pipeline behind the Professions tab.
--
-- This is the expensive, search-independent build (DB lookups + the per-crafter
-- visibility gate + tooltip search text), plus the cheap per-keystroke filters
-- layered over its cache. It lives in GUI/BrowserTab.lua but touches no frame —
-- the first CreateFrame in that file is 300 lines below the last function tested
-- here — so it is exercised in place through the file's test seam rather than
-- being relocated.
--
-- The gate is the part that has bitten repeatedly: this build BAKES each
-- crafter's visibility verdict into the cached row, so a list warmed during the
-- roster's cold-start window keeps serving ex-members for the rest of the
-- session. The roster is therefore driven to ready for real here.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, B, gdb, HOME

local ALCHEMY, TAILORING = 171, 197
local POTION_SPELL, ELIXIR_SPELL = 2330, 2331
local BOLT_SPELL = 2963

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	B = env.loadModule("GUI/BrowserTab.lua").BrowserTab
end)

before_each(function()
	env.install()
	-- These recipes exist on the simulated client. Without this the Vanilla
	-- "spell not on this client" filter in BuildFullList drops every one of
	-- them — that filter had never actually run offline until the harness
	-- installed GetSpellInfo, because its `GetSpellInfo and …` guard
	-- short-circuited on a missing global.
	env.spellsExist(POTION_SPELL, ELIXIR_SPELL, BOLT_SPELL)
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	HOME = ns:GetCurrentGuildTag()
	env.setRecipeDB({
		[ALCHEMY] = {
			[POTION_SPELL] = { name = "Minor Healing Potion", craftedItemId = 118,
			                   requiredSkill = 1,   difficulty = { 1, 28, 55, 95 } },
			[ELIXIR_SPELL] = { name = "Elixir of Lion's Strength", craftedItemId = 2454,
			                   requiredSkill = 100, difficulty = { 100, 130, 160, 190 } },
		},
		[TAILORING] = {
			[BOLT_SPELL]  = { name = "Bolt of Linen Cloth", craftedItemId = 2996,
			                  requiredSkill = 1, difficulty = { 1, 30, 55, 80 } },
		},
	})
	-- Nothing here needs a real item; keep the tooltip scraper quiet.
	_G.GetItemInfo = function() return nil end
	_G.GetItemIcon = function() return nil end
	_G.GetSpellTexture = function() return nil end
end)

local function knows(charKey, profId, spellId, tag)
	gdb.recipes[profId] = gdb.recipes[profId] or {}
	gdb.recipes[profId][spellId] = gdb.recipes[profId][spellId] or { crafters = {} }
	gdb.recipes[profId][spellId].crafters[charKey] = tag or HOME
end

local function names(list)
	local out = {}
	for _, row in ipairs(list) do out[#out + 1] = row.name end
	return out
end

describe("BuildFullList", function()
	it("returns nothing for a profession nobody crafts", function()
		assert.same({}, B._BuildFullList(ALCHEMY, "guild", {}))
	end)

	it("drops a recipe whose spell does not exist on this client", function()
		-- Vanilla-only filter: a synced recipe from a later expansion (or a
		-- bogus id) has no spell here, and listing it would offer the player a
		-- craft that cannot exist. Reachable offline only since the harness
		-- installed GetSpellInfo — before that the guard short-circuited on the
		-- missing global and this branch never ran.
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		knows("Bob-Testrealm", ALCHEMY, 999999)      -- deliberately not declared
		local list = B._BuildFullList(ALCHEMY, "guild", {})
		assert.equal(1, #list)
		assert.equal(POTION_SPELL, list[1].id)
	end)

	it("lists a recipe a guildmate crafts, with the crafter attached", function()
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		local list = B._BuildFullList(ALCHEMY, "guild", {})
		assert.equal(1, #list)
		assert.equal(POTION_SPELL, list[1].id)
		assert.equal("Bob", list[1].crafters[1].name)
		assert.is_false(list[1].greyed)
	end)

	it("sorts by name so the list is stable between builds", function()
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		knows("Bob-Testrealm", ALCHEMY, ELIXIR_SPELL)
		assert.same({ "Elixir of Lion's Strength", "Minor Healing Potion" },
			names(B._BuildFullList(ALCHEMY, "guild", {})))
	end)

	it("shows the local player as 'You' rather than by name", function()
		-- The login path records the current character in accountChars; the
		-- "You" label is gated on that, not on the character key alone.
		gdb.accountChars[ns:GetCharacterKey()] = true
		knows(ns:GetCharacterKey(), ALCHEMY, POTION_SPELL)
		local row = B._BuildFullList(ALCHEMY, "guild", {})[1]
		assert.equal("You", row.crafters[1].name)
		assert.is_true(row.crafters[1].isYou)
	end)

	it("labels an own ALT with its name alongside You", function()
		gdb.accountChars["Alt-Testrealm"] = true
		env.roster({ { name = "Testchar", isOnline = true }, { name = "Alt", isOnline = true } })
		knows("Alt-Testrealm", ALCHEMY, POTION_SPELL)
		local row = B._BuildFullList(ALCHEMY, "guild", {})[1]
		assert.is_true(row.crafters[1].name:find("Alt", 1, true) ~= nil)
		assert.is_true(row.crafters[1].isYou)
	end)

	it("hides a crafter the visibility gate rejects", function()
		knows("Nobody-Testrealm", ALCHEMY, POTION_SPELL)
		assert.same({}, B._BuildFullList(ALCHEMY, "guild", {}))
	end)

	it("includes crafterless recipes, greyed, when showAll is set", function()
		local list = B._BuildFullList(ALCHEMY, "guild", { showAll = true })
		assert.equal(2, #list)
		assert.is_true(list[1].greyed)
		assert.equal(0, #list[1].crafters)
	end)

	it("the missing view yields ONLY recipes nobody can make", function()
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		assert.same({ "Elixir of Lion's Strength" }, names(B._BuildFullList(ALCHEMY, "missing", {})))
	end)

	it("the mine view yields only what this account crafts", function()
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		knows("Alt-Testrealm",  ALCHEMY, ELIXIR_SPELL)
		gdb.accountChars["Alt-Testrealm"] = true
		assert.same({ "Elixir of Lion's Strength" }, names(B._BuildFullList(ALCHEMY, "mine", {})))
	end)

	it("shows own alts in the mine view even from another guild", function()
		-- The Mine view is deliberately account-scoped, not guild-scoped: a
		-- cross-guild alt is hidden from the guild views but must still appear
		-- to its own owner here.
		knows("Away-Testrealm", ALCHEMY, POTION_SPELL, "ffffff")
		gdb.accountChars["Away-Testrealm"] = true
		assert.equal(1, #B._BuildFullList(ALCHEMY, "mine", {}))
	end)

	it("walks every profession when asked for all of them", function()
		knows("Bob-Testrealm", ALCHEMY,   POTION_SPELL)
		knows("Bob-Testrealm", TAILORING, BOLT_SPELL)
		assert.equal(2, #B._BuildFullList(0, "guild", {}))
	end)

	it("accepts a multi-select set of professions", function()
		knows("Bob-Testrealm", ALCHEMY,   POTION_SPELL)
		knows("Bob-Testrealm", TAILORING, BOLT_SPELL)
		local list = B._BuildFullList({ [TAILORING] = true }, "guild", {})
		assert.same({ "Bolt of Linen Cloth" }, names(list))
	end)

	it("ignores a recipe our own data has never heard of", function()
		knows("Bob-Testrealm", ALCHEMY, 999999)
		assert.same({}, B._BuildFullList(ALCHEMY, "guild", {}))
	end)

	it("carries the learn skill for the tier filter", function()
		knows("Bob-Testrealm", ALCHEMY, ELIXIR_SPELL)
		assert.equal(100, B._BuildFullList(ALCHEMY, "guild", {})[1].reqSkill)
	end)

	it("falls back to the orange difficulty when no required skill is shipped", function()
		env.setRecipeDB({ [ALCHEMY] = { [POTION_SPELL] =
			{ name = "Potion", craftedItemId = 118, difficulty = { 42, 60, 80, 100 } } } })
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		assert.equal(42, B._BuildFullList(ALCHEMY, "guild", {})[1].reqSkill)
	end)

	it("folds crafter names into the search text so you can search by player", function()
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		local row = B._BuildFullList(ALCHEMY, "guild", {})[1]
		assert.is_true(row.searchText:find("bob", 1, true) ~= nil)
		assert.is_true(row.searchText:find("minor healing potion", 1, true) ~= nil)
	end)

	it("marks every row as spell-keyed with its crafted item recorded separately", function()
		-- The v1.0.5 tooltip bug in one assertion: an id is a SPELL id, and the
		-- item it makes is a different field.
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		local row = B._BuildFullList(ALCHEMY, "guild", {})[1]
		assert.is_true(row.isSpell)
		assert.equal(POTION_SPELL, row.spellId)
		assert.equal(118, row.craftedItemId)
	end)

	it("lists two crafters of the same recipe once each", function()
		knows("Bob-Testrealm", ALCHEMY, POTION_SPELL)
		knows(ns:GetCharacterKey(), ALCHEMY, POTION_SPELL)
		assert.equal(2, #B._BuildFullList(ALCHEMY, "guild", {})[1].crafters)
	end)
end)

describe("FilterList", function()
	local full

	before_each(function()
		full = {
			{ name = "Minor Healing Potion", searchText = "minor healing potion heal" },
			{ name = "Elixir of Agility",    searchText = "elixir of agility agility +5" },
		}
	end)

	it("returns the list untouched for an empty query", function()
		assert.equal(full, B._FilterList(full, ""))
		assert.equal(full, B._FilterList(full, nil))
		assert.equal(full, B._FilterList(full, "   "))
	end)

	it("matches case-insensitively", function()
		assert.equal(1, #B._FilterList(full, "MINOR"))
	end)

	it("requires EVERY term, in any order", function()
		-- Effect text ships stat-first ("Agility +5"), so "5 agi" has to match by
		-- tokens; a single-substring match returned nothing and looked broken.
		assert.equal(1, #B._FilterList(full, "5 agi"))
		assert.equal(1, #B._FilterList(full, "agi 5"))
		assert.equal(0, #B._FilterList(full, "agility potion"))
	end)

	it("returns nothing when a term matches nothing", function()
		assert.equal(0, #B._FilterList(full, "zzz"))
	end)

	it("treats a row with no search text as unmatchable", function()
		assert.equal(0, #B._FilterList({ { name = "x" } }, "x"))
	end)
end)

describe("tier bands", function()
	it("maps a learn skill to its trainer rank", function()
		assert.equal("apprentice",  B._TierBandKey(1))
		assert.equal("apprentice",  B._TierBandKey(75))
		assert.equal("journeyman",  B._TierBandKey(76))
		assert.equal("artisan",     B._TierBandKey(300))
		assert.equal("master",      B._TierBandKey(301))
		assert.equal("zenmaster",   B._TierBandKey(600))
	end)

	it("classifies nothing below rank 1", function()
		assert.is_nil(B._TierBandKey(nil))
		assert.is_nil(B._TierBandKey(0))
	end)

	it("puts anything past the top band in the top band", function()
		assert.equal("zenmaster", B._TierBandKey(9999))
	end)

	it("labels a band with its localized rank name and universal range", function()
		assert.equal("Apprentice (1-75)", B._TierBandLabel(B._SKILL_TIER_BANDS[1]))
	end)

	it("covers 1..600 with disjoint, contiguous bands", function()
		local prev
		for _, band in ipairs(B._SKILL_TIER_BANDS) do
			if prev then assert.equal(prev + 1, band.min) end
			assert.is_true(band.cap >= band.min)
			prev = band.cap
		end
		assert.equal(1, B._SKILL_TIER_BANDS[1].min)
		assert.equal(600, prev)
	end)
end)

describe("FilterTiers", function()
	local full = {
		{ name = "low",  reqSkill = 10 },
		{ name = "high", reqSkill = 400 },
		{ name = "unknown" },
	}

	it("returns everything when no tier filter is set", function()
		assert.equal(full, B._FilterTiers(full, nil))
	end)

	it("keeps only the enabled bands", function()
		assert.same({ "low", "unknown" }, names(B._FilterTiers(full, { apprentice = true })))
	end)

	it("never hides a recipe whose skill it cannot classify", function()
		assert.same({ "unknown" }, names(B._FilterTiers(full, {})))
	end)
end)

describe("listCacheKey", function()
	it("distinguishes profession, view and the show-all flag", function()
		assert.is_true(B._listCacheKey(171, "guild", false) ~= B._listCacheKey(197, "guild", false))
		assert.is_true(B._listCacheKey(171, "guild", false) ~= B._listCacheKey(171, "mine", false))
		assert.is_true(B._listCacheKey(171, "guild", false) ~= B._listCacheKey(171, "guild", true))
	end)

	it("gives the same key for the same multi-select, whatever the table", function()
		-- Two different tables holding the same selection must hit one cache
		-- entry, or every dropdown toggle rebuilds the whole list.
		assert.equal(B._listCacheKey({ [171] = true, [197] = true }, "guild", false),
		             B._listCacheKey({ [197] = true, [171] = true }, "guild", false))
	end)

	it("defaults the view to guild", function()
		assert.equal(B._listCacheKey(171, "guild", false), B._listCacheKey(171, nil, false))
	end)
end)

describe("profession dropdown", function()
	it("offers All first, then every craftable profession by name", function()
		local entries = B._GetProfDropdownEntries()
		assert.equal(0, entries[1].profId)
		assert.is_true(#entries > 1)
		for i = 3, #entries do
			assert.is_true(entries[i - 1].name <= entries[i].name)
		end
	end)

	it("omits professions this client version cannot have", function()
		local prev = ns.IsProfessionAvailable
		ns.IsProfessionAvailable = function(profId) return profId ~= 755 end
		local entries = B._GetProfDropdownEntries()
		ns.IsProfessionAvailable = prev
		for _, e in ipairs(entries) do assert.is_true(e.profId ~= 755) end
	end)
end)

describe("reagent id resolution", function()
	it("prefers a stored id", function()
		assert.equal(2589, B._ResolveReagentItemId({ itemId = 2589 }))
	end)

	it("parses one out of the link and caches it back", function()
		local r = { itemLink = "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r" }
		assert.equal(2589, B._ResolveReagentItemId(r))
		assert.equal(2589, r.itemId)
	end)

	it("falls back to a name lookup", function()
		_G.GetItemInfoInstant = function(name) return name == "Linen Cloth" and 2589 or nil end
		assert.equal(2589, B._ResolveReagentItemId({ name = "Linen Cloth" }))
	end)

	it("gives up cleanly on nothing usable", function()
		_G.GetItemInfoInstant = function() return nil end
		assert.is_nil(B._ResolveReagentItemId({}))
		assert.is_nil(B._ResolveReagentItemId(nil))
	end)

	it("rebuilds a missing link from the id and caches it", function()
		_G.GetItemInfo = function(id)
			if id == 2589 then return "Linen Cloth", "LINK" end
		end
		local r = { itemId = 2589 }
		assert.equal("LINK", B._ResolveReagentItemLink(r))
		assert.equal("LINK", r.itemLink)
	end)

	it("returns nothing while the client has not cached the item", function()
		_G.GetItemInfo = function() return nil end
		assert.is_nil(B._ResolveReagentItemLink({ itemId = 2589 }))
	end)
end)
