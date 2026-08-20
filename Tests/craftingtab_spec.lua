-- The Crafting tab's list filter and sort, and the Profit Planner's row builder
-- and money formatting. Both tabs' frame-free halves, exercised through their
-- test seams.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, CT, PT, Ace, gdb

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	-- SharedWidgets creates addon.GUI, which CraftingTab reaches for at file
	-- scope (PersistentChoice). It loads before the tabs in every .toc.
	env.loadModule("GUI/SharedWidgets.lua")
	CT = env.loadModule("GUI/CraftingTab.lua").CraftingTab
	PT = env.loadModule("GUI/AHProfitTab.lua").AHProfitTab
	Ace = ns.lib
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({})
	-- Both spellings -- the code reads through addon.Item.*, which prefers
	-- C_Item exactly as the client does. See env.itemAPI.
	env.itemAPI("GetItemInfo", function() return nil end)
	_G.GetCoinTextureString = nil
	local fr = Ace.db.factionrealm
	fr.ahPrices, fr.vendorPrices = {}, {}
end)

describe("CraftingTab filter", function()
	local function tab(search, haveOnly)
		return { _search = search, _haveOnly = haveOnly }
	end

	it("keeps everything with no filters set", function()
		assert.is_true(CT._passesFilter(tab(nil, false), { name = "Minor Healing Potion", num = 0 }))
	end)

	it("have-materials hides what cannot be made right now", function()
		assert.is_false(CT._passesFilter(tab(nil, true), { name = "x", num = 0 }))
		assert.is_true(CT._passesFilter(tab(nil, true),  { name = "x", num = 3 }))
	end)

	it("matches the recipe name", function()
		assert.is_true(CT._passesFilter(tab("healing"), { name = "Minor Healing Potion" }))
		assert.is_false(CT._passesFilter(tab("mana"),   { name = "Minor Healing Potion" }))
	end)

	it("matches the effect text term by term, in any order", function()
		-- Effect text ships stat-first ("Agility +5"), so a whole-string match
		-- missed the natural "5 agi".
		local e = { name = "Enchant Boots", effect = "Agility +5" }
		assert.is_true(CT._passesFilter(tab("5 agi"), e))
		assert.is_true(CT._passesFilter(tab("agi 5"), e))
		assert.is_false(CT._passesFilter(tab("5 str"), e))
	end)

	it("is case-insensitive", function()
		assert.is_true(CT._passesFilter(tab("MINOR"), { name = "Minor Healing Potion" }))
	end)
end)

