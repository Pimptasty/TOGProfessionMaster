-- GUI/GuildTab.lua — the two functions that decide what the Guild tab claims
-- about your guild's coverage.
--
-- Both are pure over the guild DB, and both have shipped wrong before:
--
--   * `BuildCounts` answers "who has this profession", from the UNION of two
--     incomplete signals. Counting only `skills` undercounts badly (most
--     crafters never open their window with the addon watching); counting only
--     `crafters` misses gathering professions entirely. Getting the union wrong
--     produces a headcount an officer will act on.
--   * `BuildMemberList` renders "300/300" next to a name, and used to render the
--     impossible "375/300" by trusting a per-character `skillMax` that is often
--     a stale Vanilla-era 300 (fixed in v1.0.1).
--
-- Written against what these SHOULD say, not what they currently do — the
-- assertions below are the specification, and each was checked to fail when the
-- behaviour it names is removed.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, gdb, savedSkillCap
local BS, ALCHEMY, HERB = 164, 171, 182
local ME    = "Testchar-Testrealm"
local MATE  = "Bob-Testrealm"
local OTHER = "Stranger-Testrealm"

-- Blacksmithing specs, which exist on Classic Era (the env's flavour).
local WEAPONSMITH, SWORDSMITH, ARMORSMITH = 9787, 17039, 9788

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/GuildTab.lua")
end)

before_each(function()
	env.installFrames()
	-- GetSpellInfo comes from the harness now (env.wow, both of Classic Era's
	-- forms). It returns nil for a spell nothing registered, which is why
	-- GuildTab's `or ("Spell " .. id)` fallback executes here — the spec rows are
	-- matched by spell id rather than by name, so the placeholder is harmless.
	-- SKILL_CAP is a field on the ADDON table, which env.install() does not
	-- reset — only globals come back. Restored in after_each so a spec here
	-- cannot change what a later spec FILE thinks this expansion's cap is.
	savedSkillCap = ns.SKILL_CAP
	gdb = env.resetDb()
	env.roster({
		{ name = "Testchar", isOnline = true },
		{ name = "Bob",      isOnline = true },
		{ name = "Stranger", isOnline = false },
	})
end)

after_each(function()
	ns.SKILL_CAP = savedSkillCap
end)

--- Record `charKey` as a crafter of one recipe in `profId`, the way a sync does.
local function crafts(profId, recipeId, charKey)
	gdb.recipes[profId] = gdb.recipes[profId] or {}
	gdb.recipes[profId][recipeId] = gdb.recipes[profId][recipeId] or { crafters = {} }
	gdb.recipes[profId][recipeId].crafters[charKey] = ns:GetCurrentGuildTag()
end

local function hasSkill(profId, charKey, rank, max)
	gdb.skills[charKey] = gdb.skills[charKey] or {}
	gdb.skills[charKey][profId] = { skillRank = rank or 300, skillMax = max or 300 }
end

--- The entry BuildCounts produced for one profession.
local function profEntry(profId)
	local list = ns.GuildTab:BuildCounts()
	for _, e in ipairs(list) do
		if e.profId == profId then return e end
	end
	return nil
end

local function specEntry(profId, specSpell)
	local e = profEntry(profId)
	for _, s in ipairs(e and e.specs or {}) do
		if s.key == specSpell then return s end
	end
	return nil
end

describe("BuildCounts — who has a profession", function()
	it("counts someone known only from their recorded skill", function()
		hasSkill(BS, MATE)
		assert.equal(1, profEntry(BS).total)
	end)

	it("counts someone known only from a recipe they craft", function()
		-- The signal that fills the gaps: most crafters never open their window
		-- with the addon watching, so skills alone undercounts the guild.
		crafts(BS, 2018, MATE)
		assert.equal(1, profEntry(BS).total)
	end)

	it("counts someone in BOTH signals exactly once", function()
		hasSkill(BS, MATE)
		crafts(BS, 2018, MATE)
		assert.equal(1, profEntry(BS).total)
	end)

	it("counts someone crafting many recipes exactly once", function()
		crafts(BS, 2018, MATE)
		crafts(BS, 2020, MATE)
		crafts(BS, 3293, MATE)
		assert.equal(1, profEntry(BS).total)
	end)

	it("excludes a character outside the current guild", function()
		-- Both tables are account-wide, so a cross-guild alt would otherwise
		-- inflate this guild's headcount — the number an officer recruits on.
		crafts(BS, 2018, MATE)
		gdb.recipes[BS][2018].crafters["Foreigner-Otherrealm"] = "xx"
		assert.equal(1, profEntry(BS).total)
	end)

	it("shows a gathering profession with nobody in it", function()
		-- Herbalism has neither recipes nor skills until someone syncs, so
		-- without the forced row the coverage gap is invisible.
		local herb = profEntry(HERB)
		assert.is_truthy(herb)
		assert.equal(0, herb.total)
	end)
end)

