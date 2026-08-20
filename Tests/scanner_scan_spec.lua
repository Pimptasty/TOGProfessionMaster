-- The scans that establish what THIS character has: the profession registry and
-- the specialisation read.
--
-- The profession registry is the owner side of the dropped-profession fix, and
-- the guards on its DELETE path are what the specs below are really about. A
-- dropped profession has no trade-skill window to re-scan, so the only way it
-- ever leaves the guild's data is the owner noticing it is gone — which means a
-- wrong "gone" reading permanently destroys data the player still has. Hence:
-- delete only from a read that can be TRUSTED (locale-independent ids, or an
-- English client), and only when the profession is absent from TWO consecutive
-- such reads, because a partial skill-line read seconds after login looks
-- exactly like a drop.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, gdb
local ME = "Testchar-Testrealm"

-- The character-panel skill lines the client reports.
local skillLines = {}

local function setSkills(list)
	skillLines = list or {}
	_G.GetNumSkillLines = function() return #skillLines end
	_G.GetSkillLineInfo = function(i)
		local s = skillLines[i]
		if not s then return nil end
		-- name(1), isHeader(2), isExpanded(3), rank(4), _, _, maxRank(7)
		return s.name, s.header or false, true, s.rank or 0, 0, 0, s.max or 300
	end
end

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	S = env.loadModule("Scanner.lua").Scanner
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	env.setRecipeDB({})
	S.DS = nil
	S._scanningGather  = nil
	S._dropCandidates  = nil
	_G.GetProfessions    = nil          -- Classic: no such API
	_G.GetProfessionInfo = nil
	_G.ExpandSkillHeader = function() end
	_G.IsSpellKnown = function() return false end
	setSkills({})
end)

describe("DetectSpecializations", function()
	it("records nothing for a character with no specialisation", function()
		S:DetectSpecializations()
		assert.same({}, gdb.specializations[ME])
	end)

	it("records the spec spell the character knows", function()
		_G.IsSpellKnown = function(id) return id == 10656 end   -- Dragonscale LW
		S:DetectSpecializations()
		assert.equal(10656, gdb.specializations[ME][165])
	end)

	it("prefers the finer Blacksmithing sub-spec over its parent", function()
		-- A swordsmith knows BOTH Weaponsmith and Swordsmith; the more specific
		-- one is what the Guild tab should break down by.
		_G.IsSpellKnown = function(id) return id == 17039 or id == 9787 end
		S:DetectSpecializations()
		assert.equal(17039, gdb.specializations[ME][164])
	end)

	it("replaces a previous reading rather than accumulating", function()
		gdb.specializations[ME] = { [165] = 10658 }
		S:DetectSpecializations()
		assert.same({}, gdb.specializations[ME])
	end)
end)

