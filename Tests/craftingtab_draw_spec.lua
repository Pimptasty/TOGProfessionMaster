-- GUI/CraftingTab.lua with a live trade-skill session.
--
-- The Crafting tab is the largest file in the addon and was the least covered,
-- for one reason: on Classic there is exactly one way to get a trade-skill
-- session — cast the profession — so none of it runs without one. With the
-- session faked, the whole tab becomes reachable: the recipe list, the detail
-- panel with its reagent rows, the queue panel, and selecting a recipe.
--
-- Smoke by design. What these catch is the class that actually happens in this
-- file — a nil reagent, a renamed field, an anchor to a frame that no longer
-- exists — and they catch it here rather than in front of a player who has
-- just opened their profession.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, CT

local RECIPES = {
	{ name = "Alchemy",             difficulty = "header", available = 0 },
	{ name = "Healing Potion",      available = 5, reagents = {
		{ name = "Peacebloom", need = 1, have = 20 },
		{ name = "Silverleaf", need = 1, have = 3  },
	} },
	{ name = "Elixir of Fortitude", available = 0, reagents = {
		{ name = "Goldthorn",  need = 2, have = 0  },
	} },
}

setup(function()
	ns = env.initDb()
	CT = env.loadCraftingTab()
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	ns.Print = function() end
	env.tradeSkillSession("Alchemy", RECIPES)
	-- Guard the fixture itself: if the engine does not believe a session is
	-- open, the tab renders its "open a profession" state and every test below
	-- passes while covering nothing. That is how the first version of this file
	-- moved coverage by 2%.
	assert.is_true(ns.CraftingEngine:IsOpen())
	assert.is_truthy(ns.CraftingEngine:GetOpenInfo())
	assert.is_true(#ns.CraftingEngine:GetKnownProfessions() > 0)
end)

-- The addon's own Print goes back (not whatever an earlier file left in
-- ns.Print), so a later spec file prints through the real one.
after_each(function()
	ns.Print = env.addonPrint
end)

describe("the Crafting tab with a profession open", function()
	it("builds the whole tab", function()
		local container = env.drawTab(CT)
		assert.is_true(env.countWidgets(container) > 0)
	end)

	it("builds again on a redraw, against the widgets it just released", function()
		local container = env.drawTab(CT)
		assert.has_no.errors(function() CT:Draw(container) end)
	end)

	it("fills its recipe list from the open session", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:FillList() end)
	end)

	it("survives a session with nothing in it", function()
		-- Casting a profession you have no recipes for, and the empty state
		-- most likely to hit an unguarded index.
		env.tradeSkillSession("Alchemy", {})
		assert.has_no.errors(function() env.drawTab(CT) end)
	end)

	it("survives no session at all", function()
		-- The tab can be opened from the main window without any profession
		-- being cast, which is the state a first-time user lands in.
		_G.GetTradeSkillLine = function() return nil end
		_G.GetNumTradeSkills = function() return 0 end
		assert.has_no.errors(function() env.drawTab(CT) end)
	end)
end)

describe("selecting a recipe", function()
	it("shows the detail panel for a craftable recipe", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:RequestSelect(171, 2) end)
		assert.has_no.errors(function() CT:RefreshDetail() end)
	end)

	it("shows one a reagent is missing for", function()
		-- available = 0 with an unmet reagent: the branch that greys the Craft
		-- button and colours the shortfall.
		env.drawTab(CT)
		CT:RequestSelect(171, 3)
		assert.has_no.errors(function() CT:RefreshDetail() end)
	end)

	it("refreshes the detail panel repeatedly", function()
		-- It re-renders on every bag change, so it runs constantly while a
		-- player crafts.
		env.drawTab(CT)
		CT:RequestSelect(171, 2)
		assert.has_no.errors(function()
			for _ = 1, 3 do CT:RefreshDetail() end
		end)
	end)

	it("changes the quantity without rebuilding the tab", function()
		env.drawTab(CT)
		CT:RequestSelect(171, 2)
		assert.has_no.errors(function()
			CT:SetQty(5)
			CT:RefreshDetail()
		end)
	end)
end)

