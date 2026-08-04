-- Foreign-window suppression: when the Crafting tab opens a profession, no other
-- profession window may stay on screen.
--
-- Opening a profession means casting it, and that cast fires TRADE_SKILL_SHOW /
-- CRAFT_SHOW — the same event every other profession UI listens for. Clicking
-- our Crafting tab therefore also pops Blizzard's window, or TSM's, leaving the
-- player with two. Reported on TBC, hence the TBC env below (it is the flavour
-- with the separate Craft window, so both frames are in play).
--
-- The load-bearing detail is that a window must be hidden WITHOUT its OnHide
-- running: every profession UI closes the trade-skill session from OnHide, and
-- that session is what our tab reads — hiding one naively blanks our own tab.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
local wow = require("env.wow")

local ns, Engine

-- A frame whose OnHide fires on Hide()/HideUIPanel, like the real thing — that
-- is the behaviour the code has to defend against, so the fake must have it.
local function newWindow()
	local f = wow.newFrame()
	f._shown = true
	f._onHideRan = 0
	f.IsShown = function(self) return self._shown end
	f.Hide = function(self)
		self._shown = false
		local h = self._scripts.OnHide
		if h then self._onHideRan = self._onHideRan + 1; h(self) end
	end
	f.Show = function(self) self._shown = true end
	return f
end

local function installGlobals()
	_G.hooksecurefunc = function() end
	_G.HideUIPanel    = function(frame) frame:Hide() end
	_G.CastSpellByName = function() end
	_G.UnitAffectingCombat = function() return false end
	-- Session probes: live unless a spec says otherwise.
	_G.GetTradeSkillLine        = function() return "Tailoring", 300, 300 end
	_G.GetCraftDisplaySkillLine = function() return "Enchanting", 300, 300 end
	_G.C_Timer = { After = function(_, fn) fn() end, NewTimer = function() return { Cancel = function() end } end }
	_G.TSM_API = nil
	_G.TradeSkillFrame, _G.CraftFrame = nil, nil
end

setup(function()
	installGlobals()
	ns = { isTBC = true, lib = { OnEnable = function() end } }
	function ns:DebugPrint() end
	Engine = wow.loadAddonFile("Modules/Crafting/CraftingEngine.lua",
		"TOGProfessionMaster", ns).CraftingEngine
end)

before_each(function()
	installGlobals()
	Engine._tabDriven = false
	Engine._sessionOpen = false
	Engine._isCraftWindow = false
	Engine._tsmFrame = nil
	Engine._tsmHooked = false
	Engine._tsmSuppressFailed = false
	Engine._suppressHooked = {}
end)

describe("_HideFrameSafely", function()
	it("hides the window without letting its OnHide close the session", function()
		local w = newWindow()
		w:SetScript("OnHide", function() error("OnHide must not run — it closes the trade-skill session") end)
		assert.is_true(Engine:_HideFrameSafely(w, true))
		assert.is_false(w:IsShown())
		assert.equal(0, w._onHideRan)
	end)

	it("puts the OnHide handler back afterwards", function()
		local w = newWindow()
		local handler = function() end
		w:SetScript("OnHide", handler)
		Engine:_HideFrameSafely(w, true)
		assert.equal(handler, w:GetScript("OnHide"))
	end)

	it("reports false for a window that is already hidden or absent", function()
		local w = newWindow()
		w._shown = false
		assert.is_false(Engine:_HideFrameSafely(w, true))
		assert.is_false(Engine:_HideFrameSafely(nil, true))
	end)
end)

