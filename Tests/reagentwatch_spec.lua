-- Modules/ReagentWatch.lua — the watch list, and the shopping-list alert latch.
--
-- The alert is the part with teeth. "You can now craft X" must fire ONCE when
-- the reagents first arrive, stay quiet while they are still there, and re-arm
-- only after the bags drop below the requirement — otherwise every BAG_UPDATE
-- while you stand at the mailbox is another line of chat. And it must NOT fire
-- on login for something already in your bags, which is a separate code path
-- written for exactly that reason.
--
-- Driven through the real WoW events the module registers rather than by
-- calling the internals, so the wiring is under test too. The harness's
-- lesson: firing the event proves things that calling the method does not.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env    = require("env_togpm")
local frames = require("env.frames")

local ns, RW, saved, printed

local THORIUM, FELCLOTH = 12359, 14256
local TRANSMUTE, MOONCLOTH_CRAFT = 17187, 18560

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/ReagentWatch.lua")
	RW = ns.ReagentWatch
end)

--- Fill the player's bags: { [itemId] = count }.
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

	-- Addon-table methods and one global; env.install() resets globals only, so
	-- these have to be put back or they follow the suite into later spec files.
	saved = {
		GetCooldownData      = ns.GetCooldownData,
		GetNumBagSlots       = ns.GetNumBagSlots,
		GetContainerNumSlots = ns.GetContainerNumSlots,
		GetContainerItemInfo = ns.GetContainerItemInfo,
		Print                = ns.Print,
		_GetItemInfo         = _G.GetItemInfo,
	}

	printed = {}
	ns.Print = function(_, msg) printed[#printed + 1] = tostring(msg) end
	_G.GetItemInfo = function(itemId)
		return ({ [THORIUM] = "Thorium Bar", [FELCLOTH] = "Felcloth" })[itemId]
	end
	ns.GetCooldownData = function()
		return {
			reagents      = { [TRANSMUTE]        = { id = THORIUM,  qty = 2 } },
			transReagents = { [MOONCLOTH_CRAFT]  = { id = FELCLOTH, qty = 1 } },
		}
	end

	bagsHolding({})
	ns.lib.db.char.shoppingList   = {}
	ns.lib.db.char.shoppingAlerts = {}
	ns.lib.db.char.reagentWatch   = {}
end)

after_each(function()
	for name, fn in pairs(saved or {}) do
		if name == "_GetItemInfo" then _G.GetItemInfo = fn else ns[name] = fn end
	end
end)

local function queue(spellId, quantity)
	ns.lib.db.char.shoppingList[spellId] = { quantity = quantity }
end

--- What the client does when bag contents change.
local function bagUpdate()
	frames.fireEvent("BAG_UPDATE")
end

