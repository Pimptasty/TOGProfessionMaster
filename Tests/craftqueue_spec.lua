-- The craft queue: what to craft next, and keeping the queue honest as crafts
-- complete.
--
-- The completion model is the part that matters. Crafting a stack produces items
-- ONE AT A TIME, each firing UNIT_SPELLCAST_SUCCEEDED, so the queue decrements
-- per item — it must never optimistically remove the whole entry, because a
-- player who walks away mid-stack has to keep the remainder queued. v0.8.1 fixed
-- two holes in exactly that: crafts started from the detail-panel button weren't
-- tracked at all, and an Enchanting batch expected one success per item when
-- DoCraft only ever makes one.
--
-- The REAL CraftingEngine is driven here, with the trade-skill WoW APIs stubbed —
-- that is the honest seam. Substituting a fake engine would test the queue
-- against our assumptions about the engine rather than the engine.

-- Every spec installs its own _G stubs over the same WoW globals; that is the
-- point of a stub, not a mistake worth a warning per line.
---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Queue, Engine, trackFrame
local crafted

-- Install a fake open trade-skill window. `rows` is an array of
-- { name=, recipeId=, num= } (num = how many the mats allow), header rows use
-- { name=, header=true }.
local function openWindow(rows)
	_G.GetTradeSkillLine       = function() return "Alchemy", 300, 300 end
	_G.GetNumTradeSkills       = function() return #rows end
	_G.ExpandTradeSkillSubClass = nil
	_G.GetTradeSkillInfo = function(i)
		local r = rows[i]
		if not r then return nil end
		if r.header then return r.name, "header", 0, true end
		return r.name, "optimal", r.num or 0, true
	end
	_G.GetTradeSkillRecipeLink = function(i)
		local r = rows[i]
		return r and not r.header and ("|Henchant:" .. r.recipeId .. "|h") or nil
	end
	_G.GetTradeSkillItemLink   = function(_index) return nil end
	_G.GetTradeSkillIcon       = function() return nil end
	_G.GetTradeSkillNumReagents = function() return 0 end
	_G.GetTradeSkillReagentInfo = function() return nil end
	_G.DoTradeSkill = function(index, qty)
		crafted[#crafted + 1] = { index = index, qty = qty }
	end
	Engine._sessionOpen   = true
	Engine._isCraftWindow = false
end

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")

	-- Capture the module's own event frame so the real UNIT_SPELLCAST_* wiring
	-- (including its "player" unit filter) is exercised, not bypassed.
	local realCreateFrame, last = _G.CreateFrame, nil
	_G.CreateFrame = function(...) last = realCreateFrame(...); return last end
	Queue = env.loadModule("Modules/Crafting/CraftQueue.lua").CraftQueue
	_G.CreateFrame = realCreateFrame
	trackFrame = last

	Engine = ns.CraftingEngine
end)

before_each(function()
	env.install()
	crafted = {}
	local q = Queue:Get()
	for i = #q, 1, -1 do q[i] = nil end
	Queue._active   = nil
	Queue._craftAll = false
	Engine._sessionOpen = false
	env.setRecipeDB({ [171] = { [2330] = { name = "Minor Healing Potion" } } })
end)

