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
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")
local wow = env.wow

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
	_G.GetNumTradeSkills        = function() return 0 end
	_G.GetTradeSkillInfo        = function() return nil end
	_G.C_Timer = { After = function(_, fn) fn() end, NewTimer = function() return { Cancel = function() end } end }
	_G.TSM_API = nil
	_G.TradeSkillFrame, _G.CraftFrame = nil, nil
end

setup(function()
	installGlobals()
	-- The real Compat.lua, for the trade-skill API checks the engine branches
	-- on; the namespace inherits a booted addon, as compat_spec does.
	ns = setmetatable({ lib = { OnEnable = function() end } }, { __index = env.boot() })
	wow.loadAddonFile("Compat.lua", "TOGProfessionMaster", ns)
	installGlobals()
	ns.isTBC, ns.isVanilla = true, false
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

	-- A client with neither the classic trade-skill API nor C_TradeSkillUI.
	it("never casts on a client with no trade-skill API at all", function()
		local casts = 0
		_G.CastSpellByName = function() casts = casts + 1 end
		_G.GetNumTradeSkills = nil
		assert.is_false(Engine:OpenProfession("Tailoring"))
		assert.equal(0, casts)
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

-- WoW Forever: no classic trade-skill globals, so the engine reads and crafts
-- through C_TradeSkillUI, and opens a profession with OpenTradeSkill rather
-- than CastSpellByName (blocked there even on a click, in game 2026-09-28).
-- Shapes from the forever tree's TradeSkillUIDocumentation.lua /
-- TradeSkillUITypesDocumentation.lua.
describe("WoW Forever (C_TradeSkillUI)", function()
	local saved, calls
	local SMITHING = 164   -- Blacksmithing's skill line

	before_each(function()
		saved = {
			GetProfessions = _G.GetProfessions, GetProfessionInfo = _G.GetProfessionInfo,
			C_TradeSkillUI = _G.C_TradeSkillUI,
			GetItemCount = C_Item and C_Item.GetItemCount,
		}
		calls = { open = {}, craft = {}, cast = 0 }
		-- Forever has none of these (absent from its source tree).
		_G.GetTradeSkillLine, _G.GetNumTradeSkills, _G.GetTradeSkillInfo = nil, nil, nil
		_G.CastSpellByName = function() calls.cast = calls.cast + 1 end
		_G.GetProfessions = function() return 1 end
		_G.GetProfessionInfo = function() return "Blacksmithing", nil, 66, 75, nil, nil, SMITHING end
		local recipes = {
			[2660] = { recipeID = 2660, name = "Rough Sharpening Stone", learned = true,
				relativeDifficulty = 3, categoryID = 10, icon = 1 },
			[2663] = { recipeID = 2663, name = "Copper Bracers", learned = true,
				relativeDifficulty = 0, categoryID = 20, icon = 2 },
			[9999] = { recipeID = 9999, name = "Unlearned", learned = false, categoryID = 20 },
		}
		_G.C_TradeSkillUI = {
			GetRecipeInfo = function(id) return recipes[id] end,
			GetAllRecipeIDs = function() return { 2660, 2663, 9999 } end,
			GetCategoryInfo = function(id) return { name = id == 10 and "Materials" or "Armor" } end,
			GetBaseProfessionInfo = function()
				return { professionID = SMITHING, professionName = "Blacksmithing",
					skillLevel = 66, maxSkillLevel = 75 }
			end,
			GetChildProfessionInfo = function() return { professionID = 0, professionName = "" } end,
			GetRecipeSchematic = function(id)
				assert.equal(2663, id)
				return { reagentSlotSchematics = {
					{ reagents = { { itemID = 2840 } }, quantityRequired = 8, required = true, dataSlotType = 1 },
					{ reagents = { { itemID = 9001 } }, quantityRequired = 1, required = false, dataSlotType = 2 },
				} }
			end,
			OpenTradeSkill = function(line) calls.open[#calls.open + 1] = line; return true end,
			CraftRecipe = function(id, n) calls.craft[#calls.craft + 1] = { id, n } end,
		}
		if _G.C_Item then _G.C_Item.GetItemCount = function(itemId) return itemId == 2840 and 20 or 0 end end
	end)

	after_each(function()
		_G.GetProfessions, _G.GetProfessionInfo = saved.GetProfessions, saved.GetProfessionInfo
		_G.C_TradeSkillUI = saved.C_TradeSkillUI
		if _G.C_Item then _G.C_Item.GetItemCount = saved.GetItemCount end
	end)

	it("takes the modern path only where the classic API is absent", function()
		assert.is_true(Engine:UsesModernAPI())
		installGlobals()   -- the classic trade-skill globals are back
		_G.GetNumTradeSkills = function() return 0 end
		_G.GetTradeSkillInfo = function() end
		assert.is_false(Engine:UsesModernAPI())
	end)

	it("opens a profession with OpenTradeSkill on its skill line, never a cast", function()
		assert.is_true(Engine:OpenProfession("Blacksmithing", "tab"))
		assert.same({ SMITHING }, calls.open)
		assert.equal(0, calls.cast)
		assert.is_true(Engine._tabDriven)
	end)

	it("drops the tab's claim when OpenTradeSkill opens nothing", function()
		_G.C_TradeSkillUI.OpenTradeSkill = function() return false end
		assert.is_false(Engine:OpenProfession("Blacksmithing", "tab"))
		assert.is_false(Engine._tabDriven)
		assert.is_false(Engine._forceTakeoverOnce)
	end)

	-- The diagnostics for the intermittent ADDON_ACTION_BLOCKED (2026-09-29).
	it("records each attempt with its trigger, the open profession and the result", function()
		Engine._openLog, Engine._openCount = {}, 0
		local during
		_G.C_TradeSkillUI.OpenTradeSkill = function() during = Engine._opening; return true end
		Engine:OpenProfession("Blacksmithing", "dropdown")
		local r = Engine._openLog[1]
		-- The block watcher pairs an ADDON_ACTION_BLOCKED with the attempt in flight.
		assert.equal(r, during)
		assert.equal("dropdown", r.how)
		assert.equal(SMITHING, r.skillLine)
		assert.equal(SMITHING, r.baseId)
		assert.equal("Blacksmithing", r.openNow)
		assert.is_true(r.first)
		assert.equal("true", r.result)
		Engine:OpenProfession("Blacksmithing", "tab")
		assert.is_false(Engine._openLog[2].first)
		-- Released after the call, so a later block is not pinned on it.
		assert.are_not.equal(during, Engine._opening)
	end)

	-- A switch lands on a list update once the new data source is built, not on
	-- TRADE_SKILL_SHOW (Blizzard_ProfessionsFrame.lua:138-161). The dropdown drew
	-- the old profession's tab on in game (2026-09-29) because this only
	-- refreshed the list.
	it("redraws the whole tab when a list update shows a different profession", function()
		local full, live = 0, 0
		local savedTab = ns.CraftingTab
		ns.CraftingTab = {
			OnSessionChanged = function() full = full + 1 end,
			OnLiveRefresh    = function() live = live + 1 end,
		}
		Engine._sessionOpen, Engine._drawnProf = true, "First Aid"
		Engine:OnEvent("TRADE_SKILL_LIST_UPDATE")
		assert.equal(1, full)
		assert.equal("Blacksmithing", Engine._drawnProf)
		-- Same profession again: the light refresh, as before.
		Engine:OnEvent("TRADE_SKILL_LIST_UPDATE")
		assert.equal(1, full)
		assert.equal(1, live)
		-- While the source is still changing, wait for the update that follows.
		_G.C_TradeSkillUI.IsDataSourceChanging = function() return true end
		Engine._drawnProf = "First Aid"
		Engine:OnEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
		assert.equal(1, full)
		ns.CraftingTab = savedTab
	end)

	-- In game 2026-09-29: "once i've opened it with TOGPM, i can't use the K key
	-- to open crafting".
	it("leaves Blizzard's window up when the player opens it, and drops the tab's claim", function()
		local w = newWindow()
		_G.ProfessionsFrame = w
		Engine:EnsureSuppressHook()
		Engine._sessionOpen, Engine._tabDriven, Engine._ownOpenAt = true, true, nil
		w._scripts.OnShow(w)
		assert.is_true(w:IsShown())
		assert.is_false(Engine._tabDriven)
		_G.ProfessionsFrame = nil
	end)

	-- A frame with the alpha/scale the cloak reads and writes.
	local function professionsWindow()
		local w = newWindow()
		w._alpha, w._scale = 1, 1
		w.GetAlpha = function(self) return self._alpha end
		w.SetAlpha = function(self, a) self._alpha = a end
		w.GetScale = function(self) return self._scale end
		w.SetScale = function(self, s) self._scale = s end
		-- One child with mouse input, the way its buttons have it.
		local child = { _mouse = true }
		function child:IsMouseEnabled() return self._mouse end
		function child:EnableMouse(on) self._mouse = on end
		w._mouse, w._child = false, child
		w.IsMouseEnabled = function(self) return self._mouse end
		w.EnableMouse = function(self, on) self._mouse = on end
		w.GetChildren = function(self) return self._child end
		return w
	end

	local bound
	local function stubBindings()
		bound = {}
		_G.GetBindingKey = function(action) if action == "TOGGLEPROFESSIONBOOK" then return "K" end end
		_G.SetOverrideBindingClick = function(_owner, _prio, key, button) bound[key] = button end
		_G.ClearOverrideBindings = function() bound = {} end
		_G.InCombatLockdown = function() return false end
	end

	-- In game 2026-09-29 every dropdown pick ended on the LAST tab's profession:
	-- a hidden ProfessionsFrame re-shown by our open sets off its tabs' casts.
	it("cloaks Blizzard's window when the tab's own open shows it, never hides it", function()
		stubBindings()
		local w = professionsWindow()
		_G.ProfessionsFrame = w
		Engine:EnsureSuppressHook()
		Engine._sessionOpen = true
		Engine:OpenProfession("Blacksmithing", "dropdown")   -- claims the session, stamps the time
		w._scripts.OnShow(w)
		assert.is_true(w:IsShown())
		assert.equal(0, w._alpha)
		assert.is_true(Engine:IsCloaked())
		assert.is_true(Engine._tabDriven)
		-- K now reveals it rather than toggling the shown frame closed.
		assert.equal("TOGPMShowProfessionsButton", bound.K)
		Engine:_UncloakProfessionsFrame()
		_G.ProfessionsFrame = nil
	end)

	it("reveals the cloaked window for K or the WoW UI button, and leaves ours open", function()
		stubBindings()
		local w = professionsWindow()
		_G.ProfessionsFrame = w
		Engine._sessionOpen, Engine._tabDriven = true, true
		Engine:HideForeignWindows()
		assert.is_true(Engine:IsCloaked())
		-- Invisible and click-through; its size is never touched (a 1% scale
		-- left the revealed window far narrower than Blizzard's, in game).
		assert.equal(0, w._alpha)
		assert.is_false(w._child._mouse)
		assert.equal(1, w._scale)
		local closed = 0
		local savedMW = ns.MainWindow
		ns.MainWindow = { frame = {}, activeTab = "crafting", Close = function() closed = closed + 1 end }
		Engine._autoOpened = true
		-- The "back to TOGPM" button parents a real button to the frame; this
		-- fake frame cannot host one, and the button is not what is under test.
		local savedToggle = Engine.ShowToggleButton
		local toggled
		Engine.ShowToggleButton = function(_, frame) toggled = frame end
		Engine:ShowDefaultUI()
		Engine.ShowToggleButton = savedToggle
		assert.equal(w, toggled)
		assert.equal(1, w._alpha)
		assert.equal(1, w._scale)
		assert.is_true(w._child._mouse)   -- each frame gets back what it had
		assert.is_false(w._mouse)
		assert.is_false(Engine:IsCloaked())
		assert.equal(0, closed)
		assert.same({}, bound)
		ns.MainWindow = savedMW
		_G.ProfessionsFrame = nil
	end)

	it("closes the cloaked window with ours, through Blizzard's own hide", function()
		stubBindings()
		local w = professionsWindow()
		local onHide = 0
		w:SetScript("OnHide", function() onHide = onHide + 1 end)
		_G.ProfessionsFrame = w
		Engine._sessionOpen, Engine._tabDriven = true, true
		Engine:HideForeignWindows()
		Engine:OnMainWindowClosed()
		assert.is_false(w:IsShown())
		assert.equal(1, onHide)   -- its OnHide ends the session, as closing it by hand does
		assert.is_false(Engine:IsCloaked())
		_G.ProfessionsFrame = nil
	end)

	it("asks twice when the first open re-showed a hidden window and did not stick", function()
		local w = professionsWindow()
		w._shown = false
		_G.ProfessionsFrame = w
		local asked, base = {}, SMITHING
		_G.C_TradeSkillUI.GetBaseProfessionInfo = function()
			return { professionID = base, professionName = "x" }
		end
		_G.C_TradeSkillUI.OpenTradeSkill = function(line)
			asked[#asked + 1] = line
			if #asked == 1 then w._shown = true; base = 356 else base = line end   -- the cascade left Fishing
			return true
		end
		Engine._openLog = {}
		assert.is_true(Engine:OpenProfession("Blacksmithing", "dropdown"))
		assert.same({ SMITHING, SMITHING }, asked)
		assert.is_true(Engine._openLog[1].retried)
		_G.ProfessionsFrame = nil
	end)

	it("records an OpenTradeSkill that raises instead of letting it escape", function()
		Engine._openLog = {}
		local during
		_G.C_TradeSkillUI.OpenTradeSkill = function() during = Engine._opening; error("boom") end
		assert.is_false(Engine:OpenProfession("Blacksmithing", "tab"))
		assert.truthy(Engine._openLog[1].result:find("error", 1, true))
		assert.equal(Engine._openLog[1], during)
		assert.are_not.equal(during, Engine._opening)
	end)

	it("reads the open profession from the base info when the child id is 0", function()
		Engine._sessionOpen = true
		local info = Engine:GetOpenInfo()
		assert.equal("Blacksmithing", info.name)
		assert.equal(66, info.rank)
		assert.equal(75, info.max)
		assert.is_false(info.isCraftWindow)
	end)

	it("lists learned recipes under their category, index = recipe id", function()
		Engine._sessionOpen = true
		local list = Engine:GetRecipeList()
		assert.equal(4, #list)
		assert.same({ kind = "header", name = "Materials" }, list[1])
		assert.equal(2660, list[2].index)
		assert.equal("trivial", list[2].difficulty)
		assert.same({ kind = "header", name = "Armor" }, list[3])
		assert.equal(2663, list[4].recipeId)
		assert.equal("optimal", list[4].difficulty)
		assert.equal(2, list[4].num)   -- 20 copper bars / 8, from the reagents
	end)

	it("reads only the basic reagent slots, with bag counts", function()
		local r = Engine:GetReagents(2663)
		assert.equal(1, #r)
		assert.equal(2840, r[1].itemId)
		assert.equal(8, r[1].need)
		assert.equal(20, r[1].have)
	end)

	it("crafts with CraftRecipe by recipe id", function()
		Engine._sessionOpen, Engine._isCraftWindow = true, false
		Engine:Craft(2663, 2663, 3)
		assert.same({ { 2663, 3 } }, calls.craft)
	end)
end)
