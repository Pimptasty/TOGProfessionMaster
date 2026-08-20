-- Recipe-name recovery, and the item/spell id-namespace collision that makes it
-- necessary.
--
-- Two separate failure modes converge here:
--   * Classic Era's GetTradeSkillInfo hands back "? 10002" placeholders when the
--     item hasn't loaded into the client cache yet, so a scanned recipe can be
--     stored with a name that is not a name.
--   * Item ids and spell ids share a namespace. GetItemInfo(spellId) sometimes
--     returns a real but obsolete/QA item — spell 26926 is "Heavy Copper Ring",
--     item 26926 is "59 TEST Green Shaman Chest" — and that test string then
--     persists in SavedVariables and renders on every row.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, gdb
local ALCHEMY = 171

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	S = env.loadModule("Scanner.lua").Scanner
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	env.setRecipeDB({})
	ns.Print = function() end
	-- Both spellings -- the code reads through addon.Item.*, which prefers
	-- C_Item exactly as the client does. See env.itemAPI.
	env.itemAPI("GetItemInfo", function() return nil end)
	_G.GetSpellInfo = function() return nil end
end)

describe("isBogusName", function()
	it("rejects the Classic Era placeholder forms", function()
		assert.is_true(S._isBogusName("? 10002"))
		assert.is_true(S._isBogusName("?10002"))
		assert.is_true(S._isBogusName("?"))
	end)

	it("rejects nothing and the empty string", function()
		assert.is_true(S._isBogusName(nil))
		assert.is_true(S._isBogusName(""))
		assert.is_true(S._isBogusName(42))
	end)

	it("accepts a real name", function()
		assert.is_false(S._isBogusName("Minor Healing Potion"))
	end)
end)

describe("isObsoleteItemName", function()
	it("catches Blizzard's internal and dev strings", function()
		assert.is_true(S._isObsoleteItemName("59 TEST Green Shaman Chest"))
		assert.is_true(S._isObsoleteItemName("QA Test Sword"))
		assert.is_true(S._isObsoleteItemName("Deprecated Thing"))
		assert.is_true(S._isObsoleteItemName("Unused Pattern"))
		assert.is_true(S._isObsoleteItemName("ZZOLD Design: Ring"))
		assert.is_true(S._isObsoleteItemName("Manual: Something [PH]"))
		assert.is_true(S._isObsoleteItemName("Pattern: Robe OLD"))
	end)

	it("leaves a legitimate name alone", function()
		assert.is_false(S._isObsoleteItemName("Minor Healing Potion"))
		assert.is_false(S._isObsoleteItemName("Contest Winner's Cloak"))  -- contains "test"
		assert.is_false(S._isObsoleteItemName(nil))
		assert.is_false(S._isObsoleteItemName(""))
	end)
end)

describe("cleanRecipeName", function()
	local ITEM_LINK   = "|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r"
	local RECIPE_LINK = "|cffffffff|Hitem:2555|h[Recipe: Minor Healing Potion]|h|r"

	it("keeps a name that is already good", function()
		assert.equal("Real Name", S._cleanRecipeName("Real Name", ITEM_LINK, RECIPE_LINK))
	end)

	it("recovers the name from the item link", function()
		assert.equal("Minor Healing Potion", S._cleanRecipeName("? 118", ITEM_LINK, nil))
	end)

	it("falls back to the recipe link", function()
		assert.equal("Recipe: Minor Healing Potion", S._cleanRecipeName("? 118", nil, RECIPE_LINK))
	end)

	it("returns the raw value when no link helps", function()
		assert.equal("? 118", S._cleanRecipeName("? 118", nil, nil))
		assert.equal("? 118", S._cleanRecipeName("? 118", "not a link", nil))
	end)

	it("ignores a link whose bracket text is itself a placeholder", function()
		assert.equal("? 118", S._cleanRecipeName("? 118", "|Hitem:1|h[? 1]|h|r", nil))
	end)
end)

