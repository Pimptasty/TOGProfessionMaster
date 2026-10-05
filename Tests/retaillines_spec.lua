-- Retail's per-expansion skill lines.
--
-- Retail splits each profession into one skill line per expansion (2872 Khaz
-- Algar Blacksmithing under 164), and a recipe's requiredSkill is on ITS line's
-- scale. Two things follow, and this file pins both:
--
--   1. Per-line ranks must reach other clients, or "Can learn now" and the
--      Requires colouring cannot gate an alt at all. They ride the OWNER-MINTED
--      professions:<charKey> leaf as an optional `l` per profession -- and must
--      leave every non-Retail client's payload and hash exactly as they were,
--      because a mixed guild converges only while every client mints the same
--      token for the same data, and an older TOGPM must still read the leaf.
--   2. A Retail window scan may list one line's recipes, not the whole
--      profession's (GetAllRecipeIDs is unverified on live; the fallback is the
--      open line only). The merge may only re-derive the lines it was shown, or
--      opening Khaz Algar strips every Dragon Isles recipe from the character.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, HM, gdb, DS
local ME     = "Testchar-Testrealm"
local OWNER  = "Bob-Testrealm"
local SMITH  = 164
local KHAZ   = 2872     -- Khaz Algar Blacksmithing
local DRAGON = 2822     -- Dragon Isles Blacksmithing
local NOW    = 1000000
local savedRetail, savedTSUI

-- What mint() in HashManager produces for `data`, computed independently so a
-- spec can say "this is the hash of THAT literal shape".
local function mintOf(data)
	if DS.MakeHashEntry then
		local e = DS:MakeHashEntry(data, nil)
		return e.hash, e.hashV2
	end
	return DS:ComputeHash(data), nil
end

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	HM = env.loadModule("Modules/HashManager.lua").HashManager
	S  = env.loadModule("Scanner.lua").Scanner
end)

before_each(function()
	env.install()
	env.serverTime = NOW
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({})
	DS = env.deltaSync()
	S.DS = DS
	S.GuildRoster = ns.Scanner and ns.Scanner.GuildRoster
	S._scanningGather, S._dropCandidates = nil, nil
	savedRetail, savedTSUI = ns.isRetail, _G.C_TradeSkillUI
end)

after_each(function()
	ns.isRetail, _G.C_TradeSkillUI = savedRetail, savedTSUI
end)

-- ---------------------------------------------------------------------------
-- The wire: shape, hash, old readers
-- ---------------------------------------------------------------------------

describe("professions leaf -- Classic is byte-identical", function()
	local LEGACY = { ["171"] = { r = 300, m = 300 }, ["182"] = { r = 150, m = 300 } }

	before_each(function()
		gdb.skills[OWNER] = {
			[171] = { skillRank = 300, skillMax = 300 },
			[182] = { skillRank = 150, skillMax = 300 },
		}
		gdb.lastScan[OWNER] = { professions = 777 }
	end)

	it("snapshots exactly the pre-Retail { r, m } shape, with no `l` key", function()
		local snap = HM:GetProfessionSnapshot(gdb, OWNER)
		assert.same(LEGACY, snap)
		for _, e in pairs(snap) do assert.is_nil(rawget(e, "l")) end
	end)

	it("mints the same token as the pre-Retail shape", function()
		HM:InvalidateCharProfessions(DS, gdb, OWNER)
		local h, h2 = mintOf(LEGACY)
		assert.equal(h,  gdb.hashes["professions:" .. OWNER].hash)
		assert.equal(h2, gdb.hashes["professions:" .. OWNER].hashV2)
	end)

	it("ships the pre-Retail data on the wire", function()
		HM:InvalidateCharProfessions(DS, gdb, OWNER)
		local leaf = S:BuildLeafPayload("professions:" .. OWNER).leaves["professions:" .. OWNER]
		assert.same(LEGACY, leaf.data)
		assert.equal((mintOf(LEGACY)), leaf.hash)
	end)

	it("never grows a `lines` key on a Classic record from any writer", function()
		-- Classic window scan, then a skill-up read, then a ride-along bump.
		S:MergeRecipesIntoGdb(gdb, ME, 171, 267, 300, { [2330] = true })
		assert.same({ skillRank = 267, skillMax = 300 }, gdb.skills[ME][171])
		_G.GetProfessions = nil
		_G.GetNumSkillLines = function() return 1 end
		_G.GetSkillLineInfo = function() return "Alchemy", false, true, 270, 0, 0, 300 end
		_G.ExpandSkillHeader = function() end
		S:ScanGatheringProfessions()
		assert.same({ skillRank = 270, skillMax = 300 }, gdb.skills[ME][171])
	end)
end)

