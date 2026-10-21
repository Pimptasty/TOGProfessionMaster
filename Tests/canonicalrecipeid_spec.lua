-- addon:CanonicalRecipeId (TOGProfessionMaster.lua): the one place a recipe id
-- read from the client becomes the id addon.recipeDB and the gdb key on. The
-- scanner's merge and crafter-set receive, the crafting engine's metadata
-- lookup and the Crafting tab's pending select all call it; before it existed
-- each carried its own copy of the step, with different guards and nothing
-- asserting they agreed.

package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns
local savedDB, savedMap

-- Alchemy (171) ships data: spell 2330 makes item 118. Tailoring (197) ships none.
local DB = {
	[171] = {
		[2330] = { name = "Minor Healing Potion", craftedItemId = 118 },
		[3170] = { name = "Elixir of Minor Fortitude" },
	},
}

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
end)

before_each(function()
	env.installFrames()
	savedDB, savedMap = ns.recipeDB, ns._craftedItemMap
	ns.recipeDB, ns._craftedItemMap = DB, nil
end)

after_each(function()
	ns.recipeDB, ns._craftedItemMap = savedDB, savedMap
end)

describe("addon:CanonicalRecipeId", function()
	it("keeps a spell id the shipped data already knows", function()
		assert.equal(2330, ns:CanonicalRecipeId(171, 2330))
	end)

	it("maps a crafted item id to the spell that makes it", function()
		assert.equal(2330, ns:CanonicalRecipeId(171, 118))
	end)

	it("returns the id unchanged for a profession with no shipped data", function()
		assert.equal(118, ns:CanonicalRecipeId(197, 118))
	end)

	it("returns an id the data does not know and cannot map unchanged", function()
		assert.equal(99999, ns:CanonicalRecipeId(171, 99999))
	end)

	it("returns the id unchanged with no recipe database loaded at all", function()
		ns.recipeDB = nil
		assert.equal(118, ns:CanonicalRecipeId(171, 118))
	end)

	it("passes a missing profession or recipe id straight through", function()
		assert.equal(118, ns:CanonicalRecipeId(nil, 118))
		assert.is_nil(ns:CanonicalRecipeId(171, nil))
	end)
end)

describe("the scanner's merge keys through it", function()
	it("stores a Vanilla crafted item id under the spell id", function()
		local gdb = env.resetDb()
		ns.Scanner:MergeRecipesIntoGdb(gdb, "Testchar-Testrealm", 171, 1, 300, { [118] = true, [3170] = true })
		assert.is_table(gdb.recipes[171][2330])
		assert.is_table(gdb.recipes[171][3170])
		assert.is_nil(gdb.recipes[171][118])
	end)
end)
