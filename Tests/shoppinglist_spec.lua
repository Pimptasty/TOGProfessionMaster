-- GUI/ShoppingListTab.lua — the reagent arithmetic behind "what do I still need
-- to buy".
--
-- Everything else in that file is rendering; this is the part with a right
-- answer, and a wrong answer sends someone to the auction house for the wrong
-- number of Arcane Crystals. Aggregation across several queued crafts, the
-- per-entry quantity multiplier, what is already in the bags, and the shortfall.
--
-- Each assertion below was checked to fail when the behaviour it names is
-- removed from the source — a sum that is "obviously right" is exactly the kind
-- that stays wrong for a year.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, tab, saved

-- Two transmutes and their reagents, in the shape GetCooldownData returns.
local ARCANITE, THORIUM, MOONCLOTH, FELCLOTH = 12360, 12359, 14342, 14256
local TRANSMUTE_ARCANITE, TRANSMUTE_MOONCLOTH = 17187, 18560
local NO_REAGENT_SPELL = 99999

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/ShoppingListTab.lua")
	tab = ns.ShoppingListTab
end)

--- Put items in the player's bags: { [itemId] = count }, one slot each.
local function bagsHolding(contents)
	local slots = {}
	for itemId, count in pairs(contents or {}) do
		slots[#slots + 1] = { itemID = itemId, stackCount = count }
	end
	ns.GetNumBagSlots       = function() return 0 end
	ns.GetContainerNumSlots = function() return #slots end
	ns.GetContainerItemInfo = function(_, _bag, slot) return slots[slot] end
end

before_each(function()
	env.installFrames()
	env.resetDb()

	-- Every one of these is a method on the ADDON table, which `env.install()`
	-- does not reset — only globals come back. Left overridden, they follow the
	-- suite into later spec FILES: the bag stubs alone break every recipe row
	-- that shows what you already have. Restored in after_each.
	saved = {
		GetCooldownData       = ns.GetCooldownData,
		GetNumBagSlots        = ns.GetNumBagSlots,
		GetContainerNumSlots  = ns.GetContainerNumSlots,
		GetContainerItemInfo  = ns.GetContainerItemInfo,
		GetItemInfo           = _G.GetItemInfo,
	}

	-- Item names drive the sort; the real GetItemInfo is not in the harness env.
	-- Returns nil for anything unnamed, as the client does for an uncached item,
	-- so the "(loading…)" fallback stays reachable.
	local names = {
		[ARCANITE] = "Arcanite Bar", [THORIUM] = "Thorium Bar",
		[MOONCLOTH] = "Mooncloth",   [FELCLOTH] = "Felcloth",
	}
	_G.GetItemInfo = function(itemId) return names[itemId] end

	ns.GetCooldownData = function()
		return {
			reagents = {
				[TRANSMUTE_ARCANITE] = { id = THORIUM, qty = 1 },
			},
			transReagents = {
				[TRANSMUTE_MOONCLOTH] = { id = FELCLOTH, qty = 2 },
			},
		}
	end

	bagsHolding({})
	ns.lib.db.char.shoppingList = {}
end)

after_each(function()
	for name, fn in pairs(saved or {}) do
		if name == "GetItemInfo" then _G.GetItemInfo = fn else ns[name] = fn end
	end
end)

--- Queue `spellId` on the shopping list `quantity` times.
local function queue(spellId, quantity)
	ns.lib.db.char.shoppingList[spellId] = { quantity = quantity }
end

local function rowFor(itemId)
	for _, row in ipairs(tab:BuildReagentList()) do
		if row.itemId == itemId then return row end
	end
	return nil
end

describe("BuildReagentList — how much to buy", function()
	it("multiplies the reagent by the queued quantity", function()
		queue(TRANSMUTE_ARCANITE, 5)
		assert.equal(5, rowFor(THORIUM).needed)
	end)

	it("treats a queued craft with no quantity as one", function()
		queue(TRANSMUTE_ARCANITE, nil)
		assert.equal(1, rowFor(THORIUM).needed)
	end)

	it("sums a reagent shared by two queued crafts", function()
		-- The whole reason the tab aggregates: two crafts needing the same bar
		-- must produce one line with the total, not two lines to add up by hand.
		ns.GetCooldownData = function()
			return {
				reagents = {
					[TRANSMUTE_ARCANITE]  = { id = THORIUM, qty = 1 },
					[TRANSMUTE_MOONCLOTH] = { id = THORIUM, qty = 3 },
				},
				transReagents = {},
			}
		end
		queue(TRANSMUTE_ARCANITE, 2)    -- 2 × 1
		queue(TRANSMUTE_MOONCLOTH, 4)   -- 4 × 3
		local rows = tab:BuildReagentList()
		assert.equal(1, #rows)
		assert.equal(14, rows[1].needed)
	end)

	it("falls back to the transmute catalogue when the main one has nothing", function()
		queue(TRANSMUTE_MOONCLOTH, 3)
		assert.equal(6, rowFor(FELCLOTH).needed)
	end)

	it("skips a queued craft whose reagents are unknown", function()
		-- A recipe the cooldown data has never heard of must drop out quietly,
		-- not error and not contribute a phantom zero-count line.
		queue(NO_REAGENT_SPELL, 4)
		queue(TRANSMUTE_ARCANITE, 1)
		local rows = tab:BuildReagentList()
		assert.equal(1, #rows)
		assert.equal(THORIUM, rows[1].itemId)
	end)
end)

describe("BuildReagentList — what's already in the bags", function()
	it("counts what the bags hold against what is needed", function()
		queue(TRANSMUTE_ARCANITE, 10)
		bagsHolding({ [THORIUM] = 4 })
		local row = rowFor(THORIUM)
		assert.equal(10, row.needed)
		assert.equal(4,  row.have)
		assert.equal(6,  row.shortfall)
	end)

	it("adds up a reagent split across several bag slots", function()
		queue(TRANSMUTE_ARCANITE, 30)
		ns.GetNumBagSlots       = function() return 0 end
		ns.GetContainerNumSlots = function() return 3 end
		ns.GetContainerItemInfo = function(_, _bag, slot)
			return ({
				{ itemID = THORIUM, stackCount = 20 },
				{ itemID = FELCLOTH, stackCount = 5 },
				{ itemID = THORIUM, stackCount = 7 },
			})[slot]
		end
		assert.equal(27, rowFor(THORIUM).have)
		assert.equal(3,  rowFor(THORIUM).shortfall)
	end)

	it("never reports a negative shortfall when the bags are over-stocked", function()
		-- "Buy -6 Thorium Bars" is not a shopping list.
		queue(TRANSMUTE_ARCANITE, 4)
		bagsHolding({ [THORIUM] = 10 })
		assert.equal(0, rowFor(THORIUM).shortfall)
	end)

	it("counts an empty bag slot as nothing", function()
		queue(TRANSMUTE_ARCANITE, 2)
		ns.GetNumBagSlots       = function() return 0 end
		ns.GetContainerNumSlots = function() return 4 end
		ns.GetContainerItemInfo = function() return nil end
		assert.equal(0, rowFor(THORIUM).have)
		assert.equal(2, rowFor(THORIUM).shortfall)
	end)

	it("treats a stack with no count as a single item", function()
		queue(TRANSMUTE_ARCANITE, 3)
		ns.GetNumBagSlots       = function() return 0 end
		ns.GetContainerNumSlots = function() return 1 end
		ns.GetContainerItemInfo = function() return { itemID = THORIUM } end
		assert.equal(1, rowFor(THORIUM).have)
	end)
end)

describe("BuildReagentList — presentation", function()
	it("sorts the list by item name", function()
		ns.GetCooldownData = function()
			return {
				reagents = {
					[TRANSMUTE_ARCANITE]  = { id = THORIUM,  qty = 1 },
					[TRANSMUTE_MOONCLOTH] = { id = FELCLOTH, qty = 1 },
				},
				transReagents = {},
			}
		end
		queue(TRANSMUTE_ARCANITE, 1)
		queue(TRANSMUTE_MOONCLOTH, 1)
		local rows = tab:BuildReagentList()
		assert.equal("Felcloth",    rows[1].itemName)
		assert.equal("Thorium Bar", rows[2].itemName)
	end)

	it("names an item the client has not cached yet without erroring", function()
		_G.GetItemInfo = function() return nil end
		queue(TRANSMUTE_ARCANITE, 1)
		local row = rowFor(THORIUM)
		assert.is_truthy(row)
		assert.is_truthy(row.itemName:find("loading", 1, true))
	end)

	it("returns an empty list for an empty shopping list", function()
		assert.same({}, tab:BuildReagentList())
	end)
end)

describe("BuildReagentList — multi-reagent cooldowns", function()
	-- The bug this covers shipped and was silent. BuildReagentList only ever
	-- read `reagents` / `transReagents`, so a cooldown whose recipe takes
	-- SEVERAL reagents — Brilliant Glass, Primal Mooncloth, Spellcloth,
	-- Shadowcloth — contributed NOTHING to the list. You queued it, the tab
	-- said nothing was missing, and you went to the auction house empty-handed.
	--
	-- It matters more now than it did: reagents are derived from ProfessionDB
	-- rather than a hand-written primary-only table, so any cooldown whose real
	-- recipe has more than one reagent lands in `multiReagents`.
	local BRILLIANT_GLASS = 47280
	local GEM_A, GEM_B = 23117, 23077

	before_each(function()
		ns.GetCooldownData = function()
			return {
				reagents = {}, transReagents = {},
				multiReagents = {
					[BRILLIANT_GLASS] = {
						{ id = GEM_A, qty = 3 },
						{ id = GEM_B, qty = 3 },
					},
				},
			}
		end
	end)

	it("counts EVERY reagent, not just one of them", function()
		queue(BRILLIANT_GLASS, 1)
		assert.equal(3, rowFor(GEM_A).needed)
		assert.equal(3, rowFor(GEM_B).needed)
	end)

	it("multiplies each reagent by the queued quantity", function()
		queue(BRILLIANT_GLASS, 4)
		assert.equal(12, rowFor(GEM_A).needed)
		assert.equal(12, rowFor(GEM_B).needed)
	end)

	it("adds a multi-reagent craft's needs to a single-reagent craft's", function()
		-- The aggregation path: two queued crafts sharing nothing still both
		-- have to appear, and one must not shadow the other.
		ns.GetCooldownData = function()
			return {
				reagents = { [TRANSMUTE_ARCANITE] = { id = THORIUM, qty = 1 } },
				transReagents = {},
				multiReagents = { [BRILLIANT_GLASS] = { { id = GEM_A, qty = 3 } } },
			}
		end
		queue(TRANSMUTE_ARCANITE, 2)
		queue(BRILLIANT_GLASS, 1)
		assert.equal(2, rowFor(THORIUM).needed)
		assert.equal(3, rowFor(GEM_A).needed)
	end)

	it("sums a reagent shared between a single- and a multi-reagent craft", function()
		ns.GetCooldownData = function()
			return {
				reagents = { [TRANSMUTE_ARCANITE] = { id = GEM_A, qty = 1 } },
				transReagents = {},
				multiReagents = { [BRILLIANT_GLASS] = { { id = GEM_A, qty = 3 } } },
			}
		end
		queue(TRANSMUTE_ARCANITE, 2)
		queue(BRILLIANT_GLASS, 1)
		assert.equal(5, rowFor(GEM_A).needed)   -- 2x1 + 1x3
	end)

	it("prefers the featured single reagent when a cooldown has both", function()
		-- Build() puts a cooldown in one table or the other, never both. If that
		-- ever changes, the single entry wins and the multi list must not be
		-- double-counted on top of it.
		ns.GetCooldownData = function()
			return {
				reagents = { [BRILLIANT_GLASS] = { id = GEM_A, qty = 1 } },
				transReagents = {},
				multiReagents = { [BRILLIANT_GLASS] = { { id = GEM_B, qty = 3 } } },
			}
		end
		queue(BRILLIANT_GLASS, 1)
		assert.equal(1, rowFor(GEM_A).needed)
		assert.is_nil(rowFor(GEM_B))
	end)
end)
