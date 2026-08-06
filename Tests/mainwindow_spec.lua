-- GUI/MainWindow.lua — the window itself, and switching between tabs.
--
-- Opening the window and clicking through its tabs is the single most-travelled
-- path in the addon, and until the harness had a widget layer none of it could
-- run outside the game. It is also where the pooled-widget hazards bite: every
-- tab switch releases one tab's widgets and hands them to the next, so anything
-- a tab fails to clean up surfaces in whichever tab happens to be opened after
-- it — which is why these specs switch tabs repeatedly rather than once.
--
-- Smoke by design (see Tests/gui_draw_spec.lua for the same reasoning): what is
-- asserted is that the window builds, routes to the right tab, and survives
-- being cycled — not what it looks like.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, MW
local ALCHEMY = 171
local ME, MATE = "Testchar-Testrealm", "Bob-Testrealm"
local POTION = 2330

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
	MW = ns.MainWindow
end)

before_each(function()
	env.installFrames()
	local gdb = env.resetDb()
	env.roster({
		{ name = "Testchar", isOnline = true },
		{ name = "Bob",      isOnline = true },
	})
	ns.Print = function() end

	env.spellsExist(POTION)
	env.setRecipeDB({
		[ALCHEMY] = { [POTION] = { name = "Healing Potion", icon = 1, reagents = {},
		                           craftedItemId = 929, requiredSkill = 60 } },
	})
	gdb.recipes[ALCHEMY] = {
		[POTION] = { name = "Healing Potion", icon = 1,
		             crafters = { [MATE] = ns:GetCurrentGuildTag(), [ME] = ns:GetCurrentGuildTag() } },
	}
	gdb.skills[ME]       = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
	gdb.accountChars[ME] = true
end)

after_each(function()
	-- The window is a persistent frame; leaving it open would hand the next
	-- spec file a half-built one.
	if MW.Close then pcall(function() MW:Close() end) end
end)

describe("opening the window", function()
	it("builds a frame with a tab group", function()
		MW:Open()
		assert.is_truthy(MW.frame)
		assert.is_truthy(MW.tabs)
	end)

	it("opens on the tab it was asked for", function()
		MW:Open("cooldowns")
		assert.equal("cooldowns", MW.activeTab)
	end)

	it("opens twice without rebuilding into a broken state", function()
		-- Persistent-window rule: a second Open refreshes rather than
		-- recreating, and must not leave two windows or a released one.
		MW:Open()
		local first = MW.frame
		MW:Open()
		assert.equal(first, MW.frame)
	end)

	it("closes and reopens", function()
		MW:Open()
		MW:Close()
		assert.has_no.errors(function() MW:Open() end)
	end)
end)

describe("switching tabs", function()
	local TABS = { "browser", "cooldowns", "missing", "guild", "ahprofit" }

	it("routes to each tab in turn", function()
		MW:Open()
		for _, key in ipairs(TABS) do
			MW:SelectTab(key)
			assert.equal(key, MW.activeTab)
		end
	end)

	it("survives a full cycle twice over", function()
		-- The pooled-widget pass: every tab has now been handed widgets another
		-- tab released. Anything not cleaned up shows up here.
		MW:Open()
		assert.has_no.errors(function()
			for _ = 1, 2 do
				for _, key in ipairs(TABS) do MW:SelectTab(key) end
			end
		end)
	end)

	it("goes back to a tab it has already shown", function()
		MW:Open("browser")
		MW:SelectTab("cooldowns")
		MW:SelectTab("browser")
		assert.equal("browser", MW.activeTab)
	end)
end)

describe("the shortcuts users actually use", function()
	it("opens the browser", function()
		ns:OpenBrowser()
		assert.equal("browser", MW.activeTab)
	end)

	it("toggles shut and open again", function()
		MW:Open()
		MW:Toggle()
		MW:Toggle()
		assert.is_truthy(MW.frame)
	end)
end)

describe("refresh", function()
	it("redraws the open tab without error", function()
		-- Fired on every GUILD_DATA_UPDATED, so it runs constantly in a live
		-- guild and is the most-repeated path in the addon.
		MW:Open("browser")
		assert.has_no.errors(function() MW:Refresh() end)
	end)

	it("redraws after the data underneath it changes", function()
		MW:Open("guild")
		local gdb = ns:GetGuildDb()
		gdb.skills["Ann-Testrealm"] = { [ALCHEMY] = { skillRank = 1, skillMax = 300 } }
		assert.has_no.errors(function() MW:Refresh() end)
	end)
end)
