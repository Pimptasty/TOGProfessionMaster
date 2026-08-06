-- Every tab, drawn for real.
--
-- Each tab builds its entire UI from `Draw(container)`, so one call per tab
-- executes the path a player triggers by clicking it — hundreds of lines of
-- widget construction that nothing could reach before the harness grew a widget
-- layer, and whose failure mode is a Lua error in someone's face at raid time.
--
-- These are deliberately SMOKE tests: they assert the tab builds against real
-- AceGUI and real data, not what it looks like. Text metrics and layout are not
-- faithful offline and asserting on them would be a false green. What they do
-- catch is the class that actually happens — a renamed field, a nil texture, a
-- method that moved, an anchor to a frame that no longer exists.
--
-- Each tab is drawn twice on purpose. AceGUI recycles widgets, so the second
-- draw hands the tab back the pooled frames it just released, and anything it
-- failed to clean up shows here rather than three tab-switches later in game.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, gdb
local ALCHEMY, TAILORING = 171, 197
local ME, MATE = "Testchar-Testrealm", "Bob-Testrealm"
local POTION, ELIXIR, BOLT = 2330, 2331, 2963

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/SyncLog.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/ReagentWatch.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Crafting/CraftQueue.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	env.loadModule("GUI/BrowserTab.lua")
	env.loadModule("GUI/CooldownsTab.lua")
	env.loadModule("GUI/MissingRecipesTab.lua")
	env.loadModule("GUI/GuildTab.lua")
	env.loadModule("GUI/AHProfitTab.lua")
	env.loadModule("GUI/CraftingTab.lua")
	env.loadModule("GUI/ShoppingListTab.lua")
	env.loadModule("GUI/ReagentTracker.lua")
end)

--- A guild with data in every table a tab might read, so the draws exercise
--- populated branches rather than the empty-state shortcut.
local function populate()
	env.spellsExist(POTION, ELIXIR, BOLT)
	env.setRecipeDB({
		[ALCHEMY]   = {
			[POTION] = { name = "Healing Potion", icon = 1, reagents = {},
			             craftedItemId = 929, requiredSkill = 60 },
			[ELIXIR] = { name = "Elixir of Fortitude", icon = 1, reagents = {},
			             craftedItemId = 3825, requiredSkill = 120 },
		},
		[TAILORING] = {
			[BOLT] = { name = "Bolt of Linen", icon = 1, reagents = {},
			           craftedItemId = 2996, requiredSkill = 1 },
		},
	})

	local tag = ns:GetCurrentGuildTag()
	gdb.recipes[ALCHEMY] = {
		-- ME crafts the potion but NOT the elixir, so the Missing Recipes tab
		-- has something to report. Giving this character every recipe in the
		-- profession makes an empty missing-list the CORRECT answer, which is
		-- how a "populated" fixture can quietly test the empty state.
		[POTION] = { name = "R" .. POTION, icon = 1, crafters = { [MATE] = tag, [ME] = tag } },
		[ELIXIR] = { name = "R" .. ELIXIR, icon = 1, crafters = { [MATE] = tag } },
	}
	gdb.recipes[TAILORING] = {
		[BOLT] = { name = "R" .. BOLT, icon = 1, crafters = { [MATE] = tag } },
	}
	gdb.skills[ME]   = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
	gdb.skills[MATE] = { [TAILORING] = { skillRank = 150, skillMax = 300 } }
	gdb.cooldowns[ME] = { [17187] = env.serverTime + 3600 }
	gdb.accountChars[ME] = true

	ns.lib.db.char.shoppingList = { [17187] = { quantity = 2, reagents = {} } }
	ns.lib.db.char.reagentWatch = { [12359] = true }
end

before_each(function()
	env.installFrames()
	gdb = env.resetDb()
	env.roster({
		{ name = "Testchar", isOnline = true },
		{ name = "Bob",      isOnline = true },
	})
	ns.Print = function() end
	populate()
end)

