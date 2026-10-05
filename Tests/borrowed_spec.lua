-- Values ProfessionDB BORROWED from another flavour (LibProfessionDB MINOR 13).
--
-- WoW Forever has no source of its own for a recipe's trainer requirement or its
-- sources, so ProfessionDB ships Vanilla's for the spells the two share and flags
-- each one: lib:IsBorrowed(spellID, field) == "Vanilla" for field
-- "requiredSkill" | "sources" | "hidden".
--
-- Two rules follow, and both are pinned here:
--
--   1. THE UNANCHORED RULE CHANGES. Tiers are placeholders when difficulty[1] == 1
--      and requiredSkill is ABSENT *or BORROWED*. A borrowed requiredSkill is
--      another flavour's trainer value and must not anchor this client's orange
--      tier. Forever recipe 3761 ships requiredSkill 85 (Vanilla's) with
--      difficulty[1] 1; the old "absent only" rule read it as orange-from-1.
--   2. A borrowed value is SHOWN but MARKED UNCONFIRMED (the operator's
--      direction): the "Requires X (N)" line, the tooltip's Sources heading and
--      the Missing Recipes source column.
--
-- Everything is feature-detected on IsBorrowed, so a ProfessionDB older than
-- MINOR 13 -- and every client whose data borrows nothing -- behaves as before.

---@diagnostic disable: duplicate-set-field, redundant-parameter, assign-type-mismatch
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, IL, M, B, L, gdb
local ME       = "Testchar-Testrealm"
local LEATHER  = 165
local PROFNAME = "Leatherworking"
local BORROWED = 3761   -- the Forever case from ProfessionDB's notice
local OWN      = 3762   -- a recipe whose values are this client's own

-- Install a ProfessionDB stand-in whose IsBorrowed answers from `flags`
-- ({ [spellID] = { [field] = "Vanilla" } }). nil flags = an older ProfessionDB
-- with no IsBorrowed at all.
local function pdbWith(flags)
	if flags == nil then
		ns._profDB = { GetRecipes = function() return {} end }
		return
	end
	ns._profDB = {
		IsBorrowed = function(_, spellID, field)
			local slot = flags[spellID]
			return slot and slot[field] or nil
		end,
	}
end

local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local function fakeTooltip()
	local t = { lines = {} }
	t.AddLine = function(_, text) t.lines[#t.lines + 1] = tostring(text) end
	t.has = function(needle)
		for _, l in ipairs(t.lines) do if l == needle then return true end end
		return false
	end
	return t
end

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	M  = env.loadModule("GUI/MissingRecipesTab.lua").MissingRecipesTab
	B  = env.loadModule("GUI/BrowserTab.lua").BrowserTab
	IL = ns.ItemLink
	L  = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
end)

before_each(function()
	env.install()
	env.installFrames()
	gdb = env.resetDb()
	env.spellsExist(BORROWED, OWN)
	env.setRecipeDB({
		[LEATHER] = {
			[BORROWED] = { name = "Borrowed Thing", requiredSkill = 85, difficulty = { 1, 30, 45, 60 } },
			[OWN]      = { name = "Own Thing",      requiredSkill = 85, difficulty = { 1, 30, 45, 60 } },
		},
	})
	ns.sourceDB = {
		[LEATHER] = {
			[BORROWED] = { trainer = { { id = 1, name = "A" } }, vendor = { { id = 2, name = "B" } } },
			[OWN]      = { trainer = { { id = 1, name = "A" } }, vendor = { { id = 2, name = "B" } } },
		},
	}
	gdb.skills[ME] = { [LEATHER] = { skillRank = 100, skillMax = 150 } }
	gdb.accountChars[ME] = true
	pdbWith({ [BORROWED] = { requiredSkill = "Vanilla", sources = "Vanilla" } })
end)

-- `_profDB` and `sourceDB` live on the namespace every spec file shares; leaving
-- the stand-ins behind would hand them to later files.
after_each(function()
	ns._profDB  = nil
	ns.sourceDB = {}
end)

-- ---------------------------------------------------------------------------

describe("the unanchored rule with a borrowed requiredSkill", function()
	it("is unanchored when requiredSkill is borrowed and difficulty[1] is 1", function()
		assert.is_true(ns.IsUnanchoredDifficulty({ 1, 30, 45, 60 }, 85, BORROWED))
	end)

	it("stays anchored when the same values are the client's own", function()
		assert.is_false(ns.IsUnanchoredDifficulty({ 1, 30, 45, 60 }, 85, OWN))
	end)

	it("stays anchored when a borrowed requiredSkill sits over a real orange above 1", function()
		assert.is_false(ns.IsUnanchoredDifficulty({ 90, 115, 127, 140 }, 85, BORROWED))
	end)

	it("only reads the requiredSkill flag, not another borrowed field", function()
		pdbWith({ [BORROWED] = { sources = "Vanilla" } })
		assert.is_false(ns.IsUnanchoredDifficulty({ 1, 30, 45, 60 }, 85, BORROWED))
	end)

	it("falls back to the old absent-only rule without a recipe id", function()
		assert.is_false(ns.IsUnanchoredDifficulty({ 1, 30, 45, 60 }, 85, nil))
		assert.is_true(ns.IsUnanchoredDifficulty({ 1, 30, 45, 60 }, nil, nil))
	end)

	it("behaves exactly as before against a ProfessionDB with no IsBorrowed", function()
		pdbWith(nil)
		assert.is_false(ns.IsUnanchoredDifficulty({ 1, 30, 45, 60 }, 85, BORROWED))
		assert.is_true(ns.IsUnanchoredDifficulty({ 1, 30, 45, 60 }, nil, BORROWED))
	end)
end)

describe("FormatSkillTiers with a borrowed requiredSkill", function()
	it("shows the borrowed recipe's placeholder tiers as unknown", function()
		assert.equal("-", ns.FormatSkillTiers({ 1, 30, 45, 60 }, 85, BORROWED))
	end)

	it("still shows an own recipe's tiers", function()
		assert.equal("1 30 45 60", plain(ns.FormatSkillTiers({ 1, 30, 45, 60 }, 85, OWN)))
	end)

	it("still shows tiers when no recipe id is passed (the pre-MINOR-13 call shape)", function()
		assert.equal("1 30 45 60", plain(ns.FormatSkillTiers({ 1, 30, 45, 60 }, 85)))
	end)

	it("marks a lone borrowed requiredSkill unconfirmed", function()
		assert.equal("85 (" .. L["Unconfirmed"] .. ")", plain(ns.FormatSkillTiers(nil, 85, BORROWED)))
	end)

	it("does not mark a lone own requiredSkill", function()
		assert.equal("85", plain(ns.FormatSkillTiers(nil, 85, OWN)))
	end)
end)

describe("the learn skill with a borrowed requiredSkill", function()
	it("keeps the borrowed trainer requirement as the learn skill", function()
		-- It is the trainer value the player is shown (marked unconfirmed), not
		-- an orange tier, so the unanchored rule does not erase it.
		assert.equal(85, ns.RecipeLearnSkill(ns.recipeDB[LEATHER][BORROWED]))
		assert.equal(85, ns.LearnSkillFrom(85, { 1, 30, 45, 60 }))
	end)

	it("answers unknown for unanchored tiers with no requiredSkill", function()
		assert.is_nil(ns.LearnSkillFrom(nil, { 1, 30, 45, 60 }))
	end)
end)

describe("the Requires line marks a borrowed requiredSkill", function()
	it("shows the borrowed value, marked unconfirmed", function()
		local _, requires = IL.ScrollHeader(LEATHER, BORROWED, "Borrowed Thing", PROFNAME)
		assert.equal("Requires Leatherworking (85, " .. L["Unconfirmed"] .. ")", requires)
	end)

	it("leaves an own value unmarked", function()
		local _, requires = IL.ScrollHeader(LEATHER, OWN, "Own Thing", PROFNAME)
		assert.equal("Requires Leatherworking (85)", requires)
	end)

	it("leaves it unmarked against a ProfessionDB with no IsBorrowed", function()
		pdbWith(nil)
		local _, requires = IL.ScrollHeader(LEATHER, BORROWED, "Borrowed Thing", PROFNAME)
		assert.equal("Requires Leatherworking (85)", requires)
	end)
end)

describe("the recipe-detail block marks borrowed sources", function()
	it("reports borrowed sources as a third return", function()
		local _, sources, borrowed = IL.RecipeDetails(LEATHER, BORROWED)
		assert.is_truthy(sources)
		assert.is_true(borrowed)
		local _, ownSources, ownBorrowed = IL.RecipeDetails(LEATHER, OWN)
		assert.is_truthy(ownSources)
		assert.is_false(ownBorrowed)
	end)

	it("does not print the borrowed recipe's placeholder tiers", function()
		assert.is_nil((IL.RecipeDetails(LEATHER, BORROWED)))
		assert.is_truthy((IL.RecipeDetails(LEATHER, OWN)))
	end)

	it("marks the Sources heading unconfirmed, once", function()
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, LEATHER, BORROWED))
		assert.is_true(tip.has(L["TooltipSources"] .. " (" .. L["Unconfirmed"] .. ")"))
		assert.is_false(tip.has(L["TooltipSources"]))
	end)

	it("leaves an own recipe's Sources heading plain", function()
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, LEATHER, OWN))
		assert.is_true(tip.has(L["TooltipSources"]))
	end)
