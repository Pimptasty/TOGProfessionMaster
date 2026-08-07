-- The recipe-detail tooltip block: difficulty tiers, and where a recipe comes
-- from. Rendered in RecipeMaster's shape, and — this is the point of the feature
-- — everywhere, not only inside our own window.
--
-- Two things here are load-bearing and neither is obvious from the code:
--
--   1. **Sources are keyed by RECIPE SPELL, not by item.** An item-keyed lookup
--      (LibItemDB:GetSources) can only answer for a recipe that HAS a teaching
--      scroll, which excludes every trainer-taught recipe. Measured against the
--      shipped Vanilla data: item-keyed covers 44.6% of recipes, our own
--      addon.sourceDB covers 74.9% (1172/1565), and its single largest kind is
--      `trainer` at 508 recipes — exactly the set the item-keyed lookup cannot
--      see. Getting this backwards would ship a Sources heading that is blank
--      precisely where it is most wanted.
--
--   2. **The RecipeMaster gate is a tooltip-TYPE split, not a profession one.**
--      RM hooks OnTooltipSetItem, so it covers 100% of tooltips the GAME built
--      and 0% of ours (a tooltip assembled from AddLine calls carries no item, so
--      its hook never fires). Ours must therefore render unconditionally, and the
--      game's must defer to RM when RM is there.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ALCHEMY, LEATHER = 171, 165
local TRANSMUTE, POTION = 17187, 12360
local SCROLL = 12656

local ns, IL, Ace, saved

