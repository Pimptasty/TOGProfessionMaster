-- The [Bank] buttons in the Shopping List.
--
-- Both of them called `TOGBankClassic.RequestItem(itemId)` behind a
-- `if TOGBankClassic and TOGBankClassic.RequestItem then` guard. `_G.TOGBankClassic`
-- is that addon's UI controller FRAME (its Modules/UI.lua creates it with
-- CreateFrame) and has never carried a RequestItem field -- so the guard was
-- never once true and both buttons did nothing at all, silently, because the
-- guard swallowed the miss. A button that looks enabled and does nothing is
-- worse than no button.
--
-- The working call is addon.Bank.ShowRequestDialog, which every other surface
-- already used. These specs pin that, and pin the guard shape: it must key on
-- OUR namespace, which we control, not on a global belonging to another addon.

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

describe("the Bank button's target", function()
	it("no longer references TOGBankClassic.RequestItem anywhere", function()
		-- Asserted over the source because the defect was a call to a function
		-- that does not exist: there is nothing to observe at runtime -- the
		-- guard simply never fires, which is exactly why it survived so long.
		local f = assert(io.open("GUI/ShoppingListTab.lua", "r"))
		local body = f:read("*a")
		f:close()
		assert.is_nil(body:find("TOGBankClassic.RequestItem", 1, true),
			"TOGBankClassic has no RequestItem field; this call can never run")
	end)

	it("routes through addon.Bank, which we own", function()
		local f = assert(io.open("GUI/ShoppingListTab.lua", "r"))
		local body = f:read("*a")
		f:close()
		local _, count = body:gsub("addon%.Bank%.ShowRequestDialog", "")
		-- Two [Bank] buttons here (the reagent row and the summary row); the
		-- file has other addon.Bank users, so this is a floor, not an exact
		-- count -- an exact one would break on any unrelated bank feature.
		assert.is_true(count >= 2, "expected both Bank buttons to route through addon.Bank")
	end)
end)

describe("addon.Bank.ShowRequestDialog", function()
	it("says so rather than opening an empty dialog when no banker has it", function()
		-- The failure mode that matters: a player clicks [Bank] for something
		-- nobody stocks. Silence reads as a broken button -- which is what the
		-- old call actually was.
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