end)

describe("Missing Recipes marks borrowed sources", function()
	it("appends the mark to a borrowed source list", function()
		local out = M._FormatSources({ vendor = true, drop = true }, true, "Vanilla")
		assert.is_truthy(out:find("(" .. L["Unconfirmed"] .. ")", 1, true))
	end)

	it("never marks Unknown -- there is no value to doubt", function()
		assert.equal(L["MissingSrcUnknown"], M._FormatSources(nil, true, "Vanilla"))
		assert.equal(L["MissingSrcUnknown"], M._FormatSources({ trainer = true }, false, "Vanilla"))
	end)

	it("marks the borrowed row and only that row", function()
		local list = M._BuildMissingList(ME, LEATHER, true, false, false, "char")
		local byId = {}
		for _, r in ipairs(list) do byId[r.spellId] = r end
		assert.is_truthy(byId[BORROWED] and byId[OWN], "both recipes should be listed")
		assert.is_truthy(byId[BORROWED].sourcesText:find(L["Unconfirmed"], 1, true))
		assert.is_falsy(byId[OWN].sourcesText:find(L["Unconfirmed"], 1, true))
	end)
end)

describe("Missing Recipes skill sort honours the unanchored rule", function()
	it("sorts unanchored tiers with the unknowns, not as skill 1", function()
		local unanchored = { spellId = 1, tiers = { 1, 25, 37, 50 } }
		local fifty      = { spellId = 2, requiredSkill = 50 }
		local unknown    = { spellId = 3 }
		local list = { unanchored, unknown, fifty }
		M.SortList({ _sortCol = "skill", _sortAsc = true, _profId = LEATHER }, list)
		assert.equal(fifty, list[1])
		-- The two unknowns tie on skill and fall back to spellId order.
		assert.equal(unanchored, list[2])
		assert.equal(unknown, list[3])
	end)

	it("still sorts an anchored orange tier by its value", function()
		local anchored = { spellId = 1, tiers = { 90, 115, 127, 140 } }
		local fifty    = { spellId = 2, requiredSkill = 50 }
		local list = { anchored, fifty }
		M.SortList({ _sortCol = "skill", _sortAsc = true, _profId = LEATHER }, list)
		assert.equal(fifty, list[1])
		assert.equal(anchored, list[2])
	end)
end)

