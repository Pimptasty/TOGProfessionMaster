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

-- The filter strip: a search and a crafting-skill range. A character the
-- filter hides is not counted, so every headcount is "how many matching".
describe("the filter strip", function()
	local GT
	before_each(function()
		GT = ns.GuildTab
		GT._filter.text, GT._filter.minSkill, GT._filter.maxSkill = "", nil, nil
		crafts(BS, 2018, MATE)
		crafts(BS, 2018, OTHER)
		hasSkill(BS, MATE, 125)
		hasSkill(BS, OTHER, 240)
	end)
	after_each(function()
		GT._filter.text, GT._filter.minSkill, GT._filter.maxSkill = "", nil, nil
	end)

	it("counts everyone when nothing is set", function()
		assert.is_false(GT:IsFiltering())
		assert.equal(2, profEntry(BS).total)
	end)

	-- The search matches every label on the page, so it is applied where the
	-- tree is built: the profession row for Blacksmithing, or nil.
	local function bsNode()
		for _, node in ipairs(GT:BuildTree(GT:BuildCounts())) do
			if node.key == BS then return node end
		end
		return nil
	end

	it("keeps only characters whose name contains the search, whatever the case", function()
		GT._filter.text = "str"
		assert.is_true(GT:IsFiltering())
		assert.equal("1", bsNode().valueText)
		assert.is_true(GT:NameMatches(OTHER))
		assert.is_false(GT:NameMatches(MATE))
	end)

	it("does not match on the realm", function()
		GT._filter.text = "testrealm"
		assert.is_nil(bsNode())
	end)

	it("keeps a whole profession whose name matches", function()
		GT._filter.text = "BLACKSMITH"
		GT._filter.text = GT._filter.text:lower()
		assert.equal("2", bsNode().valueText)
	end)

	it("keeps a whole specialisation whose name matches", function()
		-- Both crafters know only an unspecialised recipe, so they sit in the
		-- Unspecialized bucket; typing its name keeps both.
		GT._filter.text = "unspecial"
		local node = bsNode()
		assert.equal("2", node.valueText)
		assert.equal(1, #node.children)
		assert.equal("2", node.children[1].valueText)
	end)

	it("finds your own characters by the word the list shows for them", function()
		hasSkill(BS, ns:GetCharacterKey())
		gdb.accountChars[ns:GetCharacterKey()] = true
		GT._filter.text = "you"
		assert.is_true(GT:NameMatches(ns:GetCharacterKey()))
		assert.is_false(GT:NameMatches(MATE))
	end)

	it("keeps only characters whose skill is inside the range, bounds included", function()
		GT._filter.minSkill, GT._filter.maxSkill = 200, 240
		local e = profEntry(BS)
		assert.equal(1, e.total)
		assert.is_true(e.memberSet[OTHER])
	end)

	it("takes a one-sided range", function()
		GT._filter.maxSkill = 125
		local e = profEntry(BS)
		assert.equal(1, e.total)
		assert.is_true(e.memberSet[MATE])
	end)

	it("tests the skill in the profession being counted, not another", function()
		-- Bob is 300 in Alchemy but 125 in Blacksmithing: a 250+ range keeps
		-- him under Alchemy only.
		hasSkill(ALCHEMY, MATE, 300)
		GT._filter.minSkill = 250
		assert.is_true(profEntry(ALCHEMY).memberSet[MATE])
		assert.is_nil(profEntry(BS).memberSet[MATE])
	end)

	it("hides a character with no recorded skill while a range is set", function()
		assert.is_true(GT:MemberPasses("Nobody-Testrealm", BS))
		GT._filter.minSkill = 1
		assert.is_false(GT:MemberPasses("Nobody-Testrealm", BS))
	end)

	it("runs the steppers to this expansion's skill cap", function()
		ns.SKILL_CAP = 375
		assert.equal(375, GT:SkillCap())
		-- Retail has no single cap: the highest recorded skillMax, else 100.
		ns.SKILL_CAP = nil
		assert.equal(300, GT:SkillCap())
		gdb.skills = {}
		assert.equal(100, GT:SkillCap())
	end)

	it("finds an offline main by the name of its alt", function()
		-- The row reads "Alt (Main)" when the alt is online, so the alt's
		-- name is what the player types.
		gdb.altGroups[OTHER] = { OTHER, "Twinky-Testrealm" }
		GT._filter.text = "twink"
		assert.is_true(GT:NameMatches(OTHER))
		assert.is_false(GT:NameMatches(MATE))
	end)

	it("opens the tree for a search and closes it when the search is cleared", function()
		local calls = {}
		local saved = GT._list
		GT._list = {
			SetData = function() end,
			SetAllExpanded = function(_, open) calls[#calls + 1] = open end,
		}
		GT._expandedBySearch = nil
		GT._filter.text = "bob"
		GT:SetTree({})
		-- A refresh mid-search must not reopen what the player collapsed.
		GT:SetTree({})
		GT._filter.text = ""
		GT:SetTree({})
		GT:SetTree({})
		GT._list = saved
		assert.same({ true, false }, calls)
	end)

	it("draws the strip, and a released strip stops a late search from updating", function()
		-- The search is debounced: its timer can fire after a tab switch
		-- released the strip, and must not write the Guild count into another
		-- tab's status bar.
		local container = env.drawTab(GT)
		assert.is_table(GT._drawToken)
		-- The skill range is the library's steppers. A typed skill filters
		-- once committed; the full range is no limit at all.
		local minStep = GT._toolbar.minSkill.stepper
		local maxStep = GT._toolbar.maxSkill.stepper
		minStep.edit:SetText("150")
		minStep.edit:GetScript("OnEnterPressed")(minStep.edit)
		assert.equal(150, GT._filter.minSkill)
		minStep.edit:SetText("1")
		minStep.edit:GetScript("OnEnterPressed")(minStep.edit)
		assert.is_nil(GT._filter.minSkill)
		-- Max starts at the skill cap, which is no limit; moving it off filters.
		assert.equal(GT:SkillCap(), maxStep._max)
		assert.equal(maxStep:GetValue(), maxStep._max)
		assert.is_nil(GT._filter["max" .. "Skill"])
		maxStep.edit:SetText("200")
		maxStep.edit:GetScript("OnEnterPressed")(maxStep.edit)
		assert.equal(200, GT._filter.maxSkill)
		container:ReleaseChildren()
		assert.is_nil(GT._drawToken)
	end)

	it("hooks the list's re-layout only on a library older than MINOR 42", function()
		-- Before MINOR 42 the rows kept the width the scroll box had at the
		-- last layout, which in game was the 40px minimum (names drawn as
		-- ".."). MINOR 42 anchors them to the scroll box (contract 0f350cea).
		local minors = LibStub.minors
		local saved = minors["LibAceGUIWidgets-1.0"]
		minors["LibAceGUIWidgets-1.0"] = 41
		local old = GT:NeedsRelayoutHook()
		minors["LibAceGUIWidgets-1.0"] = 42
		local new = GT:NeedsRelayoutHook()
		minors["LibAceGUIWidgets-1.0"] = saved
		assert.is_true(old)
		assert.is_false(new)
	end)

	it("Draw hooks the scroll box only on a library older than MINOR 42", function()
		-- Fires the scroll box's resize on a freshly built list and counts
		-- the calls that reach list._relayout, which only our hook makes (the
		-- library's own handler calls its local relayout directly).
		local minors = LibStub.minors
		local savedMinor, savedList = minors["LibAceGUIWidgets-1.0"], GT._list
		local function relayoutsOnResize(minor)
			minors["LibAceGUIWidgets-1.0"] = minor
			GT._list = nil
			env.drawTab(GT)
			local list = assert(GT._list)
			local calls = 0
			list._relayout = function() calls = calls + 1 end
			local fn = list.box.scroll:GetScript("OnSizeChanged")
			if fn then fn(list.box.scroll, 600, 300) end
			return calls
		end
		local old = relayoutsOnResize(41)
		local new = relayoutsOnResize(42)
		minors["LibAceGUIWidgets-1.0"], GT._list = savedMinor, savedList
		assert.equal(1, old)
		assert.equal(0, new)
	end)

	it("puts the counts in one centred column under the Characters header", function()
		-- LibAceGUIWidgets contract a79b0269 (MINOR 42): the count column
		-- starts where the header's column starts and is the header's width.
		local W, savedList = ns.W, GT._list
		local real, seen = W.CreateExpandableList, nil
		W.CreateExpandableList = function(self, parent, opts)
			seen = opts
			return real(self, parent, opts)
		end
		GT._list = nil
		local ok, err = pcall(env.drawTab, GT)
		W.CreateExpandableList, GT._list = real, savedList
		assert(ok, err)
		assert.is_table(seen)
		assert.same({ offset = 320, width = 80, justify = "CENTER" }, seen.valueColumn)
	end)

	it("sizes the column headers at the library's scale, like the count column", function()
		-- The scale is one setting for every addon on the client; the list
		-- scales valueColumn by it, so the headers must too.
		local W, GUI = ns.W, ns.GUI
		local realHdr, widths = GUI.MakeColumnHeader, {}
		GUI.MakeColumnHeader = function(opts)
			widths[#widths + 1] = opts.width
			return realHdr(opts)
		end
		local savedScale = W:GetScale()
		W:SetScale(1.5)
		local ok, err = pcall(env.drawTab, GT)
		W:SetScale(savedScale)
		GUI.MakeColumnHeader = realHdr
		assert(ok, err)
		assert.same({ 480, 120 }, widths)
	end)

	it("redraws the window on a scale change only while the Guild tab shows", function()
		env.drawTab(GT)
		local W, mw = ns.W, ns.MainWindow
		local savedTab, savedFrame, savedRefresh = mw.activeTab, mw.frame, mw.Refresh
		local calls = 0
		mw.Refresh = function() calls = calls + 1 end
		mw.frame = mw.frame or {}
		local savedScale = W:GetScale()
		mw.activeTab = "guild"
		W:SetScale(1.25)
		mw.activeTab = "browser"
		W:SetScale(1.5)
		W:SetScale(savedScale)
		mw.activeTab, mw.frame, mw.Refresh = savedTab, savedFrame, savedRefresh
		assert.equal(1, calls)
	end)

	it("moves a Max left at no limit to the new skill cap on a redraw", function()
		local container = env.drawTab(GT)
		local step = GT._toolbar.maxSkill.stepper
		local saved = ns.SKILL_CAP
		ns.SKILL_CAP = 375
		container:ReleaseChildren()
		env.drawTab(GT)
		ns.SKILL_CAP = saved
		assert.equal(375, step:GetValue())
		assert.is_nil(GT._filter.maxSkill)
	end)

	it("leaves a Max the player set, and a Max being typed in, where it is", function()
		local container = env.drawTab(GT)
		local step = GT._toolbar.maxSkill.stepper
		local saved = ns.SKILL_CAP
		-- A real bound survives a cap change.
		step.edit:SetText("200")
		step.edit:GetScript("OnEnterPressed")(step.edit)
		ns.SKILL_CAP = 375
		container:ReleaseChildren()
		container = env.drawTab(GT)
		local kept = step:GetValue()
		-- Back to no limit, then a redraw while the box has focus.
		GT._filter.maxSkill = nil
		step:SetValue(300)
		step.edit:SetFocus()
		ns.SKILL_CAP = 450
		container:ReleaseChildren()
		env.drawTab(GT)
		local focused = step:GetValue()
		step.edit:ClearFocus()
		ns.SKILL_CAP = saved
		GT._filter.maxSkill = nil
		assert.equal(200, kept)
		assert.equal(300, focused)
	end)

	it("leaves out the empty rows in the tree while filtering", function()
		GT._filter.text = "bob"
		local tree = GT:BuildTree(GT:BuildCounts())
		for _, node in ipairs(tree) do
			assert.is_true(tonumber(node.valueText) > 0)
			for _, child in ipairs(node.children or {}) do
				if child.valueText then assert.is_true(tonumber(child.valueText) > 0) end
			end
		end
		assert.equal(1, #tree)
	end)
end)

-- The tree handed to LibAceGUIWidgets' expandable list: profession ->
-- specialisation -> member, with the empty parts shown but not expandable.
describe("BuildTree", function()
	local tree

	before_each(function()
		local GT = ns.GuildTab
		local orig = GT.BuildMemberList
		GT.BuildMemberList = function()
			return { { name = "Mate", online = true, skillText = " (300/300)" } }
		end
		tree = GT:BuildTree({
			{ profId = 164, name = "Blacksmithing", total = 2, specs = {
				{ key = "armor", name = "Armorsmith", count = 1, memberSet = { x = true } },
				{ key = "weapon", name = "Weaponsmith", count = 0 },
			} },
			{ profId = 129, name = "First Aid", total = 1, specs = {}, memberSet = { x = true } },
			{ profId = 182, name = "Herbalism", total = 0, specs = {} },
		})
		GT.BuildMemberList = orig
	end)

	it("keys each profession by its id and counts it", function()
		assert.equal(164, tree[1].key)
		assert.equal("2", tree[1].valueText)
	end)

	it("puts members under a specialisation that has any", function()
		local armor = tree[1].children[1]
		assert.equal("armor", armor.key)
		assert.equal("Mate (300/300)", armor.children[1].label)
	end)

	it("shows an empty specialisation with nothing to expand", function()
		assert.is_nil(tree[1].children[2].children)
		assert.equal("Weaponsmith", tree[1].children[2].label)
	end)

	it("expands a profession with no specialisations straight to its members", function()
		assert.equal("Mate (300/300)", tree[2].children[1].label)
	end)

	it("shows a profession nobody has, dimmed, with nothing to expand", function()
		assert.is_nil(tree[3].children)
		assert.equal("Herbalism", tree[3].label)
		assert.is_table(tree[3].color)
	end)
end)