describe("BuildCounts — specializations", function()
	it("infers a spec from a spec-gated recipe the crafter knows", function()
		-- A Swordsmith-only pattern can only be learned by a Swordsmith, so this
		-- classifies crafters who never synced a detected spec.
		env.setRecipeDB({ [BS] = { [16994] = { requiredSpec = SWORDSMITH } } })
		crafts(BS, 16994, MATE)
		assert.equal(1, specEntry(BS, SWORDSMITH).count)
	end)

	-- A swordsmith necessarily knows Weaponsmith recipes too; classifying them as
	-- Weaponsmith would hide the finer coverage an officer is looking for. The
	-- rule has to hold whichever recipe the scan happens to reach first, so both
	-- orders are asserted.
	--
	-- Recipe ids 1 and 2 rather than real ones ON PURPOSE: small contiguous
	-- integer keys land in the table's ARRAY part, so `pairs` visits them in
	-- order and the test controls which spec is seen first. With real ids this
	-- test passed even with the preference deleted — it was asserting hash
	-- ordering, not the rule.
	local function bothSpecsKnown(firstSpec, secondSpec)
		env.setRecipeDB({ [BS] = {
			[1] = { requiredSpec = firstSpec },
			[2] = { requiredSpec = secondSpec },
		} })
		crafts(BS, 1, MATE)
		crafts(BS, 2, MATE)
	end

	it("prefers the sub-spec when the parent is seen first", function()
		bothSpecsKnown(WEAPONSMITH, SWORDSMITH)
		assert.equal(1, specEntry(BS, SWORDSMITH).count)
		assert.equal(0, specEntry(BS, WEAPONSMITH).count)
	end)

	it("prefers the sub-spec when the sub-spec is seen first", function()
		bothSpecsKnown(SWORDSMITH, WEAPONSMITH)
		assert.equal(1, specEntry(BS, SWORDSMITH).count)
		assert.equal(0, specEntry(BS, WEAPONSMITH).count)
	end)

	it("prefers a detected spec over an inferred one", function()
		env.setRecipeDB({ [BS] = { [9954] = { requiredSpec = WEAPONSMITH } } })
		crafts(BS, 9954, MATE)
		gdb.specializations[MATE] = { [BS] = ARMORSMITH }
		assert.equal(1, specEntry(BS, ARMORSMITH).count)
	end)

	it("lists a canonical spec nobody has, at zero", function()
		crafts(BS, 2018, MATE)
		local axesmith = specEntry(BS, 17041)
		assert.is_truthy(axesmith)
		assert.equal(0, axesmith.count)
	end)

	it("does not invent specs for a profession that has none on this client", function()
		-- Alchemy's specs arrived in TBC; on Classic Era the tab must not claim
		-- coverage gaps for specialisations the client has never had.
		crafts(ALCHEMY, 2330, MATE)
		local e = profEntry(ALCHEMY)
		assert.is_truthy(e)
		assert.equal(0, #e.specs)
	end)
end)

describe("BuildMemberList — the skill reading next to a name", function()
	local function skillTextFor(charKey, profId)
		local rows = ns.GuildTab:BuildMemberList({ [charKey] = true }, profId)
		return rows[1] and rows[1].skillText or ""
	end

	it("never renders a rank above its own cap", function()
		-- The v1.0.1 bug: a stale Vanilla-era skillMax of 300 against a TBC rank
		-- of 375 rendered "375/300", which cannot exist.
		ns.SKILL_CAP = 375
		hasSkill(BS, MATE, 375, 300)
		local text = skillTextFor(MATE, BS)
		assert.is_truthy(text:find("375/375", 1, true))
		assert.is_nil(text:find("375/300", 1, true))
	end)

	it("shows this expansion's cap, not the character's stale one", function()
		ns.SKILL_CAP = 375
		hasSkill(BS, MATE, 200, 300)
		assert.is_truthy(skillTextFor(MATE, BS):find("200/375", 1, true))
	end)

	it("clamps to the rank when the data is odder still", function()
		ns.SKILL_CAP = 375
		hasSkill(BS, MATE, 400, 300)
		assert.is_truthy(skillTextFor(MATE, BS):find("400/400", 1, true))
	end)

	it("says nothing at all when no skill was ever recorded", function()
		crafts(BS, 2018, MATE)
		assert.equal("", skillTextFor(MATE, BS))
	end)

	it("says nothing for a rank of zero rather than '0/375'", function()
		ns.SKILL_CAP = 375
		hasSkill(BS, MATE, 0, 300)
		assert.equal("", skillTextFor(MATE, BS))
	end)

	it("sorts online members above offline ones", function()
		local rows = ns.GuildTab:BuildMemberList({ [MATE] = true, [OTHER] = true }, BS)
		assert.equal(2, #rows)
		assert.is_true(rows[1].online)
		assert.is_false(rows[2].online)
	end)
end)
