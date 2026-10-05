-- The recipe detail panel — what you get after clicking a recipe in the browser.
--
-- ~500 lines across DrawDetail, EnsureDetailPanel and the two row builders, none
-- of which had ever run outside the game. It is also the only place in the addon
-- where the shopping list is edited by hand, and the reagent counts shown here
-- are what the player shops from: get the multiplier wrong and they buy the
-- wrong amount of everything.
--
-- Each test drives a FRESH tab table (`setmetatable({}, {__index = BrowserTab})`)
-- so the pooled detail frames and the selection state cannot leak between tests
-- or into the specs that drive the real shared tab.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Ace, BT, L
local ME   = "Testchar-Testrealm"
local MATE = "Bob-Testrealm"

local COPPER, TIN = 2840, 3576

setup(function()
	ns = env.initDb()
	Ace = ns.lib
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/BrowserTab.lua")
	BT = ns.BrowserTab
	L  = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.roster({
		{ name = "Testchar", isOnline = true },
		{ name = "Bob",      isOnline = true },
	})
	env.setRecipeDB({})
	Ace.db.char.shoppingList = {}
end)

--- A detail panel with nothing selected yet. No container, so EnsureDetailPanel
--- parents to UIParent — which is the documented fallback, not a shortcut.
local function panel()
	return setmetatable({}, { __index = BT })
end

local function entryWith(fields)
	local e = {
		id = 3320, name = "Rough Sharpening Stone", icon = 135247,
		reagents = { { name = "Rough Stone", itemId = COPPER, count = 1 } },
		crafters = {},
	}
	for k, v in pairs(fields or {}) do e[k] = v end
	return e
end

-- The reagents / Known By list is a library RowList (tab._dpList). These read
-- its rows and the text its columns draw for them -- what the player sees.
local function rowsWhere(tab, pred)
	local out = {}
	for _, e in ipairs(tab._dpList and tab._dpList.data or {}) do
		if pred(e) then out[#out + 1] = e end
	end
	return out
end

local function shownReagentRows(tab)
	return rowsWhere(tab, function(e) return e.kind == "reagent" end)
end

-- A crafter row, or the one "no data yet" row that stands in for none.
local function shownCrafterRows(tab)
	return rowsWhere(tab, function(e) return e.kind == "crafter" or e.kind == "none" end)
end

local function cell(tab, key, e)
	for _, col in ipairs(tab._dpList.columns) do
		if col.key == key then return col.format(nil, e) end
	end
	error("no column " .. key)
end

local function hasHeading(tab, text)
	return #rowsWhere(tab, function(e) return e._header == text end) == 1
end

-- Right-click a row the way the list does, and report who was whispered.
local function rightClick(tab, e)
	local whispered
	local savedMenu, savedWhisper = _G.Menu, ns.UI.OpenWhisper
	_G.Menu = nil
	ns.UI.OpenWhisper = function(who) whispered = who end
	tab._dpList.onRowClick(e, 1, tab._dpList, "RightButton", UIParent)
	_G.Menu, ns.UI.OpenWhisper = savedMenu, savedWhisper
	return whispered
end

-- ---------------------------------------------------------------------------

describe("the header", function()
	it("shows the recipe's name", function()
		local tab = panel()
		tab:DrawDetail(entryWith())
		assert.is_truthy(tab._dpName:GetText():find("Rough Sharpening Stone", 1, true))
	end)

	it("takes its colour from the item link's quality", function()
		-- A green recipe must not render in the same colour as a white one; the
		-- colour is carried in the link, not stored separately.
		local tab = panel()
		tab:DrawDetail(entryWith({ itemLink = "|cff1eff00|Hitem:3320::::::::|h[Stone]|h|r" }))
		assert.is_truthy(tab._dpName:GetText():find("|cff1eff00", 1, true))
	end)

	-- WoW Forever: a recipe shown only on a borrowed never-implemented flag
	-- keeps its "(unconfirmed)" when selected, as its row has it.
	it("marks an unconfirmed recipe, and only that one", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ unconfirmed = true }))
		assert.is_truthy(tab._dpName:GetText():find("(" .. ns.UnconfirmedText() .. ")", 1, true))
		tab:DrawDetail(entryWith())
		assert.is_nil(tab._dpName:GetText():find(ns.UnconfirmedText(), 1, true))
	end)

	it("falls back to the brand gold when the entry has no link at all", function()
		-- Trainer-taught recipes reach here with no link. Rendering them in
		-- whatever colour was left over from the last selection is the bug.
		local tab = panel()
		tab:DrawDetail(entryWith({ itemLink = nil }))
		assert.is_truthy(tab._dpName:GetText():find("|cffffd100", 1, true))
	end)

	it("hides the placeholder and shows the panel's body", function()
		local tab = panel()
		tab:DrawDetail(entryWith())
		assert.is_false(tab._dpPH:IsShown())
		assert.is_true(tab._dpBody:IsShown())
	end)

	it("puts the placeholder back when the selection is cleared", function()
		local tab = panel()
		tab:DrawDetail(entryWith())
		tab:ClearDetail()
		assert.is_true(tab._dpPH:IsShown())
		assert.is_false(tab._dpBody:IsShown())
		assert.is_nil(tab._selectedEntry)
	end)
