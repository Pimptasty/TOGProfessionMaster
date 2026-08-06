-- Recipe identity in the profession browser: spell id vs item id.
--
-- Every key in addon.recipeDB (LibProfessionDB) is the recipe's trade-skill
-- SPELL id — for every profession and every flavour. Feeding one to an item API
-- silently resolves whatever unrelated ITEM happens to share the number, and WoW
-- has plenty of collisions: spell 13937 is "Enchant 2H Weapon - Greater Impact",
-- item 13937 is the staff "Headmaster's Charge". That is exactly what made
-- enchant hovers show a random staff (reported on TBC, present on every
-- flavour). Crafted-item recipes hid it because their itemLink is built from
-- craftedItemId and wins first; enchants produce no item and fell through.
--
-- These specs drive the browser's link/tooltip helpers directly, with GetItemInfo
-- deliberately answering for the colliding item — so any future call site that
-- treats entry.id as an item id fails here instead of in a bug report.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

-- Collision fixtures. The spell ids are real Vanilla/TBC Enchanting recipes;
-- the item ids are the unrelated items sharing those numbers.
local ENCHANT_SPELL_ID = 13937        -- "Enchant 2H Weapon - Greater Impact"
local COLLIDING_ITEM   = "|cff1eff00|Hitem:13937::::::::60:::::|h[Headmaster's Charge]|h|r"
local POTION_SPELL_ID  = 2330         -- Alchemy: Minor Healing Potion (recipe spell)
local POTION_ITEM_ID   = 118          -- …the potion it produces
local POTION_LINK      = "|cffffffff|Hitem:118::::::::60:::::|h[Minor Healing Potion]|h|r"

local items = {
	[13937] = COLLIDING_ITEM,
	[118]   = POTION_LINK,
}

local ns, BrowserTab

-- One Lua state runs the whole suite and specs reassign globals freely, so every
-- global this file owns is reinstalled on each test rather than once at load.
local function installGlobals()
	_G.GetItemInfo = function(id)
		local link = items[id]
		if not link then return nil end
		return link:match("%[(.-)%]"), link
	end
	_G.GetSpellLink = function(id)
		return "|cff71d5ff|Hspell:" .. id .. "|h[Spell " .. id .. "]|h|r"
	end
	_G.GetItemInfoInstant = function(id) return items[id] and id or nil end
	_G.GetItemIcon        = function() return nil end
	_G.GetSpellInfo       = function(id) return "Spell " .. id end
	_G.GetSpellTexture    = function() return nil end
	_G.GetTime            = function() return 0 end
	-- BrowserTab schedules its background cache warm at file scope; nothing here
	-- drives the timers, they just have to exist for the file to load.
	_G.C_Timer = {
		After    = function() end,
		NewTimer = function() return { Cancel = function() end } end,
	}
end

setup(function()
	installGlobals()
	ns = env.initDb()
	BrowserTab = env.loadModule("GUI/BrowserTab.lua").BrowserTab
end)

before_each(function()
	env.install()
	installGlobals()
end)

describe("BrowserTab entry identity", function()
	it("exposes the helpers the browser uses for links and spell tooltips", function()
		assert.is_function(BrowserTab._ResolveRecipeLink)
		assert.is_function(BrowserTab._SetSpellTooltip)
		assert.is_function(BrowserTab._AppendBrandTooltipLines)
	end)
end)

describe("ResolveRecipeLink", function()
	it("never resolves the recipe's spell id as an item (the enchant bug)", function()
		-- An enchant: recipeDB key only, no crafted item, no cached links.
		local link = BrowserTab._ResolveRecipeLink({
			id      = ENCHANT_SPELL_ID,
			spellId = ENCHANT_SPELL_ID,
			isSpell = true,
			name    = "Enchant 2H Weapon - Greater Impact",
		})
		assert.is_nil(link:find("|Hitem:", 1, true))
		assert.is_true(link:find("|Hspell:" .. ENCHANT_SPELL_ID, 1, true) ~= nil)
	end)

	it("treats a bare id as a spell even without the isSpell flag", function()
		-- Exactly the entry BuildList produced before the fix: the recipeDB key
		-- and nothing else. The old helper asked GetItemInfo(13937) here and
		-- handed back Headmaster's Charge — this is the regression guard.
		local link = BrowserTab._ResolveRecipeLink({
			id   = ENCHANT_SPELL_ID,
			name = "Enchant 2H Weapon - Greater Impact",
		})
		assert.is_nil(link:find("|Hitem:", 1, true))
		assert.is_nil(link:find("Headmaster", 1, true))
		assert.is_true(link:find("|Hspell:" .. ENCHANT_SPELL_ID, 1, true) ~= nil)
	end)

	it("still resolves an enchant when the client has no spell link for it", function()
		_G.GetSpellLink = function() return nil end
		local link = BrowserTab._ResolveRecipeLink({
			id      = ENCHANT_SPELL_ID,
			spellId = ENCHANT_SPELL_ID,
			isSpell = true,
			name    = "Enchant 2H Weapon - Greater Impact",
		})
		assert.is_true(link:find("|Hspell:" .. ENCHANT_SPELL_ID, 1, true) ~= nil)
		assert.is_true(link:find("Enchant 2H Weapon - Greater Impact", 1, true) ~= nil)
	end)

	it("prefers the cached crafted-item link", function()
		local link = BrowserTab._ResolveRecipeLink({
			id = POTION_SPELL_ID, spellId = POTION_SPELL_ID, isSpell = true,
			craftedItemId = POTION_ITEM_ID, itemLink = POTION_LINK,
		})
		assert.equal(POTION_LINK, link)
	end)

	it("rebuilds a missing crafted-item link from craftedItemId, not from id", function()
		local link = BrowserTab._ResolveRecipeLink({
			id = POTION_SPELL_ID, spellId = POTION_SPELL_ID, isSpell = true,
			craftedItemId = POTION_ITEM_ID,
		})
		assert.equal(POTION_LINK, link)
	end)

	it("returns nil when there is nothing to link", function()
		assert.is_nil(BrowserTab._ResolveRecipeLink({ name = "orphan" }))
		assert.is_nil(BrowserTab._ResolveRecipeLink(nil))
	end)
end)

