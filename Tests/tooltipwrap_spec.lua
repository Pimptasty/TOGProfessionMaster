-- Our tooltip block must never be the thing that makes a tooltip wide.
--
-- `AddLine`'s fifth argument is `wrapText`, and OMITTING IT MEANS FALSE. A
-- non-wrapping line cannot break, so the frame grows to fit it — that is the
-- mechanism by which an addon's tooltip ends up wider than the game's. Every
-- line in `AppendRecipeDetails` omitted it until v1.0.7.
--
-- HOW BIG IS THIS, HONESTLY: small, and the file says so rather than overselling
-- itself. Most of the block cannot widen anything — difficulty is four numbers,
-- the vendor price is a coin string, and a source label is one localized WORD
-- ("Vendor", "Trainer"), because `RecipeDetails` renders the source KIND and
-- never the NPC names the shipped data carries. The single line that can run
-- long is an unlearned character: name, realm, skill and specialisation, one per
-- alt. That line is why the flag matters; the rest go through the same helper so
-- there is one rule rather than a judgement call per line.
--
-- It went unnoticed because **`recipedetails_spec`'s fake tooltip cannot see the
-- bug.** Its `AddLine` is `function(_, text, r, g, b)` — four arguments, the
-- fifth silently dropped. Forty-odd assertions run through that fake and not one
-- could ever have caught a missing wrap flag, because the fake does not record
-- the field the bug lives in. That is the reason this is a separate file driving
-- the real tooltip, rather than a few more cases over there.
--
-- So this file drives the REAL harness `GameTooltip`, which stores `wrap`
-- alongside the text (`env/frames.lua`'s GameTooltip type). Testing against our
-- own fake here would be testing our fake.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ALCHEMY = 171
local TRANSMUTE, POTION = 17187, 12360
local SCROLL = 12656

local ns, IL, Ace, realGetItemDB

setup(function()
	ns = env.initDb()
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("Tooltip.lua")
	IL  = ns.ItemLink
	Ace = ns.lib
	realGetItemDB = ns.GetItemDB
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
	Ace.db.profile.tooltipRecipeDetails = "always"
end)

after_each(function()
	ns.sourceDB = {}
	Ace.db.profile.tooltipRecipeDetails = nil
	ns._recipeItemIndex = nil
	ns.GetItemDB = realGetItemDB
	ns._itemDB   = nil
end)

--- Every line currently on the real GameTooltip, as { text, wrap } pairs.
local function linesOf(tip)
	local out = {}
	for i = 1, tip:NumLines() do
		local line = tip:GetLine(i)
		out[#out + 1] = { text = tostring(line and line.left), wrap = line and line.wrap }
	end
	return out
end

local function renderBlock()
	local tip = _G.GameTooltip
	tip:ClearLines()
	tip._togpmRecipeBlock = nil
	assert.is_true(IL.AppendRecipeDetails(tip, ALCHEMY, TRANSMUTE),
		"the block did not render, so this file would assert nothing")
	return tip
end

describe("every line the recipe block adds wraps", function()
	it("renders something to check in the first place", function()
		-- Guards the guard. A block that rendered nothing would make every
		-- assertion below vacuously true.
		local tip = renderBlock()
		assert.is_true(#linesOf(tip) >= 4)
	end)

	it("sets wrapText on all of them, with no exceptions", function()
		local tip = renderBlock()
		local unwrapped = {}
		for _, line in ipairs(linesOf(tip)) do
			if line.wrap ~= true then
				unwrapped[#unwrapped + 1] = line.text
			end
		end
		table.sort(unwrapped)
		assert.equal("", table.concat(unwrapped, " | "),
			"these lines cannot wrap, so each one can widen the whole tooltip")
	end)

	-- A source label is a KIND WORD, not an NPC name. Pinned deliberately: the
	-- first draft of this file asserted the opposite, on the assumption that
	-- v1.0.7's NPC-name data reached the tooltip. It does not, and a spec that
	-- had encoded that guess would have taught the next reader something false.
	it("renders the source as a bare kind word, so it cannot be the wide line", function()
		ns.sourceDB = {
			[ALCHEMY] = { [TRANSMUTE] = { vendor = { [1234] = "Buzzek Bracketswing" } } },
		}
		local tip = renderBlock()
		local sourceLine
		for _, line in ipairs(linesOf(tip)) do
			if line.text:match("^%s+%a") and not line.text:find("%d") then
				sourceLine = sourceLine or line
			end
		end
		assert.is_not_nil(sourceLine, "no source line rendered")
		assert.is_nil(sourceLine.text:find("Buzzek", 1, true),
			"the NPC name reached the tooltip; this spec's premise needs revisiting")
		assert.is_true(sourceLine.wrap)
	end)
end)

describe("the tooltip defaults ship the feature ON", function()
	-- These had ZERO coverage before v1.0.7: both were changed from off to on
	-- and the whole 1342-case suite stayed green, which is not a pass — it is a
	-- gap. A default is the only behaviour every player gets without touching a
	-- setting, so it is the single most load-bearing value in the file.
	local DEFAULTS

	setup(function()
		DEFAULTS = ns.SETTINGS_DEFAULTS or (ns.lib and ns.lib.db
		           and ns.lib.db.defaults and ns.lib.db.defaults.profile)
	end)

	it("exposes the defaults table to assert against", function()
		assert.is_table(DEFAULTS)
	end)

	it("shows the crafters line without the player opting in", function()
		-- The addon's most useful surface: hover a crafted item, see who in the
		-- guild can make it. Shipping it off meant nobody had it.
		assert.is_true(DEFAULTS.tooltipShowCrafters)
	end)

	it("renders the recipe block on game tooltips even with RecipeMaster loaded", function()
		-- "auto" stood down whenever RM was installed. Our block is not a
		-- duplicate of RM's — only we carry which of YOUR characters could still
		-- learn it — so standing down withheld rows nothing else provides.
		assert.equal("always", DEFAULTS.tooltipRecipeDetails)
	end)

	it("leaves the diagnostic IDs footer off", function()
		-- Deliberately still off: itemId/spellId is for bug reports, not for
		-- every tooltip in the game.
		assert.is_false(DEFAULTS.tooltipShowIds)
	end)
end)