describe("professions leaf -- Retail per-line ranks", function()
	before_each(function()
		gdb.skills[OWNER] = { [SMITH] = { skillRank = 50, skillMax = 100,
			lines = { [KHAZ] = { skillRank = 40, skillMax = 100 },
			          [DRAGON] = { skillRank = 100, skillMax = 100 } } } }
	end)

	it("ride as an optional `l` on the profession's entry", function()
		assert.same({ [tostring(SMITH)] = { r = 50, m = 100, l = {
			[tostring(KHAZ)]   = { r = 40,  m = 100 },
			[tostring(DRAGON)] = { r = 100, m = 100 },
		} } }, HM:GetProfessionSnapshot(gdb, OWNER))
	end)

	it("are covered by the owner's minted token", function()
		HM:InvalidateCharProfessions(DS, gdb, OWNER)
		local with = gdb.hashes["professions:" .. OWNER].hash
		assert.is_true(with ~= (mintOf({ [tostring(SMITH)] = { r = 50, m = 100 } })))
	end)

	it("an OLDER reader decodes the new entry without error and keeps r / m", function()
		-- The released (v1.2.0) professions: decode, verbatim: it reads only r and
		-- m, so the extra `l` is ignored rather than tripping it.
		local function v120decode(leafData)
			local newset = {}
			for profIdStr, rec in pairs(leafData) do
				local profId = tonumber(profIdStr)
				if profId and type(rec) == "table" then
					newset[profId] = {
						skillRank = tonumber(rec.r) or 0,
						skillMax  = tonumber(rec.m) or 0,
					}
				end
			end
			return newset
		end
		local ok, out = pcall(v120decode, HM:GetProfessionSnapshot(gdb, OWNER))
		assert.is_true(ok)
		assert.same({ [SMITH] = { skillRank = 50, skillMax = 100 } }, out)
	end)
end)

describe("professions leaf -- receive", function()
	local function deliver(data, token, ts)
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER,
			leaves  = { ["professions:" .. OWNER] = { data = data, hash = token, updatedAt = ts } },
		})
	end

	it("stores the delivered lines, adopts the owner's token VERBATIM, and gates on them", function()
		deliver({ [tostring(SMITH)] = { r = 50, m = 100, l = { [tostring(KHAZ)] = { r = 40, m = 100 } } } },
			424242, 900)
		assert.same({ [KHAZ] = { skillRank = 40, skillMax = 100 } }, gdb.skills[OWNER][SMITH].lines)
		assert.equal(424242, gdb.hashes["professions:" .. OWNER].hash)   -- never recomputed
		_G.C_TradeSkillUI = nil
		assert.equal(40, ns:GetRecipeSkillRank(OWNER, SMITH, { skillLine = KHAZ }))
	end)

	it("skips malformed line entries without erroring", function()
		deliver({ [tostring(SMITH)] = { r = 50, m = 100, l = { junk = { r = 1 }, [tostring(KHAZ)] = 7 } } },
			1, 900)
		assert.is_nil(gdb.skills[OWNER][SMITH].lines)
		deliver({ [tostring(SMITH)] = { r = 51, m = 100, l = "nonsense" } }, 2, 901)
		assert.equal(51, gdb.skills[OWNER][SMITH].skillRank)
		assert.is_nil(gdb.skills[OWNER][SMITH].lines)
	end)

	it("a snapshot without `l` (an older relay) stores no lines, so nothing is gated", function()
		-- KNOWN COST: a relay on an older TOGPM ships the owner's token with the
		-- data it rebuilt, which has no `l`. The receiver cannot tell, and the
		-- alt goes ungated (nil) until the owner's next re-mint -- never gated
		-- wrongly.
		deliver({ [tostring(SMITH)] = { r = 50, m = 100 } }, 5, 900)
		assert.is_nil(gdb.skills[OWNER][SMITH].lines)
		_G.C_TradeSkillUI = nil
		assert.is_nil(ns:GetRecipeSkillRank(OWNER, SMITH, { skillLine = KHAZ }))
	end)

	it("a crafters ride-along that bumps the rank keeps the delivered lines", function()
		local lines = { [KHAZ] = { skillRank = 40, skillMax = 100 } }
		gdb.skills[OWNER] = { [SMITH] = { skillRank = 50, skillMax = 100, lines = lines } }
		S:OnGuildDataReceived("Bob", {
			charKey = OWNER,
			leaves  = { ["crafters:" .. SMITH] = { data = { [9001] = { [OWNER] = true } }, hash = 1, updatedAt = 1 } },
			skills  = { [SMITH] = { [OWNER] = { skillRank = 60, skillMax = 100 } } },
		})
		assert.equal(60, gdb.skills[OWNER][SMITH].skillRank)
		assert.same(lines, gdb.skills[OWNER][SMITH].lines)
	end)
