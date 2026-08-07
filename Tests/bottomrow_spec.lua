-- Buttons parked on a window's bottom status row must be clickable.
--
-- AceGUI's Frame widget lays two MOUSE-ENABLED resize strips along the bottom:
-- `sizer_s` spans the full width and is 25 tall, `sizer_se` is a 25x25 corner
-- (AceGUIContainer-Frame.lua:253-280). Anything parented to the frame and
-- anchored on that strip competes with them for hit-testing. Reported in game
-- as a dead lower half on the bottom-row buttons; the same bug was found and
-- fixed in FastGuildInvite, whose `LiftAboveSizers` helper is the reference
-- (fastguildinvite/functions.lua:15).
--
-- Note what is NOT claimed: that an equal frame level always loses. AceGUI's own
-- close button sits at the same level as the sizers, overlaps them, and works
-- fine. The exact tiebreak is unestablished; lifting clear of the strips sidesteps
-- it, which is what FGI did and what fixed it there.
--
-- The fix is a frame LEVEL, not a position, so it is exactly the kind of claim
-- this harness can check: env/frames.lua models GetFrameLevel/SetFrameLevel
-- with real child propagation, taken from wowless.
--
-- Worth stating what these specs do NOT prove: hit-testing itself is not
-- modelled, so this asserts the ORDERING that governs it rather than a click
-- landing. That is the honest limit of an offline check here.

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

after_each(function()
	if MW and MW.Close then pcall(function() MW:Close() end) end
end)

--- The AceGUI Frame widget behind the main window.
local function windowWidget()
	return MW.frame
end

local function sizers(widget)
	return { s = widget.sizer_s, se = widget.sizer_se, e = widget.sizer_e }
end

--- Highest level among the mouse-enabled resize strips a button must clear.
local function topSizerLevel(widget)
	local top = -1
	for _, sz in pairs(sizers(widget)) do
		if sz and sz.IsMouseEnabled and sz:IsMouseEnabled() then
			local lvl = sz:GetFrameLevel() or 0
			if lvl > top then top = lvl end
		end
	end
	return top
end

-- ---------------------------------------------------------------------------

describe("the AceGUI frame really does lay mouse-enabled sizers on the bottom", function()
	-- Preconditions. If AceGUI ever stops creating these, or stops enabling
	-- their mouse, the specs below would pass for the wrong reason — so the
	-- premise gets asserted rather than assumed.
	it("creates a bottom strip and a bottom-right corner", function()
		ns:OpenBrowser()
		local sz = sizers(windowWidget())
		assert.is_truthy(sz.s)
		assert.is_truthy(sz.se)
	end)

	it("overlaps the bottom-row icons, which is the whole problem", function()
		-- Geometry rather than IsMouseEnabled. AceGUI calls `sizer_se:EnableMouse()`
		-- with NO argument, and Blizzard documents the parameter as
		-- `Nilable = false, Default = false` (SimpleScriptRegionAPIDocumentation
		-- :77) — so what a bare call does in the live client is not something
		-- these docs settle, and asserting it would be asserting a guess.
		--
		-- The overlap needs no such assumption: sizer_s is 25 tall from the
		-- bottom edge, the help icon sits 15 up and is 24 tall, the gear 17 up
		-- and 20 tall. Both are partly inside the strip. That, plus FGI hitting
		-- this in game and fixing it exactly this way, is the evidence.
		ns:OpenBrowser()
		local frames = require("env.frames")
		local sz = sizers(windowWidget())
		local gear = assert(ns.MainWindow._gearIcon)
		assert.is_true(frames.overlaps(gear, sz.s),
			"gear does not overlap the bottom resize strip — premise no longer holds")
	end)
end)

describe("bottom-row buttons clear the resize strips", function()
	it("the settings gear does", function()
		ns:OpenBrowser()
		local w = windowWidget()
		local gear = assert(MW._gearIcon, "gear icon not built")
		assert.is_true(gear:GetFrameLevel() > topSizerLevel(w),
			"gear sits at or below the resize strips, so its lower half eats clicks")
	end)

	it("the help icon does", function()
		ns:OpenBrowser()
		local w = windowWidget()
		local help = assert(MW._helpIcon, "help icon not built")
		assert.is_true(help:GetFrameLevel() > topSizerLevel(w),
			"help icon sits at or below the resize strips")
	end)
end)

