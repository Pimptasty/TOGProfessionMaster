-- Scanner.lua driven through a real trade-skill session.
--
-- The scan is where the addon's data comes from: it walks the open profession
-- window and writes recipes, crafters, skills and cooldowns into the guild DB.
-- Existing specs cover its merge and normalise halves with hand-built input;
-- these drive the READ half against a live session, which is the part that only
-- ever ran in game.
--
-- Two things make it worth doing rather than trusting the merge specs: the walk
-- has to skip HEADER rows (a real Classic-scan bug class — headers have no
-- reagents and no link, so code that forgets them walks off the end), and the
-- scan is the only writer of the data every other spec hand-builds. If it
-- writes a different shape than those specs assume, nothing else would notice.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, gdb
local ME = "Testchar-Testrealm"
local ALCHEMY = 171

local RECIPES = {
	{ name = "Alchemy",              difficulty = "header" },
	{ name = "Minor Healing Potion", available = 5, link = "|Hitem:118|h[Minor Healing Potion]|h",
	  reagents = { { name = "Peacebloom", need = 1, have = 20 } } },
	{ name = "Elixir of Fortitude",  available = 0, link = "|Hitem:3825|h[Elixir of Fortitude]|h",
	  reagents = { { name = "Goldthorn", need = 2, have = 0 } } },
}

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	S = ns.Scanner
end)

before_each(function()
	env.installFrames()
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	ns.Print = function() end
	gdb.accountChars[ME] = true
	env.tradeSkillSession("Alchemy", RECIPES)
end)

describe("scanning an open profession", function()
	it("writes the recipes it walked into the guild DB", function()
		S:ScanTradeSkillInto(ME)
		local recipes = gdb.recipes[ALCHEMY] or {}
		assert.is_true(next(recipes) ~= nil)
	end)

	it("does not record the header row as a recipe", function()
		-- "Alchemy" is a category header, not something you can craft. Recording
		-- it puts an uncraftable row in every guildmate's browser.
		S:ScanTradeSkillInto(ME)
		for _, rd in pairs(gdb.recipes[ALCHEMY] or {}) do
			assert.is_not.equal("Alchemy", rd.name)
		end
	end)

	it("records this character as a crafter of what it scanned", function()
		S:ScanTradeSkillInto(ME)
		local found = false
		for _, rd in pairs(gdb.recipes[ALCHEMY] or {}) do
			if rd.crafters and rd.crafters[ME] then found = true end
		end
		assert.is_true(found)
	end)

	it("records the skill rank for the profession", function()
		S:ScanTradeSkillInto(ME)
		assert.is_truthy(gdb.skills[ME])
		assert.is_truthy(gdb.skills[ME][ALCHEMY])
		assert.equal(300, gdb.skills[ME][ALCHEMY].skillRank)
	end)

	it("scans twice without duplicating anything", function()
		-- Every profession open re-scans, so this runs constantly.
		S:ScanTradeSkillInto(ME)
		local function count()
			local n = 0
			for _ in pairs(gdb.recipes[ALCHEMY] or {}) do n = n + 1 end
			return n
		end
		local first = count()
		S:ScanTradeSkillInto(ME)
		assert.equal(first, count())
	end)

	it("survives a window with only a header in it", function()
		env.tradeSkillSession("Alchemy", { { name = "Alchemy", difficulty = "header" } })
		assert.has_no.errors(function() S:ScanTradeSkillInto(ME) end)
	end)

	it("survives no session at all", function()
		_G.GetTradeSkillLine = function() return nil end
		_G.GetNumTradeSkills = function() return 0 end
		assert.has_no.errors(function() S:ScanTradeSkillInto(ME) end)
	end)

	-- Deliberately NOT tested: a nil charKey. Both callers guard it — the linked
	-- path checks the name normalises and is a guildmate, the local path uses
	-- GetCharacterKey(), which cannot be nil once the player is in the world —
	-- so a spec demanding a nil guard would be inventing a requirement the code
	-- does not have. It raises today, and raising beats silently writing the
	-- scan into gdb.skills[nil].
end)

describe("the craft window (Enchanting on Vanilla/TBC)", function()
	it("scans the separate Craft API into the same tables", function()
		-- Enchanting uses GetCraftInfo rather than GetTradeSkillInfo, and it is
		-- the path that has broken on its own before.
		env.tradeSkillSession("Enchanting", RECIPES)
		assert.has_no.errors(function() S:ScanCraftSkillInto(ME) end)
	end)

	it("survives an empty craft window", function()
		env.tradeSkillSession("Enchanting", {})
		assert.has_no.errors(function() S:ScanCraftSkillInto(ME) end)
	end)
end)

describe("gathering professions", function()
	it("records a gathering skill that has no craft window", function()
		-- Herbalism has no recipes, so the skill line is the only signal it
		-- exists at all.
		env.tradeSkillSession("Alchemy", RECIPES, {
			knows = {
				{ name = "Alchemy",    rank = 300, max = 300 },
				{ name = "Herbalism",  rank = 225, max = 300 },
			},
		})
		S:ScanGatheringProfessions()
		assert.is_truthy(gdb.skills[ME])
	end)
end)

describe("after a local scan", function()
	it("refreshes without error", function()
		S:ScanTradeSkillInto(ME)
		assert.has_no.errors(function() S:RefreshAfterLocalScan(ME) end)
	end)

	it("rebuilds alt groups over the scanned data", function()
		S:ScanTradeSkillInto(ME)
		assert.has_no.errors(function() S:RebuildAltGroups(gdb) end)
	end)
end)
