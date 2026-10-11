-- The [TOGPM] lines appended to item tooltips.
--
-- Two lines, both opt-in: who in the guild can craft this, and the itemId /
-- spellId diagnostic footer. The crafters lookup is the interesting half — it
-- goes from an item id, through the shipped recipe data, to crafter membership,
-- through the same visibility gate the rest of the UI uses, and it has to dedup
-- a crafter who reaches the item by more than one recipe.
--
-- It also re-verifies the tooltip is still showing the item it was called for,
-- because the append can be deferred and the player may have moved on.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Tooltip, Ace, gdb
local POTION = 118      -- Minor Healing Potion, made by Alchemy 2330
local MATE   = "Bob-Testrealm"

setup(function()
	ns = env.initDb()
	Tooltip = env.loadModule("Tooltip.lua")
	Ace = ns.lib
end)

-- A tooltip that reports the item it is showing, and records what we add.
local function fakeTooltip(itemId)
	local t = { lines = {} }
	t.GetItem  = function() return "Name", "|cffffffff|Hitem:" .. itemId .. "|h[x]|h|r" end
	t.AddLine  = function(_, text) t.lines[#t.lines + 1] = text end
	return t
end

local function allText(t)
	return table.concat(t.lines, "\n")
end

before_each(function()
	env.install()
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({
		-- `teaches` is what the IDs line reports as the spell that makes the item.
		[171] = { [2330] = { name = "Minor Healing Potion", craftedItemId = POTION, teaches = 2330 } },
	})
	_G.GetItemInfo = function() return nil end
	Ace.db.profile.tooltipShowCrafters = true
	Ace.db.profile.tooltipShowIds      = true
end)

-- Cases swap ns.ItemLink and _G.TooltipUtil for stubs. Restored here rather
-- than inline, so a case that raises halfway cannot leak a stub into every
-- later spec file in the same Lua state.
local savedItemLink, savedTooltipUtil
before_each(function()
	savedItemLink, savedTooltipUtil = ns.ItemLink, _G.TooltipUtil
end)
after_each(function()
	ns.ItemLink, _G.TooltipUtil = savedItemLink, savedTooltipUtil
end)

local function crafter(charKey, tag)
	gdb.recipes[171] = gdb.recipes[171] or {}
	gdb.recipes[171][2330] = gdb.recipes[171][2330] or { crafters = {} }
	gdb.recipes[171][2330].crafters[charKey] = tag or ns:GetCurrentGuildTag()
end

describe("crafters line", function()
	it("lists a guild crafter of the item", function()
		crafter(MATE)
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("Bob", 1, true) ~= nil)
		assert.is_true(allText(t):find("[TOGPM]", 1, true) ~= nil)
	end)

	it("says nothing when nobody in the guild crafts it", function()
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("Bob", 1, true) == nil)
	end)

	it("stays silent entirely when both toggles are off", function()
		crafter(MATE)
		Ace.db.profile.tooltipShowCrafters = false
		Ace.db.profile.tooltipShowIds      = false
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.equal(0, #t.lines)
	end)

	it("reads never-written settings as the shipped defaults: crafters on, IDs off", function()
		-- Crafters has shipped ON since v1.0.7 and its checkbox reads a missing
		-- key as on. This case used to assert silence, which pinned the reader
		-- that disagreed with the checkbox.
		crafter(MATE)
		Ace.db.profile.tooltipShowCrafters = nil
		Ace.db.profile.tooltipShowIds      = nil
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("Bob", 1, true) ~= nil)
		assert.is_nil(allText(t):find("itemId=", 1, true))
	end)

	it("abandons the append if the player has hovered off the item", function()
		-- The append can run deferred; writing into whatever tooltip is up now
		-- would pollute an unrelated item.
		crafter(MATE)
		local t = fakeTooltip(999999)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.equal(0, #t.lines)
	end)

	it("skips Bind-on-Pickup items, which can't be traded anyway", function()
		crafter(MATE)
		-- Both spellings: Tooltip.lua reads the BOP flag through
		-- addon.Item.GetInfo, which prefers C_Item and would not see a stub
		-- written only to the bare global. See env.itemAPI.
		env.itemAPI("GetItemInfo", function()
			return "Soulbound", "link", 1, 60, 60, "", "", 1, "", "", 0, 0, 0, 1
		end)
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("Bob", 1, true) == nil)
		-- ...but the diagnostic line still fires, and says why.
		assert.is_true(allText(t):find("bop-skipped", 1, true) ~= nil)
	end)

	it("hides a crafter the visibility gate rejects", function()
		crafter("Nobody-Testrealm")
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("Nobody", 1, true) == nil)
	end)

	it("lists a crafter once even when two recipes make the same item", function()
		env.setRecipeDB({
			[171] = {
				[2330] = { craftedItemId = POTION },
				[2331] = { craftedItemId = POTION },   -- e.g. a discovery variant
			},
		})
		crafter(MATE)
		gdb.recipes[171][2331] = { crafters = { [MATE] = ns:GetCurrentGuildTag() } }
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		local _, count = allText(t):gsub("Bob", "")
		assert.equal(1, count)
	end)

	it("lists a crafter once when two PROFESSIONS make the same item", function()
		-- Gold Bar: Mining's Smelt Gold and Alchemy's Transmute Iron to Gold.
		-- The old dedup was per (character, profession), so a miner-alchemist
		-- printed as "Bob, Bob".
		local GOLD = 3577
		env.setRecipeDB({
			[186] = { [3308]  = { craftedItemId = GOLD } },
			[171] = { [11479] = { craftedItemId = GOLD } },
		})
		gdb.recipes[186] = { [3308]  = { crafters = { [MATE] = ns:GetCurrentGuildTag() } } }
		gdb.recipes[171] = { [11479] = { crafters = { [MATE] = ns:GetCurrentGuildTag() } } }
		local t = fakeTooltip(GOLD)
		Tooltip.Tooltip.AppendCrafters(t, GOLD)
		local _, count = allText(t):gsub("Bob", "")
		assert.equal(1, count)
	end)

	it("does not treat a recipe's teaching scroll as something its crafters make", function()
		-- The cached index holds scrolls too; the crafters lookup must take only
		-- the crafted half, or hovering "Recipe: Minor Healing Potion" would list
		-- every alchemist as able to make the scroll.
		local SCROLLID = 2553
		env.setRecipeDB({
			[171] = { [2330] = { craftedItemId = POTION } },
		})
		ns.ItemLink = { TeachingItem = function() return SCROLLID end }   -- after_each restores
		crafter(MATE)
		-- Precondition: the scroll IS in the index, so the absence below is the
		-- filter working and not the scroll simply never being indexed.
		local hits = ns.Tooltip._RecipesForItem(SCROLLID)
		local t = fakeTooltip(SCROLLID)
		Tooltip.Tooltip.AppendCrafters(t, SCROLLID)
		assert.equal(1, hits and #hits or 0)
		assert.is_false(hits[1].crafted)
		assert.is_true(allText(t):find("Bob", 1, true) == nil)
		assert.is_true(allText(t):find("recipe-not-found", 1, true) ~= nil)
	end)

	it("orders an item's recipes so the first hit does not depend on table layout", function()
		env.setRecipeDB({
			[186] = { [3308]  = { craftedItemId = 3577 } },
			[171] = { [11479] = { craftedItemId = 3577 } },
		})
		local hits = ns.Tooltip._RecipesForItem(3577)
		assert.equal(2, #hits)
		assert.equal(171, hits[1].profId)
		assert.equal(186, hits[2].profId)
	end)

	it("sorts a non-numeric recipe key as text instead of raising", function()
		-- `<` between a number and a string raises, and this runs inside a hook
		-- that every item tooltip in the game reaches.
		env.setRecipeDB({
			[171] = { [11479] = { craftedItemId = 3577 }, ["x11480"] = { craftedItemId = 3577 } },
		})
		local hits
		assert.has_no.errors(function() hits = ns.Tooltip._RecipesForItem(3577) end)
		assert.equal(2, #hits)
		assert.equal(11479, hits[1].recipeId)     -- "11479" < "x11480" as text
		assert.equal("x11480", hits[2].recipeId)
	end)

	it("puts online crafters first, then sorts by name", function()
		env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true },
		             { name = "Al", isOnline = false }, { name = "Zed", isOnline = true } })
		crafter("Al-Testrealm")
		crafter("Zed-Testrealm")
		crafter(MATE)
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		local text = allText(t)
		local bob, zed, al = text:find("Bob", 1, true), text:find("Zed", 1, true), text:find("Al|", 1, true)
		assert.is_truthy(bob and zed and al, "a crafter is missing from the line")
		assert.is_true(bob < zed, "online crafters not sorted by name")
		assert.is_true(zed < al, "offline crafter listed before an online one")
	end)

	it("reads the item through TooltipUtil on a frame with no GetItem (WoW Forever)", function()
		-- The quest-reward tooltip raised "attempt to call a nil value" in game
		-- 2026-09-27; the modern engine keeps the item in GameTooltipDataMixin.
		crafter(MATE)
		local t = fakeTooltip(POTION)
		t.GetItem = nil
		-- after_each restores the real TooltipUtil.
		_G.TooltipUtil = { GetDisplayedItem = function()
			return "Name", "|cffffffff|Hitem:" .. POTION .. "|h[x]|h|r"
		end }
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		_G.TooltipUtil = nil
		local t2 = fakeTooltip(POTION)
		t2.GetItem = nil
		Tooltip.Tooltip.AppendCrafters(t2, POTION)
		assert.is_true(allText(t):find("Bob", 1, true) ~= nil)
		-- Neither spelling available: nothing to verify the item against, so
		-- nothing is written.
		assert.equal(0, #t2.lines)
	end)

	it("counts an offline crafter as online when a known alt is on", function()
		-- A bank alt is nearly always parked offline; its main being online is
		-- what makes the crafter actually reachable.
		crafter("Sleeper-Testrealm")
		gdb.altGroups["Sleeper-Testrealm"] = { "Sleeper-Testrealm", MATE }
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("Sleeper", 1, true) ~= nil)
		assert.is_true(allText(t):find(ns.ColorOnline, 1, true) ~= nil)
	end)
