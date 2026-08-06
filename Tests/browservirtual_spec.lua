-- BrowserTab's virtual scroll — 35 pooled frames standing in for a list of
-- thousands.
--
-- The whole trick is that pool row `i` shows recipe `firstIdx + i` and is
-- positioned at its ABSOLUTE place in the content, so scrolling moves the
-- content while the frames are re-pointed underneath. Get the index maths or
-- the placement wrong and the list shows the wrong recipes, or the right ones
-- in the wrong order — both of which look like a data bug rather than a scroll
-- bug, which is why this is worth pinning.
--
-- Runs against the REAL pool (BuildPool) and a real AceGUI ScrollFrame, so the
-- frames under test are the ones that ship.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, GUI, BT

local ROW  = 14    -- ROW_HEIGHT in GUI/BrowserTab.lua
local POOL = 35    -- POOL_SIZE

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/BrowserTab.lua")
	BT = ns.BrowserTab
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	GUI = env.aceGUI()
end)

local function recipes(n)
	local out = {}
	for i = 1, n do
		out[i] = { id = 1000 + i, name = "Recipe " .. i, icon = 1, crafters = {} }
	end
	return out
end

--- A tab instance with the real pool built into a real scroll frame. Its own
--- table rather than the shared BrowserTab, so pool frames and selection state
--- cannot leak into the specs that exercise the real tab.
local function tabWith(rows, offset)
	local tab = setmetatable({}, { __index = BT })
	local scroll = GUI:Create("ScrollFrame")
	scroll.content:SetHeight(#rows * ROW)
	local status = scroll.status or scroll.localstatus
	status.offset = offset or 0

	tab:BuildPool(scroll.content)
	tab._scroll  = scroll
	tab._recipes = rows
	return tab, scroll
end

local function shownEntries(tab)
	local out = {}
	for i = 1, POOL do
		local f = tab._pool[i]
		if f and f:IsShown() then out[#out + 1] = f._entry and f._entry.name end
	end
	return out
end

describe("UpdateVirtualRows — which recipes land in the pool", function()
	it("starts at the first recipe when unscrolled", function()
		local tab = tabWith(recipes(100), 0)
		tab:UpdateVirtualRows()
		assert.equal("Recipe 1", tab._pool[1]._entry.name)
		assert.equal("Recipe 2", tab._pool[2]._entry.name)
	end)

	it("advances by whole rows as the offset grows", function()
		-- Two rows of scroll means pool row 1 holds the third recipe.
		local tab = tabWith(recipes(100), 2 * ROW)
		tab:UpdateVirtualRows()
		assert.equal("Recipe 3", tab._pool[1]._entry.name)
		assert.equal("Recipe 4", tab._pool[2]._entry.name)
	end)

	it("ignores a partial row of scroll rather than skipping one", function()
		-- Half a row down is still showing the same first recipe; flooring is
		-- what keeps the list from jumping an entry mid-drag.
		local tab = tabWith(recipes(100), ROW - 1)
		tab:UpdateVirtualRows()
		assert.equal("Recipe 1", tab._pool[1]._entry.name)
	end)

	it("fills every pooled frame when there are plenty of recipes", function()
		local tab = tabWith(recipes(100), 0)
		tab:UpdateVirtualRows()
		assert.equal(POOL, #shownEntries(tab))
	end)
end)

describe("UpdateVirtualRows — running out of recipes", function()
	it("shows only as many rows as there are recipes", function()
		local tab = tabWith(recipes(3), 0)
		tab:UpdateVirtualRows()
		assert.same({ "Recipe 1", "Recipe 2", "Recipe 3" }, shownEntries(tab))
	end)

	it("hides the pooled frames past the end of the list", function()
		-- Leftovers from a previous, longer list would otherwise keep showing
		-- recipes that are no longer in the filtered set.
		local tab = tabWith(recipes(3), 0)
		tab:UpdateVirtualRows()
		assert.is_false(tab._pool[4]:IsShown())
		assert.is_false(tab._pool[POOL]:IsShown())
	end)

	it("shows nothing at all for an empty list", function()
		local tab = tabWith(recipes(0), 0)
		tab:UpdateVirtualRows()
		assert.same({}, shownEntries(tab))
	end)

	it("shows the tail when scrolled to the end of a short list", function()
		local tab = tabWith(recipes(40), 38 * ROW)
		tab:UpdateVirtualRows()
		assert.equal("Recipe 39", tab._pool[1]._entry.name)
		assert.equal("Recipe 40", tab._pool[2]._entry.name)
		assert.is_false(tab._pool[3]:IsShown())
	end)
end)

describe("UpdateVirtualRows — where the rows are placed", function()
	it("anchors each row at its absolute place in the content", function()
		-- The frames do not move with the scroll; the content does. So row i
		-- must sit at the recipe's own offset, not at the pool slot's.
		local tab = tabWith(recipes(100), 0)
		tab:UpdateVirtualRows()
		local _, _, _, _, y1 = tab._pool[1]:GetPoint(1)
		local _, _, _, _, y3 = tab._pool[3]:GetPoint(1)
		assert.equal(0, y1)
		assert.equal(-(2 * ROW), y3)
	end)

	it("keeps that absolute placement after scrolling", function()
		local tab = tabWith(recipes(100), 10 * ROW)
		tab:UpdateVirtualRows()
		-- Pool row 1 now holds recipe 11, so it belongs at recipe 11's offset.
		local _, _, _, _, y = tab._pool[1]:GetPoint(1)
		assert.equal(-(10 * ROW), y)
	end)
end)

describe("UpdateVirtualRows — selection highlight", function()
	it("highlights only the selected recipe", function()
		local rows = recipes(10)
		local tab  = tabWith(rows, 0)
		tab._selectedEntry = rows[4]
		tab:UpdateVirtualRows()

		local highlighted = {}
		for i = 1, 10 do
			if tab._pool[i]._highlightLocked then highlighted[#highlighted + 1] = i end
		end
		assert.same({ 4 }, highlighted)
	end)
end)
