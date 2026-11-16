-- Talent specs for every guildmate, and the public read API (TOGPM.API).
--
-- Asked for by Ultimate Guild Roster (inbox cfb23d25, 2026-11-13): it writes
-- guild notes like "[DEM/AFF] Tail/Ench" and must stop reading TOGPM_GuildDB.
--
-- What this pins:
--   1. ReadPlayerTalentSpec picks the right client family -- talent tabs (Era /
--      TBC Anniversary), specializations (MoP / Retail), trait trees (Forever)
--      -- with the call shapes read from each flavour's Blizzard UI source.
--   2. The spec rides the owner-minted professions:<charKey> snapshot as `t`;
--      with no spec recorded the snapshot and its hash are byte-identical to
--      before, and an older reader skips `t` cleanly.
--   3. The owner re-mints on a spec change only when it already holds an
--      authoritative snapshot, with a strictly newer timestamp.
--   4. A receiver adopts `t`, keeps the spec it has when `t` is absent, and the
--      API's CharacterChanged names the CHARACTER, not the sender.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, S, HM, API, gdb, DS
local ME    = "Testchar-Testrealm"
local OWNER = "Bob-Testrealm"
local NOW   = 1000000

local TALENT_GLOBALS = { "C_SpecializationInfo", "C_Traits", "C_ClassTalents", "GetNumTalentTabs",
                         "GetNumTalentGroups", "GetNumSpecGroups", "IsInitialSpec" }
local saved, savedFlags

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
	HM  = env.loadModule("Modules/HashManager.lua").HashManager
	API = env.loadModule("Modules/API.lua").API
	S   = env.loadModule("Scanner.lua").Scanner
end)

before_each(function()
	env.install()
	env.serverTime = NOW
	gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({})
	DS = env.deltaSync()
	S.DS = DS
	saved = {}
	for _, k in ipairs(TALENT_GLOBALS) do saved[k] = _G[k]; _G[k] = nil end
	savedFlags = { isMoP = ns.isMoP, isRetail = ns.isRetail }
	ns.isMoP, ns.isRetail = false, false
end)

after_each(function()
	for _, k in ipairs(TALENT_GLOBALS) do _G[k] = saved[k] end
	ns.isMoP, ns.isRetail = savedFlags.isMoP, savedFlags.isRetail
end)

-- Era / TBC Anniversary: three tabs, points per talent group.
local function talentTabs(pointsByGroup, activeGroup, numGroups)
	local names = { "Affliction", "Demonology", "Destruction" }
	-- Stubs take the real calls' parameter counts: the LSP reads a stub as the
	-- global's signature and flags Compat.lua's calls otherwise.
	_G.GetNumTalentTabs   = function(_, _) return 3 end
	_G.GetNumTalentGroups = function(_, _) return numGroups or 1 end
	_G.C_SpecializationInfo = {
		IsInitialized      = function() return true end,
		GetActiveSpecGroup = function(_, _) return activeGroup or 1 end,
		GetSpecializationInfo = function(i, _, _, _, _, group)
			-- id, name, description, icon, role, primaryStat, pointsSpent
			return 300 + i, names[i], "", 0, "DAMAGER", 0, pointsByGroup[group][i]
		end,
	}
end

-- ---------------------------------------------------------------------------
-- 1. Reading the player's own spec
-- ---------------------------------------------------------------------------

