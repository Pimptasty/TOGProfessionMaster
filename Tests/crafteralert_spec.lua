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