describe("the marker string", function()
	it("is short, player-facing, and in the English locale", function()
		assert.equal("unconfirmed", L["Unconfirmed"])
		assert.equal(L["Unconfirmed"], ns.UnconfirmedText())
	end)
end)

-- ---------------------------------------------------------------------------
-- A recipe whose "never implemented" flag is BORROWED (IsBorrowed(id, "hidden"))
-- is let through by RecipeGate -- it may exist on WoW Forever -- so the rows that
-- show it, in the Professions and Missing Recipes lists, say it is unconfirmed,
-- and so does the row's tooltip. A recipe hidden on its own flag stays hidden; a
-- recipe with no flag is unmarked; a ProfessionDB with no IsBorrowed marks
-- nothing (and hides the flagged recipe, as before MINOR 13).
-- ---------------------------------------------------------------------------
describe("a recipe shown on a borrowed never-implemented flag", function()
	local MAYBE  = 3764   -- hidden on Vanilla's list, borrowed: shown, marked
	local HIDDEN = 3765   -- hidden on this client's own list: not shown
	local savedLib

	-- The gate reads ProfessionDB through LibStub, the addon helpers through
	-- addon:GetProfessionDB(); in game they are the same library, so the
	-- stand-in goes in both places. `borrows` = false models a ProfessionDB
	-- older than MINOR 13 (IsHiddenRecipe, no IsBorrowed).
	local function install(borrows)
		local lib = {
			IsHiddenRecipe = function(_, id) return id == MAYBE or id == HIDDEN end,
		}
		if borrows then
			lib.IsBorrowed = function(_, id, field)
				return id == MAYBE and field == "hidden" and "Vanilla" or nil
			end
		end
		LibStub.libs["LibProfessionDB-1.0"] = lib
		ns._profDB = lib
	end

	-- A recorder for GameTooltip: the tooltip specs read back what was added.
	local savedTooltip, tip
	local function recorderTooltip()
		local t = { lines = {}, colours = {} }
		t.AddLine = function(_, text, r, g, b)
			t.lines[#t.lines + 1] = tostring(text)
			t.colours[tostring(text)] = { r, g, b }
		end
		for _, m in ipairs({ "AddDoubleLine", "Show", "Hide", "SetOwner", "ClearLines",
		                     "SetText", "SetSpellByID", "SetItemByID", "SetHyperlink" }) do
			t[m] = function() end
		end
		t.NumLines  = function() return #t.lines end
		t.IsShown   = function() return true end
		t.GetItem   = function() return nil end
		t.has = function(needle)
			for _, l in ipairs(t.lines) do if l == needle then return true end end
			return false
		end
		return t
	end

	before_each(function()
		savedLib     = LibStub.libs["LibProfessionDB-1.0"]
		savedTooltip = _G.GameTooltip
		env.spellsExist(BORROWED, OWN, MAYBE, HIDDEN)
		env.setRecipeDB({
			[LEATHER] = {
				[OWN]    = { name = "Own Thing",    requiredSkill = 85 },
				[MAYBE]  = { name = "Maybe Thing",  requiredSkill = 85 },
				[HIDDEN] = { name = "Hidden Thing", requiredSkill = 85 },
			},
		})
		ns.sourceDB = { [LEATHER] = {} }
		install(true)
	end)

	after_each(function()
		LibStub.libs["LibProfessionDB-1.0"] = savedLib
		ns._profDB = nil
		_G.GameTooltip = savedTooltip
	end)

	local function byId(list, key)
		local out = {}
		for _, r in ipairs(list) do out[r[key]] = r end
		return out
	end

	describe("RecipeGate:IsUnconfirmed", function()
		it("is true only for the recipe the gate lets through on a borrowed flag", function()
			assert.is_true(ns.RecipeGate:IsUnconfirmed(MAYBE))
			assert.is_false(ns.RecipeGate:IsUnconfirmed(HIDDEN))
			assert.is_false(ns.RecipeGate:IsUnconfirmed(OWN))
		end)

		it("agrees with the gate: the marked recipe passes, the own-flag one does not", function()
			assert.is_true((ns.RecipeGate:IsValidOnClient(LEATHER, MAYBE, ns.recipeDB[LEATHER][MAYBE])))
			assert.is_false((ns.RecipeGate:IsValidOnClient(LEATHER, HIDDEN, ns.recipeDB[LEATHER][HIDDEN])))
		end)

		it("is false for a recipe whose other fields are borrowed but whose flag is not", function()
			-- Both places the library can be found: RecipeGate reads it through
			-- addon:GetProfessionDB, which caches it in ns._profDB.
			local lib = {
				IsHiddenRecipe = function() return false end,
				IsBorrowed     = function(_, _, field) return field ~= "hidden" and "Vanilla" or nil end,
			}
			LibStub.libs["LibProfessionDB-1.0"] = lib
			ns._profDB = lib
			assert.is_false(ns.RecipeGate:IsUnconfirmed(OWN))
		end)

		it("is false against a ProfessionDB with no IsBorrowed", function()
			install(false)
			assert.is_false(ns.RecipeGate:IsUnconfirmed(MAYBE))
		end)

		it("is false when ProfessionDB is not installed", function()
			LibStub.libs["LibProfessionDB-1.0"] = nil
			ns._profDB = nil   -- clear the accessor's cache so it looks again
			assert.is_false(ns.RecipeGate:IsUnconfirmed(MAYBE))
		end)
	end)

	describe("the Professions list", function()
		it("lists the borrowed-flag recipe, marked, and not the own-flag one", function()
			local rows = byId(B._BuildFullList(LEATHER, "guild", { showAll = true }), "id")
			assert.is_truthy(rows[MAYBE], "the borrowed-flag recipe should be listed")
			assert.is_nil(rows[HIDDEN])
			assert.is_true(rows[MAYBE].unconfirmed)
			assert.is_nil(rows[OWN].unconfirmed)
		end)

		it("marks nothing, and hides the flagged recipe, against a ProfessionDB with no IsBorrowed", function()
			install(false)
			local rows = byId(B._BuildFullList(LEATHER, "guild", { showAll = true }), "id")
			assert.is_nil(rows[MAYBE])
			assert.is_nil(rows[OWN].unconfirmed)
		end)

		it("puts (unconfirmed) after the name in the row's name cell", function()
			local savedW, cfg = ns.W, nil
			ns.W = { RowList = { New = function(_, _, c) cfg = c; return {} end } }
			B:BuildRowList({})
			ns.W = savedW
			local nameCol
			for _, col in ipairs(cfg.columns) do if col.key == "name" then nameCol = col end end
			local marked = plain(nameCol.format(nil, { name = "Maybe Thing", unconfirmed = true }))
			local own    = plain(nameCol.format(nil, { name = "Own Thing" }))
			assert.equal("Maybe Thing (" .. L["Unconfirmed"] .. ")", marked)
			assert.equal("Own Thing", own)
		end)

		it("says what the mark means on the row's tooltip, and only on that row", function()
			tip = recorderTooltip()
			_G.GameTooltip = tip
			B._AppendBrandTooltipLines({ id = MAYBE, profId = LEATHER, name = "Maybe Thing", unconfirmed = true })
			assert.is_true(tip.has(L["UnconfirmedRecipe"]))

			tip = recorderTooltip()
			_G.GameTooltip = tip
			B._AppendBrandTooltipLines({ id = OWN, profId = LEATHER, name = "Own Thing" })
			assert.is_false(tip.has(L["UnconfirmedRecipe"]))
		end)

		it("keeps the tooltip line when the recipe-detail block is switched off", function()
			local profile = ns.lib.db.profile
			local saved = profile.tooltipRecipeDetails
			profile.tooltipRecipeDetails = "never"
			tip = recorderTooltip()
			_G.GameTooltip = tip
			B._AppendBrandTooltipLines({ id = MAYBE, profId = LEATHER, name = "Maybe Thing", unconfirmed = true })
			profile.tooltipRecipeDetails = saved
			assert.is_true(tip.has(L["UnconfirmedRecipe"]))
		end)
	end)

	describe("the Missing Recipes list", function()
		it("lists the borrowed-flag recipe, marked, and not the own-flag one", function()
			local rows = byId(M._BuildMissingList(ME, LEATHER, true, false, false, "char"), "spellId")
			assert.is_truthy(rows[MAYBE], "the borrowed-flag recipe should be listed")
			assert.is_nil(rows[HIDDEN])
			assert.is_true(rows[MAYBE].unconfirmed)
			assert.is_nil(rows[OWN].unconfirmed)
		end)

		it("marks nothing against a ProfessionDB with no IsBorrowed", function()
			install(false)
			local rows = byId(M._BuildMissingList(ME, LEATHER, true, false, false, "char"), "spellId")
			assert.is_nil(rows[MAYBE])
			assert.is_nil(rows[OWN].unconfirmed)
		end)

		it("puts (unconfirmed) after the recipe name in the row", function()
			local marked = M:RowDisplay({ spellId = MAYBE, name = "Maybe Thing", unconfirmed = true }).name
			local own    = M:RowDisplay({ spellId = OWN, name = "Own Thing" }).name
			assert.is_truthy(plain(marked):find("(" .. L["Unconfirmed"] .. ")", 1, true))
			assert.is_falsy(plain(own):find(L["Unconfirmed"], 1, true))
		end)

		it("says what the mark means on the row's tooltip, and only on that row", function()
			tip = recorderTooltip()
			_G.GameTooltip = tip
			M:ShowRowTooltip({ spellId = MAYBE, profId = LEATHER, unconfirmed = true }, CreateFrame("Frame"))
			assert.is_true(tip.has(L["UnconfirmedRecipe"]))

			tip = recorderTooltip()
			_G.GameTooltip = tip
			M:ShowRowTooltip({ spellId = OWN, profId = LEATHER }, CreateFrame("Frame"))
			assert.is_false(tip.has(L["UnconfirmedRecipe"]))
		end)
	end)

	describe("ItemLink helpers", function()
		it("add nothing for a confirmed recipe", function()
			assert.equal("", IL.UnconfirmedRowSuffix(nil))
			local t = fakeTooltip()
			assert.is_false(IL.AppendUnconfirmed(t, nil))
			assert.equal(0, #t.lines)
		end)

		it("survive a tooltip without AddLine", function()
			assert.is_false(IL.AppendUnconfirmed({}, true))
			assert.is_false(IL.AppendUnconfirmed(nil, true))
		end)
	end)
end)