describe("CraftingTab sort", function()
	local rows = {
		{ name = "Beta",  requiredSkill = 100, num = 1 },
		{ name = "Alpha", requiredSkill = 200, num = 5 },
		{ name = "Gamma", requiredSkill = 100, num = 0 },
	}

	local function sorted(col, asc)
		local copy = {}
		for i, r in ipairs(rows) do copy[i] = r end
		table.sort(copy, CT._comparator(col, asc))
		local out = {}
		for _, r in ipairs(copy) do out[#out + 1] = r.name end
		return out
	end

	it("sorts by name", function()
		assert.same({ "Alpha", "Beta", "Gamma" }, sorted("name", true))
		assert.same({ "Gamma", "Beta", "Alpha" }, sorted("name", false))
	end)

	it("sorts by skill, breaking ties by name", function()
		assert.same({ "Beta", "Gamma", "Alpha" }, sorted("skill", true))
	end)

	it("sorts by craftable count", function()
		assert.same({ "Alpha", "Beta", "Gamma" }, sorted("craft", false))
	end)

	it("treats a missing skill or count as zero rather than erroring", function()
		local a, b = { name = "a" }, { name = "b", requiredSkill = 5 }
		assert.is_true(CT._comparator("skill", true)(a, b))
	end)
end)

describe("CraftingTab profession pickers", function()
	local profs = {
		{ name = "Alchemy", profId = 171 },
		{ name = "Tailoring", profId = 197 },
	}

	it("finds a profession by name and by id", function()
		assert.equal(171, CT._findProf(profs, "Alchemy").profId)
		assert.equal("Tailoring", CT._findProfById(profs, 197).name)
		assert.is_nil(CT._findProf(profs, "Mining"))
		assert.is_nil(CT._findProfById(profs, nil))
		assert.is_nil(CT._findProfById(profs, 999))
	end)

	it("prefers the open profession over the saved one", function()
		assert.equal("Tailoring", CT._activeProfession(profs, { name = "Tailoring" }))
	end)

	it("falls back to the first profession when nothing is saved", function()
		Ace.db.char.craftSelProf = nil
		assert.equal("Alchemy", CT._activeProfession(profs, nil))
	end)

	it("uses the saved profession when it is still known", function()
		Ace.db.char.craftSelProf = "Tailoring"
		assert.equal("Tailoring", CT._activeProfession(profs, nil))
	end)

	it("ignores a saved profession the character no longer has", function()
		Ace.db.char.craftSelProf = "Mining"
		assert.equal("Alchemy", CT._activeProfession(profs, nil))
	end)

	it("copes with no professions at all", function()
		assert.is_nil(CT._activeProfession({}, nil))
	end)
end)

describe("price-source tag", function()
	it("abbreviates a known source in its own colour", function()
		local tag = CT._PriceSourceTag("togpm-ah")
		assert.is_true(tag:find("TOGPM", 1, true) ~= nil)
		assert.is_true(tag:find(ns.PriceSourceColors["togpm-ah"], 1, true) ~= nil)
	end)

	it("falls back to the raw source name", function()
		assert.is_true(CT._PriceSourceTag("brand-new"):find("brand-new", 1, true) ~= nil)
	end)

	it("is empty with no source", function()
		assert.equal("", CT._PriceSourceTag(nil))
	end)
end)

describe("Profit Planner helpers", function()
	it("shortens a character key", function()
		assert.equal("Bob", PT._charShort("Bob-Testrealm"))
		assert.equal("Bob", PT._charShort("Bob"))
		assert.equal("?", PT._charShort(nil))
	end)

	it("formats money, and nothing at all for a non-number", function()
		assert.equal("1g 0s 0c", PT._moneyText(10000))
		assert.equal("", PT._moneyText(nil))
	end)

	it("colours profit green and loss red, with the sign", function()
		local up, down = PT._colorProfit(500), PT._colorProfit(-500)
		assert.is_true(up:find("+", 1, true) ~= nil)
		assert.is_true(up:find("40c040", 1, true) ~= nil)
		assert.is_true(down:find("-", 1, true) ~= nil)
		assert.is_true(down:find("ff4040", 1, true) ~= nil)
		assert.equal("", PT._colorProfit("free"))
	end)

	it("lists which of MY characters know a recipe, deduped and sorted", function()
		gdb.accountChars["Bob-Testrealm"] = true
		gdb.accountChars["Alt-Testrealm"] = true
		local out = PT._knownByMyChars({ crafters = {
			["Bob-Testrealm"] = "tag", ["Alt-Testrealm"] = "tag", ["Someone-Testrealm"] = "tag" } })
		assert.same({ "Alt", "Bob" }, out)
	end)

	it("returns nothing when none of them are mine", function()
		assert.is_nil(PT._knownByMyChars({ crafters = { ["Someone-Testrealm"] = "tag" } }))
		assert.is_nil(PT._knownByMyChars(nil))
		assert.is_nil(PT._knownByMyChars({}))
	end)

	it("parses an item id out of a link", function()
		assert.equal(2589, PT._itemIdFromLink("|cffffffff|Hitem:2589|h[Linen]|h|r"))
		assert.is_nil(PT._itemIdFromLink("|Hspell:2589|h"))
		assert.is_nil(PT._itemIdFromLink(nil))
	end)

	it("collects candidate item ids without duplicates or junk", function()
		local out, seen = {}, {}
		PT._addCandidateItemId(out, seen, 118)
		PT._addCandidateItemId(out, seen, "118")   -- same id, other type
		PT._addCandidateItemId(out, seen, 0)
		PT._addCandidateItemId(out, seen, nil)
		PT._addCandidateItemId(out, seen, "abc")
		PT._addCandidateItemId(out, seen, 2589)
		assert.same({ 118, 2589 }, out)
	end)

	it("counts the keys of a map", function()
		assert.equal(0, PT._countKeys({}))
		assert.equal(2, PT._countKeys({ a = 1, [5] = 2 }))
	end)
end)

describe("Profit Planner rows", function()
	it("builds nothing without recipe data", function()
		assert.same({}, PT:BuildRows("live"))
	end)

	-- The planner only ever costs a craft through LibProfessionDB, so the real
	-- library and one of MY characters knowing the recipe are both required.
	local function myAlchemist()
		local lib = assert(env.professionDB(), "sibling ProfessionDB install required")
		env.setRecipeDB({ [171] = { [2330] = { name = "Minor Healing Potion", craftedItemId = 118 } } })
		gdb.accountChars["Bob-Testrealm"] = true
		gdb.recipes[171] = { [2330] = { crafters = { ["Bob-Testrealm"] = ns:GetCurrentGuildTag() } } }
		for itemId in pairs(lib:GetReagents(171, 2330)) do
			ns.Price.StoreVendorPrice(itemId, 50)
		end
	end

	it("builds a row for a craftable with a price on both sides", function()
		myAlchemist()
		ns.Price.StoreAHPrice(118, 100000)     -- sells for far more than it costs
		local rows = PT:BuildRows("live")
		assert.equal(1, #rows)
		assert.equal(118, rows[1].itemId)
		assert.is_true(rows[1].profit > 0)
	end)

	it("reports a loss when the mats cost more than the sale", function()
		myAlchemist()
		ns.Price.StoreAHPrice(118, 1)
		assert.is_true(PT:BuildRows("live")[1].profit < 0)
	end)

	it("leaves profit unknown when there is no sale price", function()
		myAlchemist()
		local rows = PT:BuildRows("live")
		assert.equal(1, #rows)
		assert.is_nil(rows[1].profit)
	end)

	it("ignores recipes none of my characters know", function()
		myAlchemist()
		gdb.accountChars["Bob-Testrealm"] = nil
		assert.same({}, PT:BuildRows("live"))
	end)
end)