describe("the watch list", function()
	it("adds, reports and removes an item", function()
		RW:Watch(THORIUM)
		assert.is_true(RW:IsWatching(THORIUM))
		RW:Unwatch(THORIUM)
		assert.is_false(RW:IsWatching(THORIUM))
	end)

	it("accepts an item id that arrives as a string", function()
		-- Ids reach this from chat links and edit boxes, not just from code.
		RW:Watch("12359")
		assert.is_true(RW:IsWatching(THORIUM))
		assert.is_true(RW:IsWatching("12359"))
	end)

	it("ignores a nil or non-numeric id rather than erroring", function()
		assert.has_no.errors(function() RW:Watch(nil) end)
		assert.has_no.errors(function() RW:Watch("not an item") end)
		assert.has_no.errors(function() RW:Unwatch(nil) end)
		assert.is_false(RW:IsWatching(nil))
		assert.same({}, ns.lib.db.char.reagentWatch)
	end)

	it("reports what the bags hold for each watched item", function()
		RW:Watch(THORIUM)
		RW:Watch(FELCLOTH)
		bagsHolding({ [THORIUM] = 7 })
		local list = RW:GetWatchedItems()
		assert.equal(2, #list)
		-- Sorted by name: Felcloth before Thorium Bar.
		assert.equal("Felcloth", list[1].itemName)
		assert.equal(0, list[1].count)
		assert.equal(7, list[2].count)
	end)

	it("tells the UI to refresh when the list changes", function()
		-- Its own listener table rather than registering on the addon itself, so
		-- unregistering cannot disturb a real subscriber — and so the handler
		-- cannot outlive this spec file.
		-- Dot-call passing our own listener as `self`: CallbackHandler refuses to
		-- unregister when self is the registry's own target, which is what
		-- `ns:UnregisterCallback(...)` would be.
		local listener, fired = {}, 0
		ns.RegisterCallback(listener, "REAGENT_WATCH_UPDATED",
			function() fired = fired + 1 end)
		RW:Watch(THORIUM)
		RW:Unwatch(THORIUM)
		ns.UnregisterCallback(listener, "REAGENT_WATCH_UPDATED")
		assert.equal(2, fired)
	end)
end)

describe("the craft-ready alert", function()
	it("fires once when the reagents first arrive", function()
		queue(TRANSMUTE, 1)
		bagsHolding({ [THORIUM] = 2 })
		bagUpdate()
		assert.equal(1, #printed)
		assert.is_truthy(printed[1]:find("Thorium Bar", 1, true))
	end)

	it("stays quiet while the reagents are still sitting there", function()
		-- BAG_UPDATE fires constantly. Without the latch this is a line of chat
		-- every time anything moves in your bags.
		queue(TRANSMUTE, 1)
		bagsHolding({ [THORIUM] = 2 })
		bagUpdate()
		bagUpdate()
		bagUpdate()
		assert.equal(1, #printed)
	end)

	it("says nothing while the reagents are short", function()
		queue(TRANSMUTE, 1)
		bagsHolding({ [THORIUM] = 1 })
		bagUpdate()
		assert.equal(0, #printed)
	end)

	it("re-arms after the bags drop below, and alerts again on restock", function()
		-- The whole point of clearing the flag: craft it, buy more, get told.
		queue(TRANSMUTE, 1)
		bagsHolding({ [THORIUM] = 2 })
		bagUpdate()
		assert.equal(1, #printed)

		bagsHolding({ [THORIUM] = 0 })   -- crafted it
		bagUpdate()
		assert.equal(1, #printed)

		bagsHolding({ [THORIUM] = 2 })   -- restocked
		bagUpdate()
		assert.equal(2, #printed)
	end)

	it("counts the queued quantity, not one craft", function()
		queue(TRANSMUTE, 3)              -- 3 × 2 Thorium = 6
		bagsHolding({ [THORIUM] = 5 })
		bagUpdate()
		assert.equal(0, #printed)

		bagsHolding({ [THORIUM] = 6 })
		bagUpdate()
		assert.equal(1, #printed)
	end)

	it("works for a craft that only the transmute catalogue knows", function()
		queue(MOONCLOTH_CRAFT, 2)
		bagsHolding({ [FELCLOTH] = 2 })
		bagUpdate()
		assert.equal(1, #printed)
	end)

	it("ignores a queued craft whose reagents are unknown", function()
		queue(424242, 1)
		bagsHolding({ [THORIUM] = 99 })
		assert.has_no.errors(bagUpdate)
		assert.equal(0, #printed)
	end)
end)

describe("login", function()
	it("does not announce something already sitting in your bags", function()
		-- Otherwise every login greets you with a wall of craft-ready lines.
		queue(TRANSMUTE, 1)
		bagsHolding({ [THORIUM] = 2 })
		frames.fireEvent("PLAYER_LOGIN")
		assert.equal(0, #printed)
	end)

	it("arms the latch silently, so no alert comes on the next bag change", function()
		queue(TRANSMUTE, 1)
		bagsHolding({ [THORIUM] = 2 })
		frames.fireEvent("PLAYER_LOGIN")
		bagUpdate()
		assert.equal(0, #printed)
	end)

	it("leaves a short craft un-armed, so restocking still alerts", function()
		queue(TRANSMUTE, 1)
		bagsHolding({ [THORIUM] = 1 })
		frames.fireEvent("PLAYER_LOGIN")
		bagsHolding({ [THORIUM] = 2 })
		bagUpdate()
		assert.equal(1, #printed)
	end)
end)

describe("ClearAlert", function()
	it("re-arms a craft removed from the shopping list and queued again", function()
		queue(TRANSMUTE, 1)
		bagsHolding({ [THORIUM] = 2 })
		bagUpdate()
		assert.equal(1, #printed)

		RW:ClearAlert(TRANSMUTE)
		bagUpdate()
		assert.equal(2, #printed)
	end)
end)