-- The reagents under a selected recipe are a LibAceGUIWidgets RowList
-- (CT._dpReagList) since v1.2.0; these read what its columns draw.
describe("the detail panel's reagent list", function()
	local function pick(index)
		env.drawTab(CT)
		CT._selIndex = index
		CT:RefreshDetail()
		assert.equal(index, CT._selIndex)
	end

	local function cell(key, e)
		for _, col in ipairs(CT._dpReagList.columns) do
			if col.key == key then return col.format(nil, e) end
		end
		error("no column " .. key)
	end

	local function column(key)
		for _, col in ipairs(CT._dpReagList.columns) do
			if col.key == key then return col end
		end
	end

	it("draws one row per reagent, the needed count before the name", function()
		pick(2)
		local data = CT._dpReagList.data
		assert.equal(2, #data)
		assert.is_truthy(cell("name", data[1]):find("1x ", 1, true))
		assert.is_truthy(cell("name", data[1]):find("Peacebloom", 1, true))
		assert.is_truthy(cell("name", data[2]):find("Silverleaf", 1, true))
	end)

	it("shows bags / bank, green when they cover the need", function()
		pick(2)
		local cnt = cell("cnt", CT._dpReagList.data[1])
		assert.is_truthy(cnt:find("20/0", 1, true))
		assert.is_truthy(cnt:find("ff40c040", 1, true))
		assert.is_false(CT._dpMiss:IsShown())
	end)

	it("shows a short reagent in red and flags Missing Materials", function()
		pick(3)
		local cnt = cell("cnt", CT._dpReagList.data[1])
		assert.is_truthy(cnt:find("0/0", 1, true))
		assert.is_truthy(cnt:find("ffff4040", 1, true))
		assert.is_true(CT._dpMiss:IsShown())
	end)

	it("replaces the rows when another recipe is picked", function()
		pick(2)
		assert.equal(2, #CT._dpReagList.data)
		CT._selIndex = 3
		CT:RefreshDetail()
		assert.equal(1, #CT._dpReagList.data)
		assert.is_truthy(cell("name", CT._dpReagList.data[1]):find("Goldthorn", 1, true))
	end)

	it("sizes itself to its rows, so the panel can shrink to fit", function()
		pick(2)
		local two = CT._dpReagHost:GetHeight()
		CT._selIndex = 3
		CT:RefreshDetail()
		local one = CT._dpReagHost:GetHeight()
		assert.is_true(two > one, ("two rows %s, one row %s"):format(two, one))
	end)

	it("hides the list when nothing is selected", function()
		pick(2)
		CT._selIndex = nil
		CT:RefreshDetail()
		assert.is_false(CT._dpReagHost:IsShown())
	end)

	it("heads its name and cost columns, each with its explanation", function()
		pick(2)
		local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
		assert.equal(L["CraftReagents"], column("name").header)
		assert.equal(L["CraftReagentsDesc"], column("name").headerTip)
		assert.equal(L["CraftColCostHdr"], column("cost").header)
		assert.equal(L["CraftColCostHdrDesc"], column("cost").headerTip)
	end)
end)

-- In game 2026-09-26: closing TOGPM in combat raised ADDON_ACTION_BLOCKED
-- "Frame:Hide()" from AceGUIContainer-Frame. The secure Craft button made every
-- ancestor protected, and its ancestors were AceGUI's pooled window. It now lives
-- on a UIParent holder and only follows the panel.
describe("the secure Craft button", function()
	local realLockdown

	before_each(function() realLockdown = _G.InCombatLockdown end)
	after_each(function()
		_G.InCombatLockdown = realLockdown
		ns.MainWindow.frame, ns.MainWindow.activeTab = nil, nil
		ns.CraftingEngine._isCraftWindow = false
	end)

	-- The offline window is never laid out, so the panel has no rect until one
	-- is given; in game AnchorAll gives it one. Place it, then let the watcher
	-- notice, exactly as it would when the layout lands after RefreshDetail.
	-- The button shows only while TOGPM's window is open on this tab, so the
	-- window's state is set to that. Since 2026-10-18 it is Enchanting's alone
	-- (trade skills craft from a plain button), so the session is the Craft
	-- window; the fixture wires the Craft API to the same recipes.
	local function selectCraftable()
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "crafting"
		ns.CraftingEngine._isCraftWindow = true
		env.drawTab(CT)
		CT._selIndex = 2
		CT:RefreshDetail()
		assert.is_truthy(CT._dpSel)
		local panel = CT._detailPanel
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 100, -100)
		panel:SetSize(400, 120)
		CT._craftBtnWatcher:GetScript("OnUpdate")(CT._craftBtnWatcher, 0)
	end

	it("is not inside the detail panel or the AceGUI window", function()
		-- The panel (and the holder with it) is built once and cached; this
		-- test's UIParent is a fresh one from installFrames, so build anew.
		CT._detailPanel = nil
		selectCraftable()
		local btn, panel = CT._dpCraft, CT._detailPanel
		local chain, f = {}, btn:GetParent()
		while f do chain[#chain + 1] = f; f = f:GetParent() end
		for _, ancestor in ipairs(chain) do
			assert.are_not.equal(panel, ancestor)
		end
		assert.equal(CT._dpCraftHolder, btn:GetParent())
		assert.equal(_G.UIParent, CT._dpCraftHolder:GetParent())
	end)

	it("is anchored to nothing but its holder -- never to the panel", function()
		-- Protection also carries to the frames a protected frame is anchored to
		-- (warcraft.wiki.gg, via Peer Review 2026-09-26).
		selectCraftable()
		local btn = CT._dpCraft
		assert.is_true(btn:GetNumPoints() >= 1)
		for i = 1, btn:GetNumPoints() do
			local _, relativeTo = btn:GetPoint(i)
			assert.equal(CT._dpCraftHolder, relativeTo)
		end
	end)

	it("lands at the panel's top-right, where it was when it was the panel's child", function()
		selectCraftable()
		local btn, panel = CT._dpCraft, CT._detailPanel
		assert.is_near(panel:GetRight() - 12, btn:GetRight(), 0.01)
		assert.is_near(panel:GetTop() - 6, btn:GetTop(), 0.01)
	end)

	it("follows the panel when the window moves", function()
		selectCraftable()
		local btn, panel = CT._dpCraft, CT._detailPanel
		local p, rel, rp, x, y = panel:GetPoint(1)
		panel:ClearAllPoints()
		panel:SetPoint(p, rel, rp, (x or 0) + 50, (y or 0) - 30)
		CT._craftBtnWatcher:GetScript("OnUpdate")(CT._craftBtnWatcher, 0)
		assert.is_near(panel:GetRight() - 12, btn:GetRight(), 0.01)
		assert.is_near(panel:GetTop() - 6, btn:GetTop(), 0.01)
		-- A trade skill's Craft button sits 34 below the panel's top and, being
		-- the panel's child, moved with it.
		ns.CraftingEngine._isCraftWindow = false
		CT:RefreshDetail()
		assert.is_near(panel:GetTop() - 34, CT._dpCraftPlain:GetTop(), 0.01)
	end)

	-- Discord 2026-09-29: the Enchant button sat dimmed under the panel and took
	-- no clicks. The window is Toplevel, so a click Raises it above the button,
	-- which is not its descendant; the watcher only followed the panel's rect.
	it("stays above the panel when the window is raised", function()
		selectCraftable()
		local btn, panel = CT._dpCraft, CT._detailPanel
		assert.is_true(btn:GetFrameLevel() > panel:GetFrameLevel())
		panel:SetFrameLevel(btn:GetFrameLevel() + 5)
		CT._craftBtnWatcher:GetScript("OnUpdate")(CT._craftBtnWatcher, 0)
		assert.is_true(btn:GetFrameLevel() > panel:GetFrameLevel(),
			("button %d, panel %d"):format(btn:GetFrameLevel(), panel:GetFrameLevel()))
	end)

	it("shows with a recipe selected and hides with none", function()
		selectCraftable()
		assert.is_true(CT._dpCraft:IsShown())
		CT._selIndex = nil
		CT:RefreshDetail()
		assert.is_false(CT._dpCraft:IsShown())
	end)

	it("hides when the panel hides, since it is not the panel's child", function()
		selectCraftable()
		CT._detailPanel:Hide()
		assert.is_false(CT._dpCraft:IsShown())
	end)

	-- In game 2026-10-18: the button stayed on screen after the window closed.
	it("hides when TOGPM's window closes, whatever the panel reports", function()
		selectCraftable()
		assert.is_true(CT._dpCraft:IsShown())
		ns.MainWindow.frame = nil
		CT:SyncCraftButton()
		assert.is_false(CT._dpCraft:IsShown())
	end)

	it("hides when the window switches to another tab", function()
		selectCraftable()
		ns.MainWindow.activeTab = "browser"
		CT:SyncCraftButton()
		assert.is_false(CT._dpCraft:IsShown())
	end)

	-- In game 2026-10-18: the button drew behind the window. The panel is first
	-- shown while its host is still under UIParent, then moved into the window's
	-- strata; a move that kept the level never re-placed the button.
	it("follows the panel into a new strata at the same level", function()
		selectCraftable()
		-- The holder's strata is what is set; the button inherits it in game.
		local holder, panel = CT._dpCraftHolder, CT._detailPanel
		panel:SetFrameStrata("MEDIUM")
		CT._craftBtnWatcher:GetScript("OnUpdate")(CT._craftBtnWatcher, 0)
		local level = panel:GetFrameLevel()
		panel:SetFrameStrata("FULLSCREEN_DIALOG")
		panel:SetFrameLevel(level)
		CT._craftBtnWatcher:GetScript("OnUpdate")(CT._craftBtnWatcher, 0)
		assert.equal("FULLSCREEN_DIALOG", holder:GetFrameStrata())
	end)

	-- Peer Review, thread 435f7185: a Raise that lifts the window without moving
	-- the panel's level must still re-place the button above the window.
	it("re-places above the window when only the window's level changes", function()
		selectCraftable()
		local win = _G.CreateFrame("Frame", nil, _G.UIParent)
		win:SetFrameStrata("FULLSCREEN_DIALOG")
		win:SetFrameLevel(1)
		ns.MainWindow.frame = { frame = win }
		CT._craftBtnWatcher:GetScript("OnUpdate")(CT._craftBtnWatcher, 0)
		local btn = CT._dpCraft
		win:SetFrameLevel(btn:GetFrameLevel() + 50)
		CT._craftBtnWatcher:GetScript("OnUpdate")(CT._craftBtnWatcher, 0)
		assert.is_true(btn:GetFrameLevel() > win:GetFrameLevel(),
			("button %d, window %d"):format(btn:GetFrameLevel(), win:GetFrameLevel()))
	end)

	-- Peer Review F2, thread 98ed0622: it only ever casts its macro, so it has
	-- no insecure PreClick crafting beside it, and takes the left button both
	-- ways for the ActionButtonUseKeyDown gate.
	it("casts the enchant's macro with no PreClick of its own", function()
		selectCraftable()
		local btn = CT._dpCraft
		assert.is_nil(btn:GetScript("PreClick"))
		assert.equal("macro", btn:GetAttribute("type"))
		assert.is_truthy(btn:GetAttribute("macrotext"):find("^/cast "))
	end)

	it("is not shown or hidden by TOGPM during combat", function()
		selectCraftable()
		_G.InCombatLockdown = function() return true end
		CT._detailPanel:Hide()
		CT._selIndex = nil
		CT:RefreshDetail()
		assert.is_true(CT._dpCraft:IsShown())   -- untouched; the state driver owns combat
	end)
end)

-- In game 2026-10-18 the secure button showed greyed and took no clicks for a
-- trade skill while reporting itself enabled and topmost. Trade skills now craft
-- from a plain button in the panel, built like Craft Max (which worked).
describe("the trade-skill Craft button", function()
	after_each(function()
		ns.MainWindow.frame, ns.MainWindow.activeTab = nil, nil
		ns.CraftingEngine._isCraftWindow = false
	end)

	local function select(index)
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "crafting"
		env.drawTab(CT)
		CT._selIndex = index
		CT:RefreshDetail()
		local panel = CT._detailPanel
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 100, -100)
		panel:SetSize(400, 120)
		CT._craftBtnWatcher:GetScript("OnUpdate")(CT._craftBtnWatcher, 0)
	end

	it("is a child of the panel, not a secure frame", function()
		select(2)
		assert.equal(CT._detailPanel, CT._dpCraftPlain:GetParent())
	end)

	it("shows for a trade skill and the secure button does not", function()
		select(2)
		assert.is_true(CT._dpCraftPlain:IsShown())
		assert.is_truthy(CT._dpCraft)   -- built, so the next line is not passing on nil
		assert.is_false(CT._dpCraft:IsShown())
	end)

	it("crafts the selected recipe at the chosen quantity", function()
		local crafted = env.tradeSkillSession("Alchemy", RECIPES)
		select(2)
		CT._qty = 3
		CT._dpCraftPlain:GetScript("OnClick")(CT._dpCraftPlain, "LeftButton")
		assert.equal(1, #crafted)
		assert.equal(2, crafted[1].index)
		assert.equal(3, crafted[1].count)
	end)

	it("is disabled when nothing can be made", function()
		select(3)
		assert.is_false(CT._dpCraftPlain:IsEnabled())
	end)

	it("hides with no recipe selected", function()
		select(2)
		CT._selIndex = nil
		CT:RefreshDetail()
		assert.is_false(CT._dpCraftPlain:IsShown())
	end)

	it("hides for Enchanting, where the secure button shows instead", function()
		ns.CraftingEngine._isCraftWindow = true
		select(2)
		assert.is_false(CT._dpCraftPlain:IsShown())
		assert.is_true(CT._dpCraft:IsShown())
	end)

	-- Peer Review N1, thread 98ed0622: an enchant with no name cannot be /cast,
	-- and showed no button at all. The plain button takes it, labelled Enchant
	-- and at the top of the column; Engine:Craft opens Blizzard's Craft window.
	it("takes an enchant with no name to cast, instead of showing nothing", function()
		local Engine = ns.CraftingEngine
		local realList, realCraft = Engine.GetRecipeList, Engine.Craft
		Engine.GetRecipeList = function(self_)
			local out = {}
			for i, e in ipairs(realList(self_)) do
				local c = {}
				for k, v in pairs(e) do c[k] = v end
				if c.index == 2 then c.name = "" end
				out[i] = c
			end
			return out
		end
		local calls = {}
		Engine.Craft = function(_, recipeId, index, qty) calls[#calls + 1] = { recipeId, index, qty } end
		Engine._isCraftWindow = true
		local ok, err = pcall(function()
			select(2)
			assert.is_false(CT._dpCraft:IsShown())
			assert.is_true(CT._dpCraftPlain:IsShown())
			local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
			assert.equal(L["CraftEnchantButton"], CT._dpCraftPlain:GetText())
			assert.is_near(CT._detailPanel:GetTop() - 6, CT._dpCraftPlain:GetTop(), 0.01)
			CT._dpCraftPlain:GetScript("OnClick")(CT._dpCraftPlain, "LeftButton")
			assert.equal(1, #calls)
			assert.equal(2, calls[1][2])
		end)
		Engine.GetRecipeList, Engine.Craft = realList, realCraft
		assert(ok, err)
	end)

	it("goes back to Craft, 34 below the top, for a trade skill after an enchant", function()
		ns.CraftingEngine._isCraftWindow = true
		select(2)
		ns.CraftingEngine._isCraftWindow = false
		CT:RefreshDetail()
		local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
		assert.is_true(CT._dpCraftPlain:IsShown())
		assert.equal(L["CraftButton"], CT._dpCraftPlain:GetText())
		assert.is_near(CT._detailPanel:GetTop() - 34, CT._dpCraftPlain:GetTop(), 0.01)
	end)
end)

-- Peer Review N3, thread 98ed0622: the secure holder hides for all of combat,
-- so the plain Craft and Craft Max buttons must not craft then either.
describe("the plain craft buttons in combat", function()
	-- Everything an example here stubs is put back in one place, so an
	-- assertion that fails mid-example cannot leak a stub into later files
	-- (Peer Review F2, thread f96e17a7).
	local realLockdown, realCan, realCraftWindow, realCraft
	before_each(function()
		realLockdown = _G.InCombatLockdown
		realCan = ns.CraftQueue.CanCraftNext
		realCraftWindow = ns.CraftingEngine._isCraftWindow
		realCraft = CT._dpCraft
	end)
	after_each(function()
		_G.InCombatLockdown = realLockdown
		ns.CraftQueue.CanCraftNext = realCan
		ns.CraftingEngine._isCraftWindow = realCraftWindow
		-- An example that rebuilds the Enchant button leaves a second one on
		-- the holder; hide it and give later examples the original back
		-- (Peer Review F1, thread f96e17a7).
		if CT._dpCraft and CT._dpCraft ~= realCraft then CT._dpCraft:Hide() end
		CT._dpCraft = realCraft
		ns.MainWindow.frame, ns.MainWindow.activeTab = nil, nil
	end)

	local function selectCraftable()
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "crafting"
		env.drawTab(CT)
		CT._selIndex = 2
		CT:RefreshDetail()
	end

	-- The regen frame is made at load, before each test's installFrames, so the
	-- event is delivered by calling its script, as the watcher's specs do.
	local function fire(event)
		CT._regenFrame:GetScript("OnEvent")(CT._regenFrame, event)
	end

	it("listens for combat starting and ending", function()
		assert.is_true(CT._regenFrame:IsEventRegistered("PLAYER_REGEN_DISABLED"))
		assert.is_true(CT._regenFrame:IsEventRegistered("PLAYER_REGEN_ENABLED"))
	end)

	it("are disabled when combat starts and enabled when it ends", function()
		selectCraftable()
		assert.is_true(CT._dpCraftPlain:IsEnabled())
		fire("PLAYER_REGEN_DISABLED")
		assert.is_false(CT._dpCraftPlain:IsEnabled())
		assert.is_false(CT._dpCraftMax:IsEnabled())
		fire("PLAYER_REGEN_ENABLED")
		assert.is_true(CT._dpCraftPlain:IsEnabled())
		assert.is_true(CT._dpCraftMax:IsEnabled())
	end)

	it("stay disabled when the panel refreshes mid-combat", function()
		selectCraftable()
		_G.InCombatLockdown = function() return true end
		CT:RefreshDetail()
		assert.is_false(CT._dpCraftPlain:IsEnabled())
		assert.is_false(CT._dpCraftMax:IsEnabled())
	end)

	it("stay disabled out of combat when nothing can be made", function()
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "crafting"
		env.drawTab(CT)
		CT._selIndex = 3
		CT:RefreshDetail()
		fire("PLAYER_REGEN_ENABLED")
		assert.is_false(CT._dpCraftPlain:IsEnabled())
		assert.is_false(CT._dpCraftMax:IsEnabled())
	end)

	-- Peer Review NEW-1, thread 98ed0622: the queue's Craft Next and Craft All
	-- reach the same Engine:Craft, so they follow the same rule.
	it("include the queue's Craft Next and Craft All", function()
		ns.CraftQueue.CanCraftNext = function() return true end
		selectCraftable()
		CT:RefreshQueue()
		assert.is_truthy(CT._craftNextBtn)
		assert.is_truthy(CT._craftAllBtn)
		assert.is_true(CT._craftNextBtn:IsEnabled())
		assert.is_true(CT._craftAllBtn:IsEnabled())
		fire("PLAYER_REGEN_DISABLED")
		assert.is_false(CT._craftNextBtn:IsEnabled())
		assert.is_false(CT._craftAllBtn:IsEnabled())
		_G.InCombatLockdown = function() return true end
		CT:RefreshQueue()
		assert.is_false(CT._craftNextBtn:IsEnabled())
		_G.InCombatLockdown = realLockdown
		fire("PLAYER_REGEN_ENABLED")
		assert.is_true(CT._craftNextBtn:IsEnabled())
		assert.is_true(CT._craftAllBtn:IsEnabled())
	end)

	it("leave the queue buttons disabled when the queue has nothing to make", function()
		ns.CraftQueue.CanCraftNext = function() return false end
		selectCraftable()
		CT:RefreshQueue()
		assert.is_truthy(CT._craftNextBtn)
		assert.is_false(CT._craftNextBtn:IsEnabled())
		assert.is_false(CT._craftAllBtn:IsEnabled())
	end)

	-- Peer Review F1, thread 0b7ff9c0, pinning the guard from thread 578fcb89: a selection gone by the time combat ends
	-- sends the regen handler through RefreshDetail's no-selection branch, which
	-- skipped the handler's own sync and left the queue buttons greyed.
	it("bring the queue buttons back after combat when the selection is gone", function()
		ns.CraftQueue.CanCraftNext = function() return true end
		local ok, err = pcall(function()
			selectCraftable()
			CT:RefreshQueue()
			fire("PLAYER_REGEN_DISABLED")
			assert.is_false(CT._craftNextBtn:IsEnabled())
			CT._selIndex = 42
			assert.is_truthy(CT._dpSel)
			fire("PLAYER_REGEN_ENABLED")
			assert.is_nil(CT._dpSel)
			assert.is_true(CT._craftNextBtn:IsEnabled())
			assert.is_true(CT._craftAllBtn:IsEnabled())
		end)
		assert(ok, err)
	end)

	-- Peer Review NEW-2, thread 98ed0622: in combat RefreshDetail moves the
	-- selection but cannot touch the secure button, so leaving combat must give
	-- the Enchant button the new enchant's /cast and enabled state.
	it("give the Enchant button the enchant picked mid-combat once combat ends", function()
		ns.CraftingEngine._isCraftWindow = true
		selectCraftable()
		assert.equal("/cast Healing Potion", CT._dpCraft:GetAttribute("macrotext"))
		_G.InCombatLockdown = function() return true end
		CT._selIndex = 3
		CT:RefreshDetail()
		assert.equal("/cast Healing Potion", CT._dpCraft:GetAttribute("macrotext"))
		_G.InCombatLockdown = realLockdown
		fire("PLAYER_REGEN_ENABLED")
		assert.equal("/cast Elixir of Fortitude", CT._dpCraft:GetAttribute("macrotext"))
		assert.is_false(CT._dpCraft:IsEnabled())
	end)

	-- The library's factory refuses in combat, so a panel drawn mid-fight has no
	-- Enchant button; the first sync after combat builds it and gives it the
	-- selected enchant's /cast.
	it("build the Enchant button after a panel drawn in combat", function()
		ns.CraftingEngine._isCraftWindow = true
		_G.InCombatLockdown = function() return true end
		CT._dpCraft = nil
		selectCraftable()
		assert.is_nil(CT._dpCraft)
		_G.InCombatLockdown = realLockdown
		CT:SyncCraftButton()
		assert.is_truthy(CT._dpCraft)
		assert.equal("/cast Healing Potion", CT._dpCraft:GetAttribute("macrotext"))
	end)
end)

describe("the queue panel", function()
	it("renders an empty queue", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:RefreshQueue() end)
	end)

	it("renders a queue with entries in it", function()
		env.drawTab(CT)
		-- Peer Review F5, thread 0b7ff9c0: this used to pass Add a table inside a
		-- pcall, so the queue stayed empty and the example drew nothing.
		ns.CraftQueue:Clear()
		ns.CraftQueue:Add(171, 2, 3)
		CT:RefreshQueue()
		assert.equal(1, #CT._queueList.data)
		assert.equal(3, CT._queueList.data[1].qty)
	end)

	it("reacts to the queue changing", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:OnQueueChanged() end)
	end)

	it("reacts to the session changing", function()
		-- Switching profession mid-session: the path that used to leave the
		-- previous profession's rows on screen.
		env.drawTab(CT)
		assert.has_no.errors(function() CT:OnSessionChanged() end)
	end)

	it("reacts to a live refresh", function()
		env.drawTab(CT)
		assert.has_no.errors(function() CT:OnLiveRefresh() end)
	end)
end)
