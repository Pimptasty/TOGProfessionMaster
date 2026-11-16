-- WoW Forever's Merchant's Favor recipe vendors (ProfessionDB MINOR 14): a vendor
-- source can carry a faction and a cost, and the recipe-detail block names the
-- vendor and its price instead of the bare word "Vendor". A vendor of the other
-- faction is left out, and a vendor with no cost renders exactly as before.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ALCHEMY, SPELLBLASTING = 171, 1251731
local FAVOR = 3402

local ns, IL, savedCurrency, savedFaction

setup(function()
	ns = env.initDb()
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	IL = ns.ItemLink
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.setRecipeDB({ [ALCHEMY] = { [SPELLBLASTING] = { name = "Spellblasting Potion" } } })
	savedCurrency, savedFaction = _G.C_CurrencyInfo, _G.UnitFactionGroup
	_G.C_CurrencyInfo = { GetCurrencyInfo = function(id)
		if id == FAVOR then return { name = "Merchant's Favor" } end
	end }
	_G.UnitFactionGroup = function() return "Alliance", "Alliance" end
end)

after_each(function()
	ns.sourceDB = {}
	_G.C_CurrencyInfo, _G.UnitFactionGroup = savedCurrency, savedFaction
end)

local function vendors(list)
	ns.sourceDB = { [ALCHEMY] = { [SPELLBLASTING] = { vendor = list } } }
end

describe("FormatVendorCost", function()
	it("names a currency cost by the client's currency name", function()
		assert.equal("45 Merchant's Favor", IL.FormatVendorCost({ { currencyID = FAVOR, amount = 45 } }))
	end)

	it("keeps the amount when the client cannot name the currency", function()
		assert.equal("10 currency 9999", IL.FormatVendorCost({ { currencyID = 9999, amount = 10 } }))
	end)

	it("joins several parts", function()
		local s = IL.FormatVendorCost({ { currencyID = FAVOR, amount = 45 }, { itemID = 123, amount = 2 } })
		assert.truthy(s:find("45 Merchant's Favor", 1, true))
		assert.truthy(s:find(" + ", 1, true))
		assert.truthy(s:find("2 x ", 1, true))
	end)

	it("answers nil for no cost at all", function()
		assert.is_nil(IL.FormatVendorCost(nil))
		assert.is_nil(IL.FormatVendorCost({}))
	end)
end)

describe("RecipeDetails with priced vendors", function()
	it("names the vendor and its Merchant's Favor price", function()
		vendors({ { id = 256729, name = "Nina Surefire", faction = "Alliance",
		            cost = { { currencyID = FAVOR, amount = 45 } } } })
		local _, sources = IL.RecipeDetails(ALCHEMY, SPELLBLASTING)
		assert.same({ "Vendor: Nina Surefire (45 Merchant's Favor)" }, sources)
	end)

	it("leaves out the other faction's vendor", function()
		vendors({
			{ id = 256729, name = "Nina Surefire", faction = "Alliance",
			  cost = { { currencyID = FAVOR, amount = 45 } } },
			{ id = 1, name = "Horde Vendor", faction = "Horde",
			  cost = { { currencyID = FAVOR, amount = 45 } } },
		})
		local _, sources = IL.RecipeDetails(ALCHEMY, SPELLBLASTING)
		assert.same({ "Vendor: Nina Surefire (45 Merchant's Favor)" }, sources)
	end)

	it("falls back to the bare Vendor word when no vendor has a cost", function()
		vendors({ { id = 5, name = "Some Vendor" } })
		local _, sources = IL.RecipeDetails(ALCHEMY, SPELLBLASTING)
		assert.same({ "Vendor" }, sources)
	end)

	it("falls back to the bare Vendor word when only the other faction is priced", function()
		vendors({ { id = 1, name = "Horde Vendor", faction = "Horde",
		            cost = { { currencyID = FAVOR, amount = 45 } } } })
		local _, sources = IL.RecipeDetails(ALCHEMY, SPELLBLASTING)
		assert.same({ "Vendor" }, sources)
	end)
end)
