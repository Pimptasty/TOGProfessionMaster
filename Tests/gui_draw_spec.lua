-- Every tab, drawn for real.
--
-- Each tab builds its entire UI from `Draw(container)`, so one call per tab
-- executes the path a player triggers by clicking it — hundreds of lines of
-- widget construction that nothing could reach before the harness grew a widget
-- layer, and whose failure mode is a Lua error in someone's face at raid time.
--
-- These are deliberately SMOKE tests: they assert the tab builds against real
-- AceGUI and real data, not what it looks like. Text metrics and layout are not
-- faithful offline and asserting on them would be a false green. What they do
-- catch is the class that actually happens — a renamed field, a nil texture, a
-- method that moved, an anchor to a frame that no longer exists.
--
-- Each tab is drawn twice on purpose. AceGUI recycles widgets, so the second
-- draw hands the tab back the pooled frames it just released, and anything it
-- failed to clean up shows here rather than three tab-switches later in game.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, gdb
local ALCHEMY, TAILORING = 171, 197
local ME, MATE = "Testchar-Testrealm", "Bob-Testrealm"
local POTION, ELIXIR, BOLT = 2330, 2331, 2963

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/SyncLog.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/ReagentWatch.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Crafting/CraftQueue.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	env.loadModule("GUI/BrowserTab.lua")
	env.loadModule("GUI/CooldownsTab.lua")
	env.loadModule("GUI/MissingRecipesTab.lua")
	env.loadModule("GUI/GuildTab.lua")
	env.loadModule("GUI/AHProfitTab.lua")
	env.loadModule("GUI/CraftingTab.lua")
	env.loadModule("GUI/ReagentTracker.lua")
end)

--- A guild with data in every table a tab might read, so the draws exercise
--- populated branches rather than the empty-state shortcut.
local function populate()
	env.spellsExist(POTION, ELIXIR, BOLT)
	env.setRecipeDB({
		[ALCHEMY]   = {
			[POTION] = { name = "Healing Potion", icon = 1, reagents = {},
			             craftedItemId = 929, requiredSkill = 60 },
			[ELIXIR] = { name = "Elixir of Fortitude", icon = 1, reagents = {},
			             craftedItemId = 3825, requiredSkill = 120 },
			-- Transmute: Arcanite, the shopping-list fixture below. Reagents are
			-- the REAL ones from ProfessionDB (1 Thorium Bar + 1 Arcane Crystal)
			-- because Data/CooldownIds.lua now derives reagents from recipeDB
			-- rather than carrying its own copy — a fixture with no reagents
			-- would leave the cooldown with none and is what this spec caught.
			[17187] = { name = "Transmute: Arcanite", icon = 1, requiredSkill = 275,
			            reagents = { [12359] = 1, [12363] = 1 }, craftedItemId = 12360 },
		},
		[TAILORING] = {
			[BOLT] = { name = "Bolt of Linen", icon = 1, reagents = {},
			           craftedItemId = 2996, requiredSkill = 1 },
		},
	})

	local tag = ns:GetCurrentGuildTag()
	gdb.recipes[ALCHEMY] = {
		-- ME crafts the potion but NOT the elixir, so the Missing Recipes tab
		-- has something to report. Giving this character every recipe in the
		-- profession makes an empty missing-list the CORRECT answer, which is
		-- how a "populated" fixture can quietly test the empty state.
		[POTION] = { name = "R" .. POTION, icon = 1, crafters = { [MATE] = tag, [ME] = tag } },
		[ELIXIR] = { name = "R" .. ELIXIR, icon = 1, crafters = { [MATE] = tag } },
	}
	gdb.recipes[TAILORING] = {
		[BOLT] = { name = "R" .. BOLT, icon = 1, crafters = { [MATE] = tag } },
	}
	gdb.skills[ME]   = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
	gdb.skills[MATE] = { [TAILORING] = { skillRank = 150, skillMax = 300 } }
	gdb.cooldowns[ME] = { [17187] = env.serverTime + 3600 }
	gdb.accountChars[ME] = true

	ns.lib.db.char.shoppingList = { [17187] = { quantity = 2, reagents = {} } }
end

before_each(function()
	env.installFrames()
	gdb = env.resetDb()
	env.roster({
		{ name = "Testchar", isOnline = true },
		{ name = "Bob",      isOnline = true },
	})
	ns.Print = function() end
	populate()
end)

