-- Do the tabs actually CALL the shared recipe block?
--
-- `recipedetails_spec.lua` proves the block renders correctly. It says nothing
-- about whether anything invokes it -- and the whole of v1.0.7 was wiring, not
-- rendering. This suite has a written warning about exactly that gap, in
-- `tooltiphooks_spec.lua`: "AppendCrafters can be perfect and the addon still
-- show nothing in game if nobody calls it -- a green suite over a dead feature."
--
-- The bug being locked down: six surfaces show recipes and only one of them
-- rendered the block, because the global OnTooltipSetItem hook fires only on
-- GameTooltip and only for a real ITEM. A recipe shown as a spell, by
-- trade-skill index, as plain text, or on a private tooltip frame inherited
-- nothing. Deleting any one of those call sites must fail a test here.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ALCHEMY, TRANSMUTE, POTION = 171, 17187, 12360

local ns, realAppend, calls

setup(function()
	ns = env.initDb()
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("Tooltip.lua")
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.setRecipeDB({
		[ALCHEMY] = { [TRANSMUTE] = { name = "Transmute", craftedItemId = POTION,
		                              difficulty = { 275, 300, 310, 320 } } },
	})
	-- Spy, not stub: record the arguments and still do the real work, so a call
	-- site passing a nil recipe id is visible rather than merely "called".
	calls = {}
	realAppend = ns.ItemLink.AppendRecipeBlocks
	ns.ItemLink.AppendRecipeBlocks = function(tooltip, profId, recipeId, craftedItemId)
		calls[#calls + 1] = { profId = profId, recipeId = recipeId, craftedItemId = craftedItemId }
		return realAppend(tooltip, profId, recipeId, craftedItemId)
	end
end)

after_each(function()
	ns.ItemLink.AppendRecipeBlocks = realAppend
	realAppend = nil
end)

-- ---------------------------------------------------------------------------

describe("the Crafting tab", function()
	-- Reachable for real: ShowItemTooltip is a plain method, so this drives the
	-- production path end to end rather than asserting over source text.
	it("passes the recipe id through to the shared block", function()
		env.loadModule("GUI/CraftingTab.lua")
		local anchor = CreateFrame("Frame")
		ns.CraftingTab:ShowItemTooltip(anchor, 1, nil, TRANSMUTE)
		assert.equal(1, #calls, "ShowItemTooltip did not call the shared block")
		assert.equal(TRANSMUTE, calls[1].recipeId)
	end)

	it("still calls it on the index-based branch, which carries no item", function()
		-- The branch that inherited nothing: SetCraftItem / SetTradeSkillItem
		-- take a trade-skill INDEX, so the tooltip has no item and the global
		-- OnTooltipSetItem hook never fires. Enchants live here.
		env.loadModule("GUI/CraftingTab.lua")
		ns.CraftingTab:ShowItemTooltip(CreateFrame("Frame"), 7, nil, TRANSMUTE)
		assert.equal(TRANSMUTE, calls[1].recipeId)
	end)

	it("does not blow up when the row has no recipe id", function()
		env.loadModule("GUI/CraftingTab.lua")
		assert.has_no.errors(function()
			ns.CraftingTab:ShowItemTooltip(CreateFrame("Frame"), 1, nil, nil)
		end)
	end)
end)

describe("every tab that shows a recipe wires the shared block", function()
	-- A SOURCE assertion, and stated as one rather than dressed up. The other
	-- four call sites are closures created deep inside a draw path (an AceGUI
	-- callback, two pooled-row OnEnter handlers built during a virtual-scroll
	-- update) and reaching them needs more tab fixture than exists today. What
	-- this cannot prove is that the call runs; what it does prove is that
	-- deleting it fails a test, which is the regression actually worth catching
	-- -- the block was absent from these tabs for a whole release.
	--
	-- Upgrade this to driving the real OnEnter when those fixtures exist.
	local WIRED = {
		["GUI/MissingRecipesTab.lua"] = "private tooltip frame — the global hook cannot reach it",
		["GUI/CooldownsTab.lua"]      = "spell: hyperlink — carries no item",
		["GUI/ShoppingListTab.lua"]   = "SetSpellByID — carries no item",
		["GUI/AHProfitTab.lua"]       = "SetText fallback — carries no item",
		["GUI/CraftingTab.lua"]       = "trade-skill index — carries no item",
		["GUI/BrowserTab.lua"]        = "hand-built tooltip — carries no item",
	}

	for path, why in pairs(WIRED) do
		it(path .. " calls the shared block (" .. why .. ")", function()
			local f = assert(io.open(path, "r"), "missing source file: " .. path)
			local body = f:read("*a")
			f:close()
			assert.is_truthy(body:find("AppendRecipeBlocks", 1, true)
			                 or body:find("AppendRecipeDetails", 1, true),
				path .. " no longer renders the recipe block — that tab's recipes "
				.. "would silently show less than the same recipe does elsewhere")
		end)
	end
end)

describe("the resolver the wiring depends on", function()
	it("answers for a recipe id with no profession in hand", function()
		-- Cooldowns, Shopping List and Crafting rows carry a spell id and no
		-- profession. If this stops resolving, every one of those call sites
		-- silently renders nothing while still "being called".
		assert.equal(ALCHEMY, ns.ItemLink.ProfessionForRecipe(TRANSMUTE))
	end)
end)