end)

describe("the reagent rows", function()
	it("draws one row per reagent", function()
		local tab = panel()
		tab:DrawDetail(entryWith({
			reagents = {
				{ name = "Rough Stone",  itemId = COPPER, count = 1 },
				{ name = "Coarse Stone", itemId = TIN,    count = 2 },
			},
		}))
		assert.equal(2, #shownReagentRows(tab))
	end)

	it("hides the rows a shorter recipe no longer needs", function()
		-- The pool is reused across selections. A three-reagent recipe followed
		-- by a one-reagent recipe must not leave two stale rows on screen.
		local tab = panel()
		tab:DrawDetail(entryWith({
			reagents = {
				{ name = "A", itemId = COPPER, count = 1 },
				{ name = "B", itemId = TIN,    count = 1 },
				{ name = "C", itemId = 2841,   count = 1 },
			},
		}))
		assert.equal(3, #shownReagentRows(tab))
		tab:DrawDetail(entryWith({ reagents = { { name = "A", itemId = COPPER, count = 1 } } }))
		assert.equal(1, #shownReagentRows(tab))
	end)

	it("names each reagent", function()
		local tab = panel()
		tab:DrawDetail(entryWith())
		assert.equal("Rough Stone", cell(tab, "name", shownReagentRows(tab)[1]))
	end)

	it("shows the recipe's own count when nothing is on the shopping list", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ reagents = { { name = "Rough Stone", itemId = COPPER, count = 4 } } }))
		assert.is_truthy(cell(tab, "count", shownReagentRows(tab)[1]):find("4", 1, true))
	end)

	it("multiplies the count by the shopping-list quantity", function()
		-- This is the number the player actually shops from. 3 of a recipe that
		-- takes 4 stone is 12 stone, and getting it wrong sends them to the AH
		-- for the wrong amount without ever looking wrong on screen.
		local tab = panel()
		local entry = entryWith({ reagents = { { name = "Rough Stone", itemId = COPPER, count = 4 } } })
		Ace.db.char.shoppingList[entry.id] = { name = entry.name, quantity = 3 }
		tab:DrawDetail(entry)
		assert.is_truthy(cell(tab, "count", shownReagentRows(tab)[1]):find("12", 1, true))
	end)

	it("does not multiply by zero for a recipe that is not on the list", function()
		local tab = panel()
		local entry = entryWith({ reagents = { { name = "Rough Stone", itemId = COPPER, count = 4 } } })
		Ace.db.char.shoppingList[entry.id] = { name = entry.name, quantity = 0 }
		tab:DrawDetail(entry)
		assert.is_truthy(cell(tab, "count", shownReagentRows(tab)[1]):find("4", 1, true))
	end)

	it("hides the reagent header entirely for a recipe with none", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ reagents = {} }))
		assert.is_false(hasHeading(tab, "Reagents"))
		assert.is_true(hasHeading(tab, "Known By"))
		assert.equal(0, #shownReagentRows(tab))
	end)

	it("shows the header again for the next recipe that does have reagents", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ reagents = {} }))
		tab:DrawDetail(entryWith())
		assert.is_true(hasHeading(tab, "Reagents"))
	end)

	it("lists the reagents under their heading, before Known By", function()
		local tab = panel()
		tab:DrawDetail(entryWith())
		local data = tab._dpList.data
		assert.equal("Reagents", data[1]._header)
		assert.equal("reagent", data[2].kind)
		assert.equal("Known By", data[3]._header)
	end)
end)