describe("ReadPlayerTalentSpec", function()
	it("talent tabs: the active group's tab with the most points", function()
		talentTabs({ [1] = { 31, 20, 0 } })
		assert.same({ a = "Affliction", ai = 301 }, ns.ReadPlayerTalentSpec())
	end)

	it("talent tabs: reads the OTHER group as the off spec when there are two", function()
		talentTabs({ [1] = { 0, 41, 10 }, [2] = { 41, 10, 0 } }, 2, 2)
		assert.same({ a = "Affliction", ai = 301, o = "Demonology", oi = 302 }, ns.ReadPlayerTalentSpec())
	end)

	it("talent tabs: a group with nothing spent has no spec, and that is still an answer", function()
		talentTabs({ [1] = { 0, 0, 0 } })
		assert.same({}, ns.ReadPlayerTalentSpec())
	end)

	it("answers nil (unknown) while the client's talent data is not loaded", function()
		talentTabs({ [1] = { 31, 20, 0 } })
		_G.C_SpecializationInfo.IsInitialized = function() return false end
		assert.is_nil(ns.ReadPlayerTalentSpec())
	end)

	it("answers nil on a client with no talent API", function()
		assert.is_nil(ns.ReadPlayerTalentSpec())
	end)

	it("MoP: each group's specialization index, never its points", function()
		ns.isMoP = true
		_G.GetNumSpecGroups = function(_) return 2 end
		_G.C_SpecializationInfo = {
			GetActiveSpecGroup = function(_, _) return 1 end,
			GetSpecialization  = function(_, _, group) return group == 1 and 3 or 1 end,
			GetSpecializationInfo = function(idx, _, _)
				return ({ 265, 266, 267 })[idx], ({ "Affliction", "Demonology", "Destruction" })[idx]
			end,
		}
		assert.same({ a = "Destruction", ai = 267, o = "Affliction", oi = 265 }, ns.ReadPlayerTalentSpec())
	end)

	it("Retail: the one active specialization, no off spec", function()
		ns.isRetail = true
		_G.GetNumSpecGroups = function(_) return 2 end
		_G.C_SpecializationInfo = {
			GetSpecialization     = function(_, _, _) return 2 end,
			GetSpecializationInfo = function(idx, _, _) return 266, idx == 2 and "Demonology" or "?" end,
		}
		assert.same({ a = "Demonology", ai = 266 }, ns.ReadPlayerTalentSpec())
	end)

	it("Forever: the trait-tree group with the most points spent, per spec group", function()
		_G.GetNumSpecGroups = function(_) return 2 end
		_G.C_SpecializationInfo = {
			GetActiveSpecGroup = function(_, _) return 1 end,
			GetCombatConfigIDForSpecGroup = function(g) return g == 1 and 11 or 22 end,
		}
		_G.C_Traits = {
			GetConfigInfo = function(configID) return { treeIDs = { configID * 10 } } end,
			GetGroupDisplayInfoByTreeID = function(_)
				return { { groupID = 1, displayName = "Affliction" }, { groupID = 2, displayName = "Demonology" } }
			end,
			GetGroupCurrencyInfo = function(configID, _)
				local a, d = 30, 5
				if configID == 22 then a, d = 2, 40 end
				return { { traitNodeGroupID = 1, currencyInfos = { { spent = a } } },
				         { traitNodeGroupID = 2, currencyInfos = { { spent = d } } } }
			end,
		}
		assert.same({ a = "Affliction", ai = 1, o = "Demonology", oi = 2 }, ns.ReadPlayerTalentSpec())
	end)
end)

-- ---------------------------------------------------------------------------
-- 2. The wire
-- ---------------------------------------------------------------------------

describe("professions snapshot carries the spec as `t`", function()
	local LEGACY = { ["171"] = { r = 300, m = 300 } }

	before_each(function()
		gdb.skills[OWNER] = { [171] = { skillRank = 300, skillMax = 300 } }
		gdb.lastScan[OWNER] = { professions = 777 }
	end)

	it("with no spec recorded the snapshot and hash are exactly as before", function()
		assert.same(LEGACY, HM:GetProfessionSnapshot(gdb, OWNER))
		HM:InvalidateCharProfessions(DS, gdb, OWNER)
		assert.equal((mintOf(LEGACY)), gdb.hashes["professions:" .. OWNER].hash)
	end)

	it("with a spec, ships it and mints over it", function()
		gdb.talents[OWNER] = { a = "Affliction", ai = 301 }
		local snap = HM:GetProfessionSnapshot(gdb, OWNER)
		assert.same({ a = "Affliction", ai = 301 }, snap.t)
		HM:InvalidateCharProfessions(DS, gdb, OWNER)
		assert.is_true(gdb.hashes["professions:" .. OWNER].hash ~= (mintOf(LEGACY)))
	end)

	it("an older reader (tonumber on every key) skips `t`", function()
		gdb.talents[OWNER] = { a = "Affliction", ai = 301 }
		local newset = {}
		for k, rec in pairs(HM:GetProfessionSnapshot(gdb, OWNER)) do
			local profId = tonumber(k)
			if profId and type(rec) == "table" then newset[profId] = rec.r end
		end
		assert.same({ [171] = 300 }, newset)
	end)
end)

