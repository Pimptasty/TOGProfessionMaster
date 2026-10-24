-- Missing Recipes sharing between accounts: the export text, the import that
-- stores another account's characters, and the views built from them.
--
-- Asked for on Discord 2026-10-24 for a player with characters on several
-- accounts who wants every character's missing recipe scrolls in one place, to
-- buy them at any Auction House. The rules pinned here are the ones the player
-- relies on without seeing them:
--   * only recipe spell ids travel; the rows are rebuilt from the recipe data;
--   * only scrolls travel (a trainer recipe is nothing to buy);
--   * importing a character REPLACES what was shared for them before, so a
--     re-import after they learn a recipe drops it, and importing twice is a no-op;
--   * this account's own characters in an import are ignored (live data wins);
--   * a list passes along a chain of accounts;
--   * "All characters" lists each scroll once, naming everyone who wants it;
--   * anything another player wrote is checked and clamped, never trusted.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Ace, M, gdb, L
local ME      = "Testchar-Testrealm"
local ALT     = "Altie-Otherrealm"
local ALCHEMY, TAILORING = 171, 197

-- A and B are taught by scrolls; T is trainer-only (no scroll item). S is a
-- Tailoring pattern, a profession only the shared character has.
local A, B, T, S = 2330, 2331, 2332, 2963

setup(function()
	ns = env.initDb()
	Ace = ns.lib
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	M = env.loadModule("GUI/MissingRecipesTab.lua").MissingRecipesTab
	L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
end)

before_each(function()
	env.install()
	env.installFrames()
	env.spellsExist(A, B, T, S)
	gdb = env.resetDb()
	env.setRecipeDB({
		[ALCHEMY] = {
			[A] = { name = "Minor Healing Potion", itemId = 2555, craftedItemId = 118, requiredSkill = 1 },
			[B] = { name = "Elixir of Lion's Strength", itemId = 2553, craftedItemId = 2454, requiredSkill = 100 },
			[T] = { name = "Greater Healing Potion", craftedItemId = 1710, requiredSkill = 200 },
		},
		[TAILORING] = {
			[S] = { name = "Bolt of Linen", itemId = 4345, craftedItemId = 2996, requiredSkill = 1 },
		},
	})
	ns.sourceDB = { [ALCHEMY] = {}, [TAILORING] = {} }
	gdb.skills[ME] = { [ALCHEMY] = { skillRank = 150, skillMax = 300 } }
	gdb.accountChars[ME] = true
	env.itemAPI("GetItemInfo", function() return nil end)
	env.itemAPI("GetItemIcon", function() return nil end)
	Ace.db.global.missingShared = {}
	M._scope, M._charKey, M._includeTrainer = "personal", nil, true
	M._canLearnOnly, M._showAll = false, false
end)

local function shared() return Ace.db.global.missingShared end