describe("SetSpellTooltip", function()
	local tip

	before_each(function()
		tip = { calls = {} }
		function tip:SetSpellByID(id) table.insert(self.calls, { "SetSpellByID", id }) end
		function tip:SetHyperlink(l)  table.insert(self.calls, { "SetHyperlink", l })  end
	end)

	it("uses SetSpellByID when the client exposes it", function()
		assert.is_true(BrowserTab._SetSpellTooltip(tip, ENCHANT_SPELL_ID))
		assert.same({ "SetSpellByID", ENCHANT_SPELL_ID }, tip.calls[1])
	end)

	it("falls back to a spell: hyperlink when it does not", function()
		tip.SetSpellByID = nil
		assert.is_true(BrowserTab._SetSpellTooltip(tip, ENCHANT_SPELL_ID))
		assert.same({ "SetHyperlink", "spell:" .. ENCHANT_SPELL_ID }, tip.calls[1])
	end)

	it("reports failure (and touches nothing) without a spell id", function()
		assert.is_false(BrowserTab._SetSpellTooltip(tip, nil))
		assert.equal(0, #tip.calls)
	end)
end)

describe("AppendBrandTooltipLines", function()
	local lines, crafterIds, idLines

	-- REPLACE THE TWO METHODS, NOT THE NAMESPACE. This used to assign a fresh
	-- two-key table over `ns.Tooltip`, which silently deleted `Tooltip.Owner`
	-- and `Tooltip.AnchorFrame` (both from Compat.lua) for every spec file that
	-- ran after this one — invisible until something later actually used them,
	-- and then failing several files away from the line that caused it. Same
	-- hazard the env's "add to a namespace, never assign it" rule exists for.
	local saved

	before_each(function()
		lines, crafterIds, idLines = {}, {}, {}
		_G.GameTooltip = { AddLine = function(_, text) table.insert(lines, text) end }
		saved = { AppendCrafters = ns.Tooltip.AppendCrafters, AppendBrandIds = ns.Tooltip.AppendBrandIds }
		ns.Tooltip.AppendCrafters = function(_, itemID) table.insert(crafterIds, itemID) end
		ns.Tooltip.AppendBrandIds = function(_, itemID, spellID)
			table.insert(idLines, { itemID = itemID, spellID = spellID })
		end
	end)

	after_each(function()
		ns.Tooltip.AppendCrafters = saved.AppendCrafters
		ns.Tooltip.AppendBrandIds = saved.AppendBrandIds
	end)

	it("looks crafters up by the crafted item, never by the recipe's spell id", function()
		BrowserTab._AppendBrandTooltipLines({
			id = POTION_SPELL_ID, spellId = POTION_SPELL_ID, isSpell = true,
			craftedItemId = POTION_ITEM_ID,
		})
		assert.same({ POTION_ITEM_ID }, crafterIds)
		assert.same({ { itemID = POTION_ITEM_ID, spellID = POTION_SPELL_ID } }, idLines)
	end)

	it("reports no item id for an enchant, which produces none", function()
		BrowserTab._AppendBrandTooltipLines({
			id = ENCHANT_SPELL_ID, spellId = ENCHANT_SPELL_ID, isSpell = true,
			effect = "Weapon Damage +7",
		})
		assert.equal(0, #crafterIds)
		assert.same({ { itemID = nil, spellID = ENCHANT_SPELL_ID } }, idLines)
		assert.same({ "Weapon Damage +7" }, lines)
	end)
end)