-- ---------------------------------------------------------------------------
-- 3. The owner's scan
-- ---------------------------------------------------------------------------

describe("Scanner:ScanTalentSpec", function()
	before_each(function()
		talentTabs({ [1] = { 31, 20, 0 } })
		gdb.skills[ME] = { [197] = { skillRank = 300, skillMax = 300 } }
	end)

	it("stores the spec and re-mints with a strictly newer timestamp", function()
		gdb.lastScan[ME] = { professions = NOW }    -- minted this same second
		S:ScanTalentSpec()
		assert.same({ a = "Affliction", ai = 301 }, gdb.talents[ME])
		assert.equal(NOW + 1, gdb.lastScan[ME].professions)
		assert.equal(NOW + 1, gdb.hashes["professions:" .. ME].updatedAt)
	end)

	it("does not mint without an authoritative snapshot, but keeps the spec for the next one", function()
		S:ScanTalentSpec()
		assert.same({ a = "Affliction", ai = 301 }, gdb.talents[ME])
		assert.is_nil(gdb.hashes["professions:" .. ME])
	end)

	it("an unchanged read writes nothing and fires nothing", function()
		gdb.lastScan[ME] = { professions = 5 }
		S:ScanTalentSpec()
		local fired = 0
		API.RegisterCallback("talents_api_spec", "CharacterChanged", function() fired = fired + 1 end)
		S:ScanTalentSpec()
		API.UnregisterCallback("talents_api_spec", "CharacterChanged")
		assert.equal(NOW, gdb.lastScan[ME].professions)
		assert.equal(0, fired)
	end)

	it("a read that throws is contained and stores nothing", function()
		_G.C_SpecializationInfo.GetSpecializationInfo = function(_, _, _, _, _, _) error("boom") end
		assert.has_no.errors(function() S:ScanTalentSpec() end)
		assert.is_nil(gdb.talents[ME])
	end)

	it("an unknown read (not loaded yet) leaves the stored spec alone", function()
		gdb.talents[ME] = { a = "Demonology", ai = 302 }
		_G.C_SpecializationInfo.IsInitialized = function() return false end
		S:ScanTalentSpec()
		assert.same({ a = "Demonology", ai = 302 }, gdb.talents[ME])
	end)
end)

-- ---------------------------------------------------------------------------
-- 4. Receive
-- ---------------------------------------------------------------------------

