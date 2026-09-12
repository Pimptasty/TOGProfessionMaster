-- Beast Training must reach Blizzard's window even when the crafting takeover is on.
--
-- Reported from Discord, 2026-09-10: "hunter training skill conflicts in classic
-- with TOGPM causing it to not be usable to train pets". On Vanilla/TBC a
-- hunter's Beast Training opens the same CraftFrame as Enchanting and fires the
-- same CRAFT_SHOW. With the takeover on, Init has unregistered that event from
-- UIParent and CraftFrame, so the only window that can teach a pet never shows,
-- and our Crafting tab opens on a session it cannot read.
--
-- The game tells the two apart by `GetCraftDisplaySkillLine()`: a name for a
-- profession, nil for Beast Training (Blizzard_CraftUI.lua hides its rank bar on
-- that nil). These specs drive the engine's CRAFT_SHOW handler with each answer
-- and assert which window the player ends up with.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
local wow = require("env.wow")

local ns, Engine, calls

local function installGlobals()
	_G.hooksecurefunc = function() end
	_G.HideUIPanel    = function(frame) frame:Hide() end
	_G.UnitAffectingCombat = function() return false end
	_G.C_Timer = { After = function(_, fn) fn() end, NewTimer = function() return { Cancel = function() end } end }
	_G.TSM_API = nil
	_G.TradeSkillFrame, _G.CraftFrame = nil, nil
	_G.CloseTradeSkill = nil
	_G.UIParent = _G.UIParent or wow.newFrame()
	_G.UIParent_OnEvent = function(_, event) calls.uiparent[#calls.uiparent + 1] = event end
	-- The two session probes. A spec flips the craft one to model Beast Training.
	_G.GetTradeSkillLine        = function() return "Tailoring", 300, 300 end
	_G.GetCraftDisplaySkillLine = function() return "Enchanting", 300, 300 end
end

--- Beast Training's answer: no skill line at all.
local function beastTraining()
	_G.GetCraftDisplaySkillLine = function() return nil end
end

setup(function()
	calls = { uiparent = {}, open = {}, close = 0 }
	installGlobals()
	ns = { isTBC = true, lib = { OnEnable = function() end } }
	function ns:DebugPrint() end
	ns.MainWindow = {
		Open  = function(_, tab) calls.open[#calls.open + 1] = tab end,
		Close = function() calls.close = calls.close + 1 end,
	}
	Engine = wow.loadAddonFile("Modules/Crafting/CraftingEngine.lua",
		"TOGProfessionMaster", ns).CraftingEngine
end)

before_each(function()
	calls = { uiparent = {}, open = {}, close = 0 }
	installGlobals()
	-- Takeover ON unless a case says otherwise: hands-off off, takeover on. This
	-- is the configuration the report came from; hands-off never had the bug.
	ns.lib.db = { profile = { craftingHandsOff = false, craftingTakeover = true }, char = {} }
	Engine._tabDriven = false
	Engine._sessionOpen = false
	Engine._isCraftWindow = false
	Engine._craftOpen = false
	Engine._tradeOpen = false
	Engine._autoOpened = false
	Engine._showingDefault = false
	Engine._forceTakeoverOnce = false
	Engine._closePending = false
	Engine._tsmFrame = nil
	Engine._tsmHooked = false
	Engine._suppressHooked = {}
	Engine._hookedFrames = {}
end)

describe("IsPetTrainingSession", function()
	it("is true for a craft window with no skill line", function()
		Engine._isCraftWindow = true
		beastTraining()
		assert.is_true(Engine:IsPetTrainingSession())
	end)

	it("treats an empty skill name the same as nil", function()
		Engine._isCraftWindow = true
		_G.GetCraftDisplaySkillLine = function() return "" end
		assert.is_true(Engine:IsPetTrainingSession())
	end)

	it("is false for Enchanting, the profession that shares the frame", function()
		Engine._isCraftWindow = true
		assert.is_false(Engine:IsPetTrainingSession())
	end)

	it("is false for a trade-skill window whatever the craft probe says", function()
		-- TRADE_SKILL_SHOW sessions never carry pet training; the craft probe
		-- is stale or absent there and must not be consulted.
		Engine._isCraftWindow = false
		beastTraining()
		assert.is_false(Engine:IsPetTrainingSession())
	end)
end)

describe("CRAFT_SHOW with the takeover on", function()
	it("REPRODUCES the report on the Enchanting path: the takeover claims the session", function()
		-- The control. Same configuration, a real profession: our tab opens and
		-- Blizzard's window is not summoned. This is what the hunter was getting.
		Engine:OnEvent("CRAFT_SHOW")
		assert.same({ "crafting" }, calls.open)
		assert.same({}, calls.uiparent)
	end)

	it("hands Beast Training straight to Blizzard's window and opens no tab", function()
		beastTraining()
		Engine:OnEvent("CRAFT_SHOW")
		assert.same({ "CRAFT_SHOW" }, calls.uiparent)
		assert.same({}, calls.open)
	end)

	it("does not claim the session, so the OnShow suppress hook leaves the frame alone", function()
		beastTraining()
		Engine._tabDriven = true               -- left over from an earlier tab-driven open
		Engine:OnEvent("CRAFT_SHOW")
		assert.is_false(Engine._tabDriven)
		assert.is_false(Engine._autoOpened)
	end)

	it("does not record pet training as the player's 'last UI' choice", function()
		-- A pet window is not a vote for either UI. The prior value is the one
		-- the takeover path would OVERWRITE (it records "togpm"), so a hand-off
		-- that leaked into OnProfessionShow is caught here -- verified by
		-- disabling the fix: this went red.
		ns.lib.db.char.craftingLastUI = "blizzard"
		beastTraining()
		Engine:OnEvent("CRAFT_SHOW")
		assert.equal("blizzard", ns.lib.db.char.craftingLastUI)
	end)

	it("still tracks the session so CRAFT_CLOSE unwinds cleanly, folding nothing of ours", function()
		-- The main window reports itself open on the Crafting tab, which is
		-- what a leaked takeover would have produced; OnProfessionClose folds
		-- it only if the session auto-opened it, and a hand-off must not have.
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "crafting"
		beastTraining()
		Engine:OnEvent("CRAFT_SHOW")
		assert.is_true(Engine._sessionOpen)
		Engine:OnEvent("CRAFT_CLOSE")
		assert.is_false(Engine._sessionOpen)
		assert.equal(0, calls.close)
		ns.MainWindow.frame, ns.MainWindow.activeTab = nil, nil
	end)
end)

describe("CRAFT_SHOW in hands-off mode", function()
	it("does not summon Blizzard's window a second time for Beast Training", function()
		-- Hands-off never unregistered UIParent's handler, so the frame is
		-- already showing; re-dispatching the event would show it twice.
		ns.lib.db.profile.craftingHandsOff = true
		beastTraining()
		Engine:OnEvent("CRAFT_SHOW")
		assert.same({}, calls.uiparent)
		assert.same({}, calls.open)
	end)
end)
