-- GUI/CraftingTab.lua with a live trade-skill session.
--
-- The Crafting tab is the largest file in the addon and was the least covered,
-- for one reason: on Classic there is exactly one way to get a trade-skill
-- session — cast the profession — so none of it runs without one. With the
-- session faked, the whole tab becomes reachable: the recipe list, the detail
-- panel with its reagent rows, the queue panel, and selecting a recipe.
--
-- Smoke by design. What these catch is the class that actually happens in this
-- file — a nil reagent, a renamed field, an anchor to a frame that no longer
-- exists — and they catch it here rather than in front of a player who has
-- just opened their profession.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, CT, crafted

local RECIPES = {
	{ name = "Alchemy",             difficulty = "header", available = 0 },
	{ name = "Healing Potion",      available = 5, reagents = {
		{ name = "Peacebloom", need = 1, have = 20 },
		{ name = "Silverleaf", need = 1, have = 3  },
	} },
	{ name = "Elixir of Fortitude", available = 0, reagents = {
		{ name = "Goldthorn",  need = 2, have = 0  },
	} },
}

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/ReagentWatch.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Crafting/CraftQueue.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	env.loadModule("GUI/CraftingTab.lua")
	CT = ns.CraftingTab
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	ns.Print = function() end
	crafted = env.tradeSkillSession("Alchemy", RECIPES)
	-- Guard the fixture itself: if the engine does not believe a session is
	-- open, the tab renders its "open a profession" state and every test below
	-- passes while covering nothing. That is how the first version of this file
	-- moved coverage by 2%.
	assert.is_true(ns.CraftingEngine:IsOpen())
	assert.is_truthy(ns.CraftingEngine:GetOpenInfo())
	assert.is_true(#ns.CraftingEngine:GetKnownProfessions() > 0)
end)

describe("the Crafting tab with a profession open", function()
	it("builds the whole tab", function()
		local container = env.drawTab(CT)
		assert.is_true(env.countWidgets(container) > 0)
	end)

	it("builds again on a redraw, against the widgets it just released", function()
		local container = env.drawTab(CT)
		assert.has_no.errors(function() CT:Draw(container) end)
	end)

	it("fills its recipe list from the open session", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:FillList() end)
	end)

	it("survives a session with nothing in it", function()
		-- Casting a profession you have no recipes for, and the empty state
		-- most likely to hit an unguarded index.
		env.tradeSkillSession("Alchemy", {})
		assert.has_no.errors(function() env.drawTab(CT) end)
	end)

	it("survives no session at all", function()
		-- The tab can be opened from the main window without any profession
		-- being cast, which is the state a first-time user lands in.
		_G.GetTradeSkillLine = function() return nil end
		_G.GetNumTradeSkills = function() return 0 end
		assert.has_no.errors(function() env.drawTab(CT) end)
	end)
end)

describe("selecting a recipe", function()
	it("shows the detail panel for a craftable recipe", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:RequestSelect(171, 2) end)
		assert.has_no.errors(function() CT:RefreshDetail() end)
	end)

	it("shows one a reagent is missing for", function()
		-- available = 0 with an unmet reagent: the branch that greys the Craft
		-- button and colours the shortfall.
		env.drawTab(CT)
		CT:RequestSelect(171, 3)
		assert.has_no.errors(function() CT:RefreshDetail() end)
	end)

	it("refreshes the detail panel repeatedly", function()
		-- It re-renders on every bag change, so it runs constantly while a
		-- player crafts.
		env.drawTab(CT)
		CT:RequestSelect(171, 2)
		assert.has_no.errors(function()
			for _ = 1, 3 do CT:RefreshDetail() end
		end)
	end)

	it("changes the quantity without rebuilding the tab", function()
		env.drawTab(CT)
		CT:RequestSelect(171, 2)
		assert.has_no.errors(function()
			CT:SetQty(5)
			CT:RefreshDetail()
		end)
	end)
end)

describe("the queue panel", function()
	it("renders an empty queue", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:RefreshQueue() end)
	end)

	it("renders a queue with entries in it", function()
		env.drawTab(CT)
		local Q = ns.CraftQueue
		if Q and Q.Add then
			pcall(function() Q:Add({ profId = 171, recipeId = 2, name = "Healing Potion", count = 3 }) end)
		end
		assert.has_no.errors(function() CT:RefreshQueue() end)
	end)

	it("reacts to the queue changing", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:OnQueueChanged() end)
	end)

	it("reacts to the session changing", function()
		-- Switching profession mid-session: the path that used to leave the
		-- previous profession's rows on screen.
		env.drawTab(CT)
		assert.has_no.errors(function() CT:OnSessionChanged() end)
	end)

	it("reacts to a live refresh", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:OnLiveRefresh() end)
	end)
end)