end)

-- ---------------------------------------------------------------------------
-- The owner: recording lines, and not losing them
-- ---------------------------------------------------------------------------

-- A Retail Blacksmithing window, Khaz Algar open. `list` is what the recipe-list
-- call returns; lineOf is the client's GetTradeSkillLineForRecipe.
local function retailWindow(list, lineOf, children)
	_G.C_TradeSkillUI = {
		IsDataSourceChanging  = function() return false end,
		GetBaseProfessionInfo = function()
			return { professionID = SMITH, professionName = "Blacksmithing", skillLevel = 40, maxSkillLevel = 100 }
		end,
		GetChildProfessionInfo = function()
			return { professionID = KHAZ, professionName = "Khaz Algar Blacksmithing",
			         skillLevel = 40, maxSkillLevel = 100,
			         parentProfessionID = SMITH, parentProfessionName = "Blacksmithing" }
		end,
		GetChildProfessionInfos = children and function() return children end or nil,
		GetAllRecipeIDs = function() return list end,
		GetRecipeInfo   = function(id) return { recipeID = id, learned = true } end,
		GetTradeSkillLineForRecipe = function(id)
			if lineOf[id] then return lineOf[id], "", SMITH end
			return nil
		end,
	}
end

describe("RecordSkillLines -- the owner records its lines", function()
	before_each(function() ns.isRetail = true end)

	it("records every child line the client lists, from one window scan", function()
		retailWindow({ 1001 }, { [1001] = KHAZ }, {
			{ professionID = KHAZ,   skillLevel = 40,  maxSkillLevel = 100, parentProfessionID = SMITH },
			{ professionID = DRAGON, skillLevel = 100, maxSkillLevel = 100, parentProfessionID = SMITH },
		})
		S:ScanModernTradeSkillInto(ME)
		assert.same({ [KHAZ]   = { skillRank = 40,  skillMax = 100 },
		              [DRAGON] = { skillRank = 100, skillMax = 100 } }, gdb.skills[ME][SMITH].lines)
	end)

	it("without the child list, upserts the open line and keeps the others", function()
		gdb.skills[ME] = { [SMITH] = { skillRank = 1, skillMax = 1,
			lines = { [DRAGON] = { skillRank = 100, skillMax = 100 } } } }
		retailWindow({ 1001 }, { [1001] = KHAZ }, nil)
		S:ScanModernTradeSkillInto(ME)
		assert.same({ [KHAZ]   = { skillRank = 40,  skillMax = 100 },
		              [DRAGON] = { skillRank = 100, skillMax = 100 } }, gdb.skills[ME][SMITH].lines)
	end)

	it("re-mints the professions leaf, strictly newer, when a line changes", function()
		gdb.skills[ME] = { [SMITH] = { skillRank = 40, skillMax = 100 } }
		gdb.lastScan[ME] = { professions = NOW }        -- same second as this scan
		HM:InvalidateCharProfessions(DS, gdb, ME)
		local before = gdb.hashes["professions:" .. ME].hash
		retailWindow({ 1001 }, { [1001] = KHAZ }, {
			{ professionID = KHAZ, skillLevel = 41, maxSkillLevel = 100, parentProfessionID = SMITH },
		})
		S:ScanModernTradeSkillInto(ME)
		local entry = gdb.hashes["professions:" .. ME]
		assert.is_true(entry.hash ~= before)
		assert.equal(NOW + 1, entry.updatedAt)
		-- The minted token is the owner's hash of exactly what it now ships.
		assert.equal((mintOf(HM:GetProfessionSnapshot(gdb, ME))), entry.hash)
		local leaf = S:BuildLeafPayload("professions:" .. ME).leaves["professions:" .. ME]
		assert.same({ [tostring(KHAZ)] = { r = 41, m = 100 } }, leaf.data[tostring(SMITH)].l)
	end)

	it("does not re-mint when nothing changed", function()
		gdb.skills[ME] = { [SMITH] = { skillRank = 40, skillMax = 100,
			lines = { [KHAZ] = { skillRank = 40, skillMax = 100 } } } }
		gdb.lastScan[ME] = { professions = 500 }
		retailWindow({ 1001 }, { [1001] = KHAZ }, {
			{ professionID = KHAZ, skillLevel = 40, maxSkillLevel = 100, parentProfessionID = SMITH },
		})
		S:ScanModernTradeSkillInto(ME)
		assert.equal(500, gdb.lastScan[ME].professions)
	end)

	-- One writer for the profession-level rank on Retail: the window (open
	-- line, 40) must not overwrite what the profession registry recorded (45),
	-- or the two would flip the record and re-mint the leaf on every pass.
	it("keeps the registry's profession rank; the window's rank goes to lines", function()
		gdb.skills[ME] = { [SMITH] = { skillRank = 45, skillMax = 100 } }
		retailWindow({ 1001 }, { [1001] = KHAZ }, nil)
		S:ScanModernTradeSkillInto(ME)
		assert.equal(45, gdb.skills[ME][SMITH].skillRank)
		assert.same({ skillRank = 40, skillMax = 100 }, gdb.skills[ME][SMITH].lines[KHAZ])
	end)

	it("uses the open line's rank when the registry has recorded nothing yet", function()
		retailWindow({ 1001 }, { [1001] = KHAZ }, nil)
		S:ScanModernTradeSkillInto(ME)
		assert.equal(40, gdb.skills[ME][SMITH].skillRank)
	end)

	it("records nothing on WoW Forever", function()
		ns.isRetail = false
		retailWindow({ 1001 }, { [1001] = KHAZ }, {
			{ professionID = KHAZ, skillLevel = 40, maxSkillLevel = 100, parentProfessionID = SMITH },
		})
		S:ScanModernTradeSkillInto(ME)
		assert.is_nil(gdb.skills[ME][SMITH].lines)
	end)

	it("a later skill-up read keeps the lines", function()
		gdb.skills[ME] = { [SMITH] = { skillRank = 40, skillMax = 100,
			lines = { [KHAZ] = { skillRank = 40, skillMax = 100 } } } }
		_G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil
		_G.ExpandSkillHeader = function() end
		_G.GetProfessions    = function() return 1 end
		_G.GetProfessionInfo = function() return "Blacksmithing", nil, 45, 100, nil, nil, SMITH end
		S:ScanGatheringProfessions()
		_G.GetProfessions, _G.GetProfessionInfo = nil, nil
		assert.equal(45, gdb.skills[ME][SMITH].skillRank)
		assert.same({ [KHAZ] = { skillRank = 40, skillMax = 100 } }, gdb.skills[ME][SMITH].lines)
	end)
end)

