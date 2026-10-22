-- Shopping list sharing: the export text, and the import that merges it.
--
-- Asked for on Discord 2026-10-21 by a player on three paid accounts who wants
-- one shopping list any of their characters can search the AH with. The rules
-- pinned here are the ones the player relies on without seeing them:
--   * only recipe ids and counts travel; everything else is rebuilt from the
--     addon's own recipe data (operator, 2026-10-21);
--   * importing ADDS to the list and never replaces it;
--   * importing the same list twice, or your own list back, changes nothing;
--   * a list exported, deleted and imported back on one character returns whole;
--   * every entry remembers which other character wants how many;
--   * the text survives being pasted through a chat client (wrapped lines);
--   * anything another player wrote is checked and clamped, never trusted.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Ace, BT, L
local ME  = "Testchar-Testrealm"
local ALT = "Altie-Otherrealm"

local LW          = 165      -- Leatherworking
local GAUNTLETS   = 19083    -- a recipe spell id this client has
local STONE       = 3320
local RUGGED      = 8170

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

local realKey

before_each(function()
	env.installFrames()
	env.resetDb()
	-- These recipes exist on the simulated client; 999999 does not, which is
	-- what "not on this game version" means to the client gate.
	env.spellsExist(GAUNTLETS, STONE)
	env.setRecipeDB({
		[LW] = {
			[GAUNTLETS] = { name = "Runic Leather Gauntlets", reagents = { [RUGGED] = 8 } },
			[STONE]     = { name = "Rough Sharpening Stone",  reagents = { [2835] = 1 } },
		},
	})
	Ace.db.char.shoppingList = {}
	realKey = ns.GetCharacterKey
end)

after_each(function()
	ns.GetCharacterKey = realKey
end)

--- Run `fn` as another character: the export or import sees that key as "me".
local function as(key, fn)
	ns.GetCharacterKey = function() return key end
	local ok, err = pcall(fn)
	ns.GetCharacterKey = realKey
	assert(ok, err)
end

local function list() return Ace.db.char.shoppingList end

local function gauntlets(qty)
	return { name = "Runic Leather Gauntlets", quantity = qty,
	         reagents = { { name = "Rugged Leather", itemId = RUGGED, count = 8 } } }
end

describe("ExportShoppingList", function()
	it("returns nothing for an empty list", function()
		assert.is_nil(BT.ExportShoppingList())
	end)

	it("carries only recipe ids and who wants how many", function()
		list()[GAUNTLETS] = gauntlets(2)
		list()[STONE] = { name = "Rough Sharpening Stone", quantity = 3, wantedBy = { [ALT] = 1 } }
		assert.equal(BT.SHARE_PREFIX .. "3320:Altie-Otherrealm=1,Testchar-Testrealm=2;19083:Testchar-Testrealm=2",
			BT.ExportShoppingList())
	end)

	it("holds no Discord markup character", function()
		list()[GAUNTLETS] = gauntlets(2)
		assert.is_nil(BT.ExportShoppingList():find("[%*_~`|]"))
	end)
end)