describe("the shopping-list controls", function()
	it("starts at zero for a recipe that is not on the list", function()
		local tab = panel()
		tab:DrawDetail(entryWith())
		assert.equal("0", tab._dpQty:GetText())
	end)

	it("adds the recipe at one on the first plus", function()
		local tab = panel()
		local entry = entryWith()
		tab:DrawDetail(entry)
		tab._dpPlus:GetScript("OnClick")(tab._dpPlus)
		assert.equal(1, Ace.db.char.shoppingList[entry.id].quantity)
		assert.equal("1", tab._dpQty:GetText())
	end)

	it("carries the recipe's name and reagents onto the list, not just a count", function()
		-- The shopping list tab renders from its OWN copy — an entry added with
		-- only a quantity shows up there as a nameless row with no reagents.
		local tab = panel()
		local entry = entryWith()
		tab:DrawDetail(entry)
		tab._dpPlus:GetScript("OnClick")(tab._dpPlus)
		local saved = Ace.db.char.shoppingList[entry.id]
		assert.equal("Rough Sharpening Stone", saved.name)
		assert.is_truthy(saved.reagents)
	end)

	it("increments an entry that is already there", function()
		local tab = panel()
		local entry = entryWith()
		tab:DrawDetail(entry)
		tab._dpPlus:GetScript("OnClick")(tab._dpPlus)
		tab._dpPlus:GetScript("OnClick")(tab._dpPlus)
		assert.equal(2, Ace.db.char.shoppingList[entry.id].quantity)
	end)

	it("decrements on minus", function()
		local tab = panel()
		local entry = entryWith()
		Ace.db.char.shoppingList[entry.id] = { name = entry.name, quantity = 3 }
		tab:DrawDetail(entry)
		tab._dpMinus:GetScript("OnClick")(tab._dpMinus)
		assert.equal(2, Ace.db.char.shoppingList[entry.id].quantity)
	end)

	it("drops the entry off the list rather than leaving it at zero", function()
		-- A zero-quantity entry would render as a row on the shopping list tab
		-- asking the player to buy nothing.
		local tab = panel()
		local entry = entryWith()
		Ace.db.char.shoppingList[entry.id] = { name = entry.name, quantity = 1 }
		tab:DrawDetail(entry)
		tab._dpMinus:GetScript("OnClick")(tab._dpMinus)
		assert.is_nil(Ace.db.char.shoppingList[entry.id])
	end)

	it("does nothing on minus when the recipe was never on the list", function()
		local tab = panel()
		local entry = entryWith()
		tab:DrawDetail(entry)
		assert.has_no.errors(function() tab._dpMinus:GetScript("OnClick")(tab._dpMinus) end)
		assert.is_nil(Ace.db.char.shoppingList[entry.id])
	end)

	it("removes the whole entry however large the quantity", function()
		local tab = panel()
		local entry = entryWith()
		Ace.db.char.shoppingList[entry.id] = { name = entry.name, quantity = 40 }
		tab:DrawDetail(entry)
		tab._dpRemove:GetScript("OnClick")(tab._dpRemove)
		assert.is_nil(Ace.db.char.shoppingList[entry.id])
		assert.equal("0", tab._dpQty:GetText())
	end)

	it("restates the reagent counts as the quantity changes", function()
		-- The counts on screen have to follow the +/- buttons, or the player is
		-- shopping from a stale figure.
		local tab = panel()
		local entry = entryWith({ reagents = { { name = "Rough Stone", itemId = COPPER, count = 2 } } })
		tab:DrawDetail(entry)
		tab._dpPlus:GetScript("OnClick")(tab._dpPlus)
		tab._dpPlus:GetScript("OnClick")(tab._dpPlus)
		assert.is_truthy(cell(tab, "count", shownReagentRows(tab)[1]):find("4", 1, true))
	end)
end)