describe("ScanGatheringProfessions", function()
	it("does nothing without the skill-line API", function()
		_G.GetNumSkillLines = nil
		local ok = pcall(function() S:ScanGatheringProfessions() end)
		assert.is_true(ok)
	end)

	it("records every profession the character holds, at its real rank", function()
		setSkills({
			{ name = "Professions", header = true },
			{ name = "Herbalism", rank = 225, max = 300 },
			{ name = "Alchemy",   rank = 300, max = 300 },
		})
		S:ScanGatheringProfessions()
		assert.same({ skillRank = 225, skillMax = 300 }, gdb.skills[ME][182])
		assert.same({ skillRank = 300, skillMax = 300 }, gdb.skills[ME][171])
	end)

	it("expands collapsed headers first, or the children are invisible", function()
		local expanded = false
		_G.ExpandSkillHeader = function() expanded = true end
		setSkills({ { name = "Herbalism", rank = 1, max = 300 } })
		S:ScanGatheringProfessions()
		assert.is_true(expanded)
	end)

	it("updates a rank that has changed", function()
		gdb.skills[ME] = { [182] = { skillRank = 100, skillMax = 300 } }
		setSkills({ { name = "Herbalism", rank = 225, max = 300 } })
		S:ScanGatheringProfessions()
		assert.equal(225, gdb.skills[ME][182].skillRank)
	end)

	it("ignores skill lines that are not professions", function()
		setSkills({ { name = "Defense", rank = 300, max = 300 } })
		S:ScanGatheringProfessions()
		assert.same({}, gdb.skills[ME])
	end)

	it("does NOT drop a missing profession on the first read", function()
		-- A partial skill-line read moments after login looks exactly like a drop.
		gdb.skills[ME] = { [182] = { skillRank = 225, skillMax = 300 } }
		setSkills({ { name = "Alchemy", rank = 300, max = 300 } })
		S:ScanGatheringProfessions()
		assert.is_true(gdb.skills[ME][182] ~= nil)
	end)

	it("drops it once a SECOND read confirms it is gone", function()
		gdb.skills[ME] = { [182] = { skillRank = 225, skillMax = 300 } }
		setSkills({ { name = "Alchemy", rank = 300, max = 300 } })
		S:ScanGatheringProfessions()
		S._scanningGather = nil
		S:ScanGatheringProfessions()
		assert.is_nil(gdb.skills[ME][182])
	end)

	it("forgets the candidate when the profession comes back", function()
		-- The self-correcting half: a partial read flags it, the next full read
		-- clears the flag, so it is never deleted.
		gdb.skills[ME] = { [182] = { skillRank = 225, skillMax = 300 } }
		setSkills({ { name = "Alchemy", rank = 300, max = 300 } })
		S:ScanGatheringProfessions()
		S._scanningGather = nil
		setSkills({ { name = "Alchemy", rank = 300, max = 300 },
		            { name = "Herbalism", rank = 225, max = 300 } })
		S:ScanGatheringProfessions()
		S._scanningGather = nil
		setSkills({ { name = "Alchemy", rank = 300, max = 300 } })
		S:ScanGatheringProfessions()
		assert.is_true(gdb.skills[ME][182] ~= nil)
	end)

	it("never deletes from a read it cannot trust", function()
		-- A non-English client can't map skill-line NAMES to ids, so the read is
		-- unreliable and the delete path must not run at all.
		local realGetLocale = _G.GetLocale
		_G.GetLocale = function() return "frFR" end
		gdb.skills[ME] = { [182] = { skillRank = 225, skillMax = 300 } }
		setSkills({ { name = "Alchimie", rank = 300, max = 300 } })
		S:ScanGatheringProfessions()
		S._scanningGather = nil
		S:ScanGatheringProfessions()
		_G.GetLocale = realGetLocale
		assert.is_true(gdb.skills[ME][182] ~= nil)
	end)

	it("uses the locale-independent ids where the client offers them", function()
		-- Cata+ hands over skillLine ids directly, which is always trustworthy.
		_G.GetProfessions = function() return 1, 2 end
		_G.GetProfessionInfo = function(idx)
			if idx == 1 then return "Alchemy", nil, 300, 300, nil, nil, 171 end
			return "Herbalism", nil, 225, 300, nil, nil, 182
		end
		S:ScanGatheringProfessions()
		assert.same({ skillRank = 300, skillMax = 300 }, gdb.skills[ME][171])
		assert.same({ skillRank = 225, skillMax = 300 }, gdb.skills[ME][182])
	end)

	it("guards against re-entering itself", function()
		-- Expanding a header fires SKILL_LINES_CHANGED, which would re-enter.
		local depth, maxDepth = 0, 0
		setSkills({ { name = "Herbalism", rank = 1, max = 300 } })
		_G.ExpandSkillHeader = function()
			depth = depth + 1
			if depth > maxDepth then maxDepth = depth end
			S:ScanGatheringProfessions()
			depth = depth - 1
		end
		S:ScanGatheringProfessions()
		assert.equal(1, maxDepth)
	end)
end)

