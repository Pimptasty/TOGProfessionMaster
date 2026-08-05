-- GUI/ReagentTracker.lua — the two numbers the tracker exists to show.
--
-- "need" comes from consolidating every reagent across the shopping list;
-- "have" is deliberately RICHER than the shopping list tab's version — it
-- counts the bank and the mailbox as well as your bags, because a reagent
-- sitting in the bank is one you do not need to buy.
--
-- The id resolution is the fragile part: a reagent can arrive carrying an item
-- LINK and no usable id, so the id is parsed out of the link, with the numeric
-- field as the fallback. Get that wrong and reagents either vanish from the
-- list or split into two rows that each show half the requirement.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, RT, saved

local THORIUM, FELCLOTH = 12359, 14256
local THORIUM_LINK = "|cffffffff|Hitem:12359:0:0:0:0:0:0:0|h[Thorium Bar]|h|r"

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/ReagentTracker.lua")
	RT = ns.ReagentTracker
end)

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
	saved = {
		GetNumBagSlots       = ns.GetNumBagSlots,
		GetContainerNumSlots = ns.GetContainerNumSlots,
		GetContainerItemInfo = ns.GetContainerItemInfo,
	}
	bagsHolding({})
	ns.lib.db.char.shoppingList = {}
	ns.lib.db.char.bankCounts   = {}
	ns.lib.db.char.mailCounts   = {}
end)

after_each(function()
	for name, fn in pairs(saved or {}) do ns[name] = fn end
end)

--- Queue a craft needing `reagents`, `quantity` times.
local function queue(spellId, quantity, reagents)
	ns.lib.db.char.shoppingList[spellId] = { quantity = quantity, reagents = reagents }
end

local function needFor(itemId)
	for _, row in ipairs(RT:BuildReagentList()) do
		if row.id == itemId then return row.need end
	end
	return nil
end

describe("BuildReagentList — what you still need", function()
	it("multiplies a reagent by the queued quantity", function()
		queue(1, 4, { { itemId = THORIUM, name = "Thorium Bar", count = 3 } })
		assert.equal(12, needFor(THORIUM))
	end)

	it("consolidates the same reagent across two queued crafts", function()
		-- One row with the total, not two rows to add up in your head.
		queue(1, 1, { { itemId = THORIUM, name = "Thorium Bar", count = 2 } })
		queue(2, 3, { { itemId = THORIUM, name = "Thorium Bar", count = 1 } })
		local list = RT:BuildReagentList()
		assert.equal(1, #list)
		assert.equal(5, list[1].need)
	end)

	it("treats a reagent with no count as one per craft", function()
		queue(1, 2, { { itemId = THORIUM, name = "Thorium Bar" } })
		assert.equal(2, needFor(THORIUM))
	end)

	it("treats a craft with no quantity as one", function()
		queue(1, nil, { { itemId = THORIUM, name = "Thorium Bar", count = 5 } })
		assert.equal(5, needFor(THORIUM))
	end)

	it("reads the item id out of an item link when there is no numeric id", function()
		-- Reagents arrive from trade-skill scans carrying a link and nothing
		-- else; without this they would silently never appear in the list.
		queue(1, 1, { { itemLink = THORIUM_LINK, name = "Thorium Bar", count = 2 } })
		assert.equal(2, needFor(THORIUM))
	end)

	it("keeps a linked and an unlinked entry for the same item together", function()
		-- The failure this guards is two rows for one reagent, each showing part
		-- of the requirement.
		queue(1, 1, { { itemLink = THORIUM_LINK, name = "Thorium Bar", count = 2 } })
		queue(2, 1, { { itemId = THORIUM, name = "Thorium Bar", count = 3 } })
		local list = RT:BuildReagentList()
		assert.equal(1, #list)
		assert.equal(5, list[1].need)
	end)

	it("skips a reagent with neither a link nor a real id", function()
		-- itemId 0 is the "no item" sentinel the scan produces for enchants.
		queue(1, 1, {
			{ itemId = 0, name = "Nothing" },
			{ itemId = THORIUM, name = "Thorium Bar", count = 1 },
		})
		local list = RT:BuildReagentList()
		assert.equal(1, #list)
		assert.equal(THORIUM, list[1].id)
	end)

	it("sorts by reagent name", function()
		queue(1, 1, {
			{ itemId = THORIUM,  name = "Thorium Bar", count = 1 },
			{ itemId = FELCLOTH, name = "Felcloth",    count = 1 },
		})
		local list = RT:BuildReagentList()
		assert.equal("Felcloth",    list[1].name)
		assert.equal("Thorium Bar", list[2].name)
	end)

	it("returns nothing for an empty shopping list", function()
		assert.same({}, RT:BuildReagentList())
	end)
end)

describe("GetPlayerBagCount — what you already have", function()
	it("counts what is in the bags", function()
		bagsHolding({ [THORIUM] = 12 })
		assert.equal(12, RT:GetPlayerBagCount(THORIUM))
	end)

	it("adds up stacks split across slots", function()
		ns.GetNumBagSlots       = function() return 0 end
		ns.GetContainerNumSlots = function() return 3 end
		ns.GetContainerItemInfo = function(_, _bag, slot)
			return ({
				{ itemID = THORIUM,  stackCount = 20 },
				{ itemID = FELCLOTH, stackCount = 5 },
				{ itemID = THORIUM,  stackCount = 4 },
			})[slot]
		end
		assert.equal(24, RT:GetPlayerBagCount(THORIUM))
	end)

	it("counts the bank as well, because that is not a reason to buy more", function()
		bagsHolding({ [THORIUM] = 5 })
		ns.lib.db.char.bankCounts = { [THORIUM] = 40 }
		assert.equal(45, RT:GetPlayerBagCount(THORIUM))
	end)

	it("counts the mailbox too", function()
		bagsHolding({ [THORIUM] = 5 })
		ns.lib.db.char.mailCounts = { [THORIUM] = 10 }
		assert.equal(15, RT:GetPlayerBagCount(THORIUM))
	end)

	it("adds bags, bank and mail together", function()
		bagsHolding({ [THORIUM] = 1 })
		ns.lib.db.char.bankCounts = { [THORIUM] = 2 }
		ns.lib.db.char.mailCounts = { [THORIUM] = 4 }
		assert.equal(7, RT:GetPlayerBagCount(THORIUM))
	end)

	it("does not count a different item", function()
		bagsHolding({ [FELCLOTH] = 99 })
		ns.lib.db.char.bankCounts = { [FELCLOTH] = 99 }
		assert.equal(0, RT:GetPlayerBagCount(THORIUM))
	end)

	it("treats a stack with no count as a single item", function()
		ns.GetNumBagSlots       = function() return 0 end
		ns.GetContainerNumSlots = function() return 1 end
		ns.GetContainerItemInfo = function() return { itemID = THORIUM } end
		assert.equal(1, RT:GetPlayerBagCount(THORIUM))
	end)

	it("reports nothing when you hold none of it", function()
		assert.equal(0, RT:GetPlayerBagCount(THORIUM))
	end)
end)
