-- The shared GameTooltip must be handed back exactly as it was found.
--
-- `_G.GameTooltip` is ONE frame shared by the whole client — Blizzard's UI, us,
-- and every other addon. A minimum width set on it is not scoped to the hover
-- that set it, and NOTHING RESETS IT AUTOMATICALLY: `GameTooltip_OnHide`
-- (Blizzard_GameTooltip/Classic/GameTooltip.lua:413) clears money frames, status
-- bars, inserted frames and the backdrop style, then sets `needsReset` — which is
-- only ever read at :541, for the secondary compare item. The minimum width is
-- untouched by all of it.
--
-- So `SetMinimumWidth(N)` + `Hide()` pins every tooltip in the game to an N-pixel
-- floor for the rest of the session. We shipped exactly that: the help icon set
-- 480 and never put it back, so one hover widened every tooltip the player saw
-- until they logged out.
--
-- Blizzard DOES lower a minimum width — it just always does so explicitly, and
-- its idiom is the pair: `SetMinimumWidth(N, true)` on show,
-- `SetMinimumWidth(0, false)` on hide (Blizzard_AchievementUI.xml:724,
-- Mists/InspectTalentFrame.lua:189, Mists/Blizzard_TalentUI.lua:1133). We restore
-- the previous value instead of zeroing, because another addon may legitimately
-- have raised it and clobbering that to 0 is the same bug pointed the other way.
--
-- WHAT THIS RUNS ON, said plainly: `env/frames.lua:996` lists `SetMinimumWidth`
-- in its NOOPS table and ships no `GetMinimumWidth` at all, so the harness cannot
-- answer "what is the minimum width now?" — which is why this bug reached a
-- player with a green suite. These specs run against the LOCAL STAND-IN in
-- `Tests/env_togpm.lua`; see `Tests/HARNESS_CONTRACT.md`. Delete the stand-in and
-- this file goes red rather than silently passing.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, MW

setup(function()
	ns = env.initDb()
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
	MW = ns.MainWindow
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	env.setRecipeDB({})
end)

-- `OpenBrowser` TOGGLES. Without this the window is left open, the next test's
-- call closes it instead of opening it, and `_helpIcon` is nil on every second
-- test — which is exactly how this file first failed: an alternating
-- pass/fail stripe that looks like state corruption and is just a toggle.
after_each(function()
	if MW and MW.Close then pcall(function() MW:Close() end) end
end)

--- Open the window and return the help icon. Separate from the hover so a test
--- can hover more than once without toggling the window shut underneath itself.
local function openHelpIcon()
	ns:OpenBrowser()
	return assert(MW._helpIcon, "help icon not built")
end

-- Drive the real handlers rather than calling MainWindow internals, so this
-- exercises the same path a player's mouse does. `assert` on the script, not
-- `if script then` — a missing handler must fail loudly, not skip the test.
local function enter(help)
	local onEnter = assert(help:GetScript("OnEnter"), "help icon has no OnEnter")
	onEnter(help)
	return help
end

local function hoverHelpIcon()
	return enter(openHelpIcon())
end

local function leaveHelpIcon(help)
	local onLeave = assert(help:GetScript("OnLeave"), "help icon has no OnLeave")
	onLeave(help)
end

describe("the help icon restores GameTooltip's minimum width", function()
	it("raises it while hovered, so the help text reads as paragraphs", function()
		hoverHelpIcon()
		assert.equal(280, _G.GameTooltip:GetMinimumWidth())
	end)

	it("puts it back to 0 on leave when nothing had set one", function()
		local help = hoverHelpIcon()
		leaveHelpIcon(help)
		assert.equal(0, _G.GameTooltip:GetMinimumWidth())
	end)

	-- THE REGRESSION. Before the fix this returned 480 forever after one hover.
	it("leaves no floor behind for the next tooltip in the game", function()
		local help = hoverHelpIcon()
		leaveHelpIcon(help)
		-- Whatever draws next gets a clean frame: a short tooltip must be able
		-- to be short. Asserting the value rather than "not 480" so a future
		-- wrong-but-different value is caught too.
		local width = _G.GameTooltip:GetMinimumWidth()
		assert.equal(0, width)
	end)

	it("restores another addon's width rather than zeroing it", function()
		-- The case the "just call SetMinimumWidth(0)" fix gets wrong.
		_G.GameTooltip:SetMinimumWidth(360)
		local help = hoverHelpIcon()
		assert.equal(280, _G.GameTooltip:GetMinimumWidth(), "our width did not take effect")
		leaveHelpIcon(help)
		assert.equal(360, _G.GameTooltip:GetMinimumWidth())
	end)

	-- `GetMinimumWidth` returns `width, forced` and `SetMinimumWidth` takes
	-- `(width, force)` — FrameAPITooltipDocumentation.lua:24-35 and :52-59.
	-- Restoring only the first return silently clears the second, which is a
	-- real behavioural bit: Blizzard pairs `(N, true)` on show with `(0, false)`
	-- on hide precisely because `force` decides whether the floor survives.
	it("restores the FORCED flag, not just the width", function()
		_G.GameTooltip:SetMinimumWidth(360, true)
		local help = hoverHelpIcon()
		leaveHelpIcon(help)
		local width, forced = _G.GameTooltip:GetMinimumWidth()
		assert.equal(360, width)
		assert.is_true(forced, "the forced flag was dropped by the restore")
	end)

	it("survives repeated hovers without accumulating", function()
		-- Guards the save slot: stashing on a second enter before the first
		-- leave would capture 280 and restore THAT, making our own width the
		-- new permanent floor — a slower version of the same bug.
		local help = openHelpIcon()
		for _ = 1, 3 do
			enter(help)
			leaveHelpIcon(help)
		end
		assert.equal(0, _G.GameTooltip:GetMinimumWidth())
	end)
end)
