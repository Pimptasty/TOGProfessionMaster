-- The tab toolbars on LibAceGUIWidgets controls, and the main window's refusal
-- to redraw under the player's hands (LAGW adoption step 6, v1.1.3).
--
-- Driven through the real window and the real library: menus are opened with
-- the dropdown box's own OnClick and picked by clicking the row the library
-- built, as a player would. Peer Review asked for these three first (thread
-- a0cbde36): every band ticked collapses back to "all"; a redraw asked for
-- while a menu is open waits and runs once when it closes; a redraw asked for
-- while a box is focused waits.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")
local wow = require("env.wow")

local ns, MW, BT, W
local ALCHEMY = 171
local ME = "Testchar-Testrealm"
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
	MW, BT, W = ns.MainWindow, ns.BrowserTab, ns.W
end)

before_each(function()
	env.installFrames()
	local gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	ns.Print = function() end
	env.spellsExist(POTION)
	env.setRecipeDB({
		[ALCHEMY] = { [POTION] = { name = "Healing Potion", icon = 1, reagents = {},
		                           craftedItemId = 929, requiredSkill = 60 } },
	})
	gdb.recipes[ALCHEMY] = {
		[POTION] = { name = "Healing Potion", icon = 1,
		             crafters = { [ME] = ns:GetCurrentGuildTag() } },
	}
	gdb.skills[ME] = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
	BT:InvalidateCache()
	BT._selectedProfId, BT._selectedTiers = 0, nil
	BT._viewMode, BT._showAllRecipes, BT._searchText = "guild", false, ""
end)

after_each(function()
	local menu = W._menus and W._menus[1]
	if menu and menu:IsShown() then menu:Hide() end
	if MW and MW.Close then pcall(function() MW:Close() end) end
end)