end)

describe("IDs line", function()
	it("reports the item id, and the spell that makes it", function()
		crafter(MATE)
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		local text = allText(t)
		assert.is_true(text:find("itemId=" .. POTION, 1, true) ~= nil)
		assert.is_true(text:find("spellId=", 1, true) ~= nil)
	end)

	it("explains an item no recipe produces", function()
		local t = fakeTooltip(999999)
		Tooltip.Tooltip.AppendCrafters(t, 999999)
		assert.is_true(allText(t):find("recipe-not-found", 1, true) ~= nil)
	end)

	it("explains a recipe that exists but has no crafters yet", function()
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("recipe-no-crafters", 1, true) ~= nil)
	end)

	it("says so when the crafters line is switched off", function()
		crafter(MATE)
		Ace.db.profile.tooltipShowCrafters = false
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("crafters-disabled", 1, true) ~= nil)
	end)

	it("counts the crafters it found", function()
		crafter(MATE)
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.is_true(allText(t):find("crafters=1", 1, true) ~= nil)
	end)
end)

describe("AppendBrandIds", function()
	it("prints whichever ids it is given", function()
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendBrandIds(t, POTION, 2330)
		local text = allText(t)
		assert.is_true(text:find("itemId=" .. POTION, 1, true) ~= nil)
		assert.is_true(text:find("spellId=2330", 1, true) ~= nil)
	end)

	it("prints a spell-only line for a recipe that makes no item", function()
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendBrandIds(t, nil, 13937)
		local text = allText(t)
		assert.is_true(text:find("itemId=", 1, true) == nil)
		assert.is_true(text:find("spellId=13937", 1, true) ~= nil)
	end)

	it("adds nothing at all when given neither id", function()
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendBrandIds(t, nil, nil)
		assert.equal(0, #t.lines)
	end)

	it("respects the same opt-in toggle as the global hook", function()
		Ace.db.profile.tooltipShowIds = false
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendBrandIds(t, POTION, 2330)
		assert.equal(0, #t.lines)
	end)

	it("defaults to off when the setting was never written", function()
		Ace.db.profile.tooltipShowIds = nil
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendBrandIds(t, POTION, 2330)
		assert.equal(0, #t.lines)
	end)
end)
