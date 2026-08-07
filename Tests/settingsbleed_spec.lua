-- Opening Settings while the main window is open must not disturb the window.
--
-- Reported in game at v1.0.6: click the gear beside Close (or shift-click the
-- minimap button) and the Professions tab's scroll frame and detail panel are
-- pushed OUTSIDE the main window, drawn over the game world, while the window
-- chrome stays put.
--
-- Both triggers call addon:OpenSettings(), so the button is not the cause —
-- what AceConfigDialog does to the shared AceGUI widget pool is. That is
-- reproducible offline, because the harness runs the real AceGUI: the same
-- pool, the same recycling, the same Acquire order.
--
-- The claim under test is deliberately narrow and geometric: after Settings
-- opens, the scroll frame is still inside the window it was drawn into. A spec
-- that only checked "no error" would pass while the UI was visibly broken.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")
local ace = require("env.ace")

local ns, MW, savedDb

setup(function()
	ns = env.initDb()
	ace.load("AceConfig-3.0", "AceConfigDialog-3.0", "AceConfigRegistry-3.0")
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	env.loadModule("GUI/BrowserTab.lua")
	env.loadModule("GUI/CooldownsTab.lua")
	env.loadModule("GUI/MissingRecipesTab.lua")
	env.loadModule("GUI/GuildTab.lua")
	env.loadModule("GUI/AHProfitTab.lua")
	env.loadModule("GUI/ShoppingListTab.lua")
	env.loadModule("GUI/ReagentTracker.lua")
	env.loadModule("GUI/Settings.lua")
	MW = ns.MainWindow

	-- Settings.lua registers its options table from OnInitialize, which initDb
	-- has already run — so it has to run once more for the registration hook to
	-- fire, or AceConfigDialog refuses to open and every assertion below dies
	-- on "isn't registered" rather than on the thing under test.
	-- Only if nobody has registered it yet: settings_spec.lua runs the same
	-- re-init, and AddToBlizOptions raises on a second call with the same path.
	-- Whichever spec file runs first does the registration; the other rides on
	-- it. Guarding on the registry rather than on a flag keeps that true however
	-- the suite is ordered, including a single-file run of either one.
	local registry = LibStub("AceConfigRegistry-3.0")
	if not registry:GetOptionsTable("TOGProfessionMaster") then
		savedDb = ns.lib.db
		ns.lib:OnInitialize()
	end
end)

teardown(function()
	if savedDb then ns.lib.db = savedDb end
end)

before_each(function()
	env.installFrames()
	local gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })

	-- Real recipes, so the Professions tab actually builds its pool. With an
	-- empty list there are no rows to displace and the spec proves nothing.
	local ALCHEMY, POTION = 171, 2330
	env.spellsExist(POTION)
	env.setRecipeDB({
		[ALCHEMY] = { [POTION] = { name = "Healing Potion", icon = 1,
		                           reagents = { { name = "Peacebloom", itemId = 2447, count = 1 } },
		                           craftedItemId = 929 } },
	})
	gdb.recipes[ALCHEMY] = {
		[POTION] = { name = "Healing Potion", icon = 1,
		             reagents = { { name = "Peacebloom", itemId = 2447, count = 1 } },
		             crafters = { ["Testchar-Testrealm"] = ns:GetCurrentGuildTag() } },
	}
	gdb.skills["Testchar-Testrealm"] = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
end)

after_each(function()
	pcall(function() ns:OpenSettings() end)   -- toggles closed if open
	if MW and MW.Close then pcall(function() MW:Close() end) end
end)

