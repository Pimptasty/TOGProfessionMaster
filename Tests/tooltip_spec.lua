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

	it("defaults to silent when the settings were never written", function()
		crafter(MATE)
		Ace.db.profile.tooltipShowCrafters = nil
		Ace.db.profile.tooltipShowIds      = nil
		local t = fakeTooltip(POTION)
		Tooltip.Tooltip.AppendCrafters(t, POTION)
		assert.equal(0, #t.lines)
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
		_G.GetItemInfo = function()
			return "Soulbound", "link", 1, 60, 60, "", "", 1, "", "", 0, 0, 0, 1
		end
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