local function ids(list)
	local out = {}
	for _, row in ipairs(list) do out[#out + 1] = row.spellId end
	table.sort(out)
	return out
end

describe("ExportMissing", function()
	it("carries this account's characters and the scrolls each is missing, no trainer recipes", function()
		assert.equal(M.SHARE_PREFIX .. ME .. "=" .. A .. "," .. B, M.ExportMissing())
	end)

	it("leaves out a scroll the character already knows", function()
		gdb.recipes[ALCHEMY] = { [A] = { crafters = { [ME] = ns:GetCurrentGuildTag() } } }
		assert.equal(M.SHARE_PREFIX .. ME .. "=" .. B, M.ExportMissing())
	end)

	it("returns nothing when no character has profession data", function()
		gdb.skills[ME] = nil
		assert.is_nil(M.ExportMissing())
	end)

	it("passes along characters shared in from another account", function()
		shared()[ALT] = { spells = { [B] = ALCHEMY } }
		assert.equal(M.SHARE_PREFIX .. ALT .. "=" .. B .. ";" .. ME .. "=" .. A .. "," .. B, M.ExportMissing())
	end)

	it("holds no Discord markup character", function()
		assert.is_nil(M.ExportMissing():find("[%*_~`|]"))
	end)
end)

describe("ImportMissing", function()
	it("stores another account's character with each scroll's profession", function()
		local added, updated, skipped = M.ImportMissing(M.SHARE_PREFIX .. ALT .. "=" .. A .. "," .. B)
		assert.equal(1, added)
		assert.equal(0, updated)
		assert.equal(0, skipped)
		assert.same({ [A] = ALCHEMY, [B] = ALCHEMY }, shared()[ALT].spells)
	end)

	it("replaces a character's earlier share, so a learned scroll drops off", function()
		M.ImportMissing(M.SHARE_PREFIX .. ALT .. "=" .. A .. "," .. B)
		local added, updated = M.ImportMissing(M.SHARE_PREFIX .. ALT .. "=" .. B)
		assert.equal(0, added)
		assert.equal(1, updated)
		assert.same({ [B] = ALCHEMY }, shared()[ALT].spells)
	end)

	it("changes nothing when the same list is imported twice", function()
		local text = M.SHARE_PREFIX .. ALT .. "=" .. A
		M.ImportMissing(text)
		local added, updated = M.ImportMissing(text)
		assert.equal(0, added)
		assert.equal(0, updated)
	end)

	it("ignores this account's own characters: their list is live", function()
		local added, updated = M.ImportMissing(M.SHARE_PREFIX .. ME .. "=" .. A)
		assert.equal(0, added)
		assert.equal(0, updated)
		assert.is_nil(shared()[ME])
	end)

	it("skips, and counts, a recipe this game version does not have", function()
		local added, _, skipped = M.ImportMissing(M.SHARE_PREFIX .. ALT .. "=999999," .. A)
		assert.equal(1, added)
		assert.equal(1, skipped)
		assert.same({ [A] = ALCHEMY }, shared()[ALT].spells)
	end)

	it("round-trips through a second account and back along the chain", function()
		local text = M.ExportMissing()
		gdb.accountChars[ME] = nil
		gdb.accountChars[ALT] = true
		gdb.skills[ME] = nil
		M.ImportMissing(text)
		assert.same({ [A] = ALCHEMY, [B] = ALCHEMY }, shared()[ME].spells)
		assert.truthy(M.ExportMissing():find(ME .. "=" .. A .. "," .. B, 1, true))
	end)

	it("still reads a list a chat client wrapped onto several lines", function()
		local text = M.SHARE_PREFIX .. ALT .. "=" .. A .. "," .. B
		assert.equal(1, (M.ImportMissing("  " .. text:sub(1, 10) .. "\r\n" .. text:sub(11) .. "\n")))
	end)

	it("refuses text that holds no shared list", function()
		assert.is_nil(M.ImportMissing(nil))
		assert.is_nil(M.ImportMissing("hello"))
		assert.is_nil(M.ImportMissing(M.SHARE_PREFIX))
		assert.is_nil(M.ImportMissing(M.SHARE_PREFIX .. "NoRealm=" .. A))
		assert.is_nil(M.ImportMissing(M.SHARE_PREFIX .. "Bad|Name-Realm=" .. A))
		assert.is_nil(M.ImportMissing(M.SHARE_PREFIX .. ("x"):rep(60) .. "-" .. ("y"):rep(10) .. "=" .. A))
		assert.same({}, shared())
	end)

	it("stops after the character cap", function()
		local parts = {}
		for i = 1, M.SHARE_MAX_CHARS + 5 do parts[i] = "C" .. i .. "-Realm=" .. A end
		assert.equal(M.SHARE_MAX_CHARS, (M.ImportMissing(M.SHARE_PREFIX .. table.concat(parts, ";"))))
	end)

	it("ForgetShared removes a shared character and never one of this account's", function()
		shared()[ALT] = { spells = { [A] = ALCHEMY } }
		shared()[ME]  = { spells = { [A] = ALCHEMY } }
		M.ForgetShared(ALT)
		M.ForgetShared(ME)
		assert.is_nil(shared()[ALT])
		assert.is_table(shared()[ME])
	end)
end)

describe("the lists built from a share", function()
	it("shows a shared character's scrolls for their profession", function()
		shared()[ALT] = { spells = { [B] = ALCHEMY } }
		M._charKey = ALT
		assert.same({ B }, ids(M:BuildFor(ALCHEMY)))
	end)

	it("All characters lists each scroll once and names who wants it", function()
		shared()[ALT] = { spells = { [B] = ALCHEMY } }
		M._charKey = M.ALL_CHARS
		local rows = M:BuildFor(ALCHEMY)
		assert.same({ A, B }, ids(rows))
		local byId = {}
		for _, r in ipairs(rows) do byId[r.spellId] = r end
		assert.same({ "Testchar" }, byId[A].forChars)
		assert.same({ "Altie", "Testchar" }, byId[B].forChars)
		assert.truthy(M:RowDisplay(byId[B]).name:find(L["ShoppingWantedBy"]:format("Altie, Testchar"), 1, true))
	end)

	it("this account's own character still gets the normal missing list", function()
		M._charKey = ME
		assert.same({ A, B, T }, ids(M:BuildFor(ALCHEMY)))
	end)
end)

describe("the tab drawn with shared characters", function()
	-- The first AceGUI Button under `widget` whose text is `text`.
	local function findButton(widget, text)
		if widget.type == "Button" and widget.text and widget.text:GetText() == text then return widget end
		for _, child in ipairs(widget.children or {}) do
			local hit = findButton(child, text)
			if hit then return hit end
		end
	end

	before_each(function()
		shared()[ALT] = { spells = { [B] = ALCHEMY, [S] = TAILORING } }
		M._scope, M._profId = nil, 0
	end)

	it("lists a shared character's scrolls, with a Forget button that removes them", function()
		local container = env.drawTab(M)
		M._scope, M._charKey, M._profId = "personal", ALT, "all"
		M:Refresh()
		assert.same({ B, S }, ids(M._list))
		local forget = assert(findButton(container, L["MissingForget"]), "no Forget button for a shared character")
		forget:Fire("OnClick")
		assert.is_nil(shared()[ALT])
		assert.equal(ME, M._charKey)
	end)

	it("All characters lists every profession's scrolls with who wants them", function()
		local container = env.drawTab(M)
		M._scope, M._charKey, M._profId = "personal", M.ALL_CHARS, "all"
		M:Refresh()
		assert.same({ A, B, S }, ids(M._list))
		assert.is_nil(findButton(container, L["MissingForget"]), "nothing to forget in the combined view")
		assert.is_truthy(findButton(container, L["ShoppingShareButton"]))
	end)

	it("offers no Forget button for this account's own character", function()
		local container = env.drawTab(M)
		M._scope, M._charKey, M._profId = "personal", ME, ALCHEMY
		M:Refresh()
		assert.is_nil(findButton(container, L["MissingForget"]))
	end)
end)

describe("the share window", function()
	local function tab() return setmetatable({ Refresh = function() end }, { __index = M }) end

	it("opens with the list selected for copying", function()
		local t = tab()
		t:OpenShareDialog()
		assert.equal(M.ExportMissing(), t._shareWin._eb:GetText())
		assert.equal(L["ShoppingShareCopyHint"], t._shareWin.statustext:GetText())
	end)

	it("reports what an import did", function()
		local t = tab()
		t:OpenShareDialog()
		t:RunShareImport("rubbish")
		assert.truthy(t._shareWin.statustext:GetText():find(L["MissingShareBad"], 1, true))
		local text = M.SHARE_PREFIX .. ALT .. "=" .. A .. ",999999"
		t:RunShareImport(text)
		assert.equal(L["MissingShareDone"]:format(1, 0) .. " " .. L["ShoppingShareSkipped"]:format(1),
			t._shareWin.statustext:GetText())
		t:RunShareImport(text)
		assert.equal(L["MissingShareNothing"] .. " " .. L["ShoppingShareSkipped"]:format(1),
			t._shareWin.statustext:GetText())
	end)
end)
