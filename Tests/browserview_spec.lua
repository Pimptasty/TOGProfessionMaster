-- The Professions tab's View dropdown: guild / mine / (+ missing).
--
-- WHY THIS FILE EXISTS. The dropdown was built from a hardcoded order array
-- `{ "guild", "mine", "missing" }` while the item table only gained `missing`
-- when the "Show All Recipes" checkbox was on. AceGUI walks the ORDER array and
-- calls `AddListItem(key, list[key])` with no existence check at all
-- (Ace3/AceGUI-3.0/widgets/AceGUIWidget-DropDown.lua:609-611), and the item's
-- `SetText` does `self.text:SetText(text or "")`
-- (AceGUIWidget-DropDown-Items.lua:101) — so a key with no entry does not
-- error. It renders a BLANK, CLICKABLE row, and clicking it set `_viewMode` to
-- a mode the list was no longer offering.
--
-- That is the shape of bug a smoke test cannot catch: the tab drew fine, the
-- widget count was right, nothing threw. Only the CONTENT of the pullout shows
-- it, which is what this file asserts.
--
-- The general rule it pins, and the reason it is worth a file rather than a
-- line: any AceGUI `SetList(list, order)` must build both halves together. A
-- second dropdown that derives its order from a constant will regrow this bug.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, B
local ALCHEMY = 171
local POTION  = 2330

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	B = env.loadModule("GUI/BrowserTab.lua").BrowserTab
	-- Loaded for the shared-scope block at the bottom, which compares the two
	-- tabs' defaults against `UI.SCOPE_DEFAULT`. Nothing here draws it.
	env.loadModule("GUI/CooldownsTab.lua")
end)

before_each(function()
	env.installFrames()
	local gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	env.spellsExist(POTION)
	env.setRecipeDB({
		[ALCHEMY] = { [POTION] = { name = "Healing Potion", icon = 1, reagents = {},
		                           craftedItemId = 929, requiredSkill = 60 } },
	})
	gdb.recipes[ALCHEMY] = {
		[POTION] = { name = "Healing Potion", icon = 1,
		             crafters = { ["Testchar-Testrealm"] = ns:GetCurrentGuildTag() } },
	}
	ns.Print = function() end
	-- Both are class-level fields on the tab, so a value set by one case would
	-- otherwise carry into the next — and the two cases below differ ONLY in
	-- these, which would make each of them assert the other's state.
	B._showAllRecipes = false
	B._viewMode = "guild"
end)

after_each(function()
	B._showAllRecipes = false
	B._viewMode = "guild"
end)

--- The View dropdown, found by its CONTENT rather than by position. The toolbar
--- holds more than one Dropdown (profession filter, sort) and their order in the
--- row is a layout decision that may change; "the one offering a `guild` view"
--- is what actually identifies this widget.
local function viewDropdown(container)
	local found
	local function walk(w)
		for _, child in ipairs(w.children or {}) do
			if child.type == "Dropdown" and type(child.list) == "table"
			   and child.list.guild ~= nil then
				found = found or child
			end
			walk(child)
		end
	end
	walk(container)
	return found
end