describe("mergeReagents", function()
	it("takes the incoming list as the shape of truth", function()
		local out = S._mergeReagents(
			{ { name = "Old", count = 9 } },
			{ { name = "Peacebloom", count = 1 } })
		assert.equal(1, #out)
		assert.equal("Peacebloom", out[1].name)
	end)

	it("keeps a richer item id the incoming payload lost", function()
		-- A peer whose scan couldn't resolve the id must not wipe ours.
		local out = S._mergeReagents(
			{ { name = "Peacebloom", itemId = 2447 } },
			{ { name = "Peacebloom", count = 1 } })
		assert.equal(2447, out[1].itemId)
	end)

	it("keeps a richer item link the incoming payload lost", function()
		local out = S._mergeReagents(
			{ { name = "Peacebloom", itemLink = "LINK" } },
			{ { name = "Peacebloom", count = 1 } })
		assert.equal("LINK", out[1].itemLink)
	end)

	it("prefers the incoming values when it has them", function()
		local out = S._mergeReagents(
			{ { name = "Peacebloom", itemId = 1, itemLink = "OLD" } },
			{ { name = "Peacebloom", itemId = 2447, itemLink = "NEW" } })
		assert.equal(2447, out[1].itemId)
		assert.equal("NEW", out[1].itemLink)
	end)

	it("treats a zero item id as missing", function()
		local out = S._mergeReagents(
			{ { name = "Peacebloom", itemId = 2447 } },
			{ { name = "Peacebloom", itemId = 0 } })
		assert.equal(2447, out[1].itemId)
	end)

	it("drops a non-string link rather than storing it", function()
		local out = S._mergeReagents(nil, { { name = "x", itemLink = 42 } })
		assert.is_nil(out[1].itemLink)
	end)

	it("returns nothing for a malformed payload", function()
		assert.is_nil(S._mergeReagents({}, "nope"))
		assert.is_nil(S._mergeReagents({}, nil))
	end)
end)

describe("ScrubObsoleteRecipeNames", function()
	it("clears a name that came from the colliding obsolete item", function()
		gdb.recipes[ALCHEMY] = { [26926] = {
			name = "59 TEST Green Shaman Chest", icon = 1, itemLink = "LINK", crafters = {},
		} }
		S:ScrubObsoleteRecipeNames()
		local rd = gdb.recipes[ALCHEMY][26926]
		assert.is_nil(rd.name)
		assert.is_nil(rd.icon)      -- was the obsolete item's icon
		assert.is_nil(rd.itemLink)
	end)

	it("leaves legitimate rows untouched", function()
		gdb.recipes[ALCHEMY] = { [2330] = { name = "Minor Healing Potion", icon = 7, crafters = {} } }
		S:ScrubObsoleteRecipeNames()
		assert.equal("Minor Healing Potion", gdb.recipes[ALCHEMY][2330].name)
		assert.equal(7, gdb.recipes[ALCHEMY][2330].icon)
	end)

	it("copes with no recipes at all", function()
		gdb.recipes = nil
		local ok = pcall(function() S:ScrubObsoleteRecipeNames() end)
		assert.is_true(ok)
	end)
end)

describe("BackfillBogusRecipeNames", function()
	it("recovers a placeholder name from the stored link", function()
		gdb.recipes[ALCHEMY] = { [2330] = {
			name = "? 2330", itemLink = "|Hitem:118|h[Minor Healing Potion]|h|r", crafters = {},
		} }
		S:BackfillBogusRecipeNames()
		assert.equal("Minor Healing Potion", gdb.recipes[ALCHEMY][2330].name)
	end)

	it("uses the item lookup for an item-keyed recipe", function()
		gdb.recipes[ALCHEMY] = { [118] = { name = "? 118", crafters = {} } }
		env.itemAPI("GetItemInfo", function(id)
			if id == 118 then
				return "Minor Healing Potion", "LINK", nil, nil, nil, nil, nil, nil, nil, 55
			end
		end)
		S:BackfillBogusRecipeNames()
		local rd = gdb.recipes[ALCHEMY][118]
		assert.equal("Minor Healing Potion", rd.name)
		assert.equal(55, rd.icon)
		assert.equal("LINK", rd.itemLink)
	end)

	it("REFUSES a name that is really the colliding obsolete item", function()
		-- This is the whole point of the guard: without it the TEST string got
		-- cached and rendered on every row.
		gdb.recipes[ALCHEMY] = { [26926] = { name = "? 26926", crafters = {} } }
		env.itemAPI("GetItemInfo", function() return "59 TEST Green Shaman Chest", "LINK" end)
		_G.GetSpellInfo = function() return nil end
		S:BackfillBogusRecipeNames()
		assert.is_true(S._isBogusName(gdb.recipes[ALCHEMY][26926].name))
	end)

	it("falls back to the spell lookup, and records that it is spell-keyed", function()
		-- Enchanting recipe ids ARE the enchant spell id; without this branch they
		-- stayed "? <id>" forever and the tooltip fell through to "item:<id>".
		gdb.recipes[333] = { [13937] = { name = "? 13937", crafters = {} } }
		_G.GetSpellInfo = function(id)
			if id == 13937 then return "Enchant 2H Weapon - Greater Impact", nil, 77 end
		end
		S:BackfillBogusRecipeNames()
		local rd = gdb.recipes[333][13937]
		assert.equal("Enchant 2H Weapon - Greater Impact", rd.name)
		assert.equal(77, rd.icon)
		assert.is_true(rd.isSpell)
		assert.equal(13937, rd.spellId)
	end)

	it("leaves a good name alone", function()
		gdb.recipes[ALCHEMY] = { [2330] = { name = "Minor Healing Potion", crafters = {} } }
		env.itemAPI("GetItemInfo", function() return "Something Else" end)
		S:BackfillBogusRecipeNames()
		assert.equal("Minor Healing Potion", gdb.recipes[ALCHEMY][2330].name)
	end)

	it("copes with no recipes at all", function()
		gdb.recipes = nil
		local ok = pcall(function() S:BackfillBogusRecipeNames() end)
		assert.is_true(ok)
	end)
end)

describe("MergeRecipeMetaIntoGdb", function()
	it("ignores a malformed payload", function()
		local ok = pcall(function() S:MergeRecipeMetaIntoGdb(gdb, ALCHEMY, "nope") end)
		assert.is_true(ok)
	end)

	it("creates the profession table on demand", function()
		S:MergeRecipeMetaIntoGdb(gdb, ALCHEMY, { [2330] = { name = "Minor Healing Potion" } })
		assert.is_true(gdb.recipes[ALCHEMY] ~= nil)
	end)

	it("never disturbs the crafters list, which lives on its own leaf", function()
		gdb.recipes[ALCHEMY] = { [2330] = { crafters = { ["Bob-Testrealm"] = "tag" } } }
		S:MergeRecipeMetaIntoGdb(gdb, ALCHEMY, { [2330] = { name = "Minor Healing Potion" } })
		assert.equal("tag", gdb.recipes[ALCHEMY][2330].crafters["Bob-Testrealm"])
	end)
end)
