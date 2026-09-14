-- The Cooldowns tab's supply mail: ONE mail per cooldown, with EVERY reagent
-- of that cooldown on it (v1.1.0).
--
-- Before this, each reagent row in the transmute popup carried its own mail
-- button, so an Arcanite transmute (Thorium Bar + Arcane Crystal) took two
-- mails. Now the planner sums every reagent, every split runs from the one
-- click, and the attach step waits for the splits to land before it touches a
-- send slot. These examples drive the harness's real bags, cursor and
-- send-mail slots -- the same PickupContainerItem / SplitContainerItem /
-- ClickSendMailItemButton chain the client runs -- and the timers the split
-- path schedules are advanced by `wow.flushTimers` / `wow.advanceTime`.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")
local wow = env.wow

local CD
local ME      = "Testchar-Testrealm"
local THORIUM = 12359
local CRYSTAL = 12360
local ARCANITE = { { id = THORIUM, qty = 1 }, { id = CRYSTAL, qty = 1 } }

setup(function()
	env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	CD = env.loadModule("GUI/CooldownsTab.lua").CooldownsTab
end)

before_each(function()
	env.install()
	wow.items[THORIUM] = { name = "Thorium Bar",    stackCount = 20 }
	wow.items[CRYSTAL] = { name = "Arcane Crystal", stackCount = 20 }
	MailFrame:Show()
end)

--- The backpack, `slots` wide, empty.
local function backpack(slots)
	wow.bags[0] = { slots = slots or 16 }
	return wow.bags[0]
end

local function stack(bag, slot, itemID, count)
	bag[slot] = { itemID = itemID, count = count, link = "|Hitem:" .. itemID .. "|h" }
	return bag[slot]
end

