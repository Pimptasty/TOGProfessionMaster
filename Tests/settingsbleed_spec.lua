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

--- Every raw frame the Browser tab parents into an AceGUI widget. Since
--- v1.1.3 that is the recipe list's host and the detail panel; the list's
--- rows, header and scrollbar are children of the host.
local function browserRawFrames()
	local BT = ns.BrowserTab
	local out = {}
	if BT._rowListHost then out[#out + 1] = BT._rowListHost end
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
	it("draws the main window with a Professions recipe list to begin with", function()
		-- Precondition, stated as its own case: if the window or the list
		-- never built, every assertion below would pass vacuously.
		ns:OpenBrowser()
		assert.is_truthy(MW.frame)
		assert.is_truthy(ns.BrowserTab._rowList)
		assert.is_truthy(ns.BrowserTab._rowListHost)
	end)

	it("leaves the recipe list parented inside the main window", function()
		ns:OpenBrowser()
		local host = assert(ns.BrowserTab._rowListHost)
		assert.is_true(isDescendantOf(host, MW.frame.frame or MW.frame))

		ns:OpenSettings()

		assert.is_true(isDescendantOf(host, MW.frame.frame or MW.frame))
	end)

	it("does not hand the main window's recipe list to the Settings dialog", function()
		-- The widget-bleed shape: AceGUI pools account-wide, so a widget
		-- released while our raw frames are still parented into it gets handed
		-- to the next consumer, and our frames ride along into their layout.
		ns:OpenBrowser()
		local host = assert(ns.BrowserTab._rowListHost)

		ns:OpenSettings()

		local AceDialog = LibStub("AceConfigDialog-3.0")
		local dlg = AceDialog.OpenFrames and AceDialog.OpenFrames["TOGProfessionMaster"]
		if not dlg then return pending("Settings dialog did not open in the harness") end
		assert.is_false(isDescendantOf(host, dlg.frame))
	end)

	it("never re-anchors the list to chrome that has been detached", function()
		-- THE v1.0.6 BUG. The old scroll was anchored, by a layout hook on the
		-- tab container, to a header bar and the detail panel -- raw frames
		-- that its own release re-parented to UIParent. A later layout pass
		-- ran the hook anyway and anchored the scroll to a frame at UIParent's
		-- origin: "the scroll frame gets pushed outside the window". The list
		-- host is anchored to the detail panel too, so the same shape is
		-- checked: release the group they sit in, then run a layout pass.
		ns:OpenBrowser()
		local BT        = ns.BrowserTab
		local host      = assert(BT._rowListHost)
		local container = assert(BT._container)

		local section = assert(BT._listSection)
		LibStub("AceGUI-3.0"):Release(section)
		-- Take it out of its parent's child list too, as AceGUI's own
		-- ReleaseChildren does. Left listed, the pooled widget is released again
		-- when the window closes, while another owner may already hold it; that
		-- left a TabGroup in the shared pool whose next ReleaseChildren hit a
		-- nil child, and every later spec file's Professions draw failed.
		for i = #container.children, 1, -1 do
			if container.children[i] == section then table.remove(container.children, i) end
		end

		if type(container.LayoutFinished) == "function" then
			container:LayoutFinished(0, 0)
		end

		-- Detached means hidden and anchored to nothing, not shown at the
		-- world's origin.
		assert.is_false(host:IsShown())
		assert.is_nil((host:GetPoint(1)))
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