-- ---------------------------------------------------------------------------
-- The merge: only the lines the scan was shown
-- ---------------------------------------------------------------------------

describe("ScanModernTradeSkillInto (Retail) -- a one-line list strips no other line", function()
	local TAG
	before_each(function()
		ns.isRetail = true
		TAG = ns:GetCurrentGuildTag()
		env.setRecipeDB({ [SMITH] = {
			[1001] = { name = "A", skillLine = KHAZ },
			[1002] = { name = "B", skillLine = KHAZ },
			[2001] = { name = "C", skillLine = DRAGON },
		} })
		gdb.recipes[SMITH] = {
			[1001] = { crafters = { [ME] = TAG } },
			[1002] = { crafters = { [ME] = TAG } },
			[2001] = { crafters = { [ME] = TAG } },
		}
	end)

	it("keeps the other line's recipes, and still drops an unlearned one on the scanned line", function()
		retailWindow({ 1001 }, { [1001] = KHAZ }, nil)
		S:ScanModernTradeSkillInto(ME)
		assert.is_not_nil(gdb.recipes[SMITH][1001].crafters[ME])
		assert.is_nil(gdb.recipes[SMITH][1002].crafters[ME])     -- on KHAZ, not listed: dropped
		assert.is_not_nil(gdb.recipes[SMITH][2001].crafters[ME]) -- DRAGON was never shown
	end)

	it("takes a recipe's line from the client when the recipe DB has none", function()
		env.setRecipeDB({})
		retailWindow({ 1001 }, { [1001] = KHAZ, [1002] = KHAZ, [2001] = DRAGON }, nil)
		S:ScanModernTradeSkillInto(ME)
		assert.is_nil(gdb.recipes[SMITH][1002].crafters[ME])
		assert.is_not_nil(gdb.recipes[SMITH][2001].crafters[ME])
	end)

	it("leaves a recipe whose line nothing can place", function()
		gdb.recipes[SMITH][3001] = { crafters = { [ME] = TAG } }
		retailWindow({ 1001 }, { [1001] = KHAZ }, nil)
		S:ScanModernTradeSkillInto(ME)
		assert.is_not_nil(gdb.recipes[SMITH][3001].crafters[ME])
	end)

	it("re-derives every line a whole-profession list covered", function()
		retailWindow({ 1001, 2001 }, { [1001] = KHAZ, [2001] = DRAGON }, nil)
		gdb.recipes[SMITH][2002] = { crafters = { [ME] = TAG } }
		ns.recipeDB[SMITH][2002] = { name = "D", skillLine = DRAGON }
		S:ScanModernTradeSkillInto(ME)
		assert.is_nil(gdb.recipes[SMITH][1002].crafters[ME])
		assert.is_nil(gdb.recipes[SMITH][2002].crafters[ME])
		assert.is_not_nil(gdb.recipes[SMITH][2001].crafters[ME])
	end)

	it("reports no change on an identical re-scan, even of a recipe it cannot place", function()
		-- 3001 has no line, so it is never cleared; listing it again must not
		-- read as a change (that would redraw on every TRADE_SKILL_UPDATE).
		retailWindow({}, {}, nil)
		local set = { [1001] = true, [1002] = true, [3001] = true }
		S:MergeRecipesIntoGdb(gdb, ME, SMITH, 40, 100, set, { [KHAZ] = true })
		assert.is_false(S:MergeRecipesIntoGdb(gdb, ME, SMITH, 40, 100, set, { [KHAZ] = true }))
	end)

	it("WoW Forever keeps the whole-profession merge", function()
		ns.isRetail = false
		retailWindow({ 1001 }, { [1001] = KHAZ }, nil)
		S:ScanModernTradeSkillInto(ME)
		assert.is_nil(gdb.recipes[SMITH][2001].crafters[ME])
	end)

	it("a Classic merge (no covered lines) still re-derives the whole profession", function()
		S:MergeRecipesIntoGdb(gdb, ME, SMITH, 40, 100, { [1001] = true })
		assert.is_nil(gdb.recipes[SMITH][2001].crafters[ME])
		assert.is_not_nil(gdb.recipes[SMITH][1001].crafters[ME])
	end)
end)
