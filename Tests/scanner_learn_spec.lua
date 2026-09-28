-- A recipe learned with the profession window CLOSED.
--
-- Player report, 2026-09-27: "when I learn a new pattern it is still in the
-- missing recipe's tab". The trade-skill scan is the only thing that writes the
-- character's own crafter set, and it only runs while the profession window is
-- open -- so a pattern read from the bag left the recipe listed as missing
-- until the next time the player opened that profession. The client says a
-- recipe was learned in two ways (NEW_RECIPE_LEARNED, and the system message);
-- both must record the recipe and refresh the tabs.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, gdb, fired
local listener = {}
local ME        = "Testchar-Testrealm"
local TAILORING = 197
local BOLT      = 3865   -- spell id of "Bolt of Mageweave"
local OTHER     = 3915   -- a second tailoring recipe

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	S = env.loadModule("Scanner.lua").Scanner
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	env.setRecipeDB({
		[TAILORING] = {
			[BOLT]  = { name = "Bolt of Mageweave" },
			[OTHER] = { name = "Brown Linen Shirt" },
		},
	})
	S.DS = nil
	_G.ERR_LEARN_RECIPE_S = "You have learned how to create a new item: %s."
	gdb.skills[ME] = { [TAILORING] = { skillRank = 200, skillMax = 225 } }
	fired = {}
	ns.RegisterCallback(listener, "GUILD_DATA_UPDATED", function(_, charKey, scopes)
		fired[#fired + 1] = { charKey = charKey, scopes = scopes }
	end)
end)

after_each(function()
	ns.UnregisterCallback(listener, "GUILD_DATA_UPDATED")
end)

local function crafterOf(recipeId)
	local rd = gdb.recipes[TAILORING] and gdb.recipes[TAILORING][recipeId]
	return rd and rd.crafters and rd.crafters[ME]
end

describe("NEW_RECIPE_LEARNED", function()
	it("records the learned recipe for this character and refreshes the recipe tabs", function()
		S:Init()
		env.frames.fireEvent("NEW_RECIPE_LEARNED", BOLT)
		assert.is_truthy(crafterOf(BOLT))
		assert.is_nil(crafterOf(OTHER))
		assert.equal(1, #fired)
		assert.equal(ME, fired[1].charKey)
		assert.same({ recipes = true }, fired[1].scopes)
	end)

	it("ignores an id no profession carries (an engraving rune fires the same event)", function()
		assert.is_false(S:OnRecipeLearned(999999))
		assert.is_false(S:OnRecipeLearned(nil))
		assert.equal(0, #fired)
	end)

	it("does not refresh again for a recipe already recorded", function()
		assert.is_true(S:OnRecipeLearned(BOLT))
		assert.is_false(S:OnRecipeLearned(BOLT))
		assert.equal(1, #fired)
	end)
end)

describe("the 'You have learned how to create a new item' system message", function()
	it("records the recipe named in the message", function()
		S:Init()
		env.frames.fireEvent("CHAT_MSG_SYSTEM", "You have learned how to create a new item: Bolt of Mageweave.")
		assert.is_truthy(crafterOf(BOLT))
		assert.equal(1, #fired)
	end)

	it("reads the name out of an item link in the message", function()
		assert.is_true(S:OnLearnMessage(
			"You have learned how to create a new item: |cffffffff|Hitem:4339::::::::|h[Bolt of Mageweave]|h|r."))
		assert.is_truthy(crafterOf(BOLT))
	end)

	it("ignores every other system message", function()
		assert.is_false(S:OnLearnMessage("Testchar has come online."))
		assert.is_false(S:OnLearnMessage(nil))
		assert.equal(0, #fired)
	end)

	it("searches only professions this character has", function()
		gdb.skills[ME] = { [165] = { skillRank = 100, skillMax = 150 } }
		assert.is_false(S:OnLearnMessage("You have learned how to create a new item: Bolt of Mageweave."))
		assert.is_nil(crafterOf(BOLT))
	end)

	it("does nothing on a client without the string", function()
		_G.ERR_LEARN_RECIPE_S = nil
		assert.is_false(S:OnLearnMessage("You have learned how to create a new item: Bolt of Mageweave."))
		assert.is_nil(crafterOf(BOLT))
	end)

	it("follows the client's own wording, rebuilt when the string differs", function()
		_G.ERR_LEARN_RECIPE_S = "Vous avez appris à créer un nouvel objet : %s."
		assert.is_true(S:OnLearnMessage("Vous avez appris à créer un nouvel objet : Bolt of Mageweave."))
		assert.is_truthy(crafterOf(BOLT))
	end)
end)