describe("ImportShoppingList", function()
	it("rebuilds the entry from the addon's own recipe data", function()
		local added, updated, skipped = BT.ImportShoppingList(BT.SHARE_PREFIX .. GAUNTLETS .. ":" .. ALT .. "=2")
		assert.equal(1, added)
		assert.equal(0, updated)
		assert.equal(0, skipped)
		local ent = list()[GAUNTLETS]
		assert.equal("Runic Leather Gauntlets", ent.name)
		assert.equal(2, ent.quantity)
		assert.same({ [ALT] = 2 }, ent.wantedBy)
		assert.equal(1, #ent.reagents)
		assert.equal(RUGGED, ent.reagents[1].itemId)
		assert.equal(8, ent.reagents[1].count)
	end)

	it("round-trips a list from one character to another", function()
		list()[GAUNTLETS] = gauntlets(2)
		local text = BT.ExportShoppingList()
		Ace.db.char.shoppingList = {}
		as(ALT, function()
			assert.equal(1, (BT.ImportShoppingList(text)))
		end)
		assert.equal(2, list()[GAUNTLETS].quantity)
		assert.equal(2, list()[GAUNTLETS].wantedBy[ME])
	end)

	it("skips, and counts, a recipe this game version does not have", function()
		local added, updated, skipped = BT.ImportShoppingList(
			BT.SHARE_PREFIX .. "999999:" .. ALT .. "=1;" .. STONE .. ":" .. ALT .. "=1")
		assert.equal(1, added)
		assert.equal(0, updated)
		assert.equal(1, skipped)
		assert.is_nil(list()[999999])
	end)

	it("adds to the list and never replaces what is already on it", function()
		list()[GAUNTLETS] = gauntlets(2)
		local text = BT.ExportShoppingList()

		as(ALT, function()
			Ace.db.char.shoppingList = {
				[GAUNTLETS] = gauntlets(1),
				[STONE]     = { name = "Rough Sharpening Stone", quantity = 4 },
			}
			local added, updated = BT.ImportShoppingList(text)
			assert.equal(0, added)
			assert.equal(1, updated)
		end)
		assert.equal(3, list()[GAUNTLETS].quantity, "1 of my own + 2 for the exporter")
		assert.equal(4, list()[STONE].quantity, "an entry the import did not name is untouched")
	end)

	it("changes nothing when the same list is imported twice", function()
		list()[GAUNTLETS] = gauntlets(2)
		local text = BT.ExportShoppingList()
		Ace.db.char.shoppingList = {}

		as(ALT, function()
			BT.ImportShoppingList(text)
			local added, updated = BT.ImportShoppingList(text)
			assert.equal(0, added)
			assert.equal(0, updated)
		end)
		assert.equal(2, list()[GAUNTLETS].quantity)
	end)

	it("replaces a character's share when their list changed, rather than adding again", function()
		list()[GAUNTLETS] = gauntlets(2)
		local first = BT.ExportShoppingList()
		list()[GAUNTLETS].quantity = 5
		local second = BT.ExportShoppingList()
		Ace.db.char.shoppingList = {}

		as(ALT, function()
			BT.ImportShoppingList(first)
			local added, updated = BT.ImportShoppingList(second)
			assert.equal(0, added)
			assert.equal(1, updated)
		end)
		assert.equal(5, list()[GAUNTLETS].quantity)
		assert.equal(5, list()[GAUNTLETS].wantedBy[ME])
	end)

	it("is a no-op when a character imports their own list back", function()
		list()[GAUNTLETS] = gauntlets(2)
		local added, updated = BT.ImportShoppingList(BT.ExportShoppingList())
		assert.equal(0, added)
		assert.equal(0, updated)
		assert.equal(2, list()[GAUNTLETS].quantity)
		assert.is_nil(list()[GAUNTLETS].wantedBy)
	end)

	-- The operator's in-game report, 2026-10-21: "i created a list on player a,
	-- copied it, then deleted the list. i then pasted it in and tried to import
	-- it, but the import didn't add anything to my list."
	it("restores a character's own list exported, deleted and imported back", function()
		list()[GAUNTLETS] = gauntlets(2)
		list()[STONE] = { name = "Rough Sharpening Stone", quantity = 3, wantedBy = { [ALT] = 1 } }
		local text = BT.ExportShoppingList()
		Ace.db.char.shoppingList = {}

		local added, updated = BT.ImportShoppingList(text)
		assert.equal(2, added)
		assert.equal(0, updated)
		assert.equal(2, list()[GAUNTLETS].quantity)
		assert.is_nil(list()[GAUNTLETS].wantedBy, "my own share is not listed as someone else's")
		assert.equal(3, list()[STONE].quantity, "1 for the alt + 2 of my own")
		assert.same({ [ALT] = 1 }, list()[STONE].wantedBy)
		assert.equal("Runic Leather Gauntlets", list()[GAUNTLETS].name)
	end)

	it("raises my own count to the imported one, never lowers it", function()
		list()[GAUNTLETS] = gauntlets(4)
		local text = BT.ExportShoppingList()
		list()[GAUNTLETS].quantity = 1
		local _, updated = BT.ImportShoppingList(text)
		assert.equal(1, updated)
		assert.equal(4, list()[GAUNTLETS].quantity)

		list()[GAUNTLETS].quantity = 6
		_, updated = BT.ImportShoppingList(text)
		assert.equal(0, updated)
		assert.equal(6, list()[GAUNTLETS].quantity)
	end)

	it("passes everyone's share along a chain of accounts, never crediting it to the middle one", function()
		list()[GAUNTLETS] = gauntlets(2)
		local fromMe = BT.ExportShoppingList()
		local fromAlt
		as(ALT, function()
			Ace.db.char.shoppingList = { [GAUNTLETS] = gauntlets(1) }
			BT.ImportShoppingList(fromMe)
			fromAlt = BT.ExportShoppingList()
		end)
		as("Third-Otherrealm", function()
			Ace.db.char.shoppingList = {}
			BT.ImportShoppingList(fromAlt)
		end)
		local ent = list()[GAUNTLETS]
		assert.equal(3, ent.quantity)
		assert.equal(2, ent.wantedBy[ME])
		assert.equal(1, ent.wantedBy[ALT])
	end)

	it("still reads a list a chat client wrapped onto several lines", function()
		local text = BT.SHARE_PREFIX .. GAUNTLETS .. ":" .. ALT .. "=2;" .. STONE .. ":" .. ALT .. "=1"
		local wrapped = "  " .. text:sub(1, 12) .. "\n" .. text:sub(13, 30) .. "\r\n " .. text:sub(31) .. "\n"
		assert.equal(2, (BT.ImportShoppingList(wrapped)))
	end)

	it("refuses text that holds no shared list", function()
		assert.is_nil(BT.ImportShoppingList(nil))
		assert.is_nil(BT.ImportShoppingList("hello"))
		assert.is_nil(BT.ImportShoppingList(BT.SHARE_PREFIX))
		assert.is_nil(BT.ImportShoppingList(BT.SHARE_PREFIX .. "abc;def"))
		assert.is_nil(BT.ImportShoppingList(BT.SHARE_PREFIX .. "19083:Altie=x"))
		assert.same({}, list())
	end)

	it("checks and clamps every field another player wrote", function()
		local text = BT.SHARE_PREFIX .. table.concat({
			GAUNTLETS .. ":" .. ALT .. "=1000000,Bad|Name=1,=3,Zero=0," .. ("x"):rep(65) .. "=1",
			"0:" .. ALT .. "=1",
			"-5:" .. ALT .. "=1",
			STONE .. ":junk",
		}, ";")
		local added, _, skipped = BT.ImportShoppingList(text)
		assert.equal(1, added)
		assert.equal(0, skipped)
		local ent = list()[GAUNTLETS]
		assert.equal(BT.SHARE_MAX_QTY, ent.quantity)
		assert.same({ [ALT] = BT.SHARE_MAX_QTY }, ent.wantedBy)
		assert.is_nil(list()[0], "a zero recipe id is refused")
		assert.is_nil(list()[STONE], "an item nobody valid wants is not added")
	end)

	it("stops after the item cap", function()
		local db, items, ids = {}, {}, {}
		for i = 1, BT.SHARE_MAX_ITEMS + 5 do
			db[i] = { name = "R" .. i }
			items[i] = i .. ":" .. ALT .. "=1"
			ids[i] = i
		end
		env.spellsExist(unpack(ids))
		env.setRecipeDB({ [LW] = db })
		assert.equal(BT.SHARE_MAX_ITEMS, (BT.ImportShoppingList(BT.SHARE_PREFIX .. table.concat(items, ";"))))
	end)
end)

describe("ShoppingWantedBy", function()
	it("lists the other characters by short name, sorted, without me", function()
		local ent = { wantedBy = { [ME] = 1, ["Zed-Otherrealm"] = 2, [ALT] = 1 } }
		assert.same({ "Altie", "Zed" }, BT.ShoppingWantedBy(ent))
		assert.same({}, BT.ShoppingWantedBy({}))
		assert.same({}, BT.ShoppingWantedBy(nil))
	end)
end)

describe("what the shopping list shows for an imported entry", function()
	local savedTip
	before_each(function() savedTip = _G.GameTooltip end)
	after_each(function() _G.GameTooltip = savedTip end)

	it("names the other characters after the recipe, in grey", function()
		local ent = { name = "Runic Leather Gauntlets", wantedBy = { [ALT] = 2 } }
		local text = BT.ShoppingRecipeName(ent, GAUNTLETS)
		assert.truthy(text:find("Runic Leather Gauntlets", 1, true))
		assert.truthy(text:find("|cff888888" .. L["ShoppingWantedBy"]:format("Altie") .. "|r", 1, true))
		assert.is_nil(BT.ShoppingRecipeName({ name = "Plain" }, 1):find("888888"),
			"nothing added for an entry only I want")
	end)

	it("lists who wants how many in the recipe tooltip", function()
		local lines = {}
		_G.GameTooltip = {
			SetOwner = function() end, ClearLines = function() end,
			SetHyperlink = function() end, Show = function() end,
			AddLine = function(_, t) lines[#lines + 1] = t end,
		}
		local ent = gauntlets(5)
		ent.itemLink = "|cff1eff00|Hitem:4239::::::::60:::::|h[Runic Leather Gauntlets]|h|r"
		ent.wantedBy = { [ALT] = 2 }
		BT:ShowShoppingTooltip({ kind = "recipe", sid = GAUNTLETS, ent = ent }, UIParent)
		assert.truthy(lines[2]:find(L["ShoppingWantedByTip"], 1, true))
		assert.equal("Altie  x2", lines[3])
		assert.equal("Testchar  x3", lines[4])
	end)
end)

describe("the toolbar's Share List button", function()
	it("runs its handler when clicked", function()
		local AceGUI = LibStub("AceGUI-3.0")
		local toolbar = AceGUI:Create("SimpleGroup")
		toolbar:SetLayout("Flow")
		local clicked = 0
		local _, btn = ns.GUI.ToolbarButton(toolbar, {
			text = L["ShoppingShareButton"], onClick = function() clicked = clicked + 1 end,
			tipTitle = L["ShoppingShareTitle"], tipBody = L["ShoppingShareTipBody"],
		})
		assert.equal(L["ShoppingShareButton"], btn.text:GetText())
		btn:Fire("OnClick")
		assert.equal(1, clicked)
		AceGUI:Release(toolbar)
	end)
end)

describe("the share window", function()
	local function tab() return setmetatable({}, { __index = BT }) end

	it("opens with the list selected for copying, or an empty-list hint", function()
		local t = tab()
		t:OpenShareDialog()
		assert.equal("", t._shareWin._eb:GetText())
		assert.equal(L["ShoppingShareEmpty"], t._shareWin.statustext:GetText())

		list()[GAUNTLETS] = gauntlets(2)
		t:OpenShareDialog()
		assert.equal(BT.ExportShoppingList(), t._shareWin._eb:GetText())
		assert.equal(L["ShoppingShareCopyHint"], t._shareWin.statustext:GetText())
	end)

	it("reports what an import did", function()
		local text = BT.SHARE_PREFIX .. GAUNTLETS .. ":" .. ALT .. "=2;999999:" .. ALT .. "=1"
		local t = tab()
		t:OpenShareDialog()

		t:RunShareImport("rubbish")
		assert.truthy(t._shareWin.statustext:GetText():find(L["ShoppingShareBad"], 1, true))

		t:RunShareImport(text)
		assert.equal(L["ShoppingShareDone"]:format(1, 0) .. " " .. L["ShoppingShareSkipped"]:format(1),
			t._shareWin.statustext:GetText())
		t:RunShareImport(text)
		assert.equal(L["ShoppingShareNothing"] .. " " .. L["ShoppingShareSkipped"]:format(1),
			t._shareWin.statustext:GetText())
	end)
end)
