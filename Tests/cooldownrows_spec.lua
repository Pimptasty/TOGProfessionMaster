-- The Cooldowns tab's row pipeline and its supply-mail planner.
--
-- Row building is where several shipped bugs lived: transmutes collapsing into
-- one group per player, multi-reagent crafts needing an expandable row, stale
-- whitelist junk (a Fire Mage talent, a city portal) being rendered as cooldowns,
-- Salt Shaker resolving to an unrelated SPELL of the same id, and rows for a
-- profession the character has since dropped.
--
-- The sort matters more than it looks: every ready cooldown ties at the same key
-- and Lua's table.sort is unstable, so without an explicit tiebreaker the Ready
-- Only list reshuffled itself on every redraw.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, CD, gdb, data
local ME   = "Testchar-Testrealm"
local MATE = "Bob-Testrealm"
local NOW  = 100000

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	CD = env.loadModule("GUI/CooldownsTab.lua").CooldownsTab
end)

before_each(function()
	env.install()
	env.serverTime = NOW
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({})
	_G.GetItemInfo  = function() return nil end
	_G.GetSpellInfo = function(id) return "Spell " .. tostring(id) end
	_G.GetItemIcon  = function() return nil end
	data = ns:GetCooldownData()
end)

-- A spell id from the shipped whitelist, and one that is a transmute.
local function anyWhitelisted()
	for spellId in pairs(data.cooldowns) do
		if not data.transmutes[spellId] and not (data.groupBySpell and data.groupBySpell[spellId])
		   and not (data.multiReagents and data.multiReagents[spellId]) then
			return spellId
		end
	end
end

local function anyTransmute()
	for spellId in pairs(data.transmutes) do return spellId end
end

local function give(charKey, spellId, expiresAt)
	gdb.cooldowns[charKey] = gdb.cooldowns[charKey] or {}
	gdb.cooldowns[charKey][spellId] = expiresAt
end

-- A cooldown that is profession-gated AND renders as a plain single row, so a
-- "did the row appear?" assertion can actually fail in both directions.
local function professionGatedSingle()
	for spellId, profId in pairs(data.professionOf) do
		if data.cooldowns[spellId]
		   and not data.transmutes[spellId]
		   and not (data.groupBySpell and data.groupBySpell[spellId])
		   and not (data.multiReagents and data.multiReagents[spellId]) then
			return spellId, profId
		end
	end
end

describe("SecondsToString", function()
	it("says Ready at or past zero", function()
		-- The locale string carries its own colour code; match the word.
		assert.is_true(CD._SecondsToString(0):find("Ready", 1, true) ~= nil)
		assert.is_true(CD._SecondsToString(-500):find("Ready", 1, true) ~= nil)
	end)

	it("drops to minutes under an hour", function()
		assert.equal("5m", CD._SecondsToString(5 * 60))
		assert.equal("0m", CD._SecondsToString(30))
	end)

	it("shows hours and minutes under a day", function()
		assert.equal("2h 30m", CD._SecondsToString(2 * 3600 + 30 * 60))
		assert.equal("2h", CD._SecondsToString(2 * 3600))
	end)

	it("shows days and hours beyond that, and drops the minutes", function()
		assert.equal("1d 2h", CD._SecondsToString(86400 + 2 * 3600 + 59 * 60))
		assert.equal("3d", CD._SecondsToString(3 * 86400))
	end)
end)

describe("CollectCooldownsByChar", function()
	it("scopes the guild view to the current guild's roster", function()
		-- Cooldowns carry no guild tag, so without this every character in the
		-- account-wide table rendered under whichever guild you were in.
		give(MATE, 12345, NOW + 60)
		give("Outsider-Testrealm", 12345, NOW + 60)
		local out = CD._CollectCooldownsByChar("guild")
		assert.is_true(out[MATE] ~= nil)
		assert.is_nil(out["Outsider-Testrealm"])
	end)

	it("the mine view returns own characters regardless of guild", function()
		give("Away-Testrealm", 12345, NOW + 60)
		gdb.accountChars["Away-Testrealm"] = true
		give(MATE, 12345, NOW + 60)
		local out = CD._CollectCooldownsByChar("mine")
		assert.is_true(out["Away-Testrealm"] ~= nil)
		assert.is_nil(out[MATE])
	end)

	it("copes with an empty database", function()
		gdb.cooldowns = nil
		assert.same({}, CD._CollectCooldownsByChar("guild"))
	end)
end)

