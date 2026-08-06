-- CooldownsTab's profession filter — and the version gate inside it.
--
-- The cooldown taxonomy lists every shared-timer cooldown per profession, each
-- entry carrying `isAvailable()` for the expansion it arrived in. That gate is
-- applied in exactly one place, `ProfessionMatchesRow`, so it is the only thing
-- standing between a Classic Era player and a filter that matches Northrend
-- Alchemy Research.
--
-- These specs run as Classic Era (the env's flavour), which makes them a real
-- multi-version assertion rather than a restatement of the table: every
-- later-expansion entry must be inert here, and the Vanilla ones must still
-- match. Drop the gate and this file fails; drop an entry and it fails too.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, matches

local ALCHEMY, TAILORING, ENCHANTING = 171, 197, 333

-- Vanilla-era cooldowns.
local MOONCLOTH = 18560
-- Later expansions, which must not match on Classic Era.
local NORTHREND_ALCHEMY_RESEARCH = 60893   -- Wrath
local PRIMAL_MOONCLOTH           = 26751   -- TBC
local GLACIAL_BAG                = 56005   -- Wrath

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/CooldownsTab.lua")
	matches = ns.CooldownsTab._ProfessionMatchesRow
end)

before_each(function()
	env.installFrames()
	env.resetDb()
end)

describe("the flavour these specs run as", function()
	it("is Classic Era, which is what makes the gate assertions mean anything", function()
		-- Stated rather than assumed: every "must not match" below is only a
		-- real assertion while this holds.
		assert.is_true(ns.isVanilla == true)
		assert.is_falsy(ns.isTBC)
		assert.is_falsy(ns.isWrath)
	end)
end)

describe("ProfessionMatchesRow — what this expansion has", function()
	it("matches a transmute row against Alchemy", function()
		assert.is_true(matches(ALCHEMY, { isTransmuteGroup = true }))
	end)

	it("matches Mooncloth against Tailoring", function()
		assert.is_true(matches(TAILORING, { spellId = MOONCLOTH }))
	end)
end)

describe("ProfessionMatchesRow — what this expansion does not have", function()
	it("does not match Northrend Alchemy Research on Classic Era", function()
		-- Wrath-only. Without the isAvailable gate this matches, and the
		-- Alchemy filter starts offering a cooldown that cannot exist.
		assert.is_false(matches(ALCHEMY, { spellId = NORTHREND_ALCHEMY_RESEARCH }))
	end)

	it("does not match TBC specialty cloth on Classic Era", function()
		assert.is_false(matches(TAILORING, { spellId = PRIMAL_MOONCLOTH }))
	end)

	it("does not match the Wrath Glacial Bag on Classic Era", function()
		assert.is_false(matches(TAILORING, { spellId = GLACIAL_BAG }))
	end)
end)

describe("ProfessionMatchesRow — rows that belong to nobody", function()
	it("matches nothing for a profession with no cooldowns", function()
		-- Enchanting has no shared-timer cooldowns; the filter must not claim
		-- rows just because the profession exists.
		assert.is_false(matches(ENCHANTING, { spellId = MOONCLOTH }))
	end)

	it("matches nothing for an unknown profession id", function()
		assert.is_false(matches(99999, { spellId = MOONCLOTH }))
		assert.is_false(matches(nil, { spellId = MOONCLOTH }))
	end)

	it("does not match a spell that belongs to another profession", function()
		assert.is_false(matches(ALCHEMY, { spellId = MOONCLOTH }))
	end)

	it("does not match a transmute row against Tailoring", function()
		assert.is_false(matches(TAILORING, { isTransmuteGroup = true }))
	end)

	it("does not match a row with no spell and no group", function()
		assert.is_false(matches(ALCHEMY, {}))
		assert.is_false(matches(TAILORING, {}))
	end)
end)
