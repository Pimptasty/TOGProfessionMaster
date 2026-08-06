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

local ns, Ace, BT, frames, L
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
	frames = env.installFrames()
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

local function shownReagentRows(tab)
	local out = {}
	for _, rf in ipairs(tab._dpReagPool or {}) do
		if rf:IsShown() then out[#out + 1] = rf end
	end
	return out
end

local function shownCrafterRows(tab)
	local out = {}
	for _, cf in ipairs(tab._dpCraftPool or {}) do
		if cf:IsShown() then out[#out + 1] = cf end
	end
	return out
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

	it("falls back to the brand gold when the entry has no link at all", function()
		-- Trainer-taught recipes reach here with no link. Rendering them in
		-- whatever colour was left over from the last selection is the bug.
		local tab = panel()
		tab:DrawDetail(entryWith({ itemLink = nil }))
		assert.is_truthy(tab._dpName:GetText():find("|cffffd100", 1, true))
	end)

	it("hides the placeholder and shows the scroll frame", function()
		local tab = panel()
		tab:DrawDetail(entryWith())
		assert.is_false(tab._dpPH:IsShown())
		assert.is_true(tab._dpSF:IsShown())
	end)

	it("puts the placeholder back when the selection is cleared", function()
		local tab = panel()
		tab:DrawDetail(entryWith())
		tab:ClearDetail()
		assert.is_true(tab._dpPH:IsShown())
		assert.is_false(tab._dpSF:IsShown())
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
		assert.equal("Rough Stone", shownReagentRows(tab)[1].nameLbl:GetText())
	end)

	it("shows the recipe's own count when nothing is on the shopping list", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ reagents = { { name = "Rough Stone", itemId = COPPER, count = 4 } } }))
		assert.is_truthy(shownReagentRows(tab)[1].countLbl:GetText():find("4", 1, true))
	end)

	it("multiplies the count by the shopping-list quantity", function()
		-- This is the number the player actually shops from. 3 of a recipe that
		-- takes 4 stone is 12 stone, and getting it wrong sends them to the AH
		-- for the wrong amount without ever looking wrong on screen.
		local tab = panel()
		local entry = entryWith({ reagents = { { name = "Rough Stone", itemId = COPPER, count = 4 } } })
		Ace.db.char.shoppingList[entry.id] = { name = entry.name, quantity = 3 }
		tab:DrawDetail(entry)
		assert.is_truthy(shownReagentRows(tab)[1].countLbl:GetText():find("12", 1, true))
	end)

	it("does not multiply by zero for a recipe that is not on the list", function()
		local tab = panel()
		local entry = entryWith({ reagents = { { name = "Rough Stone", itemId = COPPER, count = 4 } } })
		Ace.db.char.shoppingList[entry.id] = { name = entry.name, quantity = 0 }
		tab:DrawDetail(entry)
		assert.is_truthy(shownReagentRows(tab)[1].countLbl:GetText():find("4", 1, true))
	end)

	it("hides the reagent header entirely for a recipe with none", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ reagents = {} }))
		assert.is_false(tab._dpReagHdr:IsShown())
		assert.equal(0, #shownReagentRows(tab))
	end)

	it("shows the header again for the next recipe that does have reagents", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ reagents = {} }))
		tab:DrawDetail(entryWith())
		assert.is_true(tab._dpReagHdr:IsShown())
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
		assert.is_truthy(shownReagentRows(tab)[1].countLbl:GetText():find("4", 1, true))
	end)
end)

describe("the Known By list", function()
	it("says so plainly when nobody is known to craft it", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {} }))
		local rows = shownCrafterRows(tab)
		assert.equal(1, #rows)
		assert.is_truthy(rows[1].lbl:GetText():find(L["NoDataYet"], 1, true))
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
		local you = shownCrafterRows(tab)[1].lbl:GetText()
		assert.is_truthy(you:find("|c" .. (ns.ColorYou or ns.BrandColor or "ffDA8CFF"), 1, true))
	end)

	it("shades an offline crafter differently from an online one", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob", charKey = MATE, online = false },
		} }))
		local offline = shownCrafterRows(tab)[1].lbl:GetText()
		assert.is_truthy(offline:find("|c" .. (ns.ColorOffline or "ffaaaaaa"), 1, true))

		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob", charKey = MATE, online = true },
		} }))
		local online = shownCrafterRows(tab)[1].lbl:GetText()
		assert.is_nil(online:find("|c" .. (ns.ColorOffline or "ffaaaaaa"), 1, true))
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

	it("leaves your own row unclickable — there is nobody to whisper", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Testchar", charKey = ME, online = true, isYou = true },
		} }))
		assert.is_nil(shownCrafterRows(tab)[1]:GetScript("OnClick"))
	end)

	it("makes a guildmate's row right-clickable to whisper", function()
		local tab = panel()
		tab:DrawDetail(entryWith({ crafters = {
			{ name = "Bob", charKey = MATE, online = true },
		} }))
		assert.is_truthy(shownCrafterRows(tab)[1]:GetScript("OnClick"))
	end)
end)