describe("BuildRows", function()
	it("returns nothing when nobody has a cooldown", function()
		assert.same({}, CD._BuildRows(false, "guild"))
	end)

	it("emits a row for a whitelisted cooldown", function()
		local spellId = anyWhitelisted()
		give(MATE, spellId, NOW + 3600)
		local rows = CD._BuildRows(false, "guild")
		assert.equal(1, #rows)
		assert.equal(MATE, rows[1].charKey)
		assert.equal("Bob", rows[1].shortName)
		assert.equal(NOW + 3600, rows[1].expiresAt)
	end)

	it("refuses to render a spell that isn't on the whitelist", function()
		-- Stale junk (a Fire Mage talent, a city portal) reached gdb.cooldowns
		-- through old code paths and peer broadcasts; it must never draw a row.
		give(MATE, 12360, NOW + 3600)   -- Impact, a mage talent
		assert.same({}, CD._BuildRows(false, "guild"))
	end)

	it("collapses every transmute for one player into a single group row", function()
		local t1 = anyTransmute()
		local t2
		for spellId in pairs(data.transmutes) do
			if spellId ~= t1 then t2 = spellId; break end
		end
		give(MATE, t1, NOW + 100)
		give(MATE, t2, NOW + 500)
		local rows = CD._BuildRows(false, "guild")
		assert.equal(1, #rows)
		assert.is_true(rows[1].isTransmuteGroup)
		-- The group carries the furthest-out expiry of its members.
		assert.equal(NOW + 500, rows[1].expiresAt)
	end)

	it("treats a transmute group as ready when every member is ready", function()
		local t1 = anyTransmute()
		give(MATE, t1, NOW - 10)
		local rows = CD._BuildRows(true, "guild")
		assert.equal(1, #rows)
		assert.is_true(rows[1].expiresAt <= NOW)
	end)

	it("readyOnly hides a cooldown that is still running", function()
		local spellId = anyWhitelisted()
		give(MATE, spellId, NOW + 3600)
		assert.same({}, CD._BuildRows(true, "guild"))
	end)

	it("readyOnly keeps a cooldown that has expired", function()
		local spellId = anyWhitelisted()
		give(MATE, spellId, NOW - 5)
		assert.equal(1, #CD._BuildRows(true, "guild"))
	end)

	it("hides a cooldown whose profession the character has dropped", function()
		local spellId, profId = professionGatedSingle()
		gdb.accountChars[ME] = true
		gdb.lastScan[ME] = { professions = 500 }

		-- Prove the row DOES render while the profession is held, so the
		-- disappearance below is the gate acting and not a fixture that could
		-- never have produced a row in the first place.
		give(ME, spellId, NOW + 3600)
		gdb.skills[ME] = { [profId] = { skillRank = 300, skillMax = 300 } }
		assert.equal(1, #CD._BuildRows(false, "guild"))

		gdb.skills[ME] = {}            -- authoritative snapshot: profession gone
		assert.same({}, CD._BuildRows(false, "guild"))
	end)

	it("never guesses for a character whose snapshot we don't hold", function()
		local spellId = professionGatedSingle()
		give(ME, spellId, NOW + 3600)
		gdb.accountChars[ME] = true
		gdb.skills[ME] = {}            -- but no lastScan.professions
		assert.equal(1, #CD._BuildRows(false, "guild"))
	end)

	it("emits one grouped row per group, not one per member spell", function()
		local groupSpell, group
		for spellId, g in pairs(data.groupBySpell or {}) do groupSpell, group = spellId, g; break end
		if not groupSpell then return end
		local second
		for sid in pairs(group.spells) do
			if sid ~= groupSpell then second = sid; break end
		end
		give(MATE, groupSpell, NOW + 100)
		if second then give(MATE, second, NOW + 900) end
		local rows = CD._BuildRows(false, "guild")
		assert.equal(1, #rows)
		assert.is_true(rows[1].isGroup)
		assert.equal(group.label, rows[1].cdName)
		if second then assert.equal(NOW + 900, rows[1].expiresAt) end
	end)

	it("hides a banker alt's Salt Shaker, which they cannot use", function()
		give(MATE, data.saltShakerItem, NOW + 3600)
		_G.TOGBankClassic_Guild = {
			Info = { alts = {} },
			GetBanks = function() return {} end,
			IsBank = function(_, ck) return ck == MATE end,
		}
		local rows = CD._BuildRows(false, "guild")
		_G.TOGBankClassic_Guild = nil
		assert.same({}, rows)
	end)

	it("names Salt Shaker from the ITEM, not the spell that shares its id", function()
		-- 15846 is both the Salt Shaker item and "Veil of Shadow"; resolving via
		-- GetSpellInfo first labelled the row with the NPC ability.
		give(MATE, data.saltShakerItem, NOW + 3600)
		_G.GetItemInfo = function(id)
			if id == data.saltShakerItem then return "Salt Shaker" end
		end
		assert.equal("Salt Shaker", CD._BuildRows(false, "guild")[1].cdName)
	end)

	it("falls back to a sane name when the client knows neither", function()
		give(MATE, data.saltShakerItem, NOW + 3600)
		_G.GetItemInfo = function() return nil end
		assert.equal("Salt Shaker", CD._BuildRows(false, "guild")[1].cdName)
	end)

	it("builds rows for several characters at once", function()
		local spellId = anyWhitelisted()
		give(MATE, spellId, NOW + 100)
		give(ME,   spellId, NOW + 200)
		assert.equal(2, #CD._BuildRows(false, "guild"))
	end)
end)

describe("SortRows", function()
	local function rows()
		return {
			{ shortName = "Zed", cdName = "Beta",  expiresAt = NOW + 500 },
			{ shortName = "Abe", cdName = "Alpha", expiresAt = NOW + 100 },
			{ shortName = "Moe", cdName = "Gamma", expiresAt = NOW - 50 },
		}
	end

	it("sorts by character name", function()
		local r = rows()
		CD._SortRows(r, "char", true)
		assert.equal("Abe", r[1].shortName)
		assert.equal("Zed", r[3].shortName)
	end)

	it("reverses on descending", function()
		local r = rows()
		CD._SortRows(r, "char", false)
		assert.equal("Zed", r[1].shortName)
	end)

	it("sorts by cooldown name", function()
		local r = rows()
		CD._SortRows(r, "cd", true)
		assert.equal("Alpha", r[1].cdName)
	end)

	it("puts ready cooldowns first when sorting by time", function()
		local r = rows()
		CD._SortRows(r, "time", true)
		assert.equal("Moe", r[1].shortName)
		assert.equal("Zed", r[3].shortName)
	end)

	it("orders tied rows deterministically, so a redraw doesn't reshuffle", function()
		-- Every ready cooldown ties at the same key; table.sort is not stable, so
		-- without the explicit tiebreaker the Ready Only view jumped around.
		local a = { { shortName = "Zed", cdName = "Beta",  expiresAt = NOW - 1 },
		            { shortName = "Abe", cdName = "Alpha", expiresAt = NOW - 9 },
		            { shortName = "Moe", cdName = "Alpha", expiresAt = NOW - 5 } }
		local b = { a[3], a[1], a[2] }
		CD._SortRows(a, "time", true)
		CD._SortRows(b, "time", true)
		for i = 1, 3 do
			assert.equal(a[i].shortName, b[i].shortName)
		end
		-- Tiebreak is cooldown name, then character name.
		assert.equal("Alpha", a[1].cdName)
		assert.equal("Abe", a[1].shortName)
	end)
end)

describe("column widths", function()
	it("splits the spare space evenly between name and reagent", function()
		local icon, name, reagent = CD._ComputeCol2InnerWidths(360, true, false, false)
		assert.equal(18, icon)
		assert.is_true(name >= 80 and reagent >= 80)
		assert.is_true(math.abs(name - reagent) <= 1)
	end)

	it("gives the whole span to the name when there is no reagent", function()
		local _, name, reagent, _, _, mail = CD._ComputeCol2InnerWidths(360, false, false, false)
		assert.equal(0, reagent)
		assert.equal(0, mail)
		assert.is_true(name >= 80)
	end)

	it("reserves space for the buttons that are actually shown", function()
		local _, _, _, ah, bank, mail = CD._ComputeCol2InnerWidths(360, true, true, true)
		assert.equal(40, ah)
		assert.equal(40, bank)
		assert.equal(20, mail)
	end)

	it("never drops below the per-cell minimums, however narrow the column", function()
		local _, name, reagent = CD._ComputeCol2InnerWidths(50, true, true, true)
		assert.is_true(name >= 80)
		assert.is_true(reagent >= 80)
	end)
end)

describe("supply-mail planner", function()
	local function bags(counts)
		local slots = {}
		for i, c in ipairs(counts) do slots[i] = { bag = 0, slot = i, count = c } end
		return slots
	end

	local function total(list)
		local n = 0
		for _, s in ipairs(list) do n = n + s.count end
		return n
	end

	it("reports nothing to send when the bags are empty", function()
		local plan = CD._CalculateFulfillmentPlan({}, 10, 0)
		assert.is_false(plan.canFulfill)
		assert.equal(0, plan.totalAttachable)
	end)

	it("attaches whole stacks when they add up exactly", function()
		local plan = CD._CalculateFulfillmentPlan(bags({ 20, 10 }), 30, 30)
		assert.is_true(plan.canFulfill)
		assert.equal(30, total(plan.stacksToAttach))
		assert.is_nil(plan.splitStack)
	end)

	it("prefers the largest stacks first", function()
		local plan = CD._CalculateFulfillmentPlan(bags({ 5, 20, 5 }), 20, 30)
		assert.is_true(plan.canFulfill)
		assert.equal(1, #plan.stacksToAttach)
		assert.equal(20, plan.stacksToAttach[1].count)
	end)

	it("skips a stack when doing so makes the total come out exact", function()
		-- Greedy alone takes 12 then can't reach 15; skipping it and taking
		-- 10 + 5 does. That retry is what this branch exists for.
		local plan = CD._CalculateFulfillmentPlan(bags({ 12, 10, 5 }), 15, 27)
		assert.is_true(plan.canFulfill)
		assert.equal(15, total(plan.stacksToAttach))
	end)

	it("splits a stack for the remainder when no combination is exact", function()
		local plan = CD._CalculateFulfillmentPlan(bags({ 20, 20 }), 30, 40)
		assert.is_true(plan.canFulfill)
		assert.is_true(plan.splitStack ~= nil)
		assert.equal(10, plan.splitStack.amount)
		assert.equal(30, total(plan.stacksToAttach) + plan.splitStack.amount)
	end)

	it("splits from a single oversized stack", function()
		local plan = CD._CalculateFulfillmentPlan(bags({ 100 }), 7, 100)
		assert.is_true(plan.canFulfill)
		assert.equal(7, plan.splitStack.amount)
		assert.equal(0, #plan.stacksToAttach)
	end)

	it("says how many more are needed when the bags fall short", function()
		local plan = CD._CalculateFulfillmentPlan(bags({ 5 }), 20, 5)
		assert.is_false(plan.canFulfill)
		assert.is_true(plan.reason:find("15", 1, true) ~= nil)
	end)
end)

describe("CountItemInBags", function()
	-- These two used to nil C_Container and install the bare bag globals, to
	-- drive Compat's fallback branch. That branch is unreachable on every
	-- flavour this addon supports — Classic Era, Anniversary and Cata/MoP all
	-- document the container API under C_Container ONLY, with no bare call sites
	-- and no deprecation fallback — so what they were really testing was code
	-- the client never reaches. They now go through the real namespace, which is
	-- the branch that runs in game.
	it("totals every stack of the item and reports where they are", function()
		env.wow.bags[0] = {
			slots = 3,
			[1] = { itemID = 2589, count = 12, link = "|Hitem:2589|h" },
			[2] = { itemID = 2589, count = 8,  link = "|Hitem:2589|h" },
			[3] = { itemID = 999,  count = 5,  link = "|Hitem:999|h" },
		}
		local total, stacks = CD._CountItemInBags(2589)
		assert.equal(20, total)
		assert.equal(2, #stacks)
		assert.equal(0, stacks[1].bag)
	end)

	it("reports nothing when the item isn't carried", function()
		-- Bags left empty, which is the harness default.
		local total, stacks = CD._CountItemInBags(2589)
		assert.equal(0, total)
		assert.equal(0, #stacks)
	end)
end)
