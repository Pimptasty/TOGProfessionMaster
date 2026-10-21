-- GUI/CraftingTab.lua: every control a player touches, driven through the
-- handler the control was given.
--
-- craftingtab_draw_spec.lua builds the tab and the Craft buttons; this file
-- presses everything else -- the profession dropdown, search and the have-
-- materials box, the recipe list's sort and clicks, the detail panel's buttons,
-- tooltips and reagent actions, the cost line, and the queue panel -- and
-- asserts what each one changed. The recipes carry item links here, so they
-- have recipe ids and can be queued.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, CT, L

local RECIPES = {
	{ name = "Alchemy",             difficulty = "header", available = 0 },
	{ name = "Healing Potion",      available = 5, link = "|cffffffff|Hitem:929::::::::|h[Healing Potion]|h|r",
	  reagents = {
		{ name = "Peacebloom", need = 1, have = 20, link = "|cffffffff|Hitem:2447::::::::|h[Peacebloom]|h|r" },
		{ name = "Silverleaf", need = 1, have = 3 },
	} },
	{ name = "Elixir of Fortitude", available = 0, link = "|cffffffff|Hitem:2458::::::::|h[Elixir of Fortitude]|h|r",
	  reagents = {
		{ name = "Goldthorn",  need = 2, have = 0, link = "|cffffffff|Hitem:3821::::::::|h[Goldthorn]|h|r" },
	} },
}