describe("receiving a professions leaf with `t`", function()
	local function deliver(data, token, ts)
		S:OnGuildDataReceived("Relay", {
			charKey = "Relay-Testrealm",
			leaves  = { ["professions:" .. OWNER] = { data = data, hash = token, updatedAt = ts } },
		})
	end

	it("adopts the spec with the snapshot", function()
		deliver({ ["197"] = { r = 300, m = 300 }, t = { a = "Affliction", ai = 301, o = "Demonology", oi = 302 } },
			4242, 900)
		assert.same({ a = "Affliction", ai = 301, o = "Demonology", oi = 302 }, gdb.talents[OWNER])
		assert.equal(4242, gdb.hashes["professions:" .. OWNER].hash)
	end)

	it("drops malformed fields rather than storing them", function()
		deliver({ ["197"] = { r = 300, m = 300 }, t = { a = 7, ai = "x", o = "Demonology" } }, 1, 900)
		assert.same({ o = "Demonology" }, gdb.talents[OWNER])
	end)

	it("a snapshot without `t` (an older relay) keeps the spec already held", function()
		-- KNOWN COST: a relay before v1.11.0 rebuilds the snapshot without `t`
		-- under the owner's token. Keeping the held spec means it can be stale
		-- until the owner's next re-mint, never erased by a relay.
		gdb.talents[OWNER] = { a = "Affliction", ai = 301 }
		deliver({ ["197"] = { r = 300, m = 300 } }, 2, 900)
		assert.same({ a = "Affliction", ai = 301 }, gdb.talents[OWNER])
	end)

	it("CharacterChanged names the character whose data changed, not the sender", function()
		local got = {}
		API.RegisterCallback("talents_api_spec", "CharacterChanged", function(_, ck) got[#got + 1] = ck end)
		deliver({ ["197"] = { r = 300, m = 300 } }, 3, 900)
		API.UnregisterCallback("talents_api_spec", "CharacterChanged")
		assert.same({ OWNER }, got)
	end)

	it("a relay serves the spec it adopted under the owner's token", function()
		deliver({ ["197"] = { r = 300, m = 300 }, t = { a = "Affliction", ai = 301 } }, 77, 900)
		local leaf = S:BuildLeafPayload("professions:" .. OWNER).leaves["professions:" .. OWNER]
		assert.same({ a = "Affliction", ai = 301 }, leaf.data.t)
		assert.equal(77, leaf.hash)
	end)
end)

-- ---------------------------------------------------------------------------
-- 5. The API
-- ---------------------------------------------------------------------------

describe("TOGPM.API", function()
	it("is published on the TOGPM global with a version", function()
		assert.equal(API, _G.TOGPM.API)
		assert.equal(1, API.VERSION)
	end)

	it("GetProfessions: primaries first, then by id, secondaries flagged", function()
		gdb.skills[OWNER] = {
			[185] = { skillRank = 150, skillMax = 300 },   -- Cooking
			[333] = { skillRank = 300, skillMax = 300 },   -- Enchanting
			[197] = { skillRank = 280, skillMax = 300 },   -- Tailoring
		}
		local got = API.GetProfessions(OWNER)
		assert.same({ 197, 333, 185 }, { got[1].profId, got[2].profId, got[3].profId })
		assert.same({ true, true, false }, { got[1].isPrimary, got[2].isPrimary, got[3].isPrimary })
		assert.equal(280, got[1].skillRank)
		assert.equal("string", type(got[1].name))
	end)

	it("GetCharacterKey is the addon's own key for the logged-in character", function()
		assert.equal(ns:GetCharacterKey(), API.GetCharacterKey())
		assert.equal(ME, API.GetCharacterKey())
	end)

	it("GetProfessions answers an empty list for an unknown character", function()
		assert.same({}, API.GetProfessions("Nobody-Testrealm"))
	end)

	it("GetSpec returns a copy, and nil when no spec is held", function()
		assert.is_nil(API.GetSpec(OWNER))
		gdb.talents[OWNER] = { a = "Affliction", ai = 301, o = "Demonology", oi = 302 }
		local spec = API.GetSpec(OWNER)
		assert.same({ active = "Affliction", activeId = 301, other = "Demonology", otherId = 302 }, spec)
		spec.active = "changed"
		assert.equal("Affliction", gdb.talents[OWNER].a)
	end)

	it("HasData and GetCharacters cover professions and specs", function()
		gdb.skills[OWNER] = { [197] = { skillRank = 1, skillMax = 75 } }
		gdb.talents["Carl-Testrealm"] = { a = "Fire" }
		assert.is_true(API.HasData(OWNER))
		assert.is_true(API.HasData("Carl-Testrealm"))
		assert.is_false(API.HasData("Nobody-Testrealm"))
		assert.same({ OWNER, "Carl-Testrealm" }, API.GetCharacters())
	end)
end)