describe("the Known By list", function()
	it("says so plainly when nobody is known to craft it", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {} }))
		local rows = shownCrafterRows(tab)
		assert.equal(1, #rows)
		assert.is_truthy(cell(tab, "name", rows[1]):find(L["NoDataYet"], 1, true))
	end)

	it("lists every crafter", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob",      charKey = MATE, online = true },
			{ name = "Testchar", charKey = ME,   online = true, isYou = true },
		} }))
		assert.equal(2, #shownCrafterRows(tab))
	end)

	it("colours your own character differently from a guildmate", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Testchar", charKey = ME, online = true, isYou = true },
		} }))
		local you = cell(tab, "name", shownCrafterRows(tab)[1])
		assert.is_truthy(you:find("|c" .. (ns.ColorYou or ns.BrandColor or "ffDA8CFF"), 1, true))
	end)

	it("shades an offline crafter differently from an online one", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob", charKey = MATE, online = false },
		} }))
		local offline = cell(tab, "name", shownCrafterRows(tab)[1])
		assert.is_truthy(offline:find("|c" .. (ns.ColorOffline or "ffaaaaaa"), 1, true))

		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob", charKey = MATE, online = true },
		} }))
		local online = cell(tab, "name", shownCrafterRows(tab)[1])
		assert.is_nil(online:find("|c" .. (ns.ColorOffline or "ffaaaaaa"), 1, true))
	end)

	it("whispers a guildmate on a right-click, and nobody for your own row", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob",      charKey = MATE, online = true },
			{ name = "Testchar", charKey = ME,   online = true, isYou = true },
		} }))
		local whispered = {}
		local savedMenu, savedWhisper = _G.Menu, ns.UI.OpenWhisper
		_G.Menu = nil
		ns.UI.OpenWhisper = function(who) whispered[#whispered + 1] = who end
		for _, e in ipairs(shownCrafterRows(tab)) do
			tab._dpList.onRowClick(e, 1, tab._dpList, "RightButton", UIParent)
			tab._dpList.onRowClick(e, 1, tab._dpList, "LeftButton", UIParent)
		end
		_G.Menu, ns.UI.OpenWhisper = savedMenu, savedWhisper
		assert.same({ MATE }, whispered)
	end)

	it("hides the crafters a shorter list no longer needs", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob",  charKey = MATE, online = true },
			{ name = "Carl", charKey = "Carl-Testrealm", online = true },
			{ name = "Dave", charKey = "Dave-Testrealm", online = false },
		} }))
		assert.equal(3, #shownCrafterRows(tab))
		tab:DrawDetail(entryWith({ crafters = { { name = "Bob", charKey = MATE, online = true } } }))
		assert.equal(1, #shownCrafterRows(tab))
	end)

	it("does nothing on a right-click of your own row -- there is nobody to whisper", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Testchar", charKey = ME, online = true, isYou = true },
		} }))
		assert.is_nil(rightClick(tab, shownCrafterRows(tab)[1]))
	end)

	it("whispers a guildmate on a right-click of their row", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob", charKey = MATE, online = true },
		} }))
		assert.equal(MATE, rightClick(tab, shownCrafterRows(tab)[1]))
	end)
end)

