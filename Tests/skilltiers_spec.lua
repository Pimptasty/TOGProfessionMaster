-- The skill-tier column and the learn-skill used by the tier filter and the
-- "Can learn now" gate, against ProfessionDB's UNANCHORED rule (its README):
-- a recipe's difficulty tiers are placeholders -- difficulty[1] must not be
-- shown or used as a threshold -- exactly when requiredSkill is ABSENT and
-- difficulty[1] == 1. The four combinations are all pinned here because each
-- one-field version of the rule is wrong for one of them.

package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
end)

before_each(function() env.install() end)

local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

describe("IsUnanchoredDifficulty", function()
	it("is unanchored when requiredSkill is absent and difficulty[1] is 1", function()
		assert.is_true(ns.IsUnanchoredDifficulty({ 1, 25, 37, 50 }, nil))
	end)

	it("is anchored when requiredSkill is absent but difficulty[1] is above 1", function()
		assert.is_false(ns.IsUnanchoredDifficulty({ 90, 115, 127, 140 }, nil))
	end)

	it("is anchored for a real apprentice craft: requiredSkill 1 and difficulty[1] 1", function()
		assert.is_false(ns.IsUnanchoredDifficulty({ 1, 30, 45, 60 }, 1))
	end)

	it("is not unanchored with no tiers at all", function()
		assert.is_false(ns.IsUnanchoredDifficulty(nil, nil))
	end)
end)

describe("FormatSkillTiers", function()
	it("shows unanchored tiers as unknown, not as thresholds", function()
		assert.equal("-", ns.FormatSkillTiers({ 1, 25, 37, 50 }, nil))
	end)

	it("shows anchored tiers with no requiredSkill", function()
		assert.equal("90 115 127 140", plain(ns.FormatSkillTiers({ 90, 115, 127, 140 }, nil)))
	end)

	it("shows a real apprentice craft's orange 1", function()
		assert.equal("1 30 45 60", plain(ns.FormatSkillTiers({ 1, 30, 45, 60 }, 1)))
	end)

	it("falls back to requiredSkill alone, and '-' for nothing", function()
		assert.equal("75", plain(ns.FormatSkillTiers(nil, 75)))
		assert.equal("-", ns.FormatSkillTiers(nil, nil))
	end)
end)

describe("RecipeLearnSkill", function()
	it("prefers requiredSkill", function()
		assert.equal(75, ns.RecipeLearnSkill({ requiredSkill = 75, difficulty = { 80, 90, 100, 110 } }))
	end)

	it("falls back to an anchored orange breakpoint", function()
		assert.equal(90, ns.RecipeLearnSkill({ difficulty = { 90, 115, 127, 140 } }))
	end)

	it("answers unknown for unanchored tiers rather than 1", function()
		assert.is_nil(ns.RecipeLearnSkill({ difficulty = { 1, 25, 37, 50 } }))
	end)

	it("keeps a real requiredSkill of 1", function()
		assert.equal(1, ns.RecipeLearnSkill({ requiredSkill = 1, difficulty = { 1, 30, 45, 60 } }))
	end)

	it("answers unknown with nothing to go on", function()
		assert.is_nil(ns.RecipeLearnSkill({}))
		assert.is_nil(ns.RecipeLearnSkill(nil))
	end)
end)