--- Every raw frame the Browser tab parents into an AceGUI widget.
local function browserRawFrames()
	local BT = ns.BrowserTab
	local out = {}
	for _, f in ipairs(BT._pool or {}) do out[#out + 1] = f end
	if BT._headerBar   then out[#out + 1] = BT._headerBar end
	if BT._detailOuter then out[#out + 1] = BT._detailOuter end
	return out
end

--- Walk up the parent chain looking for `ancestor`.
local function isDescendantOf(frame, ancestor)
	local p = frame
	local guard = 0
	while p and guard < 50 do
		if p == ancestor then return true end
		p = p.GetParent and p:GetParent() or nil
		guard = guard + 1
	end
	return false
end

describe("opening Settings with the main window open", function()
	it("draws the main window with a Professions scroll frame to begin with", function()
		-- Precondition, stated as its own case: if the window or the scroll
		-- never built, every assertion below would pass vacuously.
		ns:OpenBrowser()
		assert.is_truthy(MW.frame)
		assert.is_truthy(ns.BrowserTab._scroll)
		assert.is_truthy(ns.BrowserTab._scroll.frame)
	end)

	it("leaves the scroll frame parented inside the main window", function()
		ns:OpenBrowser()
		local scroll = assert(ns.BrowserTab._scroll)
		assert.is_true(isDescendantOf(scroll.frame, MW.frame.frame or MW.frame))

		ns:OpenSettings()

		assert.is_true(isDescendantOf(scroll.frame, MW.frame.frame or MW.frame))
	end)

	it("does not hand the main window's scroll widget to the Settings dialog", function()
		-- The widget-bleed shape: AceGUI pools account-wide, so a widget
		-- released while our raw frames are still parented into it gets handed
		-- to the next consumer, and our frames ride along into their layout.
		ns:OpenBrowser()
		local scroll = assert(ns.BrowserTab._scroll)

		ns:OpenSettings()

		local AceDialog = LibStub("AceConfigDialog-3.0")
		local dlg = AceDialog.OpenFrames and AceDialog.OpenFrames["TOGProfessionMaster"]
		if not dlg then return pending("Settings dialog did not open in the harness") end
		assert.is_false(isDescendantOf(scroll.frame, dlg.frame))
	end)

	it("never re-anchors the scroll to chrome that has been detached", function()
		-- THE BUG. BrowserTab installs `container.LayoutFinished =
		-- AnchorScrollToFill`, which anchors the scroll frame to _headerBar and
		-- _detailOuter. Both are raw frames that DetachPool re-parents to
		-- UIParent and strips of anchors when the scroll is released. Nothing
		-- stops a later layout pass from running that hook anyway — and
		-- anchoring the scroll to a frame sitting at UIParent's origin is
		-- precisely "the scroll frame gets pushed outside the window".
		ns:OpenBrowser()
		local BT     = ns.BrowserTab
		local scroll = assert(BT._scroll)
		local container = assert(BT._container)

		-- Release the scroll the way AceGUI actually does it: Fire("OnRelease")
		-- — which is where our DetachPool of the chrome lives — and only THEN
		-- ClearAllPoints on the widget's own frame (AceGUI-3.0.lua:177 and
		-- :196). Detaching without releasing is not a state the game reaches,
		-- and a spec built on it proves nothing.
		LibStub("AceGUI-3.0"):Release(scroll)

		-- Then let a layout pass fire, which is all opening Settings has to do.
		if type(container.LayoutFinished) == "function" then
			container:LayoutFinished(0, 0)
		end

		-- The scroll must still be anchored inside the window, not to a frame
		-- that is now floating on UIParent.
		local _, relTo = scroll.frame:GetPoint(1)
		if relTo then
			assert.is_true(isDescendantOf(relTo, MW.frame.frame or MW.frame),
				"scroll anchored to a detached frame")
		end
	end)

	it("keeps every pooled row inside the main window, or hidden", function()
		-- A row is allowed to be detached (hidden, re-parented to UIParent) —
		-- that is what DetachPool does on purpose. What it must never be is
		-- SHOWN while parented outside the window, which is the reported bug:
		-- rows drawn over the game world.
		ns:OpenBrowser()
		ns:OpenSettings()

		local stray = {}
		for _, f in ipairs(browserRawFrames()) do
			if f:IsShown() and not isDescendantOf(f, MW.frame.frame or MW.frame) then
				stray[#stray + 1] = tostring(f._name or f)
			end
		end
		assert.equal(0, #stray)
	end)
end)