--- Draw a tab twice and hand back the container. The second draw is the
--- pooled-widget pass; see the file header.
local function drawTwice(tab, opts)
	local container = env.drawTab(tab, opts)
	tab:Draw(container)
	return container
end

--- Rows actually produced. A widget COUNT is the wrong evidence and was
--- initially used here: the Browser and Profit tabs render rows as raw pooled
--- frames rather than AceGUI children, so a child count is blind to them, and
--- the Guild tab deliberately lists every profession even at zero, so its count
--- is constant by design. Three of the seven "populated" cases were therefore
--- passing on a number that never moved. Each tab is asked for its own list
--- instead — the thing it would have to build to have drawn anything.
local function rowCount(list)
	if type(list) ~= "table" then return 0 end
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	return n
end

describe("every tab builds against real AceGUI, with data in it", function()
	it("Professions (BrowserTab) lists the guild's recipes", function()
		drawTwice(ns.BrowserTab)
		assert.is_true(rowCount(ns.BrowserTab._recipes) > 0)
	end)

	it("Cooldowns lists a running cooldown", function()
		drawTwice(ns.CooldownsTab)
		local rows = ns.CooldownsTab._BuildRows(false, "mine")
		assert.is_true(rowCount(rows) > 0)
	end)

	it("Missing Recipes lists what this character lacks", function()
		drawTwice(ns.MissingRecipesTab)
		assert.is_true(rowCount(ns.MissingRecipesTab._list) > 0)
	end)

	it("Guild counts the profession coverage", function()
		-- This tab lists every profession even at zero, so the evidence is the
		-- counts it computed, not how many rows it drew.
		drawTwice(ns.GuildTab)
		local list = ns.GuildTab:BuildCounts()
		local total = 0
		for _, e in ipairs(list) do total = total + (e.total or 0) end
		assert.is_true(total > 0)
	end)

	it("Profit Planner builds its rows", function()
		drawTwice(ns.AHProfitTab)
		assert.is_true(rowCount(ns.AHProfitTab._rows) > 0)
	end)

	it("Crafting builds against an open session", function()
		local crafting = env.tradeSkillSession("Alchemy", {
			{ name = "Alchemy", difficulty = "header" },
			{ name = "Healing Potion", available = 3,
			  reagents = { { name = "Peacebloom", need = 1, have = 5 } } },
		})
		assert.is_truthy(crafting)
		assert.is_true(ns.CraftingEngine:IsOpen())
		drawTwice(ns.CraftingTab)
		assert.is_true(env.countWidgets(ns.CraftingTab._container) > 1)
	end)

	it("Shopping List lists the queued reagents", function()
		drawTwice(ns.ShoppingListTab)
		assert.is_true(rowCount(ns.ShoppingListTab:BuildReagentList()) > 0)
	end)
end)

describe("every tab survives an empty guild", function()
	-- The state a brand-new install is in, and the one most likely to hit an
	-- unguarded `#list` or a nil field.
	before_each(function()
		gdb = env.resetDb()
		env.setRecipeDB({})
		ns.lib.db.char.shoppingList = {}
		ns.lib.db.char.reagentWatch = {}
	end)

	it("Professions (BrowserTab)", function()
		assert.has_no.errors(function() env.drawTab(ns.BrowserTab) end)
	end)

	it("Cooldowns", function()
		assert.has_no.errors(function() env.drawTab(ns.CooldownsTab) end)
	end)

	it("Missing Recipes", function()
		assert.has_no.errors(function() env.drawTab(ns.MissingRecipesTab) end)
	end)

	it("Guild", function()
		assert.has_no.errors(function() env.drawTab(ns.GuildTab) end)
	end)

	it("Profit Planner", function()
		assert.has_no.errors(function() env.drawTab(ns.AHProfitTab) end)
	end)

	it("Crafting", function()
		assert.has_no.errors(function() env.drawTab(ns.CraftingTab) end)
	end)

	it("Shopping List", function()
		assert.has_no.errors(function() env.drawTab(ns.ShoppingListTab) end)
	end)
end)