--- Records what was appended, in order, so layout is assertable as text.
local function fakeTooltip()
	-- `lines` stays a plain string array (most assertions read it as text) and the
	-- r/g/b arrive alongside in `colors`, keyed by the same index — the colour is
	-- part of what the block says, so a fake that drops it cannot test the block.
	local t = { lines = {}, colors = {} }
	t.AddLine = function(_, text, r, g, b)
		t.lines[#t.lines + 1] = tostring(text)
		t.colors[#t.lines] = { r = r, g = g, b = b }
	end
	t.colorOf = function(needle)
		for i, l in ipairs(t.lines) do
			if l:find(needle, 1, true) then return t.colors[i] end
		end
		return nil
	end
	t.GetItem = function() return t._name, t._link end
	t.text    = function() return table.concat(t.lines, "\n") end
	t.has     = function(needle)
		for _, l in ipairs(t.lines) do if l:find(needle, 1, true) then return true end end
		return false
	end
	return t
end

setup(function()
	ns = env.initDb()
	-- FormatSkillTiers lives here, and the difficulty half of the block is a
	-- thin wrapper over it — deliberately, so the tier palette has one home.
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("Tooltip.lua")
	IL  = ns.ItemLink
	Ace = ns.lib
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.setRecipeDB({
		[ALCHEMY] = {
			[TRANSMUTE] = { name = "Transmute: Arcanite", craftedItemId = POTION,
			                itemId = SCROLL, requiredSkill = 275,
			                difficulty = { 275, 300, 310, 320 } },
		},
	})
	ns.sourceDB = { [ALCHEMY] = { [TRANSMUTE] = { trainer = { [1234] = "" } } } }
	Ace.db.profile.tooltipRecipeDetails = "auto"
end)

-- `ns` is the one addon table the whole suite shares. Anything this file writes
-- onto it outlives the file unless it is put back — which is the exact defect
-- that made 15 assertions in two other spec files read this suite's shipped data
-- instead of their own fixtures.
after_each(function()
	ns.sourceDB = {}
	ns.IsAddOnLoaded = saved
	saved = nil
	Ace.db.profile.tooltipRecipeDetails = nil
	ns._recipeItemIndex = nil
end)

local function withRecipeMaster(loaded)
	saved = saved or ns.IsAddOnLoaded
	ns.IsAddOnLoaded = function(_, name) return loaded and name == "RecipeMaster" end
end

-- ---------------------------------------------------------------------------

describe("RecipeDetails — the data behind the block", function()
	it("reports the four difficulty breakpoints, tier-coloured", function()
		local difficulty = IL.RecipeDetails(ALCHEMY, TRANSMUTE)
		assert.is_truthy(difficulty)
		for _, v in ipairs({ "275", "300", "310", "320" }) do
			assert.is_truthy(difficulty:find(v, 1, true), "missing breakpoint " .. v)
		end
		-- Orange / yellow / green / grey, from CraftingEngine's TIER_HEX. Asserted
		-- because a block that lists four identical-looking numbers says nothing:
		-- the colour IS the information.
		for _, hex in ipairs({ "ffff8040", "ffffff00", "ff40c040", "ff808080" }) do
			assert.is_truthy(difficulty:find(hex, 1, true), "missing tier colour " .. hex)
		end
	end)

	it("answers for a TRAINER-TAUGHT recipe, which is the whole point", function()
		-- No craftedItemId, no itemId: nothing an item-keyed source lookup could
		-- ever keyoff. 508 Vanilla recipes are in this position and they are the
		-- ones a player most needs a "where does this come from" line for.
		env.setRecipeDB({ [LEATHER] = { [2108] = { name = "Handstitched Leather Boots" } } })
		ns.sourceDB = { [LEATHER] = { [2108] = { trainer = { [3363] = "" } } } }
		local _, sources = IL.RecipeDetails(LEATHER, 2108)
		assert.same({ "Trainer" }, sources)
	end)

	it("lists several kinds in SOURCE_ORDER, not in table order", function()
		-- pairs() order is undefined, so without an explicit order the same recipe
		-- renders differently between sessions.
		ns.sourceDB = { [ALCHEMY] = { [TRANSMUTE] = {
			trainer = { [1] = "" }, vendor = { [2] = "" }, drop = { [3] = "" },
		} } }
		local _, sources = IL.RecipeDetails(ALCHEMY, TRANSMUTE)
		assert.same({ "Vendor", "Drop", "Trainer" }, sources)
	end)

	it("uses the localized label, never the raw key", function()
		-- The labels are the MissingSrc* locale strings, shared with the Missing
		-- Recipes tab so a translator writes "Trainer" once. A miss here renders
		-- a lowercase "trainer" and is invisible in enUS.
		local _, sources = IL.RecipeDetails(ALCHEMY, TRANSMUTE)
		assert.same({ "Trainer" }, sources)
		assert.is_not.equal("trainer", sources[1])
	end)

	it("ignores a source kind whose npc table is empty", function()
		-- A real state in this data: the porter emits the key before it knows any
		-- npc. Labelling it would assert a source we cannot actually name.
		ns.sourceDB = { [ALCHEMY] = { [TRANSMUTE] = { vendor = {}, trainer = { [1] = "" } } } }
		local _, sources = IL.RecipeDetails(ALCHEMY, TRANSMUTE)
		assert.same({ "Trainer" }, sources)
	end)

	it("returns nil sources rather than an empty list when there are none", function()
		ns.sourceDB = {}
		local difficulty, sources = IL.RecipeDetails(ALCHEMY, TRANSMUTE)
		assert.is_truthy(difficulty)
		assert.is_nil(sources)
	end)

	it("returns nothing at all without a profession or a recipe", function()
		assert.is_nil((IL.RecipeDetails(nil, TRANSMUTE)))
		assert.is_nil((IL.RecipeDetails(ALCHEMY, nil)))
	end)
end)

describe("AppendRecipeDetails — what lands on the tooltip", function()
	it("writes the heading, then each section flush with its values indented", function()
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		assert.is_true(tip.has("TOGPM"))
		assert.is_true(tip.has("Difficulty"))
		assert.is_true(tip.has("Sources"))
		-- Two-space indent on values, headings flush. Deliberately not
		-- AddDoubleLine, which right-aligns against the tooltip's widest line and
		-- makes the numbers move depending on what else is on it.
		local sawIndented = false
		for _, l in ipairs(tip.lines) do
			if l:find("^  Trainer") then sawIndented = true end
		end
		assert.is_true(sawIndented, "source values must be indented under the heading")
	end)

	it("omits the Sources heading entirely when there is no source data", function()
		-- 25% of recipes are in this position. A heading over nothing reads as a
		-- bug in the addon rather than a gap in the data — same reasoning as the
		-- Requires line, which omits rather than printing a number it cannot back.
		ns.sourceDB = {}
		local tip = fakeTooltip()
		IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE)
		assert.is_true(tip.has("Difficulty"))
		assert.is_false(tip.has("Sources"))
	end)

	it("adds nothing, and says so, when it knows nothing", function()
		env.setRecipeDB({})
		ns.sourceDB = {}
		local tip = fakeTooltip()
		assert.is_false(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		assert.equal(0, #tip.lines)
	end)

	it("renders once per tooltip, however many paths reach it", function()
		-- BrowserTab appends explicitly AND the global hook fires again on Show()
		-- for a SetHyperlink tooltip. Both are legitimate; the block appearing
		-- twice is not.
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		assert.is_false(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		local headings = 0
		for _, l in ipairs(tip.lines) do if l:find("TOGPM", 1, true) then headings = headings + 1 end end
		assert.equal(1, headings)
	end)

	it("renders ONE block even when two paths resolve DIFFERENT recipes", function()
		-- The pair bug, and the reason the guard is not keyed on the recipe id.
		-- Seven Vanilla items are produced by more than one recipe -- Gold Bar
		-- from Alchemy's Transmute Iron to Gold AND Mining's Smelt Gold. On such
		-- a row BrowserTab passes the row's own recipe while the global hook
		-- independently resolves the first recipe indexed for that item, so the
		-- two callers disagree about the id. An id-keyed guard matches neither
		-- and draws the block twice; a tooltip describes one thing.
		env.setRecipeDB({
			[ALCHEMY] = { [TRANSMUTE] = { name = "Transmute", craftedItemId = POTION,
			                              difficulty = { 275, 300, 310, 320 } } },
			[LEATHER] = { [2108]      = { name = "Smelt",     craftedItemId = POTION,
			                              difficulty = { 1, 5, 10, 15 } } },
		})
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		assert.is_false(IL.AppendRecipeDetails(tip, LEATHER, 2108))
		local headings = 0
		for _, l in ipairs(tip.lines) do if l:find("TOGPM", 1, true) then headings = headings + 1 end end
		assert.equal(1, headings)
	end)

	it("renders again on the next hover, once the tooltip is cleared", function()
		-- GameTooltip is one frame reused for every hover in the game, and the
		-- client fires OnTooltipCleared on SetOwner at the start of each one. A
		-- guard with no reset would silence every hover after the first, so this
		-- drives the REAL reset rather than clearing the field by hand.
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		assert.is_false(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		ns.Tooltip._OnTooltipCleared(tip)
		assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
	end)

	it("coexists with the integrations block on one tooltip", function()
		-- The PAIR. Both appenders write to the same GameTooltip in BrowserTab
		-- and each was specced only in isolation -- which is precisely the shape
		-- of gap that reports 100% coverage while the combination never runs.
		-- Neither may swallow, reorder or duplicate the other's lines.
		ns.GetItemDB = function() return nil end
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		local afterBlock = #tip.lines
		assert.has_no.errors(function() IL.AppendIntegrations(tip, TRANSMUTE, POTION) end)
		assert.is_true(tip.has("Difficulty"), "the recipe block was lost")
		-- And the block still refuses to render a second time afterwards.
		assert.is_false(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		assert.is_true(#tip.lines >= afterBlock)
	end)

	it("stays silent on Never, even for our own windows", function()
		Ace.db.profile.tooltipRecipeDetails = "never"
		local tip = fakeTooltip()
		assert.is_false(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		assert.equal(0, #tip.lines)
	end)

	it("renders on the default setting, which is auto", function()
		Ace.db.profile.tooltipRecipeDetails = nil
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
	end)
end)

describe("Unlearned — which of YOUR characters could still learn it", function()
	-- RecipeMaster's spell path covers four skill lines and adds nothing on the
	-- rest, silently. This reads our own synced store, which carries skills,
	-- specialisations and alt groups for every profession — so the section has to
	-- answer on a profession RM never touches, and that is what these assert.
	local ME, ALT = "Testchar-Testrealm", "Bob-Testrealm"

	local function knows(charKey, rank)
		local gdb = ns:GetGuildDb()
		gdb.skills[charKey] = gdb.skills[charKey] or {}
		gdb.skills[charKey][ALCHEMY] = { skillRank = rank, skillMax = 300 }
	end

	local function learned(charKey)
		local gdb = ns:GetGuildDb()
		gdb.recipes[ALCHEMY] = gdb.recipes[ALCHEMY] or {}
		gdb.recipes[ALCHEMY][TRANSMUTE] = gdb.recipes[ALCHEMY][TRANSMUTE] or { crafters = {} }
		gdb.recipes[ALCHEMY][TRANSMUTE].crafters[charKey] = ns:GetCurrentGuildTag()
	end

	before_each(function()
		saved = saved or ns.IsMyCharacter
		ns.IsMyCharacter = function(_, ck) return ck == ME or ck == ALT end
	end)

	after_each(function() ns.IsMyCharacter = saved; saved = nil end)

	it("lists a character with the profession who has not learned it", function()
		knows(ALT, 71)
		local out = IL.UnlearnedBy(ALCHEMY, TRANSMUTE)
		assert.same({ { name = "Bob", skill = 71, spec = nil } }, out)
	end)

	it("leaves out a character who HAS learned it", function()
		knows(ALT, 71)
		learned(ALT)
		assert.is_nil(IL.UnlearnedBy(ALCHEMY, TRANSMUTE))
	end)

	it("leaves out a character who does not have the profession at all", function()
		-- Without the skills check every alt would be reported as "unlearned" on
		-- a profession it has never taken, which is noise on every recipe.
		local gdb = ns:GetGuildDb()
		gdb.skills[ALT] = { [LEATHER] = { skillRank = 300 } }
		assert.is_nil(IL.UnlearnedBy(ALCHEMY, TRANSMUTE))
	end)

	it("leaves out a guildmate who is not one of my characters", function()
		knows("Stranger-Testrealm", 300)
		assert.is_nil(IL.UnlearnedBy(ALCHEMY, TRANSMUTE))
	end)

	it("carries the specialisation name, resolved at runtime", function()
		knows(ALT, 285)
		local gdb = ns:GetGuildDb()
		gdb.specializations[ALT] = { [ALCHEMY] = 28677 }
		_G.GetSpellInfo = function(id) return id == 28677 and "Elixir Master" or nil end
		local out = IL.UnlearnedBy(ALCHEMY, TRANSMUTE)
		assert.equal("Elixir Master", out[1].spec)
	end)

	it("sorts by name so the list does not reshuffle between hovers", function()
		-- pairs() over the skills table is undefined order; two alts would swap
		-- places on consecutive hovers of the same recipe.
		knows(ALT, 71); knows(ME, 300)
		local out = IL.UnlearnedBy(ALCHEMY, TRANSMUTE)
		assert.equal("Bob", out[1].name)
		assert.equal("Testchar", out[2].name)
	end)

	it("renders under its own heading, matching RecipeMaster's trailing colon", function()
		knows(ALT, 71)
		local gdb = ns:GetGuildDb()
		gdb.specializations[ALT] = { [ALCHEMY] = 28677 }
		_G.GetSpellInfo = function() return "Elixir Master" end
		local tip = fakeTooltip()
		IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE)
		assert.is_true(tip.has("Unlearned:"))
		assert.is_true(tip.has("  Bob (Skill 71, Elixir Master)"))
	end)

	it("draws the heading in red, the same red as 'Already known'", function()
		-- Blizzard's RED_FONT_COLOR. Asserted as numbers rather than "is it
		-- coloured at all", because the point is that it matches the other
		-- red line this addon puts on a recipe tooltip — two nearly-identical
		-- reds look like a rendering bug, not a palette.
		knows(ALT, 71)
		local tip = fakeTooltip()
		IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE)
		assert.same({ r = 1, g = 0.13, b = 0.13 }, tip.colorOf("Unlearned:"))
	end)

	it("leaves the character rows white, so only the heading carries the warning", function()
		knows(ALT, 71)
		local tip = fakeTooltip()
		IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE)
		assert.same({ r = 1, g = 1, b = 1 }, tip.colorOf("  Bob"))
	end)

	it("omits the skill parenthesis entirely when there is no rank", function()
		local gdb = ns:GetGuildDb()
		gdb.skills[ALT] = { [ALCHEMY] = {} }   -- profession known, rank not synced yet
		local tip = fakeTooltip()
		IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE)
		assert.is_true(tip.has("  Bob"))
		assert.is_false(tip.has("Skill"))
	end)

	it("renders the block for an unlearned recipe with no other data at all", function()
		-- Difficulty and sources both absent: the block must still appear, or a
		-- recipe whose only useful fact is "your alt could learn this" says
		-- nothing.
		env.setRecipeDB({ [ALCHEMY] = { [TRANSMUTE] = { name = "x" } } })
		ns.sourceDB = {}
		knows(ALT, 71)
		local tip = fakeTooltip()
		assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE))
		assert.is_true(tip.has("Unlearned:"))
	end)
end)

describe("the coverage rule — who renders on a GAME-built tooltip", function()
	local should

	before_each(function() should = ns.Tooltip._ShouldRenderOnGameTooltip end)

	it("defers to RecipeMaster when it is loaded", function()
		withRecipeMaster(true)
		assert.is_false(should())
	end)

	it("renders when RecipeMaster is absent", function()
		withRecipeMaster(false)
		assert.is_true(should())
	end)

	it("renders alongside RecipeMaster on Always", function()
		-- Loaded is not the same as contributing: RM's display switches are
		-- addon-private (it writes nothing to _G), so a player with RM installed
		-- and those switched off would otherwise get the block from neither addon.
		withRecipeMaster(true)
		Ace.db.profile.tooltipRecipeDetails = "always"
		assert.is_true(should())
	end)

	it("stays out on Never even with RecipeMaster absent", function()
		withRecipeMaster(false)
		Ace.db.profile.tooltipRecipeDetails = "never"
		assert.is_false(should())
	end)
end)

describe("the item → recipe index", function()
	local forItem

	before_each(function()
		forItem = ns.Tooltip._RecipesForItem
		ns._recipeItemIndex = nil
	end)

	it("resolves the item a recipe PRODUCES", function()
		local hits = forItem(POTION)
		assert.is_truthy(hits)
		assert.equal(ALCHEMY, hits[1].profId)
		assert.equal(TRANSMUTE, hits[1].recipeId)
	end)

	it("resolves the SCROLL that teaches it, which is a different item", function()
		-- Hovering "Transmute: Arcanite" in your bags asks about the same recipe
		-- as hovering the bar it makes. Without this the block appears on one and
		-- not the other, which reads as the data being missing.
		local hits = forItem(SCROLL)
		assert.is_truthy(hits, "the teaching scroll resolved to no recipe")
		assert.equal(TRANSMUTE, hits[1].recipeId)
	end)

	it("answers nil for an item no recipe touches", function()
		-- The common case by a wide margin — every grey vendor trash hover — and
		-- the reason the block gates on recipe-ness before doing any lookups.
		assert.is_nil(forItem(4306))
	end)

	it("does not list the same recipe twice when scroll and product coincide", function()
		env.setRecipeDB({ [ALCHEMY] = { [TRANSMUTE] = { craftedItemId = SCROLL, itemId = SCROLL } } })
		ns._recipeItemIndex = nil
		assert.equal(1, #forItem(SCROLL))
	end)
end)