describe("ScanTradeSkillInto", function()
	before_each(function()
		_G.GetTradeSkillLine = function() return "Alchemy", 267, 300 end
		_G.GetNumTradeSkills = function() return 1 end
		_G.GetTradeSkillInfo = function(_index) return "Minor Healing Potion", "optimal", 5, true end
		_G.GetTradeSkillRecipeLink = function(_index) return "|Henchant:2330|h" end
		_G.GetTradeSkillItemLink = function(_index) return nil end
		_G.ExpandTradeSkillSubClass = nil
		env.setRecipeDB({ [171] = { [2330] = { name = "Minor Healing Potion", craftedItemId = 118 } } })
	end)

	it("records the character's real rank and cap", function()
		-- The 3-return Classic signature: reading it as the 4-return modern one
		-- silently stored maxRank as the current rank for the addon's whole history.
		S:ScanTradeSkillInto(ME)
		assert.same({ skillRank = 267, skillMax = 300 }, gdb.skills[ME][171])
	end)

	it("stores the recipe against the character", function()
		S:ScanTradeSkillInto(ME)
		assert.is_true(gdb.recipes[171][2330].crafters[ME] ~= nil)
	end)

	it("stamps the profession's scan time", function()
		env.serverTime = 4242
		S:ScanTradeSkillInto(ME)
		assert.equal(4242, gdb.lastScan[ME][171])
	end)

	it("ignores a window that has not resolved yet", function()
		_G.GetTradeSkillLine = function() return "UNKNOWN" end
		S:ScanTradeSkillInto(ME)
		assert.is_nil(gdb.skills[ME])
	end)

	it("ignores a profession name it cannot resolve", function()
		_G.GetTradeSkillLine = function() return "Basket Weaving", 1, 1 end
		S:ScanTradeSkillInto(ME)
		assert.is_nil(gdb.skills[ME])
	end)

	it("skips rows that are headers rather than recipes", function()
		_G.GetTradeSkillInfo = function(_index) return "Potions", "header", 0, true end
		S:ScanTradeSkillInto(ME)
		-- The profession table is still created (the scan ran); it just has no
		-- recipes in it.
		assert.same({}, gdb.recipes[171])
	end)
end)

--- A LINKED trade skill -- someone in the guild has linked their window to you.
---
--- This whole entry point had NO spec, and the guard inside it -- "record it only
--- if the linker is a guildmate" -- had therefore never executed in either
--- direction. Found by the "does anything diagnose from an ABSENCE?" sweep the
--- harness asked consumers to run: `IsInGuild` is a STRICT membership check with
--- a live-scan fallback before the roster's first build, so an unready roster
--- answers "not a guildmate" for everybody, and the symptom is a linked window
--- that silently records nothing.
describe("OnTradeSkillEvent -- a linked window", function()
	before_each(function()
		env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
		S.GuildRoster = ns.Scanner.GuildRoster
		_G.UnitAffectingCombat = function() return false end
		env.tradeSkillSession("Alchemy", {
			{ name = "Minor Healing Potion", link = "|Henchant:2330|h[Minor Healing Potion]|h" },
		})
	end)

	it("records a guildmate's linked window under THEIR key, not ours", function()
		_G.IsTradeSkillLinked = function() return true, "Bob" end
		S:OnTradeSkillEvent()
		assert.is_not_nil(gdb.skills["Bob-Testrealm"])
		assert.is_nil(gdb.skills[ME])
	end)

	it("records NOTHING for someone who is not in the guild", function()
		-- The gate this describe exists for. A stranger's linked window is not
		-- guild data and must not enter the database under any key.
		_G.IsTradeSkillLinked = function() return true, "Stranger" end
		S:OnTradeSkillEvent()
		assert.is_nil(gdb.skills["Stranger-Testrealm"])
		assert.is_nil(gdb.skills[ME])
	end)

	it("records nothing when no roster library is loaded at all", function()
		S.GuildRoster = nil
		_G.IsTradeSkillLinked = function() return true, "Bob" end
		S:OnTradeSkillEvent()
		assert.is_nil(gdb.skills["Bob-Testrealm"])
	end)

	it("never falls through to scanning a linked window into OUR OWN key", function()
		-- The failure that would be worst and quietest: a linked window read as
		-- our own recipes, so the guild is told we know things we do not.
		_G.IsTradeSkillLinked = function() return true, "Stranger" end
		S:OnTradeSkillEvent()
		assert.is_nil(gdb.recipes[171])
	end)

	it("scans into our own key when the window is NOT linked", function()
		_G.IsTradeSkillLinked = function() return false end
		S:OnTradeSkillEvent()
		assert.is_not_nil(gdb.skills[ME])
	end)

	it("does nothing at all while in combat", function()
		_G.UnitAffectingCombat = function() return true end
		_G.IsTradeSkillLinked = function() return false end
		S:OnTradeSkillEvent()
		assert.is_nil(gdb.skills[ME])
	end)
end)