describe("queue mutations", function()
	it("starts empty", function()
		assert.is_true(Queue:IsEmpty())
		assert.equal(0, Queue:Count())
	end)

	it("appends a new recipe to the BOTTOM so existing priorities survive", function()
		Queue:Add(171, 2330, 2)
		Queue:Add(171, 2331, 1)
		assert.equal(2330, Queue:Get()[1].recipeId)
		assert.equal(2331, Queue:Get()[2].recipeId)
	end)

	it("accumulates onto an existing entry, keeping its rank", function()
		Queue:Add(171, 2330, 2)
		Queue:Add(171, 2331, 1)
		Queue:Add(171, 2330, 3)
		assert.equal(5, Queue:Get()[1].qty)
		assert.equal(2, Queue:Count())
	end)

	it("keeps the same recipe id in two professions apart", function()
		Queue:Add(171, 2330, 1)
		Queue:Add(197, 2330, 1)
		assert.equal(2, Queue:Count())
	end)

	it("floors a fractional quantity and never queues less than one", function()
		Queue:Add(171, 2330, 2.9)
		assert.equal(2, Queue:Get()[1].qty)
		Queue:Add(171, 2331, 0)
		assert.equal(1, Queue:Get()[2].qty)
		Queue:Add(171, 2332, -5)
		assert.equal(1, Queue:Get()[3].qty)
	end)

	it("ignores an add with no recipe", function()
		Queue:Add(nil, 2330, 1)
		Queue:Add(171, nil, 1)
		assert.is_true(Queue:IsEmpty())
	end)

	it("removes an entry when its quantity is set to zero or below", function()
		Queue:Add(171, 2330, 3)
		Queue:SetQty(1, 0)
		assert.is_true(Queue:IsEmpty())
	end)

	it("ignores SetQty and Remove for an index that isn't there", function()
		Queue:SetQty(4, 2)
		Queue:Remove(4)
		assert.is_true(Queue:IsEmpty())
	end)

	it("removes by index", function()
		Queue:Add(171, 2330, 1)
		Queue:Add(171, 2331, 1)
		Queue:Remove(1)
		assert.equal(1, Queue:Count())
		assert.equal(2331, Queue:Get()[1].recipeId)
	end)

	it("clears everything, including an in-flight batch", function()
		Queue:Add(171, 2330, 1)
		Queue._active   = { recipeId = 2330, profId = 171, remaining = 1 }
		Queue._craftAll = true
		Queue:Clear()
		assert.is_true(Queue:IsEmpty())
		assert.is_nil(Queue._active)
		assert.is_false(Queue._craftAll)
	end)
end)

describe("Move (drag-to-reorder)", function()
	before_each(function()
		Queue:Add(171, 1, 1); Queue:Add(171, 2, 1); Queue:Add(171, 3, 1)
	end)

	it("moves an entry to the top", function()
		Queue:Move(3, 1)
		assert.equal(3, Queue:Get()[1].recipeId)
		assert.equal(1, Queue:Get()[2].recipeId)
	end)

	it("clamps a target past either end instead of erroring", function()
		Queue:Move(1, 99)
		assert.equal(1, Queue:Get()[3].recipeId)
		Queue:Move(3, -4)
		assert.equal(1, Queue:Get()[1].recipeId)
	end)

	it("does nothing for a no-op move or a missing source", function()
		Queue:Move(2, 2)
		Queue:Move(9, 1)
		assert.equal(2, Queue:Get()[2].recipeId)
	end)
end)

describe("NextEligible", function()
	it("finds nothing while no profession window is open", function()
		Queue:Add(171, 2330, 1)
		assert.is_nil(Queue:NextEligible())
		assert.is_false(Queue:CanCraftNext())
	end)

	it("takes the highest-ranked entry that can actually be made now", function()
		openWindow({ { name = "Minor Healing Potion", recipeId = 2330, num = 5 } })
		Queue:Add(171, 2331, 1)   -- not in the open window at all
		Queue:Add(171, 2330, 1)
		local i, entry = Queue:NextEligible()
		assert.equal(2, i)
		assert.equal(2330, entry.recipeId)
	end)

	it("skips a recipe the mats don't allow", function()
		openWindow({ { name = "Minor Healing Potion", recipeId = 2330, num = 0 } })
		Queue:Add(171, 2330, 1)
		assert.is_nil(Queue:NextEligible())
	end)

	it("skips entries for a profession that isn't the open one", function()
		openWindow({ { name = "Minor Healing Potion", recipeId = 2330, num = 5 } })
		Queue:Add(197, 2330, 1)
		assert.is_nil(Queue:NextEligible())
	end)
end)

