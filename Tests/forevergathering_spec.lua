-- WoW Forever camp objects: Herbalism, Skinning and Fishing have real recipes
-- there (Greenhouse, Camp Chair, Fish Bowl ...), so they count as recipe
-- professions on Forever and on no other client. CRAFTING_PROFS itself must
-- not change, because it also shapes the frozen gathering skills: sync leaf.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local HERB, SKIN, FISH, SMELTING, ALCHEMY = 182, 393, 356, 374, 171
local PDB = "LibProfessionDB-1.0"

local ns, HashManager, DS, savedLib

-- A ProfessionDB stand-in answering only the flavour question.
local function asFlavour(name)
	LibStub.libs[PDB] = { IsGameVersion = function(_, v) return v == name end }
end

setup(function()
	ns = env.boot()
	HashManager = env.loadModule("Modules/HashManager.lua").HashManager
	DS = env.deltaSync()
end)

before_each(function()
	env.install()
	savedLib = LibStub.libs[PDB]
end)

after_each(function()
	LibStub.libs[PDB] = savedLib
end)

describe("IsRecipeProfession", function()
	it("is true for every crafting profession on any client", function()
		asFlavour("Vanilla")
		for profId in pairs(ns.CRAFTING_PROFS) do
			assert.is_true(ns.IsRecipeProfession(profId))
		end
	end)

	it("keeps Herbalism, Skinning and Fishing out on a non-Forever client", function()
		for _, flavour in ipairs({ "Vanilla", "TBC", "Wrath", "Cata", "Mists", "Retail" }) do
			asFlavour(flavour)
			assert.is_false(ns.IsRecipeProfession(HERB), flavour)
			assert.is_false(ns.IsRecipeProfession(SKIN), flavour)
			assert.is_false(ns.IsRecipeProfession(FISH), flavour)
		end
	end)

	it("counts Herbalism, Skinning and Fishing on WoW Forever", function()
		asFlavour("Forever")
		assert.is_true(ns.IsRecipeProfession(HERB))
		assert.is_true(ns.IsRecipeProfession(SKIN))
		assert.is_true(ns.IsRecipeProfession(FISH))
	end)

	it("never counts Smelting, which is Mining's window", function()
		asFlavour("Forever")
		assert.is_false(ns.IsRecipeProfession(SMELTING))
	end)

	it("treats a missing ProfessionDB as not Forever", function()
		LibStub.libs[PDB] = nil
		assert.is_false(ns.IsRecipeProfession(HERB))
		assert.is_true(ns.IsRecipeProfession(ALCHEMY))
	end)

	it("leaves CRAFTING_PROFS itself without the gathering lines", function()
		asFlavour("Forever")
		assert.is_nil(ns.CRAFTING_PROFS[HERB])
		assert.is_nil(ns.CRAFTING_PROFS[SKIN])
		assert.is_nil(ns.CRAFTING_PROFS[FISH])
	end)
end)

describe("PadMissingProfessionPlaceholders on WoW Forever", function()
	it("asks guildmates for the camp-object professions too", function()
		asFlavour("Forever")
		local map = {}
		HashManager:PadMissingProfessionPlaceholders(DS, map)
		for _, profId in ipairs({ HERB, SKIN, FISH }) do
			assert.equal(DS:ComputeHash({}), map["crafters:" .. profId].hash)
			assert.equal(0, map["crafters:" .. profId].updatedAt)
		end
	end)

	it("adds no gathering placeholder anywhere else", function()
		asFlavour("Vanilla")
		local map = {}
		HashManager:PadMissingProfessionPlaceholders(DS, map)
		assert.is_nil(map["crafters:" .. HERB])
		assert.is_nil(map["crafters:" .. SKIN])
		assert.is_nil(map["crafters:" .. FISH])
		assert.is_not_nil(map["crafters:" .. ALCHEMY])
	end)
end)