--- Draw a tab twice and hand back the container. The second draw is the
--- pooled-widget pass; see the file header.
local function drawTwice(tab, opts)
	local container = env.drawTab(tab, opts)
	tab:Draw(container)
	return container
end

--- Rows actually produced. A widget COUNT is the wrong evidence and was
--- initially used here: the Browser and Profit tabs render rows as raw pooled
--- frames rather than AceGUI children, so a child count is blind to them, and
--- the Guild tab deliberately lists every profession even at zero, so its count
--- is constant by design. Three of the seven "populated" cases were therefore
--- passing on a number that never moved. Each tab is asked for its own list
--- instead — the thing it would have to build to have drawn anything.
local function rowCount(list)
	if type(list) ~= "table" then return 0 end
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	return n
end

describe("every tab builds against real AceGUI, with data in it", function()
	it("Professions (BrowserTab) lists the guild's recipes", function()
		drawTwice(ns.BrowserTab)
		assert.is_true(rowCount(ns.BrowserTab._recipes) > 0)
	end)

	it("Professions reuses one column-header bar across redraws", function()
		-- Draw re-runs on every GUILD_DATA_UPDATED. WoW never frees a frame, so a
		-- fresh header bar per Draw (as up to v1.1.2) leaked three frames each time.
		local container = env.drawTab(ns.BrowserTab)
		local first = ns.BrowserTab._headerBar
		assert.is_not_nil(first)
		ns.BrowserTab:Draw(container)
		assert.equal(first, ns.BrowserTab._headerBar)
		assert.equal(container.content, first:GetParent())
	end)

	it("the Scan AH button explains itself while disabled, and hands back a clean frame", function()
		-- Disabled whenever the AH is closed, which is when its tooltip matters.
		-- A disabled Button hears no OnEnter unless motion scripts are on while
		-- disabled; up to v1.1.2 they were not, so the tooltip never appeared.
		local realAH = ns.AH
		ns.AH = { IsScanning = function() return false end, IsOpen = function() return false end }
		local AceGUI = LibStub("AceGUI-3.0")
		local parent = AceGUI:Create("SimpleGroup")
		local ok, btn = pcall(ns.GUI.MakeScanAHButton, {
			parent = parent, tabName = "spec", label = "Scan AH", progressLabel = "%d/%d",
			tooltipTitle = "Scan AH", tooltipDesc = "Open the Auction House first.",
			getItems = function() return {} end,
		})
		ns.AH = realAH
		assert.is_true(ok, tostring(btn))
		assert.is_false(btn.frame:IsEnabled())
		GameTooltip:Hide()
		btn.frame:Fire("OnEnter")
		assert.is_true(GameTooltip:IsShown(), "no tooltip on the disabled button")
		GameTooltip:Hide()
		AceGUI:Release(btn)
		assert.is_false(btn.frame:GetMotionScriptsWhileDisabled(),
			"the pooled frame kept motion-while-disabled after release")
	end)

	it("Cooldowns lists a running cooldown", function()
		drawTwice(ns.CooldownsTab)
		local rows = ns.CooldownsTab._BuildRows(false, "mine")
		assert.is_true(rowCount(rows) > 0)
	end)

	it("Cooldowns creates no new frames when it redraws", function()
		-- Every refresh (GUILD_DATA_UPDATED included) redraws the tab. Up to
		-- v1.1.2 each redraw created ~10 raw frames per row and dropped them;
		-- WoW never frees one. The rows are now a RowList built once per
		-- session. RedrawTable is the production redraw: release, then Draw.
		local container = env.drawTab(ns.CooldownsTab)
		ns.CooldownsTab:RedrawTable(container)  -- warm the AceGUI pools too
		local list = ns.CooldownsTab._rowList
		local made, realCreate = 0, _G.CreateFrame
		_G.CreateFrame = function(...) made = made + 1; return realCreate(...) end
		local ok, err = pcall(ns.CooldownsTab.RedrawTable, ns.CooldownsTab, container)
		_G.CreateFrame = realCreate
		assert.is_true(ok, tostring(err))
		assert.is_true(#ns.CooldownsTab._BuildRows(false, "mine") > 0)
		assert.equal(0, made, "a redraw created raw frames")
		assert.equal(list, ns.CooldownsTab._rowList, "a redraw built a second list")
	end)

	it("Cooldowns' fixed columns leave the cooldown name at least 80 px in the locked window", function()
		-- The window is locked at 720 wide for this tab; the tab content is
		-- narrower still (660 here, less a 20 px scrollbar). Every other column
		-- is fixed, so the name gets what is left -- and must not be squeezed to
		-- nothing, on TBC/Wrath least of all, where the spec-bonus column takes
		-- its share too. The DECLARED widths are summed rather than the drawn
		-- ones: the library widens a column to fit its header text, and the
		-- harness's text metrics are deliberately not the client's (it measures
		-- "Time Left" at 169 px), so a drawn width here would be a false result.
		env.drawTab(ns.CooldownsTab, { width = 660 })
		local fixed = 0
		for _, col in ipairs(ns.CooldownsTab._rowList.columns) do
			fixed = fixed + (col.width or 0)
		end
		assert.is_true(660 - 20 - fixed >= 80, ("fixed columns take %d of 640 px"):format(fixed))
	end)

	it("a pooled Cooldowns row shows nothing from the group row it drew before", function()
		local tab = ns.CooldownsTab
		env.drawTab(tab)
		local rl, host = tab._rowList, tab._rowListHost
		local now = env.serverTime
		local function shownText()
			local out = {}
			local function walk(f)
				for _, r in ipairs({ f:GetRegions() }) do
					if r.GetText and r:IsVisible() and r:GetText() then out[#out + 1] = r:GetText() end
				end
				for _, c in ipairs({ f:GetChildren() }) do walk(c) end
			end
			walk(host)
			return table.concat(out, "\n")
		end
		-- A group row with a reagent: "[+]" on the name, and a mail button.
		rl:SetData({ { expiresAt = now, shortName = "Bob", charKey = MATE,
			cdName = "Transmutes", isGroup = true, isTransmuteGroup = true,
			spellId = 17187, reagentItemId = 12359, reagentQty = 1 } })
		local before = shownText()
		assert.is_truthy(before:find("[+] Transmutes", 1, true))
		assert.is_truthy(before:find("INV_Letter_15", 1, true))

		-- The same pooled row, now a plain cooldown with no reagent.
		rl:SetData({ { expiresAt = now, shortName = "Bob", charKey = MATE,
			cdName = "Salt Shaker", spellId = POTION } })
		local after = shownText()
		assert.is_truthy(after:find("Salt Shaker", 1, true))
		assert.is_nil(after:find("[+]", 1, true), "the group row's [+] survived")
		assert.is_nil(after:find("INV_Letter_15", 1, true), "the mail button survived")
	end)

	it("Missing Recipes lists what this character lacks", function()
		drawTwice(ns.MissingRecipesTab)
		assert.is_true(rowCount(ns.MissingRecipesTab._list) > 0)
	end)

	-- Missing Recipes' rows are a RowList parked in the result section.
	it("Missing Recipes hands its entries to the list, and its row tooltip carries the recipe block", function()
		local MR = ns.MissingRecipesTab
		ns.W:ClearDiagnostics()
		env.drawTab(MR)
		local rl = MR._rowList
		assert.is_truthy(rl)
		assert.equal(MR._list, rl.data)
		assert.is_true(MR._rowListHost:IsShown())

		local calls = {}
		local real = ns.ItemLink.AppendRecipeBlocks
		ns.ItemLink.AppendRecipeBlocks = function(_, profId, recipeId)
			calls[#calls + 1] = { profId = profId, recipeId = recipeId }
		end
		local entry = MR._list[1]
		local ok, err = pcall(rl.onRowEnter, entry, 1, rl, MR._rowListHost)
		ns.ItemLink.AppendRecipeBlocks = real
		assert.is_true(ok, err)
		assert.equal(1, #calls)
		assert.equal(entry.spellId, calls[1].recipeId)
		-- The single-profession view's entries carry no profId; the tooltip
		-- names the selected profession instead.
		assert.equal(ALCHEMY, calls[1].profId)
		local diag = ns.W:Diagnostics()
		assert.equal(0, #diag, diag[1] and diag[1].message)
	end)

	it("Missing Recipes sorts through its own SortList when a header is clicked", function()
		local MR = ns.MissingRecipesTab
		env.drawTab(MR)
		local btn = MR._rowList._headerLabels.skill.btn
		local before = MR._sortAsc
		btn:GetScript("OnClick")(btn)
		assert.equal("skill", MR._sortCol)
		assert.equal(not before, MR._sortAsc)
		assert.equal(MR._list, MR._rowList.data)
	end)

	it("Missing Recipes hides the list when a refresh ends on a hint", function()
		local MR = ns.MissingRecipesTab
		env.drawTab(MR)
		assert.is_true(MR._rowListHost:IsShown())
		MR._searchText = "no recipe is called this"
		MR:RefreshList()
		MR._searchText = nil
		assert.equal(0, #MR._list)
		assert.is_false(MR._rowListHost:IsShown())
	end)

	it("Guild counts the profession coverage", function()
		-- This tab lists every profession even at zero, so the evidence is the
		-- counts it computed, not how many rows it drew.
		drawTwice(ns.GuildTab)
		local list = ns.GuildTab:BuildCounts()
		local total = 0
		for _, e in ipairs(list) do total = total + (e.total or 0) end
		assert.is_true(total > 0)
	end)

	it("Profit Planner builds its rows", function()
		drawTwice(ns.AHProfitTab)
		assert.is_true(rowCount(ns.AHProfitTab._rows) > 0)
	end)

	-- The Profit Planner's rows are a LibAceGUIWidgets RowList, built once on a
	-- host the tab owns and parked in each draw's group.
	it("Profit Planner hands its rows to one list that outlives the redraw", function()
		local PT = ns.AHProfitTab
		-- drawTwice (above) draws this tab into one container twice without a
		-- release, which no window does; the second TabGroup gets no height
		-- and the list records that. Start this spec from a clean record.
		ns.W:ClearDiagnostics()
		env.drawTab(PT)
		local list, host = PT._list, PT._listHost
		assert.is_truthy(list)
		assert.equal(PT._rows, list.data)
		PT:RedrawCurrentTable()
		assert.equal(list, PT._list)
		assert.equal(host, PT._listHost)
		assert.equal(PT._rows, list.data)
		local diag = ns.W:Diagnostics()
		assert.equal(0, #diag, diag[1] and diag[1].message)
	end)

	it("Profit Planner sorts through its own SortRows when a header is clicked", function()
		local PT = ns.AHProfitTab
		env.drawTab(PT)
		local recipeHeader = PT._list._headerLabels.recipe.btn
		recipeHeader:GetScript("OnClick")(recipeHeader)
		assert.equal("recipe", PT._sortCol)
		assert.is_true(PT._sortAsc)
		recipeHeader:GetScript("OnClick")(recipeHeader)
		assert.is_false(PT._sortAsc)
		local data = PT._list.data
		for i = 2, #data do
			assert.is_true(data[i - 1].recipe:lower() >= data[i].recipe:lower())
		end
	end)

	it("Profit Planner gives its list host back to UIParent when the tab is released", function()
		local PT = ns.AHProfitTab
		local container = env.drawTab(PT)
		container:ReleaseChildren()
		assert.equal(UIParent, PT._listHost:GetParent())
		assert.is_false(PT._listHost:IsShown())
		assert.is_nil(PT._rows)
	end)

	it("Crafting builds against an open session", function()
		local crafting = env.tradeSkillSession("Alchemy", {
			{ name = "Alchemy", difficulty = "header" },
			{ name = "Healing Potion", available = 3,
			  reagents = { { name = "Peacebloom", need = 1, have = 5 } } },
		})
		assert.is_truthy(crafting)
		assert.is_true(ns.CraftingEngine:IsOpen())
		drawTwice(ns.CraftingTab)
		assert.is_true(env.countWidgets(ns.CraftingTab._container) > 1)
	end)
end)

describe("every tab survives an empty guild", function()
	-- The state a brand-new install is in, and the one most likely to hit an
	-- unguarded `#list` or a nil field.
	before_each(function()
		gdb = env.resetDb()
		env.setRecipeDB({})
		ns.lib.db.char.shoppingList = {}
	end)

	it("Professions (BrowserTab)", function()
		assert.has_no.errors(function() env.drawTab(ns.BrowserTab) end)
	end)

	it("Cooldowns", function()
		assert.has_no.errors(function() env.drawTab(ns.CooldownsTab) end)
	end)

	it("Missing Recipes", function()
		assert.has_no.errors(function() env.drawTab(ns.MissingRecipesTab) end)
	end)

	it("Guild", function()
		assert.has_no.errors(function() env.drawTab(ns.GuildTab) end)
	end)

	it("Profit Planner", function()
		assert.has_no.errors(function() env.drawTab(ns.AHProfitTab) end)
	end)

	it("Crafting", function()
		assert.has_no.errors(function() env.drawTab(ns.CraftingTab) end)
	end)
end)
