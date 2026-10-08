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

	-- Reported on Discord 2026-08-30: the title bar sat above the top of the
	-- screen, unreachable, until the reporter dropped UI scale to 65%. The
	-- status table restores top/left saved under whatever coordinate space the
	-- player had at the time; the window must stay on the screen it has now.
	-- Asserted from where the window LANDED, not from a flag: PersistWindow
	-- (LibAceGUIWidgets MINOR 36) moves a restored window fully onto the screen
	-- and writes the corrected position back into the saved table.
	it("is clamped to the screen, so a restored off-screen position cannot strand it", function()
		ns.lib.db.char.frames.mainWindow = { width = 720, height = 500, top = 2000, left = 100 }
		MW:Open()
		local _, screenH = UIParent:GetWidth(), UIParent:GetHeight()
		assert.is_true(MW.frame.frame:GetTop() <= screenH)
		assert.is_true(ns.lib.db.char.frames.mainWindow.top <= screenH)
	end)

	-- PersistWindow clamps only on restore, so a title bar dragged past the top
	-- edge mid-session needs the frame's own clamp while the window is open --
	-- and the pooled frame must get its old setting back, or the flag follows
	-- it into the next addon AceGUI hands it to.
	it("stays clamped while open and hands the pooled frame back unclamped", function()
		MW:Open()
		local raw = MW.frame.frame
		assert.is_true(raw:IsClampedToScreen())
		MW:Close()
		assert.is_false(raw:IsClampedToScreen())
	end)

	it("caps a saved Browser size at the screen instead of restoring it taller than the display", function()
		-- 1024x768 harness screen; a size saved under a bigger coordinate space.
		ns.lib.db.char.frames.mainWindow = { width = 720, height = 500,
		                                     browserWidth = 1400, browserHeight = 1200 }
		MW:Open("browser")
		assert.equal(768,  MW.frame.frame:GetHeight())
		assert.equal(1024, MW.frame.frame:GetWidth())
	end)

	it("restores a saved Browser size that fits, unchanged", function()
		ns.lib.db.char.frames.mainWindow = { width = 720, height = 500,
		                                     browserWidth = 800, browserHeight = 600 }
		MW:Open("browser")
		assert.equal(600, MW.frame.frame:GetHeight())
		assert.equal(800, MW.frame.frame:GetWidth())
	end)
end)

describe("the help and settings icons", function()
	it("anchors the help tooltip to the ICON, not to the MainWindow table", function()
		-- Reported in game 2026-09-11: "Wrong object type for function
		-- 'SetOwner'" from MainWindow.lua's help-icon OnEnter. A lint rename had
		-- dropped the handler's `self` parameter while the body still passed
		-- `self` to SetOwner -- which inside Open() is the MainWindow table. The
		-- harness's SetOwner takes anything, so the check is on WHAT arrived.
		MW:Open()
		local icon = MW._helpIcon
		icon:GetScript("OnEnter")(icon)
		local owner = GameTooltip:GetOwner()
		assert.equal(icon, owner)
		assert.is_not.equal(MW, owner)
		icon:GetScript("OnLeave")(icon)
	end)

	it("anchors the settings tooltip to the gear icon", function()
		MW:Open()
		local gear = MW._gearIcon
		gear:GetScript("OnEnter")(gear)
		assert.equal(gear, (GameTooltip:GetOwner()))
		gear:GetScript("OnLeave")(gear)
	end)
end)

