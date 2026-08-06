-- GUI/AHProfitTab.lua — ApplyFilters, which decides what the Profit Planner
-- shows you.
--
-- Pure over its input rows, and the place where a wrong answer is expensive in
-- both directions: a row wrongly hidden is a craft you never make, a row
-- wrongly shown is one you make at a loss.
--
-- The rule most at risk is the empty profession set. "No professions ticked"
-- must match NOTHING, not everything — the natural `if next(set) then` tidy-up
-- inverts it, and the result looks plausible on screen because a full list is
-- what you see before you touch the filter.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, PT

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/AHProfitTab.lua")
	PT = ns.ProfitTab or ns.AHProfitTab
end)

before_each(function()
	env.installFrames()
	env.resetDb()
end)

--- Run ApplyFilters with an explicit filter, bypassing the persisted state so
--- the assertion is about the filtering rather than about storage.
local function filtered(filter, rows)
	local tab = { _mode = "live", GetFilter = function() return filter end }
	local out = {}
	for _, row in ipairs(PT.ApplyFilters(tab, rows)) do out[#out + 1] = row.recipe end
	return out
end

local ROWS = {
	{ recipe = "Arcanite Bar",   profession = "Alchemy",     profit = 500,  source = "tsm",
	  crafters = "Bob", _crafterSet = { ["Bob-Testrealm"] = true } },
	{ recipe = "Mooncloth",      profession = "Tailoring",   profit = -100, source = "auctionator",
	  crafters = "Ann", _crafterSet = { ["Ann-Testrealm"] = true } },
	{ recipe = "Thorium Widget", profession = "Engineering", profit = 0,    source = "tsm",
	  crafters = "Bob, Ann", _crafterSet = { ["Bob-Testrealm"] = true, ["Ann-Testrealm"] = true } },
}

describe("ApplyFilters — no filter", function()
	it("passes every row through", function()
		assert.same({ "Arcanite Bar", "Mooncloth", "Thorium Widget" }, filtered({}, ROWS))
	end)

	it("returns nothing for no rows", function()
		assert.same({}, filtered({}, nil))
		assert.same({}, filtered({}, {}))
	end)
end)

describe("ApplyFilters — professions", function()
	it("keeps only the ticked professions", function()
		assert.same({ "Arcanite Bar", "Thorium Widget" },
			filtered({ professions = { Alchemy = true, Engineering = true } }, ROWS))
	end)

	it("matches NOTHING when the set is empty", function()
		-- The whole point: an empty set is "you have unticked everything", which
		-- is a real state with a real answer, and that answer is an empty list.
		assert.same({}, filtered({ professions = {} }, ROWS))
	end)

	it("ignores the profession filter entirely when it is absent", function()
		-- nil is different from empty: no filter has been applied at all.
		assert.equal(3, #filtered({ professions = nil }, ROWS))
	end)
end)

describe("ApplyFilters — crafter", function()
	it("treats All as no filter", function()
		assert.equal(3, #filtered({ crafterFilter = "All" }, ROWS))
	end)

	it("keeps only rows that character can craft", function()
		assert.same({ "Mooncloth", "Thorium Widget" },
			filtered({ crafterFilter = "Ann-Testrealm" }, ROWS))
	end)

	it("drops a row that lists no crafters at all", function()
		local rows = { { recipe = "Orphan", profession = "Alchemy", profit = 1 } }
		assert.same({}, filtered({ crafterFilter = "Bob-Testrealm" }, rows))
	end)
end)

describe("ApplyFilters — profitable only", function()
	it("drops losses and break-even rows", function()
		-- Zero profit is not profit; showing it under "+ Profit only" would be
		-- an invitation to craft for nothing.
		assert.same({ "Arcanite Bar" }, filtered({ positiveOnly = true }, ROWS))
	end)

	it("treats a missing profit as zero rather than erroring", function()
		local rows = { { recipe = "Unpriced", profession = "Alchemy" } }
		assert.same({}, filtered({ positiveOnly = true }, rows))
	end)

	it("reads a profit that arrived as a string", function()
		local rows = { { recipe = "Stringy", profession = "Alchemy", profit = "250" } }
		assert.same({ "Stringy" }, filtered({ positiveOnly = true }, rows))
	end)
end)

describe("ApplyFilters — price source", function()
	it("treats All as no filter", function()
		assert.equal(3, #filtered({ sourceFilter = "All" }, ROWS))
	end)

	it("keeps only rows priced by that source", function()
		assert.same({ "Arcanite Bar", "Thorium Widget" },
			filtered({ sourceFilter = "tsm" }, ROWS))
	end)

	it("drops an unpriced row when a specific source is chosen", function()
		-- "No price" is not the same as "priced by TSM", and the row would
		-- otherwise show a blank price under a source filter.
		local rows = { { recipe = "Unpriced", profession = "Alchemy", profit = 1 } }
		assert.same({}, filtered({ sourceFilter = "tsm" }, rows))
	end)
end)

describe("ApplyFilters — search", function()
	it("matches the recipe name", function()
		assert.same({ "Arcanite Bar" }, filtered({ search = "arcanite" }, ROWS))
	end)

	it("matches the profession", function()
		assert.same({ "Mooncloth" }, filtered({ search = "tailoring" }, ROWS))
	end)

	it("matches a crafter name", function()
		assert.same({ "Mooncloth", "Thorium Widget" }, filtered({ search = "ann" }, ROWS))
	end)

	it("is case-insensitive", function()
		assert.same({ "Arcanite Bar" }, filtered({ search = "ARCANITE" }, ROWS))
	end)

	it("an empty search is not a filter", function()
		assert.equal(3, #filtered({ search = "" }, ROWS))
	end)

	it("finds nothing when nothing matches", function()
		assert.same({}, filtered({ search = "zzzz" }, ROWS))
	end)
end)

describe("ApplyFilters — combined", function()
	it("requires every active filter to pass, not any of them", function()
		-- Engineering AND profitable is empty even though each alone is not.
		assert.same({}, filtered({
			professions  = { Engineering = true },
			positiveOnly = true,
		}, ROWS))

		assert.same({ "Arcanite Bar" }, filtered({
			professions  = { Alchemy = true },
			positiveOnly = true,
			sourceFilter = "tsm",
			search       = "bar",
		}, ROWS))
	end)
end)