describe("HideForeignWindows", function()
	it("does nothing when the session is not ours", function()
		_G.TradeSkillFrame = newWindow()
		Engine._sessionOpen, Engine._tabDriven = true, false
		Engine:HideForeignWindows()
		assert.is_true(_G.TradeSkillFrame:IsShown())
	end)

	it("hides both Blizzard frames for a tab-driven session", function()
		_G.TradeSkillFrame, _G.CraftFrame = newWindow(), newWindow()
		Engine._sessionOpen, Engine._tabDriven = true, true
		Engine:HideForeignWindows()
		assert.is_false(_G.TradeSkillFrame:IsShown())
		assert.is_false(_G.CraftFrame:IsShown())
	end)

	it("hides TSM's window too", function()
		Engine._sessionOpen, Engine._tabDriven = true, true
		Engine._tsmFrame = newWindow()
		Engine:HideForeignWindows()
		assert.is_false(Engine._tsmFrame:IsShown())
		assert.is_false(Engine._tsmSuppressFailed)
	end)

	it("stops suppressing TSM if hiding its window killed the session", function()
		Engine._sessionOpen, Engine._tabDriven = true, true
		Engine._tsmFrame = newWindow()
		-- Simulate the failure mode: the hide tore the trade-skill session down,
		-- so our tab has no data. A second window beats an empty tab.
		_G.GetTradeSkillLine = function() return nil end
		Engine:HideForeignWindows()
		assert.is_true(Engine._tsmSuppressFailed)

		_G.GetTradeSkillLine = function() return "Tailoring", 300, 300 end
		local second = newWindow()
		Engine._tsmFrame = second
		Engine:HideForeignWindows()
		assert.is_true(second:IsShown())
	end)
end)

describe("EnsureTSMHook", function()
	it("is a no-op when TSM is not installed", function()
		Engine:EnsureTSMHook()
		assert.is_false(Engine._tsmHooked)
	end)

	it("registers through TSM's public API and captures the frame it is handed", function()
		local registered
		_G.TSM_API = {
			RegisterUICallback = function(uiName, tag, fn)
				registered = { uiName = uiName, tag = tag }
				fn(true, "the-tsm-frame")
			end,
		}
		Engine._sessionOpen, Engine._tabDriven = true, true
		Engine:EnsureTSMHook()
		assert.is_true(Engine._tsmHooked)
		assert.equal("CRAFTING", registered.uiName)
		assert.equal("the-tsm-frame", Engine._tsmFrame)
	end)

	it("survives TSM rejecting the registration and retries later", function()
		_G.TSM_API = { RegisterUICallback = function() error("Callback already registered") end }
		Engine:EnsureTSMHook()
		assert.is_false(Engine._tsmHooked)
	end)

	it("drops the frame when TSM reports its UI closed", function()
		local fn
		_G.TSM_API = { RegisterUICallback = function(_, _, f) fn = f end }
		Engine:EnsureTSMHook()
		fn(true, "the-tsm-frame")
		assert.equal("the-tsm-frame", Engine._tsmFrame)
		fn(false)
		assert.is_nil(Engine._tsmFrame)
	end)
end)

describe("session ownership", function()
	it("claims the session when the tab opens a profession", function()
		assert.is_true(Engine:OpenProfession("Tailoring"))
		assert.is_true(Engine._tabDriven)
		assert.is_true(Engine._forceTakeoverOnce)
	end)

	it("does not claim it — or cast — in combat", function()
		_G.UnitAffectingCombat = function() return true end
		ns.Print = function() end
		assert.is_false(Engine:OpenProfession("Tailoring"))
		assert.is_false(Engine._tabDriven)
	end)

	it("releases the claim when the user asks for the native window", function()
		Engine._sessionOpen, Engine._tabDriven = true, true
		_G.UIParent_OnEvent = function() end
		Engine:ShowDefaultUI()
		assert.is_false(Engine._tabDriven)
	end)

	it("releases the claim when the session ends", function()
		Engine._sessionOpen, Engine._tabDriven = true, true
		Engine._tsmFrame = newWindow()
		Engine:OnProfessionClose()
		assert.is_false(Engine._tabDriven)
		assert.is_nil(Engine._tsmFrame)
	end)
end)