-- Reported in game 2026-09-11: Devilsaur Gauntlets drew "Rugged Leather",
-- "Rune Thread" and "Item #15417" -- with Devilsaur Leather's REAL icon beside
-- the placeholder. These drive the whole path the screenshot came from: the
-- reagent table built by the real addon:GetRecipeReagents while the item cache
-- is cold, then drawn by the real DrawDetail, then read back off the fontstring
-- a player would see. reagentname_spec pins the resolver; this pins that the
-- panel actually calls it.
describe("a reagent the client had not cached when the list was built", function()
	local PROF, SPELL = 165, 23799            -- Leatherworking, Devilsaur Gauntlets
	local DEVILSAUR, RUGGED = 15417, 8170
	local LINK = "|cffffffff|Hitem:15417::::::::60:::::|h[Devilsaur Leather]|h|r"
	local savedIdb

	local function itemDB(names)
		return {
			GetName = function(_, id) return names[id] end,
			GetLink = function(_, id) return names[id] and ("|Hitem:" .. id .. "|h[" .. names[id] .. "]|h") or nil end,
		}
	end

	--- The entry exactly as the browser builds it: reagents from the real
	--- accessor, against whatever the cache and LibItemDB hold RIGHT NOW.
	local function gauntlets()
		return entryWith({ id = SPELL, profId = PROF, name = "Devilsaur Gauntlets",
		                   reagents = ns:GetRecipeReagents(PROF, SPELL) })
	end

	--- The reagent names on screen, as a set. Order is pairs()-order from the
	--- recipe DB, so a spec asks "is this name drawn" rather than "is it first".
	local function drawnNames(tab)
		local out = {}
		for _, e in ipairs(shownReagentRows(tab)) do out[cell(tab, "name", e)] = true end
		return out
	end

	before_each(function()
		savedIdb = ns._itemDB
		ns._itemDB = false
		env.setRecipeDB({
			[PROF] = { [SPELL] = { name = "Devilsaur Gauntlets",
			                       reagents = { [DEVILSAUR] = 8, [RUGGED] = 30 } } },
		})
		-- Rugged Leather is cached, Devilsaur Leather is not -- the report's shape.
		env.wow.items[RUGGED] = { name = "Rugged Leather", link = "|Hitem:8170|h[Rugged Leather]|h" }
	end)

	after_each(function()
		ns._itemDB = savedIdb
	end)

	it("REPRODUCES the report without LibItemDB: cold at build, drawn as a number", function()
		local tab = panel()
		tab:DrawDetail(gauntlets())
		local names = drawnNames(tab)
		assert.is_true(names["Rugged Leather"])
		assert.is_true(names["Item #15417"])
	end)

	it("draws LibItemDB's name instead of the number when the cache is cold", function()
		ns._itemDB = itemDB({ [DEVILSAUR] = "Devilsaur Leather" })
		local tab = panel()
		tab:DrawDetail(gauntlets())
		local names = drawnNames(tab)
		assert.is_true(names["Rugged Leather"])
		assert.is_true(names["Devilsaur Leather"])
		assert.is_nil(names["Item #15417"])
	end)

	it("heals on the next draw once the cache is warm, and heals the entry the shopping list would save", function()
		local tab = panel()
		local entry = gauntlets()                       -- built cold: placeholder inside
		tab:DrawDetail(entry)
		assert.is_true(drawnNames(tab)["Item #15417"])

		env.wow.items[DEVILSAUR] = { name = "Devilsaur Leather", link = LINK }
		tab:DrawDetail(entry)                           -- same table, redrawn warm
		local names = drawnNames(tab)
		assert.is_true(names["Devilsaur Leather"])
		assert.is_nil(names["Item #15417"])

		-- This is the table the + button copies into Ace.db.char.shoppingList.
		-- Before the fix it carried the placeholder to disk.
		local saved
		for _, r in ipairs(entry.reagents) do if r.itemId == DEVILSAUR then saved = r end end
		assert.equal("Devilsaur Leather", saved.name)
		assert.equal(LINK, saved.itemLink)
	end)

	it("heals a placeholder already sitting in the shopping-list SavedVariable", function()
		-- Data written by a build BEFORE this fix: the placeholder is on disk with
		-- no flag saying so. The expanded reagent row in the shopping-list
		-- section must still draw the real name once anything can resolve it.
		ns._itemDB = itemDB({ [DEVILSAUR] = "Devilsaur Leather" })
		Ace.db.char.shoppingList[SPELL] = {
			name = "Devilsaur Gauntlets", quantity = 1,
			reagents = { { itemId = DEVILSAUR, count = 8, name = "Item #15417" } },
		}
		local tab = panel()
		tab._slExpanded = { [SPELL] = true }
		-- The AceGUI container: the list parks in .content, and the fill sets
		-- the widget's height.
		tab:FillShoppingListSection({ content = CreateFrame("Frame", nil, UIParent),
		                              SetHeight = function() end })
		local rl, reagentRow = tab._slList, nil
		for _, row in ipairs(rl.data) do
			if row.kind == "reagent" then reagentRow = row end
		end
		assert.is_truthy(reagentRow, "the expanded recipe drew no reagent row")
		local nameCol
		for _, col in ipairs(rl.columns) do if col.key == "name" then nameCol = col end end
		assert.equal("Devilsaur Leather", nameCol.format(nil, reagentRow))
		assert.equal("Devilsaur Leather", Ace.db.char.shoppingList[SPELL].reagents[1].name)
	end)
end)