--- What is on the mail, in slot order, as { {itemID, count}, ... }.
local function attached()
	local out = {}
	for i = 1, ATTACHMENTS_MAX_SEND do
		local it = wow.sendMailItems[i]
		if it then out[#out + 1] = { it.itemID, it.count } end
	end
	return out
end

--- Items on the mail summed per item id.
local function attachedTotals()
	local out = {}
	for _, a in ipairs(attached()) do out[a[1]] = (out[a[1]] or 0) + a[2] end
	return out
end

--- The last chat line with the addon's coloured prefix stripped.
local function lastChat()
	local line = wow.chat[#wow.chat] or ""
	return (line:gsub("^|c%x%x%x%x%x%x%x%xTOG Profession Master:|r ", ""))
end

local function send(reagents)
	CD._PrepareSupplyMail(ME, "Transmute: Arcanite", "Arcanite Bar", reagents or ARCANITE)
end

describe("EmptyBagSlots", function()
	it("hands back the first n empties in bag order", function()
		local bag = backpack(4)
		stack(bag, 1, THORIUM, 1)
		stack(bag, 3, CRYSTAL, 1)
		assert.same({ { bag = 0, slot = 2 }, { bag = 0, slot = 4 } }, CD._EmptyBagSlots(2))
	end)

	it("stops at n, and hands back fewer when the bags have fewer", function()
		backpack(3)
		assert.equal(2, #CD._EmptyBagSlots(2))
		assert.equal(3, #CD._EmptyBagSlots(5))
	end)
end)

describe("PlanSupplyMail", function()
	it("covers every reagent with whole stacks when they fit exactly", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 1)
		stack(bag, 2, CRYSTAL, 1)
		local plan = CD._PlanSupplyMail(ARCANITE)
		assert.is_true(plan.ok)
		assert.equal(2, #plan.stacks)
		assert.equal(0, #plan.splits)
		assert.same({ { qty = 1, name = "Thorium Bar" }, { qty = 1, name = "Arcane Crystal" } }, plan.lines)
	end)

	it("plans a split for every reagent that needs one", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 20)
		stack(bag, 2, CRYSTAL, 5)
		local plan = CD._PlanSupplyMail(ARCANITE)
		assert.is_true(plan.ok)
		assert.equal(0, #plan.stacks)
		assert.equal(2, #plan.splits)
		assert.equal(THORIUM, plan.splits[1].itemId)
		assert.equal(1, plan.splits[1].amount)
		assert.equal(CRYSTAL, plan.splits[2].itemId)
	end)

	it("refuses the whole mail when ANY reagent is short, and names every shortfall", function()
		-- A supply mail with the bars and no crystal is not a supply mail.
		local bag = backpack()
		stack(bag, 1, THORIUM, 1)
		local plan = CD._PlanSupplyMail(ARCANITE)
		assert.is_false(plan.ok)
		assert.equal(1, #plan.problems)
		assert.is_true(plan.problems[1]:find("Arcane Crystal", 1, true) ~= nil)

		bag[1] = nil
		plan = CD._PlanSupplyMail(ARCANITE)
		assert.is_false(plan.ok)
		assert.equal(2, #plan.problems)
	end)

	it("reports how many more when a reagent is carried but not enough of it", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 2)
		stack(bag, 2, CRYSTAL, 1)
		local plan = CD._PlanSupplyMail({ { id = THORIUM, qty = 5 }, { id = CRYSTAL, qty = 1 } })
		assert.is_false(plan.ok)
		assert.is_true(plan.problems[1]:find("Thorium Bar", 1, true) ~= nil)
		assert.is_true(plan.problems[1]:find("3", 1, true) ~= nil)
	end)

	it("refuses a mail that would take more attachment slots than a mail has", function()
		local bag = backpack(20)
		for slot = 1, 13 do stack(bag, slot, THORIUM, 1) end
		local plan = CD._PlanSupplyMail({ { id = THORIUM, qty = 13 } })
		assert.is_false(plan.ok)
		assert.is_true(plan.problems[1]:find("13", 1, true) ~= nil)
		assert.is_true(plan.problems[1]:find(tostring(ATTACHMENTS_MAX_SEND), 1, true) ~= nil)
	end)

	it("names an item the client has not cached by its id", function()
		local bag = backpack()
		stack(bag, 1, 999, 1)
		local plan = CD._PlanSupplyMail({ { id = 999, qty = 1 } })
		assert.is_true(plan.ok)
		assert.equal("item:999", plan.lines[1].name)
	end)

	it("has nothing to say about an empty reagent list except that it cannot", function()
		backpack()
		local plan = CD._PlanSupplyMail({})
		assert.is_false(plan.ok)
		assert.equal(1, #plan.problems)
	end)

	it("treats a missing or zero quantity as one, never as nothing to send", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 3)
		local plan = CD._PlanSupplyMail({ { id = THORIUM, qty = 0 }, { id = THORIUM } })
		assert.is_true(plan.ok)
		assert.equal(1, plan.lines[1].qty)
		assert.equal(1, plan.lines[2].qty)
	end)
end)

describe("PrepareSupplyMail", function()
	it("needs the mailbox open", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 1)
		stack(bag, 2, CRYSTAL, 1)
		MailFrame:Hide()
		send()
		assert.same({}, attached())
		assert.is_true(lastChat():find("mailbox", 1, true) ~= nil)
	end)

	it("refuses when the mail already carries something", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 1)
		stack(bag, 2, CRYSTAL, 1)
		wow.sendMailItems[1] = { itemID = 1, count = 1 }
		send()
		assert.same({ { 1, 1 } }, attached())
		assert.equal(1, bag[1].count)
	end)

	it("says every shortfall and attaches nothing when a reagent is missing", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 1)
		send()
		assert.same({}, attached())
		assert.equal(1, bag[1].count)
		assert.is_true(lastChat():find("Arcane Crystal", 1, true) ~= nil)
	end)

	it("attaches every reagent of the cooldown to ONE mail, straight from the click", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 1)
		stack(bag, 2, CRYSTAL, 1)
		send()
		assert.same({ { THORIUM, 1 }, { CRYSTAL, 1 } }, attached())
		assert.is_nil(bag[1])
		assert.is_nil(bag[2])
		assert.is_nil(wow.cursor)
		-- Whole stacks need no timer at all.
		assert.equal(0, wow.pendingTimerCount())
		assert.equal("Testchar", SendMailNameEditBox:GetText())
		assert.equal("Cooldown supply: Transmute: Arcanite", SendMailSubjectEditBox:GetText())
		assert.equal("Attached 1x Thorium Bar, 1x Arcane Crystal for Testchar.", lastChat())
	end)

	it("splits every reagent that needs it from the ONE click, then attaches them all", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 20)
		stack(bag, 2, CRYSTAL, 5)
		send()
		-- Nothing on the mail yet: the pieces are still being placed.
		assert.same({}, attached())
		assert.equal("Splitting 1x Thorium Bar, 1x Arcane Crystal \226\128\148 attaching in a moment.", lastChat())
		assert.is_true(wow.pendingTimerCount() > 0)

		wow.flushTimers()
		assert.same({ { THORIUM, 1 }, { CRYSTAL, 1 } }, attached())
		assert.equal(19, bag[1].count)
		assert.equal(4,  bag[2].count)
		-- The slots the pieces were placed into are empty again.
		assert.is_nil(bag[3])
		assert.is_nil(bag[4])
		assert.is_nil(wow.cursor)
		assert.equal("Attached 1x Thorium Bar, 1x Arcane Crystal for Testchar.", lastChat())
	end)

	it("mixes whole stacks and a split for the same reagent in one mail", function()
		-- 3 bars from a 1-stack and a 20-stack: the 1 goes whole, 2 are split off.
		local bag = backpack()
		stack(bag, 1, THORIUM, 20)
		stack(bag, 2, THORIUM, 1)
		stack(bag, 3, CRYSTAL, 1)
		send({ { id = THORIUM, qty = 3 }, { id = CRYSTAL, qty = 1 } })
		wow.flushTimers()
		assert.same({ [THORIUM] = 3, [CRYSTAL] = 1 }, attachedTotals())
		assert.equal(18, bag[1].count)
		assert.is_nil(bag[2])
		assert.is_nil(bag[3])
	end)

	it("mails a single-reagent cooldown the same way", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 20)
		send({ { id = THORIUM, qty = 4 } })
		wow.flushTimers()
		assert.same({ { THORIUM, 4 } }, attached())
		assert.equal(16, bag[1].count)
	end)

	it("needs a free bag slot for every split, and touches nothing without them", function()
		local bag = backpack(2)
		stack(bag, 1, THORIUM, 20)
		stack(bag, 2, CRYSTAL, 5)
		send()
		assert.equal(20, bag[1].count)
		assert.equal(5,  bag[2].count)
		assert.equal(0, wow.pendingTimerCount())
		assert.is_true(lastChat():find("2 free bag slot", 1, true) ~= nil)
	end)

	it("gives up rather than attaching half a mail when a split piece vanished", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 20)
		stack(bag, 2, CRYSTAL, 5)
		send()
		-- Both pieces have landed (slots 3 and 4) by 0.4s; the attach fires at 0.5s.
		wow.advanceTime(0.4)
		assert.equal(THORIUM, bag[3].itemID)
		assert.equal(CRYSTAL, bag[4].itemID)
		bag[4] = nil                          -- the player moved the crystal piece
		wow.flushTimers()
		assert.same({}, attached())
		assert.is_true(lastChat():find("did not land", 1, true) ~= nil)
	end)

	it("fills the recipient, subject and body of the mail", function()
		-- The body box is the client's MailEditBox (a ScrollingEditBox; Blizzard's
		-- own code calls SetText on it, MailFrame.lua:1010). The harness does not
		-- model it, so a one-method stand-in captures the text. Not owned by the
		-- env, so it is removed again below rather than left for later files.
		local body
		_G.MailEditBox = { SetText = function(_, t) body = t end }
		local bag = backpack()
		stack(bag, 1, THORIUM, 1)
		stack(bag, 2, CRYSTAL, 1)
		send()
		_G.MailEditBox = nil
		assert.equal("Testchar", SendMailNameEditBox:GetText())
		assert.equal("Cooldown supply: Transmute: Arcanite", SendMailSubjectEditBox:GetText())
		assert.is_true(body:find("Hi Testchar!", 1, true) ~= nil)
		assert.is_true(body:find("Arcanite Bar", 1, true) ~= nil)
	end)

	it("puts everything back and says so when a stack the plan counted on has moved", function()
		-- Thorium needs a split; the crystal goes whole. The crystal is moved out
		-- of its slot after the click and before the attach, so its pickup fails:
		-- the thorium piece that was already attached comes back off the mail
		-- rather than going alone under a message claiming both were sent.
		local bag = backpack()
		stack(bag, 1, THORIUM, 20)
		stack(bag, 2, CRYSTAL, 1)
		send()
		wow.advanceTime(0.2)                  -- the thorium piece has landed in slot 3
		assert.equal(THORIUM, bag[3].itemID)
		bag[2] = nil                          -- the player moved the crystal
		wow.flushTimers()
		assert.same({}, attached())
		assert.is_true(lastChat():find("Could not attach", 1, true) ~= nil)
		-- The piece is back in the bags, not lost on the cursor.
		local pieces = 0
		for slot = 1, bag.slots do
			if bag[slot] and bag[slot].itemID == THORIUM and bag[slot].count == 1 then pieces = pieces + 1 end
		end
		assert.equal(1, pieces)
		assert.is_nil(wow.cursor)
	end)

	it("stops if something else was attached while the splits were landing", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 20)
		stack(bag, 2, CRYSTAL, 1)
		send()
		wow.sendMailItems[1] = { itemID = 1, count = 1 }
		wow.flushTimers()
		assert.same({ { 1, 1 } }, attached())
		assert.equal(1, bag[2].count)          -- the crystal was never picked up
		assert.is_true(lastChat():find("already has items", 1, true) ~= nil)
	end)

	it("stops if the mailbox was closed while the splits were landing", function()
		local bag = backpack()
		stack(bag, 1, THORIUM, 20)
		stack(bag, 2, CRYSTAL, 1)
		send()
		MailFrame:Hide()
		wow.flushTimers()
		assert.same({}, attached())
		assert.equal(19, bag[1].count)       -- the split happened; the piece sits in the bag
		assert.equal(THORIUM, bag[3].itemID)
		assert.is_true(lastChat():find("mailbox", 1, true) ~= nil)
	end)
end)
