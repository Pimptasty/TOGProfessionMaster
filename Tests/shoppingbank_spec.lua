-- addon.Bank.ShowRequestDialog: the [Bank] request every surface routes through.
--
-- This file used to also pin the two [Bank] buttons on the Shopping List tab
-- (GUI/ShoppingListTab.lua). That tab was never drawn by the main window and
-- was deleted as dead code in v1.1.2, so only the dialog's own contract is
-- left here.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ITEM_ID = 2589

local ns

setup(function()
	ns = env.initDb()
end)

before_each(function()
	env.installFrames()
	env.resetDb()
end)

describe("addon.Bank.ShowRequestDialog", function()
	it("says so rather than opening an empty dialog when no banker has it", function()
		-- The failure mode that matters: a player clicks [Bank] for something
		-- nobody stocks. Silence reads as a broken button.
		local said = {}
		_G.TOGBankClassic_Guild = { GetBanks = function() return {} end, Info = { alts = {} } }
		_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) said[#said + 1] = msg end }

		ns.Bank.ShowRequestDialog(ITEM_ID, "Linen Cloth", nil, nil)
		assert.equal(1, #said)
		assert.is_truthy(said[1]:find("No bankers", 1, true))
	end)

	it("does nothing at all when TOGBankClassic is not loaded", function()
		-- Must not error: the buttons are only built when the addon is loaded,
		-- but it can be disabled between the build and the click.
		_G.TOGBankClassic_Guild = nil
		assert.has_no.errors(function()
			ns.Bank.ShowRequestDialog(ITEM_ID, "Linen Cloth", nil, nil)
		end)
	end)
end)