-- Reported on Discord 2026-08-28, reproduced with ElvUI off: six Shadoweave
-- recipes on the shopping list, all expanded, and the section drew every row at
-- full height -- taller than the tab, so the column headers and the recipe
-- list were pushed below the window's bottom edge. The section is now capped
-- at a share of the tab's height and scrolls inside itself.
describe("the shopping-list section against a window it would overflow", function()
	local ROW = 14
	local TAB_H = 300                         -- the tab container's live height
	local CAP = math.floor(TAB_H * 0.4)       -- what the section may show

	--- A tab whose container has a real height, and a section widget that
	--- records the height the fill gives it and passes it on to its content,
	--- less the 40 px of InlineGroup chrome -- the InlineGroup's role.
	local function tabAndSection()
		local tab = panel()
		local cont = CreateFrame("Frame", nil, UIParent)
		cont:SetHeight(TAB_H)
		tab._container = { frame = cont }
		local content = CreateFrame("Frame", nil, UIParent)
		content:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
		content:SetSize(500, 100)
		local section = { content = content, height = nil }
		function section:SetHeight(h)
			self.height = h
			self.content:SetHeight(h - 40)
		end
		return tab, section
	end

	-- The list's rows, the rows it has room to draw, and how far it scrolls.
	local function listState(tab)
		local rl = tab._slList
		local _, maxScroll = rl.scrollbar:GetMinMaxValues()
		return #rl.data, rl.visibleRowCount, maxScroll
	end
	local CAP_ROWS = math.floor(CAP / ROW)    -- whole rows only

	--- N recipes, each with `reagents` reagents, every one expanded.
	local function listOf(n, reagents)
		Ace.db.char.shoppingList = {}
		local expanded = {}
		for i = 1, n do
			local rs = {}
			for j = 1, reagents do rs[j] = { itemId = 1000 + j, count = j, name = "Reagent " .. j } end
			Ace.db.char.shoppingList[100 + i] = { name = ("Shadoweave %02d"):format(i), quantity = 1, reagents = rs }
			expanded[100 + i] = true
		end
		return expanded
	end

	it("REPRODUCES the report's row count and keeps the section inside the cap", function()
		local tab, section = tabAndSection()
		tab._slExpanded = listOf(6, 4)                 -- 6 headers + 24 reagent rows
		tab:FillShoppingListSection(section)
		local rows = 6 + 24
		local data, visible, maxScroll = listState(tab)
		assert.equal(rows, data)                               -- every row still exists...
		assert.equal(CAP_ROWS * ROW + 40, section.height)      -- ...but the section is capped
		assert.equal(CAP_ROWS, visible)
		assert.is_true(tab._slList.scrollbar:IsShown())
		assert.equal(rows - CAP_ROWS, maxScroll)
	end)

	it("does not reserve a scrollbar or cap a list that fits", function()
		local tab, section = tabAndSection()
		tab._slExpanded = listOf(2, 1)                 -- 4 rows
		tab:FillShoppingListSection(section)
		assert.equal(4 * ROW + 40, section.height)
		local _, visible, maxScroll = listState(tab)
		assert.equal(4, visible)
		assert.is_false(tab._slList.scrollbar:IsShown())
		assert.equal(0, maxScroll)
	end)

	it("scrolls the rows and clamps when the list shrinks", function()
		local tab, section = tabAndSection()
		tab._slExpanded = listOf(6, 4)
		tab:FillShoppingListSection(section)
		tab._slList:SetScrollOffset(5)
		assert.equal(5, tab._slList:GetScrollOffset())

		-- Collapse everything: 6 rows fit, so the offset must come back to 0
		-- rather than leave the rows scrolled out of an unscrollable section.
		tab._slExpanded = {}
		tab:FillShoppingListSection(section)
		assert.equal(0, tab._slList:GetScrollOffset())
		assert.is_false(tab._slList.scrollbar:IsShown())
	end)

	it("keeps the player's place when a row is added", function()
		-- Every [+] / [-] / toggle refills the list; a refill that jumped to the
		-- top would lose the row the player just clicked.
		local tab, section = tabAndSection()
		tab._slExpanded = listOf(6, 4)
		tab:FillShoppingListSection(section)
		tab._slList:SetScrollOffset(5)
		tab:FillShoppingListSection(section)
		assert.equal(5, tab._slList:GetScrollOffset())
	end)

	it("draws whole rows only, as many as the cap has room for", function()
		-- The cap is a share of the tab's height, which is rarely a multiple of
		-- a row; a section sized to it exactly would cut the last row in half.
		local tab, section = tabAndSection()
		tab._slExpanded = listOf(6, 4)
		tab:FillShoppingListSection(section)
		local _, visible = listState(tab)
		assert.equal(CAP_ROWS, visible)
		assert.equal(0, (section.height - 40) % ROW)
	end)

	it("falls back to a fixed row count before the tab has a height", function()
		local tab = panel()                            -- no _container at all
		assert.equal(ROW * 10, tab:ShoppingListMaxHeight())
	end)

	it("detaches the list from the pooled section on release", function()
		-- A real InlineGroup: the hand-back rides AceGUI's own release.
		local AceGUI = LibStub("AceGUI-3.0")
		local tab = tabAndSection()
		local section = AceGUI:Create("InlineGroup")
		tab._slExpanded = listOf(2, 1)
		tab:FillShoppingListSection(section)
		assert.equal(section.content, tab._slListHost:GetParent())
		AceGUI:Release(section)
		assert.equal(UIParent, tab._slListHost:GetParent())
		assert.is_false(tab._slListHost:IsShown())
	end)
end)
