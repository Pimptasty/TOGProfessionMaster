-- The crafter-online visual alert: each style picked in Settings does the one
-- thing it names. The edge flashes go through LibAceGUIWidgets' FlashScreen,
-- the real library, spied rather than stubbed so its own arguments are the
-- thing asserted.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, W, flashes, origFlash

setup(function()
	ns = env.initDb()
	W = assert(ns.W, "LibAceGUIWidgets MINOR 36 did not load")
	origFlash = W.FlashScreen
end)

before_each(function()
	env.install()
	flashes = {}
	W.FlashScreen = function(self, opts)
		flashes[#flashes + 1] = opts
		return origFlash(self, opts)
	end
end)

after_each(function()
	W.FlashScreen = origFlash
end)

describe("the edge-flash styles", function()
	for style, color in pairs({ flashGold = "ffffd100", flashRed = "ffff2626", flashBlue = "ff408cff" }) do
		it(style .. " flashes the screen edges three times in its own colour", function()
			ns:FireCrafterAlertVisual(style)
			assert.equal(1, #flashes)
			assert.equal(color, flashes[1].color)
			assert.equal(3, flashes[1].times)
		end)
	end

	it("falls back to gold for a style it does not know", function()
		ns:FireCrafterAlertVisual("somethingElse")
		assert.equal("ffffd100", flashes[1].color)
	end)
end)

describe("the other styles do not flash the screen", function()
	it("taskbar flashes the client icon", function()
		local flashed = 0
		_G.FlashClientIcon = function() flashed = flashed + 1 end
		ns:FireCrafterAlertVisual("taskbar")
		assert.equal(1, flashed)
		assert.equal(0, #flashes)
	end)

	it("errorText writes the message to the error frame", function()
		local got
		_G.UIErrorsFrame = { AddMessage = function(_, msg) got = msg end }
		ns:FireCrafterAlertVisual("errorText", "Bob is online")
		assert.equal("Bob is online", got)
		assert.equal(0, #flashes)
	end)
end)

-- The chat line for a recipe on the shopping list. Until 2026-10-17 the alt
-- form passed its two names the wrong way round: when Alt (an alt of the
-- crafter Main) logged in, chat read "Main is online (alt of Alt)". The string
-- is "<who came online> is online (alt of <the crafter>)".
describe("the crafter-online chat line", function()
	local gdb, printed
	local RECIPE = 17187   -- any id: the alert reads it only as a key

	before_each(function()
		gdb = env.resetDb()
		printed = {}
		ns.Print = function(_, msg) printed[#printed + 1] = msg end
		local p = ns.lib.db.profile
		p.crafterAlert = true
		p.crafterAlertSuppressAudio  = true
		p.crafterAlertSuppressVisual = true
		ns.lib.db.char.shoppingAlerts = { [RECIPE] = true }
		gdb.recipes = { [171] = { [RECIPE] = { name = "Transmute: Arcanite", crafters = { ["Main-Testrealm"] = 1 } } } }
		gdb.altGroups = { ["Main-Testrealm"] = { "Main-Testrealm", "Alt-Testrealm" } }
	end)

	it("names the crafter when the crafter logs in", function()
		ns:OnCrafterCameOnline("Main-Testrealm")
		assert.equal(1, #printed)
		assert.is_true(printed[1]:find("Main is online", 1, true) ~= nil)
		assert.is_nil(printed[1]:find("alt of", 1, true))
	end)

	it("names who came online first, then the crafter they are an alt of", function()
		ns:OnCrafterCameOnline("Alt-Testrealm")
		assert.equal(1, #printed)
		assert.is_true(printed[1]:find("Alt is online (alt of Main)", 1, true) ~= nil)
	end)

	it("says nothing for a character with no listed recipe", function()
		ns:OnCrafterCameOnline("Stranger-Testrealm")
		assert.equal(0, #printed)
	end)
end)
