-- Missing Recipes' [List] button: adds the row's recipe scroll to Personal
-- Shopper's shopping list through its public PersonalShopperAPI (version 1),
-- which Personal Shopper asked for when it removed its own finder.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ALCHEMY, SPELL, SCROLL = 171, 2330, 2555

local ns, M, savedAPI, printed, calls

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	M = env.loadModule("GUI/MissingRecipesTab.lua").MissingRecipesTab
end)

local realPrint, realRowDisplay

before_each(function()
	env.install()
	savedAPI = _G.PersonalShopperAPI
	calls, printed = {}, {}
	_G.PersonalShopperAPI = { version = 1, AddToShoppingList = function(itemId, qty, category)
		calls[#calls + 1] = { itemId = itemId, qty = qty, category = category }
		if itemId == SCROLL then return true end
		return false, "Bind on Pickup"
	end }
	realPrint, realRowDisplay = ns.Print, M.RowDisplay
	ns.Print = function(_, msg) printed[#printed + 1] = msg end
	M.RowDisplay = function() return { itemName = "Recipe: Minor Healing Potion" } end
end)

after_each(function()
	_G.PersonalShopperAPI = savedAPI
	ns.Print, M.RowDisplay = realPrint, realRowDisplay
end)

describe("[List] on Missing Recipes", function()
	it("is offered for a row with a scroll when Personal Shopper is loaded", function()
		assert.is_true(M:CanShopList({ profId = ALCHEMY, spellId = SPELL, itemId = SCROLL }))
	end)

	it("is not offered for a trainer-only row", function()
		assert.is_false(M:CanShopList({ profId = ALCHEMY, spellId = SPELL }))
	end)

	it("is not offered without Personal Shopper, read at call time", function()
		_G.PersonalShopperAPI = nil
		assert.is_false(M:CanShopList({ profId = ALCHEMY, spellId = SPELL, itemId = SCROLL }))
		_G.PersonalShopperAPI = { version = 1 }
		assert.is_false(M:CanShopList({ profId = ALCHEMY, spellId = SPELL, itemId = SCROLL }))
	end)

	it("adds one of the scroll under '<Profession> Recipes' and says so", function()
		assert.is_true(M:AddToShoppingList({ profId = ALCHEMY, spellId = SPELL, itemId = SCROLL }))
		assert.same({ { itemId = SCROLL, qty = 1, category = ns.PROF_NAMES[ALCHEMY] .. " Recipes" } }, calls)
		assert.equal(1, #printed)
		assert.truthy(printed[1]:find("added to your shopping list", 1, true))
	end)

	it("prints Personal Shopper's reason when it refuses", function()
		assert.is_false(M:AddToShoppingList({ profId = ALCHEMY, spellId = SPELL, itemId = 999 }))
		assert.equal(1, #printed)
		assert.truthy(printed[1]:find("Bind on Pickup", 1, true))
	end)
end)