describe("the sweep — nothing else on the window sits under a sizer", function()
	-- The generic guard, so this cannot come back via a button added later.
	-- Every raw child of the AceGUI frame that OVERLAPS a resize strip must sit
	-- above it. Anything that does not overlap is none of this rule's business.
	--
	-- Scope, established by grep rather than guessed: only `AceGUI:Create("Frame")`
	-- windows have sizers, and this addon makes exactly two — the main window and
	-- the Sync Log. Everything else that looks like a window is a raw
	-- CreateFrame on UIParent with no resize strips at all: the Reagent Tracker
	-- (`TOGPMReagentTracker`), the Cooldowns group popup, and the bank request
	-- dialog. The Sync Log's one raw button is anchored TOPRIGHT and already sets
	-- its own level to parent+10, so it was never exposed.
	it("every raw frame WE park on the window clears the strips", function()
		-- Scoped to our own frames on purpose. An earlier version of this swept
		-- every child of the AceGUI frame and reported three "offenders" — which
		-- turned out to be AceGUI's OWN closebutton, statusbg and content
		-- (constructor order, AceGUIContainer-Frame.lua:199/206/294). Those
		-- overlap the strips at the same frame level and the Close button is
		-- perfectly clickable in game, so flagging them was a false positive and
		-- "equal level means unclickable" is not the whole rule.
		--
		-- What IS established: FGI hit this on its own bottom-row buttons and
		-- lifting them fixed it. So this guards the thing we control — our
		-- frames — and leaves AceGUI's alone.
		ns:OpenBrowser()
		local frames = require("env.frames")
		local w   = windowWidget()
		local sz  = sizers(w)
		local top = topSizerLevel(w)

		local ours = {
			_helpIcon = ns.MainWindow._helpIcon,
			_gearIcon = ns.MainWindow._gearIcon,
		}
		local offenders = {}
		for name, child in pairs(ours) do
			local hits = {}
			for k, s in pairs(sz) do
				if s and frames.overlaps(child, s) then hits[#hits + 1] = k end
			end
			if #hits > 0 and (child:GetFrameLevel() or 0) <= top then
				offenders[#offenders + 1] = ("%s level=%s over sizer_%s"):format(
					name, tostring(child:GetFrameLevel()), table.concat(hits, "+"))
			end
		end
		table.sort(offenders)
		assert.equal("", table.concat(offenders, " | "))
	end)
end)

describe("LiftAboveSizers", function()
	it("raises a button clear of its parent", function()
		local parent = CreateFrame("Frame", nil, UIParent)
		parent:SetFrameLevel(100)
		local btn = CreateFrame("Button", nil, parent)
		btn:SetFrameLevel(100)
		ns.GUI.LiftAboveSizers(btn)
		assert.is_true(btn:GetFrameLevel() > 101)
	end)

	it("clears the sizers by a margin, not by exactly one", function()
		-- The sizers sit at parent+1, so parent+1 would be a tie. What a tie
		-- resolves to is NOT something I have established -- AceGUI's own close
		-- button ties with them and works fine -- so the margin is here because
		-- FGI's fix used one and it worked, not because I can explain the
		-- tiebreak. Clearing by 5 removes the question.
		local parent = CreateFrame("Frame", nil, UIParent)
		parent:SetFrameLevel(100)
		local btn = CreateFrame("Button", nil, parent)
		ns.GUI.LiftAboveSizers(btn)
		assert.is_true(btn:GetFrameLevel() >= 105)
	end)

	it("honours an explicit offset", function()
		local parent = CreateFrame("Frame", nil, UIParent)
		parent:SetFrameLevel(50)
		local btn = CreateFrame("Button", nil, parent)
		ns.GUI.LiftAboveSizers(btn, 9)
		assert.equal(59, btn:GetFrameLevel())
	end)

	it("does nothing, and does not raise, on a nil or level-less object", function()
		assert.has_no.errors(function() ns.GUI.LiftAboveSizers(nil) end)
		assert.has_no.errors(function() ns.GUI.LiftAboveSizers({}) end)
	end)
end)