describe("CraftNext", function()
	it("crafts no more than the mats allow", function()
		openWindow({ { name = "Minor Healing Potion", recipeId = 2330, num = 3 } })
		Queue:Add(171, 2330, 10)
		Queue:CraftNext()
		assert.same({ { index = 1, qty = 3 } }, crafted)
	end)

	it("crafts no more than the queued quantity", function()
		openWindow({ { name = "Minor Healing Potion", recipeId = 2330, num = 99 } })
		Queue:Add(171, 2330, 2)
		Queue:CraftNext()
		assert.same({ { index = 1, qty = 2 } }, crafted)
	end)

	it("resolves the LIVE index rather than a remembered one", function()
		-- Indices shift with expand/filter state; crafting a stale one would make
		-- the wrong item.
		openWindow({
			{ name = "Potions", header = true },
			{ name = "Minor Healing Potion", recipeId = 2330, num = 1 },
		})
		Queue:Add(171, 2330, 1)
		Queue:CraftNext()
		assert.equal(2, crafted[1].index)
	end)

	it("does nothing when nothing is eligible", function()
		Queue:Add(171, 2330, 1)
		Queue:CraftNext()
		assert.equal(0, #crafted)
	end)
end)

describe("completion tracking", function()
	before_each(function()
		openWindow({ { name = "Minor Healing Potion", recipeId = 2330, num = 5 } })
	end)

	it("decrements one per finished craft and leaves the remainder queued", function()
		Queue:Add(171, 2330, 3)
		Queue:TrackCraft(2330, 3)
		Queue:_OnCraftSuccess()
		assert.equal(2, Queue:Get()[1].qty)
		Queue:_OnCraftSuccess()
		assert.equal(1, Queue:Get()[1].qty)
	end)

	it("drops the entry once the last one is made", function()
		Queue:Add(171, 2330, 1)
		Queue:TrackCraft(2330, 1)
		Queue:_OnCraftSuccess()
		assert.is_true(Queue:IsEmpty())
		assert.is_nil(Queue._active)
	end)

	it("ignores a success for a recipe that isn't queued", function()
		Queue:TrackCraft(2330, 1)
		Queue:_OnCraftSuccess()
		assert.is_true(Queue:IsEmpty())
	end)

	it("ignores a success when no batch is being tracked", function()
		Queue:Add(171, 2330, 2)
		Queue:_OnCraftSuccess()
		assert.equal(2, Queue:Get()[1].qty)
	end)

	it("expects at least one success even if asked for zero", function()
		Queue:TrackCraft(2330, 0)
		assert.equal(1, Queue._active.remaining)
	end)

	it("stamps the batch with the OPEN profession", function()
		Queue:TrackCraft(2330, 1)
		assert.equal(171, Queue._active.profId)
	end)

	it("decrements from the real UNIT_SPELLCAST_SUCCEEDED event", function()
		Queue:Add(171, 2330, 2)
		Queue:TrackCraft(2330, 2)
		trackFrame:Fire("OnEvent", "UNIT_SPELLCAST_SUCCEEDED", "player")
		assert.equal(1, Queue:Get()[1].qty)
	end)

	it("ignores spellcast events from anyone but the player", function()
		Queue:Add(171, 2330, 2)
		Queue:TrackCraft(2330, 2)
		trackFrame:Fire("OnEvent", "UNIT_SPELLCAST_SUCCEEDED", "party1")
		assert.equal(2, Queue:Get()[1].qty)
	end)

	it("keeps the unmade remainder queued when the batch is interrupted", function()
		Queue:Add(171, 2330, 5)
		Queue:TrackCraft(2330, 5)
		trackFrame:Fire("OnEvent", "UNIT_SPELLCAST_SUCCEEDED", "player")
		trackFrame:Fire("OnEvent", "UNIT_SPELLCAST_INTERRUPTED", "player")
		assert.equal(4, Queue:Get()[1].qty)
		assert.is_nil(Queue._active)
	end)

	it("stops a Craft All run on interrupt", function()
		Queue:Add(171, 2330, 5)
		Queue._craftAll = true
		Queue:TrackCraft(2330, 5)
		trackFrame:Fire("OnEvent", "UNIT_SPELLCAST_FAILED", "player")
		assert.is_false(Queue._craftAll)
	end)
end)

describe("CraftAll", function()
	it("does nothing on an empty queue", function()
		Queue:CraftAll()
		assert.is_false(Queue._craftAll)
	end)

	it("chains to the next entry as each batch finishes", function()
		openWindow({
			{ name = "Minor Healing Potion", recipeId = 2330, num = 1 },
			{ name = "Elixir", recipeId = 2331, num = 1 },
		})
		-- C_Timer.After fires immediately in the offline env, so the chain runs
		-- through synchronously.
		_G.C_Timer = { After = function(_, fn) fn() end }
		Queue:Add(171, 2330, 1)
		Queue:Add(171, 2331, 1)
		Queue:CraftAll()
		assert.equal(1, #crafted)

		Queue:TrackCraft(2330, 1)
		Queue:_OnCraftSuccess()
		assert.equal(2, #crafted)
		assert.equal(2, crafted[2].index)
	end)

	it("stops itself once nothing is left to make", function()
		openWindow({ { name = "Minor Healing Potion", recipeId = 2330, num = 1 } })
		_G.C_Timer = { After = function(_, fn) fn() end }
		Queue:Add(171, 2330, 1)
		Queue:CraftAll()
		Queue:TrackCraft(2330, 1)
		Queue:_OnCraftSuccess()
		assert.is_false(Queue._craftAll)
	end)
end)