-- Settings -> Display -> "Background opacity". The window's two FILLS fade; its
-- contents do not; and the pooled widgets get their stock colours back on close.
describe("background opacity", function()
	local function fills()
		local _, _, _, frameA = MW.frame.frame:GetBackdropColor()
		local _, _, _, paneA  = MW.tabs.border:GetBackdropColor()
		return frameA, paneA
	end

	after_each(function() ns.lib.db.profile.windowOpacity = nil end)

	it("opens fully opaque by default: AceGUI's own fills", function()
		MW:Open()
		local frameA, paneA = fills()
		assert.equal(1,   frameA)
		assert.equal(0.5, paneA)
	end)

	it("applies the saved opacity on open, to the fills and in proportion", function()
		ns.lib.db.profile.windowOpacity = 0.4
		MW:Open()
		local frameA, paneA = fills()
		assert.equal(0.4, frameA)
		assert.is_true(math.abs(paneA - 0.2) < 1e-9)       -- the pane's 0.5 scaled by 0.4
	end)

	it("does NOT fade the window itself -- text and borders stay readable", function()
		-- SetAlpha on the frame would take the contents with it; the setting is
		-- the background only. The frame's alpha is the tell.
		ns.lib.db.profile.windowOpacity = 0.4
		MW:Open()
		assert.equal(1, MW.frame.frame:GetAlpha())
	end)

	it("changes live while the window is open", function()
		MW:Open()
		ns.lib.db.profile.windowOpacity = 0.7
		MW:ApplyOpacity()
		local frameA = fills()
		assert.equal(0.7, frameA)
	end)

	it("clamps: never below 20%, never above 100%", function()
		ns.lib.db.profile.windowOpacity = 0.01
		MW:Open()
		assert.equal(0.2, (fills()))
		ns.lib.db.profile.windowOpacity = 3
		MW:ApplyOpacity()
		assert.equal(1, (fills()))
	end)

	it("puts the stock colours back before the widgets return to the pool", function()
		-- Both widgets are recycled across addons and neither resets its
		-- backdrop colour on release; a faded fill would surface in whichever
		-- addon acquires them next.
		ns.lib.db.profile.windowOpacity = 0.3
		MW:Open()
		local frame, pane = MW.frame.frame, MW.tabs.border
		MW:Close()
		local _, _, _, frameA = frame:GetBackdropColor()
		local _, _, _, paneA  = pane:GetBackdropColor()
		assert.equal(1,   frameA)
		assert.equal(0.5, paneA)
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

-- Discord 2026-08-28, with a screenshot: six expanded Shadoweave recipes and
-- the shopping-list section drew past the bottom of the window, taking the
-- "Recipes / Crafters" header and the recipe list with it. This is the report
-- end to end: the real window, the real Browser draw, the real InlineGroup,
-- and the geometry a player would see.
describe("a long shopping list inside the real window", function()
	local function longList()
		local sl = ns.lib.db.char.shoppingList
		local expanded = {}
		for i = 1, 6 do
			local rs = {}
			for j = 1, 4 do rs[j] = { itemId = 1000 + j, count = j, name = "Reagent " .. j } end
			sl[500 + i] = { name = ("Shadoweave %02d"):format(i), quantity = 1, reagents = rs }
			expanded[500 + i] = true
		end
		ns.BrowserTab._slExpanded = expanded
	end

	after_each(function()
		ns.BrowserTab._slExpanded = {}
	end)

	-- The column header anchors to the section's BOTTOM and the recipe list
	-- to the header's, so "the section is taller than the tab" IS the report.
	-- Sizes are what the harness measures reliably; its anchor resolution for
	-- an AceGUI List child is not (it reported the section's bottom above its
	-- top), so the geometry itself is not asserted here.
	it("keeps the section shorter than the tab, with every row still reachable", function()
		longList()
		MW:Open("browser")
		local BT = ns.BrowserTab
		local tabH = BT._container.frame:GetHeight()
		assert.is_true(tabH > 0)
		-- 30 rows exist in the list...
		local rl = BT._slList
		assert.equal(30, #rl.data)
		-- ...the section is capped at its share of the tab, in whole rows, well
		-- inside it...
		local shown = math.floor(BT:ShoppingListMaxHeight() / 14)
		local sectionH = BT._slSection.frame:GetHeight()
		assert.equal(shown * 14 + 40 + BT.SL_SLACK, sectionH)
		assert.is_true(sectionH < tabH * 0.6)
		-- ...and the scrollbar is what reaches the rest.
		assert.is_true(rl.scrollbar:IsShown())
		local _, maxScroll = rl.scrollbar:GetMinMaxValues()
		assert.equal(30 - shown, maxScroll)
	end)

	it("REPRODUCES the report when the cap is taken away: the section outgrows the tab", function()
		-- The control: the same window with the fix removed sizes the section
		-- to every row, past the tab's own height.
		longList()
		local real = ns.BrowserTab.ShoppingListMaxHeight
		ns.BrowserTab.ShoppingListMaxHeight = function() return 100000 end
		MW:Open("browser")
		local BT = ns.BrowserTab
		local sectionH, tabH = BT._slSection.frame:GetHeight(), BT._container.frame:GetHeight()
		ns.BrowserTab.ShoppingListMaxHeight = real
		assert.equal(30 * 14 + 40 + BT.SL_SLACK, sectionH)
		assert.is_true(sectionH > tabH)
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