-- Replaced fields, put back after every test whatever the test did.
local saved = {}
local function stub(tbl, key, value)
	saved[#saved + 1] = { tbl, key, tbl[key] }
	tbl[key] = value
end

setup(function()
	ns = env.initDb()
	CT = env.loadCraftingTab()
	L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
end)

local printed

before_each(function()
	env.installFrames()
	env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	printed = {}
	ns.Print = function(_, msg) printed[#printed + 1] = msg end
	env.tradeSkillSession("Alchemy", RECIPES)
	CT._search, CT._haveOnly, CT._sortCol, CT._sortAsc = "", false, nil, true
	CT._selIndex, CT._selId, CT._qty = nil, nil, 1
	CT._pendingSelect, CT._pendingNotified, CT._autoOpenOnUserNav = nil, nil, nil
	ns.CraftQueue:Clear()
	assert.is_truthy(ns.CraftingEngine:GetOpenInfo())
end)

after_each(function()
	for i = #saved, 1, -1 do
		local s = saved[i]
		s[1][s[2]] = s[3]
	end
	saved = {}
	-- The addon's own Print, not whatever an earlier spec file left in ns.Print.
	ns.Print = env.addonPrint
	ns.MainWindow.frame, ns.MainWindow.activeTab, ns.MainWindow.tabs = nil, nil, nil
end)

local function profId() return ns.CraftingEngine:GetOpenInfo().profId end

local function recipeNames()
	local out = {}
	for _, e in ipairs(CT._rows) do
		if e.kind == "recipe" then out[#out + 1] = e.name end
	end
	return out
end

local function rowByName(name)
	for _, e in ipairs(CT._rows) do
		if e.name == name then return e end
	end
end

local function column(list, key)
	for _, col in ipairs(list.columns) do
		if col.key == key then return col end
	end
	error("no column " .. key)
end

local function findChild(widget, wtype)
	for _, c in ipairs(widget.children or {}) do
		if c.type == wtype then return c end
		local inner = findChild(c, wtype)
		if inner then return inner end
	end
end

local function click(frame) frame:GetScript("OnClick")(frame, "LeftButton") end

local function select(index)
	env.drawTab(CT)
	CT._selIndex = index
	CT:RefreshDetail()
	assert.is_truthy(CT._dpSel)
end

-- Records Engine:OpenProfession calls instead of casting.
local function captureOpens()
	local opens = {}
	stub(ns.CraftingEngine, "OpenProfession", function(_, name, how) opens[#opens + 1] = { name, how } end)
	return opens
end

describe("the profession dropdown", function()
	local function twoProfessions()
		env.tradeSkillSession("Alchemy", RECIPES, { knows = {
			{ name = "Alchemy", rank = 300, max = 300 },
			{ name = "Blacksmithing", rank = 150, max = 225 },
		} })
		assert.equal(2, #ns.CraftingEngine:GetKnownProfessions())
	end

	it("lists each profession with its rank", function()
		twoProfessions()
		env.drawTab(CT)
		local items = CT._toolbar.prof.opts.items()
		assert.equal(2, #items)
		assert.equal("Alchemy (300/300)", items[1].text)
		assert.equal("Blacksmithing (150/225)", items[2].text)
		assert.equal("Alchemy", CT._toolbar.prof.opts.value)
	end)

	it("opens the profession picked", function()
		twoProfessions()
		env.drawTab(CT)
		local opens = captureOpens()
		CT._toolbar.prof.opts.onChange("Blacksmithing")
		assert.same({ { "Blacksmithing", "dropdown" } }, opens)
	end)

	it("does nothing to the window when the open profession is picked again", function()
		twoProfessions()
		env.drawTab(CT)
		local opens = captureOpens()
		CT._toolbar.prof.opts.onChange("Alchemy")
		assert.same({}, opens)
	end)

	it("keeps the queue across a switch, unless the setting clears it", function()
		twoProfessions()
		env.drawTab(CT)
		captureOpens()
		ns.CraftQueue:Add(profId(), 929, 2)
		CT._toolbar.prof.opts.onChange("Blacksmithing")
		assert.equal(1, ns.CraftQueue:Count())
		stub(ns.lib.db.profile, "clearQueueOnProfSwitch", true)
		CT._toolbar.prof.opts.onChange("Blacksmithing")
		assert.equal(0, ns.CraftQueue:Count())
	end)
end)

describe("the tab with no profession window open", function()
	local function noWindow()
		local known = { { name = "Alchemy", castName = "Alchemy", profId = 171, rank = 300, max = 300 } }
		stub(ns.CraftingEngine, "GetKnownProfessions", function() return known end)
		stub(ns.CraftingEngine, "GetOpenInfo", function() return nil end)
	end

	it("opens the saved profession when the player clicked the tab", function()
		noWindow()
		local opens = captureOpens()
		CT._autoOpenOnUserNav = true
		assert.is_true(CT._autoOpenOnUserNav)
		env.drawTab(CT)
		assert.same({ { "Alchemy", "tab" } }, opens)
		assert.is_nil(CT._autoOpenOnUserNav)   -- consumed: one click, one open
	end)

	it("does not open it on a redraw no click caused", function()
		noWindow()
		local opens = captureOpens()
		env.drawTab(CT)
		assert.same({}, opens)
	end)

	it("offers an Open button that opens it", function()
		noWindow()
		local opens = captureOpens()
		local container = env.drawTab(CT)
		local btn = findChild(container, "Button")
		assert.is_truthy(btn)
		btn:Fire("OnClick")
		assert.same({ { "Alchemy", "button" } }, opens)
	end)

	it("has no Open button on WoW Forever", function()
		noWindow()
		stub(ns.CraftingEngine, "UsesModernAPI", function() return true end)
		local container = env.drawTab(CT)
		assert.is_nil(findChild(container, "Button"))
	end)

	it("says so on a client with no trade-skill API", function()
		noWindow()
		stub(ns.CraftingEngine, "HasTradeSkillAPI", function() return false end)
		local container = env.drawTab(CT)
		local found = false
		for _, c in ipairs(container.children) do
			if c.type == "Label" and c.label and (c.label:GetText() or ""):find(L["CraftUnsupportedClient"], 1, true) then
				found = true
			end
		end
		assert.is_true(found)
		assert.is_nil(findChild(container, "Button"))
	end)
end)

describe("a jump from the Profit Planner", function()
	it("selects the recipe once its profession's list is built", function()
		CT:RequestSelect(profId(), 929)
		env.drawTab(CT)
		assert.equal(2, CT._selIndex)
		assert.equal(929, CT._selId)
		assert.is_nil(CT._pendingSelect)
	end)

	it("clears the filters that could hide the target", function()
		CT._search, CT._haveOnly = "zzz", true
		CT:RequestSelect(profId(), 929)
		assert.equal("", CT._search)
		assert.is_false(CT._haveOnly)
	end)

	-- The map is only consulted for a profession with shipped data (as in game,
	-- where the map is built from that data), and 929 is not in it.
	it("matches a Profit Planner spell id through the crafted-item map", function()
		stub(ns, "GetSpellIdForCraftedItem", function(_, _, rid) return rid == 929 and 7836 or nil end)
		stub(ns, "recipeDB", { [profId()] = { [7836] = {} } })
		CT:RequestSelect(profId(), 7836)
		env.drawTab(CT)
		assert.equal(2, CT._selIndex)
	end)

	-- The crafted-item map would turn Healing Potion's 929 into 2458 and select it
	-- (index 2); the recipe database knowing 929 keeps it 929, so the request for
	-- 2458 lands on the Elixir (index 3). Index 3 is reachable only through the
	-- recipe database branch (Peer Review, thread 05fbaa28).
	it("takes an engine id the recipe database already knows as it is", function()
		stub(ns, "GetSpellIdForCraftedItem", function(_, _, rid) return rid == 929 and 2458 or nil end)
		stub(ns, "recipeDB", { [profId()] = { [929] = {} } })
		CT:RequestSelect(profId(), 2458)
		env.drawTab(CT)
		assert.equal(3, CT._selIndex)
		assert.equal(2458, CT._selId)
	end)

	it("says once that this character does not know the recipe", function()
		CT:RequestSelect(profId(), 99999)
		env.drawTab(CT)
		assert.is_nil(CT._pendingSelect)
		assert.same({ L["ProfitCraftNotKnownHere"] }, printed)
		CT._pendingSelect = { profId = profId(), recipeId = 99998 }
		CT:TrySelectPending()
		assert.equal(1, #printed)
	end)

	it("says so when the profession is one this character does not have", function()
		CT:RequestSelect(99, 929)
		env.drawTab(CT)
		assert.is_nil(CT._pendingSelect)
		assert.same({ L["ProfitCraftNotKnownHere"] }, printed)
	end)

	it("waits while a different profession is still open", function()
		env.drawTab(CT)
		CT._pendingSelect = { profId = 99, recipeId = 929 }
		CT:TrySelectPending()
		assert.is_truthy(CT._pendingSelect)
		assert.is_nil(CT._selIndex)
	end)

	it("switches to the target profession inside the click", function()
		env.tradeSkillSession("Alchemy", RECIPES, { knows = {
			{ name = "Alchemy", rank = 300, max = 300 },
			{ name = "Blacksmithing", rank = 150, max = 225 },
		} })
		local bs
		for _, p in ipairs(ns.CraftingEngine:GetKnownProfessions()) do
			if p.name == "Blacksmithing" then bs = p end
		end
		assert.is_truthy(bs)
		local opens = captureOpens()
		CT:RequestSelect(bs.profId, 1)
		CT._autoOpenOnUserNav = true
		env.drawTab(CT)
		assert.same({ { "Blacksmithing", "jump" } }, opens)
		assert.equal("Blacksmithing", CT._toolbar.prof.opts.value)
	end)

	it("drops a request whose profession never opened", function()
		local pending
		stub(_G, "C_Timer", { After = function(_, fn) pending = fn end })
		CT:RequestSelect(profId(), 929)
		assert.is_truthy(pending)
		pending()
		assert.is_nil(CT._pendingSelect)
	end)

	it("leaves a newer request alone when an older one times out", function()
		local timers = {}
		stub(_G, "C_Timer", { After = function(_, fn) timers[#timers + 1] = fn end })
		CT:RequestSelect(profId(), 929)
		CT:RequestSelect(profId(), 2458)
		timers[1]()
		assert.equal(2458, CT._pendingSelect.recipeId)
	end)

	it("ignores a request with no recipe", function()
		CT:RequestSelect(profId(), nil)
		assert.is_nil(CT._pendingSelect)
	end)
end)

describe("the toolbar filters", function()
	it("search narrows the list to matching recipes", function()
		local container = env.drawTab(CT)
		local box = findChild(container, "LAGW-SearchBox")
		assert.is_truthy(box)
		box:Fire("OnTextChanged", "healing")
		assert.equal("healing", CT._search)
		assert.same({ "Healing Potion" }, recipeNames())
		box:Fire("OnTextChanged", nil)
		assert.equal("", CT._search)
		assert.same({ "Healing Potion", "Elixir of Fortitude" }, recipeNames())
	end)

	it("have-materials shows only what can be made now", function()
		env.drawTab(CT)
		local opts = CT._toolbar.haveOnly.opts
		assert.is_false(opts.get())
		opts.set(true)
		assert.is_true(opts.get())
		assert.same({ "Healing Potion" }, recipeNames())
		opts.set(nil)
		assert.is_false(CT._haveOnly)
	end)

	it("the Blizzard button shows the game's own window", function()
		local shown = 0
		stub(ns.CraftingEngine, "ShowDefaultUI", function() shown = shown + 1 end)
		local container = env.drawTab(CT)
		local btn = findChild(container, "Button")
		assert.is_truthy(btn)
		btn:Fire("OnClick")
		assert.equal(1, shown)
	end)

	it("stops filling a list the window has released", function()
		local container = env.drawTab(CT)
		assert.is_true(CT._listLive)
		assert.is_not_nil(CT._rows)
		assert.equal(3, #CT._rows)
		container:ReleaseChildren()
		assert.is_nil(CT._listLive)
		assert.is_nil(CT._rows)
		CT:FillList()
		assert.is_nil(CT._rows)
	end)
end)

describe("the recipe list", function()
	it("sorts flat by a column and back to the categories", function()
		env.drawTab(CT)
		CT._list.onSortChanged("craft", true)
		assert.equal("craft", CT._sortCol)
		assert.is_false(CT._sortAsc)
		assert.equal("Healing Potion", CT._rows[1].name)
		assert.equal(2, #CT._rows)          -- no header row when sorted
		CT._list.onSortChanged("name", false)
		assert.equal("Elixir of Fortitude", CT._rows[1].name)
		-- Neither recipe has a required skill, so the tie falls to the name, A-Z,
		-- even sorted descending: a craft-count or name sort would put the
		-- Healing Potion first.
		CT._list.onSortChanged("skill", true)
		assert.same({ "Elixir of Fortitude", "Healing Potion" }, recipeNames())
		assert.equal(2, #CT._rows)
		CT._list.onSortChanged(nil, false)
		assert.equal("header", CT._rows[1].kind)
	end)

	it("selects a recipe on a left click", function()
		env.drawTab(CT)
		CT._qty = 4
		CT._list.onRowClick(rowByName("Elixir of Fortitude"), nil, nil, "LeftButton")
		assert.equal(3, CT._selIndex)
		assert.equal(2458, CT._selId)
		assert.equal(1, CT._qty)
		assert.equal("Elixir of Fortitude", CT._dpSel.name)
	end)

	it("ignores a right click and a click on a category", function()
		env.drawTab(CT)
		CT._list.onRowClick(rowByName("Healing Potion"), nil, nil, "RightButton")
		assert.is_nil(CT._selIndex)
		assert.is_nil(CT._dpSel)
		assert.equal("header", CT._rows[1].kind)
		CT._list.onRowClick(CT._rows[1], nil, nil, "LeftButton")
		assert.is_nil(CT._selIndex)
		assert.is_nil(CT._dpSel)
	end)

	it("links the item instead of selecting on a modified click", function()
		env.drawTab(CT)
		stub(ns.ItemLink, "Click", function() return true end)
		CT._list.onRowClick(rowByName("Healing Potion"), nil, nil, "LeftButton")
		assert.is_nil(CT._selIndex)
	end)

	it("draws its cells: difficulty colour, white when selected, craftable count", function()
		env.drawTab(CT)
		local e = rowByName("Healing Potion")
		local name = column(CT._list, "name")
		assert.is_truthy(name.format(e.name, e):find("Healing Potion", 1, true))
		CT._selIndex = e.index
		assert.is_truthy(name.format(e.name, e):find("ffffffff", 1, true))
		assert.equal("|cffffffff|r", name.format(nil, { difficulty = "nope" }))
		local craft = column(CT._list, "craft")
		assert.equal("|cff40c0405|r", craft.format(nil, { num = 5 }))
		assert.equal("|cff8080800|r", craft.format(nil, { num = 0 }))
		local tierArgs
		stub(ns, "FormatSkillTiers", function(...) tierArgs = { ... }; return "tiers" end)
		assert.equal("tiers", column(CT._list, "skill").format(nil, { tiers = "t", requiredSkill = 75, recipeId = 929 }))
		assert.same({ "t", 75, 929 }, tierArgs)
		assert.equal(134400, column(CT._list, "_icon").icon({}))
		assert.equal(7, column(CT._list, "_icon").icon({ icon = 7 }))
	end)

	it("remembers its scroll position", function()
		env.drawTab(CT)
		CT._list.onScroll(CT._list, 3)
		assert.equal(3, ns.GUI.ListScroll.Get("crafting"))
	end)

	it("keeps the selection highlight off when nothing is selected", function()
		env.drawTab(CT)
		CT._selIndex = 3
		CT:SyncListSelection()
		assert.equal("Elixir of Fortitude", CT._list:GetSelected().name)
		CT._selIndex = nil
		CT:SyncListSelection()
		assert.is_nil(CT._list:GetSelected())
		local list = CT._list
		CT._list = nil
		assert.has_no.errors(function() CT:SyncListSelection() end)
		CT._list = list
	end)
end)

describe("the detail panel's controls", function()
	it("Queue adds the selected recipe at the chosen quantity", function()
		select(2)
		CT._qty = 2
		click(CT._dpQueue)
		assert.same({ { profId = profId(), recipeId = 929, qty = 2 } }, ns.CraftQueue:Get())
	end)

	it("Queue does nothing with no recipe selected", function()
		select(2)
		CT._dpSel = nil
		click(CT._dpQueue)
		click(CT._dpCraftMax)
		assert.equal(0, ns.CraftQueue:Count())
	end)

	it("Craft Max queues what can be made and starts crafting it", function()
		local crafted = env.tradeSkillSession("Alchemy", RECIPES)
		select(2)
		click(CT._dpCraftMax)
		assert.equal(5, CT._qty)
		assert.equal(1, #crafted)
		assert.equal(5, crafted[1].count)
	end)

	it("MAX sets the quantity to what can be made", function()
		select(2)
		click(CT._dpMax)
		assert.equal(5, CT._qty)
		CT._dpSel = nil
		click(CT._dpMax)
		assert.equal(1, CT._qty)
	end)

	it("the quantity box sets the quantity", function()
		select(2)
		CT._dpStepper._onChange(7)
		assert.equal(7, CT._qty)
	end)

	it("puts back a quantity changed elsewhere and keeps one being typed", function()
		select(2)
		CT._qty = 3
		CT:RefreshDetail()
		assert.equal(3, CT._dpStepper:GetValue())
		assert.equal("3", CT._dpStepper.edit:GetText())
		-- Half-way through typing 12: a bag update's refresh leaves the box alone.
		-- Setting the value instead would force "3" back into it.
		local edit = CT._dpStepper.edit
		edit:SetFocus()
		edit:SetText("12")
		CT:RefreshDetail()
		assert.equal("12", edit:GetText())
		assert.equal(3, CT._dpStepper:GetValue())
		edit:ClearFocus()
	end)

	it("drops a selection the list no longer has", function()
		select(2)
		CT._selIndex = 42
		CT:RefreshDetail()
		assert.is_nil(CT._selIndex)
		assert.is_nil(CT._dpSel)
	end)

	it("explains every button and heading on hover", function()
		select(2)
		local titles = {}
		local function hover(frame)
			local enter = frame:GetScript("OnEnter")
			if not enter or frame == CT._dpNameBtn then return end
			GameTooltip:Hide()
			GameTooltip:ClearLines()
			enter(frame)
			assert.is_true(GameTooltip:IsShown())
			local first = GameTooltip._lines and GameTooltip._lines[1]
			titles[#titles + 1] = first and first.left or "<no line>"
			frame:GetScript("OnLeave")(frame)
			assert.is_false(GameTooltip:IsShown())
		end
		for _, f in ipairs({ CT._detailPanel:GetChildren() }) do hover(f) end
		for _, f in ipairs({ CT._queuePanel:GetChildren() }) do hover(f) end
		table.sort(titles)
		local want = {
			L["CraftQueueButton"], L["CraftMaxButton"], L["CraftButton"], L["CraftMax"],
			L["CraftMissingMaterials"], L["CraftCostLabel"], L["CraftQueueHeaderTitle"],
		}
		table.sort(want)
		assert.same(want, titles)
		-- The recipe name shows the crafted item's own tooltip, which the harness
		-- leaves without text lines, so it is checked by the link it was given.
		local linked
		stub(GameTooltip, "SetHyperlink", function(_, link) linked = link end)
		GameTooltip:Hide()
		CT._dpNameBtn:GetScript("OnEnter")(CT._dpNameBtn)
		assert.equal(RECIPES[2].link, linked)
		assert.is_true(GameTooltip:IsShown())
		CT._dpNameBtn:GetScript("OnLeave")(CT._dpNameBtn)
		assert.is_false(GameTooltip:IsShown())
	end)

	it("shows nothing on the recipe name with no recipe selected", function()
		select(2)
		CT._dpSel = nil
		GameTooltip:Hide()
		CT._dpNameBtn:GetScript("OnEnter")(CT._dpNameBtn)
		assert.is_false(GameTooltip:IsShown())
	end)
end)

describe("the item tooltip", function()
	local function tipCalls()
		local calls = {}
		for _, m in ipairs({ "SetHyperlink", "SetCraftItem", "SetSpellByID", "SetTradeSkillItem" }) do
			stub(GameTooltip, m, function(_, arg) calls[#calls + 1] = { m, arg } end)
		end
		return calls
	end

	it("shows the crafted item when there is a link", function()
		local calls = tipCalls()
		local anchor = CreateFrame("Frame")
		CT:ShowItemTooltip(anchor, 2, RECIPES[2].link, 929)
		assert.equal("SetHyperlink", calls[1][1])
		assert.is_true(GameTooltip:IsShown())
	end)

	it("falls back to the trade-skill entry with no link", function()
		local calls = tipCalls()
		CT:ShowItemTooltip(CreateFrame("Frame"), 3, nil, nil)
		assert.same({ "SetTradeSkillItem", 3 }, calls[1])
	end)

	it("uses the Craft window's entry for Enchanting", function()
		local calls = tipCalls()
		stub(ns.CraftingEngine, "GetOpenInfo", function() return { isCraftWindow = true, profId = 333 } end)
		CT:ShowItemTooltip(CreateFrame("Frame"), 4, nil, nil)
		assert.same({ "SetCraftItem", 4 }, calls[1])
	end)

	it("uses the recipe's spell on WoW Forever", function()
		local calls = tipCalls()
		stub(ns.CraftingEngine, "UsesModernAPI", function() return true end)
		CT:ShowItemTooltip(CreateFrame("Frame"), 2329, nil, nil)
		assert.same({ "SetSpellByID", 2329 }, calls[1])
	end)
end)

describe("the reagent rows' Bank and AH buttons", function()
	local function reagentRow()
		select(2)
		return CT._dpReagList.data[1]
	end

	it("show [Bank] for a reagent the guild bank holds, and request it", function()
		local requested
		stub(ns, "Bank", {
			GetStock = function(id) return id == 2447 and 4 or 0 end,
			ButtonText = function() return "[Bank]" end,
			StatusText = function() return "4 in the bank" end,
			ShowRequestDialog = function(id, name, link) requested = { id, name, link } end,
		})
		local e = reagentRow()
		local col = column(CT._dpReagList, "bankBtn")
		assert.is_true(col.show(e))
		assert.equal("[Bank]", col.text(e))
		local title, body = col.tip(e)
		assert.equal(L["TooltipBankTitle"], title)
		assert.is_truthy(body:find("4 in the bank", 1, true))
		col.onClick(e)
		assert.same({ 2447, "Peacebloom", RECIPES[2].reagents[1].link }, requested)
		assert.is_falsy(col.show(CT._dpReagList.data[2]))   -- no item id
	end)

	it("leave the status line off a bank tooltip with no status", function()
		stub(ns, "Bank", {
			GetStock = function() return 1 end,
			ButtonText = function() return "[Bank]" end,
			StatusText = function() return nil end,
		})
		local e = reagentRow()
		local col = column(CT._dpReagList, "bankBtn")
		local _, body = col.tip(e)
		assert.equal(L["CraftBankReagentDesc"], body)
		-- A bank module with no request dialog: the click reads nothing and calls
		-- nothing, and is not an error.
		local touched = {}
		local real = ns.Bank
		stub(ns, "Bank", setmetatable({}, { __index = function(_, k)
			touched[#touched + 1] = k
			return real[k]
		end }))
		col.onClick(e)
		assert.same({ "ShowRequestDialog" }, touched)
	end)

	it("show [AH] for a reagent with listings, and search for it", function()
		local searched
		stub(ns, "AH", {
			GetListingsFor = function(id) return id == 2447 and { count = 2 } or nil end,
			SearchFor = function(name) searched = name end,
		})
		local e = reagentRow()
		local col = column(CT._dpReagList, "ahBtn")
		assert.is_true(col.show(e))
		assert.is_false(col.show(CT._dpReagList.data[2]))
		assert.is_truthy(col.text(e):find("[AH]", 1, true))
		local title = col.tip(e)
		assert.equal(L["TooltipAHTitle"], title)
		col.onClick(e)
		assert.equal("Peacebloom", searched)
	end)

	it("do nothing when the AH has no search", function()
		local listed = 0
		stub(ns, "AH", { GetListingsFor = function() listed = listed + 1 end })
		local e = reagentRow()
		local touched = {}
		local real = ns.AH
		ns.AH = setmetatable({}, { __index = function(_, k)
			touched[#touched + 1] = k
			return real[k]
		end })
		listed = 0
		column(CT._dpReagList, "ahBtn").onClick(e)
		assert.same({ "SearchFor" }, touched)
		assert.equal(0, listed)
	end)

	it("show the reagent's item tooltip on hover, and only for a linked one", function()
		local e = reagentRow()
		local rowFrame = CreateFrame("Frame")
		GameTooltip:Hide()
		CT._dpReagList.onRowEnter(CT._dpReagList.data[2], nil, nil, rowFrame)
		assert.is_false(GameTooltip:IsShown())
		CT._dpReagList.onRowEnter(e, nil, nil, rowFrame)
		assert.is_true(GameTooltip:IsShown())
		CT._dpReagList.onRowLeave(e)
		assert.is_false(GameTooltip:IsShown())
	end)

	it("draw the reagent icon, with a fallback", function()
		local icon = column(CT._dpReagList, "_icon").icon
		assert.equal(134400, icon({ r = {} }))
		assert.equal(9, icon({ r = { texture = 9 } }))
	end)
end)

describe("the crafting cost line", function()
	local function price(o)
		stub(ns, "Price", {
			GetReagentCost = function(id) return o.unit and o.unit[id], o.unit and "auctionator" end,
			Money = function(n) return tostring(n) .. "c" end,
			GetSourceColor = function() return "ffaabbcc" end,
			CraftCostForReagents = function() return o.total or 0, o.priced or 0, o.count or 0, o.stale end,
			GetSaleLive = o.sale and function() return o.sale, "tsm" end or nil,
		})
	end

	local function costText()
		select(2)
		return CT._dpCost:GetText() or ""
	end

	it("says none when no reagent has a price", function()
		price({ priced = 0, count = 2 })
		local text = costText()
		assert.is_truthy(text:find(L["CraftCostNone"], 1, true))
		assert.is_truthy(CT._dpReagList.data[1].costText:find("—", 1, true))
		assert.is_true(CT._dpCost:IsShown())
	end)

	it("marks a partly priced and stale total, and shows the sale price without a profit", function()
		price({ unit = { [2447] = 10 }, total = 10, priced = 1, count = 2, stale = true, sale = 500 })
		local text = costText()
		assert.is_truthy(text:find("10c", 1, true))
		assert.is_truthy(text:find(" * ~", 1, true))
		assert.is_truthy(text:find("500c", 1, true))
		assert.is_truthy(text:find("[TSM]", 1, true))
		assert.is_nil(text:find(L["CraftProfitLabel"], 1, true))
		assert.is_truthy(CT._dpReagList.data[1].costText:find("[AUC]", 1, true))
	end)

	it("shows a profit in green when the sale beats the cost", function()
		price({ total = 100, priced = 2, count = 2, sale = 500 })
		local text = costText()
		assert.is_truthy(text:find("ff40c040+400c", 1, true))
	end)

	it("shows a loss in red when the cost beats the sale", function()
		price({ total = 900, priced = 2, count = 2, sale = 500 })
		local text = costText()
		assert.is_truthy(text:find("ffff4040-400c", 1, true))
	end)

	it("is hidden with no price module", function()
		stub(ns, "Price", nil)
		select(2)
		assert.is_false(CT._dpCost:IsShown())
		assert.equal("", CT._dpReagList.data[1].costText)
	end)
end)

describe("the queue panel's rows", function()
	local function openWindow()
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "crafting"
	end

	it("draws one row per entry, greyed when it cannot be made here", function()
		openWindow()
		env.drawTab(CT)
		ns.CraftQueue:Add(profId(), 929, 3)
		ns.CraftQueue:Add(profId(), 2458, 1)
		ns.CraftQueue:Add(999, 1, 1)
		local data = CT._queueList.data
		assert.equal(3, #data)
		assert.equal("Healing Potion", data[1].name)
		assert.equal(3, data[1].qty)
		assert.is_true(data[1].craftable)
		assert.is_false(data[2].craftable)
		assert.is_false(data[3].craftable)
		assert.is_truthy(CT._queueTitle:GetText():find("3", 1, true))
		local name = column(CT._queueList, "name")
		assert.is_truthy(name.format("Healing Potion", data[1]):find("ffffffff", 1, true))
		assert.is_truthy(name.format(nil, data[2]):find("ff888888", 1, true))
		assert.is_truthy(column(CT._queueList, "qty").format(3):find("x3", 1, true))
		assert.is_truthy(column(CT._queueList, "qty").format(nil):find("x0", 1, true))
		assert.equal(134400, column(CT._queueList, "icon").icon({}))
		assert.is_truthy(column(CT._queueList, "remove").text():find("x", 1, true))
	end)

	it("removes an entry on a left click of its x, never a right click", function()
		openWindow()
		env.drawTab(CT)
		ns.CraftQueue:Add(profId(), 929, 3)
		ns.CraftQueue:Add(profId(), 2458, 1)
		local remove = column(CT._queueList, "remove")
		remove.onClick(nil, 1, nil, "RightButton")
		assert.equal(2, ns.CraftQueue:Count())
		remove.onClick(nil, 1, nil, "LeftButton")
		assert.equal(1, ns.CraftQueue:Count())
		assert.equal(2458, ns.CraftQueue:Get()[1].recipeId)
		assert.equal(1, #CT._queueList.data)
	end)

	it("reorders on a drag", function()
		openWindow()
		env.drawTab(CT)
		ns.CraftQueue:Add(profId(), 929, 3)
		ns.CraftQueue:Add(profId(), 2458, 1)
		CT._queueList.onReorder(2, 1)
		assert.equal(2458, ns.CraftQueue:Get()[1].recipeId)
		assert.equal("Elixir of Fortitude", CT._queueList.data[1].name)
	end)

	it("Craft Next, Craft All and Clear All drive the queue", function()
		local crafted = env.tradeSkillSession("Alchemy", RECIPES)
		openWindow()
		env.drawTab(CT)
		ns.CraftQueue:Add(profId(), 929, 2)
		click(CT._craftNextBtn)
		assert.equal(1, #crafted)
		assert.equal(2, crafted[1].count)
		click(CT._craftAllBtn)
		assert.equal(2, #crafted)
		click(CT._clearAllBtn)
		assert.equal(0, ns.CraftQueue:Count())
	end)

	it("does not redraw while the window is closed or on another tab", function()
		env.drawTab(CT)
		ns.CraftQueue:Add(profId(), 929, 3)
		assert.equal(0, #CT._queueList.data)
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "browser"
		CT:OnQueueChanged()
		assert.equal(0, #CT._queueList.data)
		openWindow()
		CT:OnQueueChanged()
		assert.equal(1, #CT._queueList.data)
	end)
end)

describe("a queue entry's name and icon", function()
	it("comes from the open window when the recipe is in it", function()
		local name, icon = CT:QueueEntryDisplay({ profId = profId(), recipeId = 929 })
		assert.equal("Healing Potion", name)
		assert.equal(1, icon)
	end)

	it("falls back to the recipe database, then the crafted item's icon", function()
		stub(ns, "recipeDB", { [5] = {
			[100] = { name = "Saved Recipe", icon = 77 },
			[101] = { name = "Iconless", craftedItemId = 929 },
		} })
		stub(ns.Item, "GetIcon", function(id) return id == 929 and 88 or nil end)
		assert.same({ "Saved Recipe", 77 }, { CT:QueueEntryDisplay({ profId = 5, recipeId = 100 }) })
		assert.same({ "Iconless", 88 }, { CT:QueueEntryDisplay({ profId = 5, recipeId = 101 }) })
	end)

	it("falls back to the spell, then the bare id", function()
		stub(ns, "recipeDB", nil)
		stub(ns.Spell, "GetInfo", function(id) return id == 200 and "Spell Name" or nil end)
		stub(ns.Spell, "GetTexture", function(id) return id == 200 and 66 or nil end)
		assert.same({ "Spell Name", 66 }, { CT:QueueEntryDisplay({ profId = 5, recipeId = 200 }) })
		assert.equal("#201", (CT:QueueEntryDisplay({ profId = 5, recipeId = 201 })))
	end)
end)

describe("live refreshes", function()
	-- Puts the list, the detail and the queue out of date: the rows gone, the
	-- detail's recipe cleared, and a queue entry added while the window was on
	-- another tab, so the queue panel did not draw it.
	local function staleEverything()
		select(2)
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "browser"
		ns.CraftQueue:Add(profId(), 929, 2)
		ns.MainWindow.activeTab = "crafting"
		assert.equal(0, #CT._queueList.data)
		CT._rows, CT._dpSel = nil, nil
	end

	local function assertAllRedrawn()
		assert.same({ "Healing Potion", "Elixir of Fortitude" }, recipeNames())
		assert.equal("Healing Potion", CT._dpSel.name)
		assert.equal(1, #CT._queueList.data)
	end

	it("redraw the list, the detail and the queue while the tab is showing", function()
		staleEverything()
		CT:OnLiveRefresh()
		assertAllRedrawn()
	end)

	it("do nothing while the window is on another tab", function()
		select(2)
		ns.MainWindow.frame, ns.MainWindow.activeTab = {}, "browser"
		CT._rows = nil
		CT:OnLiveRefresh()
		assert.is_nil(CT._rows)
		-- The same call on the Crafting tab does fill them.
		ns.MainWindow.activeTab = "crafting"
		CT:OnLiveRefresh()
		assert.is_not_nil(CT._rows)
		assert.equal(3, #CT._rows)
	end)

	it("follow an AH scan landing", function()
		staleEverything()
		ns.callbacks:Fire("AH_SCAN_COMPLETE")
		assertAllRedrawn()
	end)

	it("redraw the whole tab when the session changes", function()
		local released, drawnTab = 0, nil
		local tabs = { ReleaseChildren = function() released = released + 1 end }
		stub(ns.MainWindow, "DrawTab", function(_, name) drawnTab = name end)
		ns.MainWindow.frame, ns.MainWindow.activeTab, ns.MainWindow.tabs = {}, "crafting", tabs
		CT:OnSessionChanged()
		assert.equal(1, released)
		assert.equal("crafting", drawnTab)
	end)
end)
