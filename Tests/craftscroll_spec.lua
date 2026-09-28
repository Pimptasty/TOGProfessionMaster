-- The Crafting tab's recipe list: putting a selected recipe on screen, and
-- keeping the list where the player left it.
--
-- The list is a LibAceGUIWidgets RowList since v1.1.2. It used to be a raw
-- frame pool with its own ScrollToRow arithmetic, pinned by nine specs here;
-- the arithmetic is now the library's (ScrollToEntry, with its own suite). What
-- is TOGPM's, and pinned below, is how the tab ASKS for it: the Profit Planner
-- jump selects the recipe, brings it into view with two rows of context, and
-- does not move a list that already shows it -- driven end to end through
-- RequestSelect and a live trade-skill session, not by calling the helper.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, CT

local N = 60   -- recipes under one category header: far more than one screen

local function session()
	local recipes = { { name = "Alchemy", difficulty = "header", available = 0 } }
	-- Each with a crafted-item link: that is where a Classic recipe's id comes
	-- from, and a recipe with no id cannot be the target of a jump.
	for i = 1, N do
		local name = ("Recipe %02d"):format(i)
		recipes[#recipes + 1] = { name = name, available = 1,
			link = ("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(5000 + i, name) }
	end
	env.tradeSkillSession("Alchemy", recipes)
end

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/ReagentWatch.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Crafting/CraftQueue.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	env.loadModule("GUI/CraftingTab.lua")
	CT = ns.CraftingTab
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	ns.Print = function() end
	session()
	CT._sortCol, CT._sortAsc, CT._selIndex = nil, true, nil
	ns.GUI.ListScroll.Set("crafting", 0)
end)

--- The engine's entry for "Recipe NN", and its row in the drawn list. The engine
--- builds fresh tables on each call, so rows are matched by trade-skill index.
local function target(n)
	local name = ("Recipe %02d"):format(n)
	for _, e in ipairs(ns.CraftingEngine:GetRecipeList()) do
		if e.kind == "recipe" and e.name == name then return e end
	end
	error("no recipe " .. name)
end

local function rowOf(e)
	for i, r in ipairs(CT._rows) do
		if r.kind == "recipe" and r.index == e.index then return i end
	end
end

--- The Profit Planner's jump, resolved the way it is in game: armed, then
--- settled by the list fill.
local function jump(e)
	CT:RequestSelect(ns.CraftingEngine:GetOpenInfo().profId, e.recipeId)
	CT:FillList()
end

describe("the recipe list on screen", function()
	it("draws the category tree, with the header first", function()
		env.drawTab(CT)
		assert.equal(N + 1, #CT._rows)
		assert.equal("header", CT._rows[1].kind)
		-- The fixture must give the list room, or every scroll below is a no-op
		-- that passes for the wrong reason.
		local vis = CT._list.visibleRowCount or 0
		assert.is_true(vis > 5 and vis < N - 10, "visible rows: " .. vis)
	end)

	it("brings a recipe below the screen into view, two rows of context under it", function()
		env.drawTab(CT)
		local e = target(40)
		assert.is_truthy(e.recipeId)
		jump(e)
		assert.equal(e.index, CT._selIndex)
		assert.equal(e.index, CT._list:GetSelected().index)
		local vis = CT._list.visibleRowCount
		assert.equal(rowOf(e) - vis + 2, CT._list:GetScrollOffset())
	end)

	it("does not move a list that already shows the recipe", function()
		env.drawTab(CT)
		jump(target(2))
		assert.equal(0, CT._list:GetScrollOffset())
		assert.equal(target(2).index, CT._selIndex)
	end)

	it("scrolls UP to a recipe above the screen, two rows of context over it", function()
		env.drawTab(CT)
		CT._list:SetScrollOffset(40)
		assert.equal(40, CT._list:GetScrollOffset())
		local e = target(20)
		jump(e)
		assert.equal(e.index, CT._selIndex)
		assert.equal(rowOf(e) - 1 - 2, CT._list:GetScrollOffset())
	end)

	it("puts the list back where it was on the next draw", function()
		env.drawTab(CT)
		CT._list:SetScrollOffset(17)
		assert.equal(17, ns.GUI.ListScroll.Get("crafting"))
		env.drawTab(CT)
		assert.equal(17, CT._list:GetScrollOffset())
	end)

	it("keeps the scroll through a live refresh", function()
		env.drawTab(CT)
		CT._list:SetScrollOffset(12)
		CT:FillList()
		assert.equal(12, CT._list:GetScrollOffset())
	end)
end)

describe("sorting the recipe list", function()
	it("drops the category rows while sorted and brings them back on the third click", function()
		env.drawTab(CT)
		CT:OnSortChanged("name", true)          -- descending, as the second click
		assert.equal(N, #CT._rows)
		assert.equal("Recipe 60", CT._rows[1].name)
		CT:OnSortChanged(nil, nil)              -- the third click: no sort
		assert.equal("header", CT._rows[1].kind)
		assert.equal(N + 1, #CT._rows)
	end)
end)

describe("clicking a recipe row", function()
	it("selects it and highlights it", function()
		env.drawTab(CT)
		local e = target(3)
		CT._list.onRowClick(e, rowOf(e), CT._list, "LeftButton")
		assert.equal(e.index, CT._selIndex)
		assert.equal(e.index, CT._list:GetSelected().index)
		assert.is_truthy(CT._dpSel)
	end)

	it("ignores a click on a category row", function()
		env.drawTab(CT)
		CT._list.onRowClick(CT._rows[1], 1, CT._list, "LeftButton")
		assert.is_nil(CT._selIndex)
	end)
end)