-- AceGUI runs a tab draw through the client's error handler, so a draw that
-- raised would surface only as a missing toolbar. Every error the handler sees
-- during a case is kept here, so expectToolbar can name it.
local caught, savedHandler = {}, nil
before_each(function()
	caught = {}
	savedHandler = _G.geterrorhandler
	_G.geterrorhandler = function()
		return function(e) caught[#caught + 1] = debug.traceback(tostring(e), 2) end
	end
end)
after_each(function()
	_G.geterrorhandler = savedHandler
end)

local function expectToolbar()
	assert.is_truthy(BT._toolbar, "the Professions tab drew no toolbar: "
		.. (#caught > 0 and table.concat(caught, " | ") or "no error reported"))
end

--- Open a toolbar dropdown's menu the way a click does, and hand it back.
local function openMenu(rec)
	local box = assert(rec and rec.box, "no dropdown box")
	box:GetScript("OnClick")(box)
	local menu = assert(W._menus and W._menus[1], "the click opened no menu")
	assert.is_true(menu:IsShown())
	return menu
end

--- Click the shown menu row whose text is `text`.
local function clickRow(menu, text)
	for _, row in ipairs(menu.rows or {}) do
		if row:IsShown() and row._lagwItem and row._lagwItem.text == text then
			row:GetScript("OnClick")(row)
			return
		end
	end
	error("the menu has no row '" .. tostring(text) .. "'")
end

local function isWithin(frame, root)
	while frame do
		if frame == root then return true end
		frame = frame:GetParent()
	end
	return false
end

describe("the Professions tab's skill-tier menu", function()
	it("collapses back to 'all tiers' once every band is ticked again", function()
		MW:Open("browser")
		expectToolbar()
		local band  = BT._SKILL_TIER_BANDS[1]
		local label = BT._TierBandLabel(band)
		local menu  = openMenu(BT._toolbar.tier)
		clickRow(menu, label)                   -- untick the first band
		assert.is_table(BT._selectedTiers)
		assert.is_nil(BT._selectedTiers[band.key])
		assert.is_true(menu:IsShown(), "a tick-box menu stays open while ticking")
		clickRow(menu, label)                   -- tick it again: every band on
		assert.is_nil(BT._selectedTiers)
	end)

	it("empties the set on Clear All, and the action row closes the menu", function()
		MW:Open("browser")
		local menu = openMenu(BT._toolbar.tier)
		clickRow(menu, ns.L and ns.L["FilterClearAll"]
			or LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")["FilterClearAll"])
		assert.same({}, BT._selectedTiers)
		assert.is_false(menu:IsShown())
	end)
end)

-- The window's stop icon: Questbook's own control (its red X, dimmed while
-- nothing is guided, its universal stop) in the bottom row beside the gear, on
-- every tab. Only with Questbook installed (operator, 2026-10-01).
describe("the window's Questbook stop icon", function()
	local AceAddon = LibStub("AceAddon-3.0")
	local savedIdb, stopped, tracking

	before_each(function()
		savedIdb, stopped, tracking = ns._itemDB, 0, false
		ns._itemDB = { WhereTrack = function() return true end,
		               WhereStopTracking = function()
		                   stopped = stopped + 1
		                   tracking = false
		                   return true
		               end }
	end)
	after_each(function()
		ns._itemDB = savedIdb
		AceAddon.addons["Questbook"] = nil
	end)

	local function questbook()
		AceAddon.addons["Questbook"] = { TrackPlace = function() end,
		                                 IsTracking = function() return tracking end }
	end

	it("sits in the bottom row with Questbook's texture, on any tab", function()
		questbook()
		MW:Open("browser")
		local icon = MW._stopIcon
		assert.is_truthy(icon, "no stop icon: "
			.. (#caught > 0 and table.concat(caught, " | ") or "no error reported"))
		assert.is_true(icon:IsShown())
		assert.equal("Interface\\RaidFrame\\ReadyCheck-NotReady", icon:GetNormalTexture():GetTexture())
	end)

	it("is dim while nothing is guided and full while something is", function()
		questbook()
		MW:Open("browser")
		assert.is_near(0.4, MW._stopIcon:GetAlpha(), 0.001)
		tracking = true
		MW:ShowGuideState()
		assert.is_near(1, MW._stopIcon:GetAlpha(), 0.001)
	end)

	it("stops the route and dims again when clicked", function()
		questbook()
		tracking = true
		MW:Open("browser")
		MW._stopIcon:GetScript("OnClick")(MW._stopIcon, "LeftButton")
		assert.equal(1, stopped)
		assert.is_near(0.4, MW._stopIcon:GetAlpha(), 0.001)
	end)

	it("is not there without Questbook, and stops watching when the window closes", function()
		MW:Open("browser")
		assert.is_nil(MW._stopIcon)
		MW:Close()
		questbook()
		MW:Open("browser")
		assert.is_truthy(MW._stopIcon)
		assert.is_true(MW._guideWatch:IsShown())
		MW:Close()
		assert.is_false(MW._guideWatch:IsShown())
	end)
end)

describe("a single-choice toolbar dropdown", function()
	it("sets the tab's value and the box's text from the picked row", function()
		MW:Open("browser")
		local rec  = BT._toolbar.prof
		local name = ns.PROF_NAMES[ALCHEMY]
		clickRow(openMenu(rec), name)
		assert.equal(ALCHEMY, BT._selectedProfId)
		assert.equal(name, rec.box.label:GetText())
	end)

	it("reuses the same box across redraws, parked inside the window", function()
		MW:Open("browser")
		local box = BT._toolbar.prof.box
		MW:Refresh()
		assert.equal(box, BT._toolbar.prof.box)
		assert.is_true(isWithin(box, MW.frame.frame))
	end)

	it("hands its frame back to UIParent when the tab is left", function()
		MW:Open("browser")
		local holder = BT._toolbar.prof.holder
		MW:SelectTab("cooldowns")
		assert.equal(UIParent, holder:GetParent())
		assert.is_false(holder:IsShown())
	end)
end)

describe("the main window does not redraw under the player's hands", function()
	it("waits while one of its menus is open, and redraws once when it closes", function()
		MW:Open("browser")
		local menu = openMenu(BT._toolbar.view)
		local before = MW._redrawCount or 0
		MW:Refresh()
		assert.equal(before, MW._redrawCount or 0)
		-- Close it the way a pick does; the deferred redraw is queued, then runs.
		clickRow(menu, "Guild")
		wow.advanceTime(0.1)
		assert.equal(before + 1, MW._redrawCount or 0)
		wow.advanceTime(1)
		assert.equal(before + 1, MW._redrawCount or 0, "one redraw, not one per retry")
	end)

	it("redraws at once when no menu of its own is open", function()
		MW:Open("browser")
		local before = MW._redrawCount or 0
		MW:Refresh()
		assert.equal(before + 1, MW._redrawCount or 0)
	end)

	it("waits while a search box inside it has the keyboard", function()
		MW:Open("browser")
		local _, search = ns.GUI.ToolbarSearch(MW.tabs, { width = 100 })
		search:SetFocus()
		assert.is_true(W:IsInputFocusedIn(MW.frame.frame), "the fixture box never took focus")
		local before = MW._redrawCount or 0
		MW._refreshDeferrals = 0
		MW:Refresh()
		assert.equal(before, MW._redrawCount or 0)
		assert.equal(1, MW._refreshDeferrals)
		search:ClearFocus()
	end)
end)

-- The two edges Peer Review named (thread a0cbde36): the library closes a menu
-- only AFTER a row's onClick returns, and nothing it does closes a menu when
-- the window that owns it goes away.
describe("a toolbar menu at the edges", function()
	it("closes with the window that owns it", function()
		MW:Open("browser")
		local menu = openMenu(BT._toolbar.view)
		MW:Close()
		assert.is_false(menu:IsShown(), "the menu outlived its window, over the game world")
	end)

	it("closes, and reports the error, when a pick's handler raises", function()
		-- A raising handler would otherwise skip the library's close, leaving the
		-- menu open and the window's deferred redraw waiting on it.
		local saved = _G.geterrorhandler
		local reported
		_G.geterrorhandler = function() return function(err) reported = err end end
		local AceGUI = LibStub("AceGUI-3.0")
		local parent = AceGUI:Create("SimpleGroup")
		local owner = {}
		local _, rec = ns.GUI.ToolbarDropdown(owner, "boom", parent, {
			items    = function() return { { value = 1, text = "One" }, { value = 2, text = "Two" } } end,
			value    = 1,
			onChange = function() error("handler failed") end,
		})
		local menu = openMenu(rec)
		local ok = pcall(clickRow, menu, "Two")
		_G.geterrorhandler = saved
		assert.is_true(ok, "the handler's error escaped the menu row")
		assert.is_false(menu:IsShown())
		assert.is_truthy(reported and tostring(reported):find("handler failed", 1, true))
		AceGUI:Release(parent)
	end)
end)

describe("a toolbar search box", function()
	it("with a debounce, reports only the text the player paused on", function()
		local AceGUI = LibStub("AceGUI-3.0")
		local parent = AceGUI:Create("SimpleGroup")
		local heard = {}
		local _, search = ns.GUI.ToolbarSearch(parent, {
			debounce  = 0.2,
			onChanged = function(text) heard[#heard + 1] = text end,
		})
		search:Fire("OnTextChanged", "a")
		search:Fire("OnTextChanged", "ab")
		wow.advanceTime(0.1)
		assert.same({}, heard)
		wow.advanceTime(0.2)
		assert.same({ "ab" }, heard)
		AceGUI:Release(parent)
	end)

	it("without one, reports every change as it happens", function()
		local AceGUI = LibStub("AceGUI-3.0")
		local parent = AceGUI:Create("SimpleGroup")
		local heard = {}
		local _, search = ns.GUI.ToolbarSearch(parent, {
			onChanged = function(text) heard[#heard + 1] = text end,
		})
		search:Fire("OnTextChanged", "a")
		assert.same({ "a" }, heard)
		AceGUI:Release(parent)
	end)
end)