--- The text of every row the pullout actually built, in order. This reads the
--- constructed ITEM WIDGETS, not the list table handed to SetList — the whole
--- defect was that those two disagreed, so asserting on the input would have
--- reproduced the bug rather than caught it.
local function rowTexts(dd)
	local out = {}
	for _, item in ipairs(dd.pullout and dd.pullout.items or {}) do
		out[#out + 1] = item.text and item.text:GetText() or ""
	end
	return out
end

describe("the View dropdown offers exactly the modes it can honour", function()
	it("has no blank row when Show All Recipes is off", function()
		-- The regression itself. Before the fix this produced THREE rows, the
		-- third with empty text and a live OnValueChanged that set
		-- `_viewMode = "missing"`.
		local container = env.drawTab(B)
		local dd = viewDropdown(container)
		assert.is_truthy(dd, "the View dropdown was not built")

		local rows = rowTexts(dd)
		assert.equal(2, #rows)
		for i, text in ipairs(rows) do
			assert.is_truthy(text and text ~= "",
				("row %d of the View dropdown is blank"):format(i))
		end
	end)

	it("gains the missing row when Show All Recipes is on", function()
		-- The other half, and the reason the fix is "build the order beside the
		-- items" rather than "delete missing from the order": the third mode is
		-- real, it is just conditional.
		B._showAllRecipes = true
		local container = env.drawTab(B)
		local dd = viewDropdown(container)
		assert.is_truthy(dd, "the View dropdown was not built")

		local rows = rowTexts(dd)
		assert.equal(3, #rows)
		for i, text in ipairs(rows) do
			assert.is_truthy(text and text ~= "",
				("row %d of the View dropdown is blank"):format(i))
		end
	end)

	it("never names a key the item list lacks", function()
		-- Stated as the invariant rather than as a count, so it keeps holding if
		-- a fourth mode is added. Every key the pullout was built from must have
		-- a label in `dd.list`; AceGUI will not complain if one does not.
		for _, showAll in ipairs({ false, true }) do
			B._showAllRecipes = showAll
			local dd = viewDropdown(env.drawTab(B))
			assert.is_truthy(dd)
			for _, item in ipairs(dd.pullout and dd.pullout.items or {}) do
				local key = item.userdata and item.userdata.value
				assert.is_truthy(key, "a pullout row carries no value")
				assert.is_truthy(dd.list[key],
					("the order named %q, which the item list has no label for")
						:format(tostring(key)))
			end
		end
	end)

	it("drops a stale missing selection when the checkbox goes off", function()
		-- Reachable in game: pick Show Missing, untick Show All Recipes. The
		-- dropdown can no longer offer that mode, so a value left pointing at it
		-- would render as a blank SELECTION rather than a blank row.
		B._showAllRecipes = false
		B._viewMode = "missing"
		local dd = viewDropdown(env.drawTab(B))
		assert.is_truthy(dd)
		assert.equal("guild", B._viewMode)
		assert.is_truthy(dd.list[B._viewMode])
	end)
end)

describe("the scope filter has one implementation, shared by both tabs", function()
	-- `docs/AUDIT.md` finding 2: the Professions and Cooldowns tabs each carried
	-- their own `_viewMode` field and their own guild/mine dropdown, with
	-- `CooldownsTab`'s comment reading "Mirrors the Browser tab's _viewMode
	-- dropdown" — a maintenance contract with nothing enforcing it. The reviewer
	-- named the way it would break: **one tab gaining a third mode.** That had
	-- already happened by the time the finding was written, and nothing failed.
	--
	-- The remedy is a merge rather than only an assertion, so these cases pin the
	-- merge: one base set, one default, and neither tab writing its own order.

	it("offers the same base modes and the same default in both tabs", function()
		local items, order = ns.UI.ScopeList()
		assert.same({ "guild", "mine" }, order)
		assert.is_truthy(items.guild)
		assert.is_truthy(items.mine)
		assert.equal("guild", ns.UI.SCOPE_DEFAULT)
		-- Both tabs' initial state must BE that default, not merely equal a
		-- literal that happens to match it today.
		assert.equal(ns.UI.SCOPE_DEFAULT, ns.CooldownsTab._viewMode)
		assert.equal(ns.UI.SCOPE_DEFAULT, B._viewMode)
	end)

	it("appends extra modes in order and never keys one without a label", function()
		local items, order = ns.UI.ScopeList({
			{ key = "missing", label = "Show Missing" },
			{ key = "broken" },                       -- no label: must be dropped
		})
		assert.same({ "guild", "mine", "missing" }, order)
		assert.equal("Show Missing", items.missing)
		assert.is_nil(items.broken)
	end)

	--- Source with comments removed, so prose about the scope filter does not
	--- read as a re-inlined copy of it. Same instrument as
	--- `Tests/recipegate_spec.lua`, for the same reason.
	local function code(path)
		local f = assert(io.open(path, "r"), "missing source file: " .. path)
		local body = f:read("*a")
		f:close()
		body = body:gsub("%-%-%[%[.-%]%]", " ")
		body = body:gsub("%-%-[^\n]*", " ")
		return body
	end

	local TABS = { "GUI/BrowserTab.lua", "GUI/CooldownsTab.lua" }

	for _, path in ipairs(TABS) do
		it(path .. " builds its View dropdown from UI.ScopeList", function()
			assert.is_truthy(code(path):find("UI.ScopeList", 1, true),
				path .. " no longer routes through addon.UI.ScopeList — its scope "
				.. "options can now disagree with the other tab's, which is exactly "
				.. "what docs/AUDIT.md finding 2 describes")
		end)

		it(path .. " does not re-inline the base order array", function()
			-- The literal that was duplicated. `{ "guild", "mine" }` appearing in a
			-- tab means a second copy of the base set has started — and a hand-built
			-- order is also how the blank-row bug above was possible.
			local body = code(path):gsub("%s+", "")
			assert.is_nil(body:find('{"guild","mine"}', 1, true),
				path .. " writes its own { \"guild\", \"mine\" } order. That belongs "
				.. "to addon.UI.ScopeList alone.")
		end)
	end
end)
