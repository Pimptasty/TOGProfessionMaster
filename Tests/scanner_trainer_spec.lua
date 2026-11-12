-- The trainer scan: profession trainers only, and never chat.
--
-- Player report, 2026-11-07 (WoW Forever): every spell learned at a CLASS
-- trainer printed "Trainer scan: 0 new, 4 updated (65 total recorded)". The
-- scan ran at any trainer, and TRAINER_UPDATE fires after each purchase, so the
-- summary repeated once per spell bought.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, gdb
local BOLT = 3865   -- spell id of "Bolt of Mageweave"

local TRAINER_GLOBALS = {
	"IsTradeskillTrainer", "GetNumTrainerServices", "GetTrainerServiceInfo",
	"GetTrainerServiceItemLink", "GetTrainerServiceSkillReq", "GetTrainerServiceCost",
	"GetTrainerServiceSkillLine",
}

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
	env.setRecipeDB({ [197] = { [BOLT] = { name = "Bolt of Mageweave" } } })
	S.DS = nil
	gdb.trainerObservations = nil
	-- One service offering Bolt of Mageweave, linked by spell id.
	_G.GetNumTrainerServices      = function() return 1 end
	_G.GetTrainerServiceInfo      = function() return "Bolt of Mageweave", nil, "available" end
	_G.GetTrainerServiceItemLink  = function() return "|Hspell:" .. BOLT .. "|h[Bolt of Mageweave]|h" end
	_G.GetTrainerServiceSkillReq  = function() return "Tailoring", 175 end
	_G.GetTrainerServiceCost      = function() return 500 end
	_G.GetTrainerServiceSkillLine = function() return 197 end
end)

after_each(function()
	for _, name in ipairs(TRAINER_GLOBALS) do _G[name] = nil end
end)

--- What `addon:Print` is handed while `fn` runs (see pricefacade_spec).
local function chatDuring(fn)
	local lines, saved = {}, ns.Print
	ns.Print = function(_, ...) lines[#lines + 1] = table.concat({ ... }, " ") end
	local ok, err = pcall(fn)
	ns.Print = saved
	if not ok then error(err, 0) end
	return lines
end

describe("the trainer scan", function()
	it("records nothing at a class trainer", function()
		_G.IsTradeskillTrainer = function() return false end
		S:OnTrainerShow()
		assert.is_nil(gdb.trainerObservations and gdb.trainerObservations[BOLT])
	end)

	it("records the requirement at a profession trainer", function()
		_G.IsTradeskillTrainer = function() return true end
		S:OnTrainerShow()
		local obs = gdb.trainerObservations[BOLT]
		assert.equal(175, obs.reqSkill)
		assert.equal(500, obs.moneyCost)
		assert.equal(197, obs.profId)
	end)

	it("still records on a client without IsTradeskillTrainer", function()
		S:OnTrainerShow()
		assert.equal(175, gdb.trainerObservations[BOLT].reqSkill)
	end)

	it("prints nothing to chat, whether it captured, updated or neither", function()
		_G.IsTradeskillTrainer = function() return true end
		local lines = chatDuring(function()
			S:OnTrainerShow()                                    -- captured
			_G.GetTrainerServiceCost = function() return 900 end
			S:OnTrainerShow()                                    -- updated
			S:OnTrainerShow()                                    -- unchanged
		end)
		assert.equal(900, gdb.trainerObservations[BOLT].moneyCost)
		assert.same({}, lines)
	end)
end)
