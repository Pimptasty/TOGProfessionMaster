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
	-- Highlight IS the selection model for a pooled list: 35 frames stand in for
	-- thousands of recipes, so "which row is selected" is only answerable through
	-- highlight state. Read via the real `IsHighlightLocked` — Classic Era
	-- documents it at SimpleFrameAPIDocumentation:702, so this is the client's own
	-- getter rather than a peek at the harness's private field.
	local function highlightedRows(tab, n)
		local out = {}
		for i = 1, n do
			if tab._pool[i]:IsHighlightLocked() then out[#out + 1] = i end
		end
		return out
	end

	it("highlights only the selected recipe", function()
		local rows = recipes(10)
		local tab  = tabWith(rows, 0)
		tab._selectedEntry = rows[4]
		tab:UpdateVirtualRows()
		assert.same({ 4 }, highlightedRows(tab, 10))
	end)

	it("highlights nothing when no recipe is selected", function()
		local rows = recipes(10)
		local tab  = tabWith(rows, 0)
		tab:UpdateVirtualRows()
		assert.same({}, highlightedRows(tab, 10))
	end)

	it("moves the highlight rather than adding a second one", function()
		-- The pooled-list failure this guards: rows are REUSED, so a frame that
		-- was highlighted for the old selection keeps its lock unless the
		-- else-branch actively clears it. Two lit rows is what that looks like.
		local rows = recipes(10)
		local tab  = tabWith(rows, 0)
		tab._selectedEntry = rows[2]
		tab:UpdateVirtualRows()
		assert.same({ 2 }, highlightedRows(tab, 10))

		tab._selectedEntry = rows[7]
		tab:UpdateVirtualRows()
		assert.same({ 7 }, highlightedRows(tab, 10))
	end)

	it("follows the recipe, not the frame, when the list scrolls", function()
		-- Recipe 4 is in pool row 4 unscrolled; after two rows of scroll the same
		-- recipe lives in pool row 2. The highlight has to move with the recipe.
		local rows = recipes(100)
		local tab  = tabWith(rows, 0)
		tab._selectedEntry = rows[4]
		tab:UpdateVirtualRows()
		assert.same({ 4 }, highlightedRows(tab, 35))

		local status = tab._scroll.status or tab._scroll.localstatus
		status.offset = 2 * ROW
		tab:UpdateVirtualRows()
		assert.same({ 2 }, highlightedRows(tab, 35))
	end)
end)

describe("row hover — which tooltip a recipe gets", function()
	-- The visible half of the teaching-item work. A recipe WITH a real scroll
	-- gets Blizzard's own tooltip for that scroll (so ATT and friends contribute);
	-- one without gets ours, opened with the same scroll-shaped header. Both
	-- paths are exercised here because a third of every list takes the second.
	local ns2, calls, savedIdb, savedPdb

	local WITH_SCROLL, SCROLL_ID, SCROLL_LINK = 3320, 12656, "|Hitem:12656|h[Plans]|h"
	local NO_SCROLL = 2259

	local savedTooltip

	before_each(function()
		ns2 = require("env_togpm").initDb()
		calls = { hyperlink = {}, lines = {}, colours = {} }
		savedIdb     = ns2._itemDB
		savedPdb     = ns2._profDB
		savedTooltip = _G.GameTooltip
		_G.GameTooltip = {
			SetHyperlink = function(_, l) calls.hyperlink[#calls.hyperlink + 1] = l end,
			ClearLines   = function() calls.lines = {} end,
			-- `lines` stays a list of plain strings (most specs read it that
			-- way); colours go alongside so a spec can assert them without
			-- reshaping the fixture every other spec depends on.
			AddLine      = function(_, t, r, g, b)
				calls.lines[#calls.lines + 1] = tostring(t)
				calls.colours[tostring(t)] = { r = r, g = g, b = b }
			end,
			AddDoubleLine = function() end,
			Show         = function() end,
			Hide         = function() end,
			NumLines     = function() return 0 end,
			SetOwner     = function() end,
			IsShown      = function() return true end,
		}
	end)

	-- Restore BOTH. This block swaps the global GameTooltip for a recorder and
	-- caches a stub LibItemDB on the addon; neither is per-test state, so leaving
	-- either behind reaches later spec FILES. It did: gui_draw_spec died on
	-- `attempt to call method 'IsReady'` from inside GetCraftedItemStatText,
	-- three files away from the cause.
	after_each(function()
		ns2._itemDB    = savedIdb
		ns2._profDB    = savedPdb
		_G.GameTooltip = savedTooltip
	end)

	local function entryFor(id, extra)
		local e = { id = id, profId = 165, name = "Barbaric Shoulders", icon = 1,
		            profName = "Leatherworking", crafters = {},
		            reagents = { { name = "Heavy Leather", count = 2 } } }
		for k, v in pairs(extra or {}) do e[k] = v end
		return e
	end

	local function hover(tab, entry)
		tab._recipes = { entry }
		tab:UpdateVirtualRows()
		local f = tab._pool[1]
		f._entry = entry
		f:GetScript("OnEnter")(f)
	end

	it("shows the real scroll's tooltip when the recipe has one", function()
		ns2._profDB = {
			GetRecipeItem = function(_, id) return id == WITH_SCROLL and SCROLL_ID or nil, false end,
		}
		ns2._itemDB = { GetLink = function(_, id) return id == SCROLL_ID and SCROLL_LINK or nil end }
		local tab = tabWith(recipes(1), 0)
		hover(tab, entryFor(WITH_SCROLL))
		assert.same({ SCROLL_LINK }, calls.hyperlink)
	end)

	it("links the SCROLL, not the crafted item", function()
		-- The distinction the feature rests on. Showing entry.itemLink here gives
		-- gear stats where a recipe was asked for.
		ns2._profDB = { GetRecipeItem = function() return SCROLL_ID, false end }
		ns2._itemDB = { GetLink = function() return SCROLL_LINK end }
		local tab = tabWith(recipes(1), 0)
		hover(tab, entryFor(WITH_SCROLL, { itemLink = "|Hitem:15053|h[Shoulders]|h" }))
		assert.same({ SCROLL_LINK }, calls.hyperlink)
	end)

	it("builds our own, scroll-shaped, when the recipe has no teaching item", function()
		ns2._profDB = {
			GetRecipeItem            = function() return nil, false end,
			GetSyntheticRecipeScroll = function()
				-- requiredSkill deliberately WRONG here (1), mirroring what
				-- LibItemDB MINOR 18 actually ships for 8 of 12 skill lines. The
				-- Requires line must come out right anyway, because it reads
				-- ProfessionDB.
				return { prefix = "Plans: ", professionID = 165, requiredSkill = 1 }
			end,
		}
		env.setRecipeDB({ [165] = { [NO_SCROLL] = {
			name = "Barbaric Shoulders", requiredSkill = 200,
		} } })
		local tab = tabWith(recipes(1), 0)
		hover(tab, entryFor(NO_SCROLL))
		assert.equal(0, #calls.hyperlink)
		local joined = table.concat(calls.lines, "\n")
		assert.is_truthy(joined:find("Plans: Barbaric Shoulders", 1, true))
		assert.is_truthy(joined:find("Requires Leatherworking (200)", 1, true))
	end)

	it("falls back to our own tooltip when the scroll link is not cached", function()
		-- GetLink is synchronous but can still miss. Showing an empty tooltip
		-- would be worse than the hand-built one.
		ns2._profDB = {
			GetRecipeItem            = function() return SCROLL_ID, false end,
			GetSyntheticRecipeScroll = function() return nil end,
			GetRecipeScrollPrefix    = function() return "Pattern: " end,
		}
		ns2._itemDB = { GetLink = function() return nil end }
		local tab = tabWith(recipes(1), 0)
		hover(tab, entryFor(WITH_SCROLL))
		assert.equal(0, #calls.hyperlink)
		assert.is_truthy(table.concat(calls.lines, "\n"):find("Pattern: Barbaric Shoulders", 1, true))
	end)

	it("still works with no ItemDB at all", function()
		ns2._itemDB, ns2._profDB = false, false
		local tab = tabWith(recipes(1), 0)
		assert.has_no.errors(function() hover(tab, entryFor(NO_SCROLL)) end)
		assert.is_truthy(table.concat(calls.lines, "\n"):find("Leatherworking: Barbaric Shoulders", 1, true))
	end)

	-- The three lines the game's own scroll tooltip opens with, in its order:
	-- the requirement, "Already known" when it is, then the Use sentence. Ours
	-- shipped without all three, each missing for a different reason, and the
	-- gap is only visible when the two tooltips are compared side by side.
	describe("the header lines the game's scroll carries", function()
		-- Blizzard's localized "Use:" / "Already known". A stock client always
		-- defines both; installing them here models that rather than letting
		-- the code's nil-guard silently turn these specs into no-ops.
		local savedUse, savedKnown
		before_each(function()
			savedUse, savedKnown = _G.ITEM_SPELL_TRIGGER_ONUSE, _G.ITEM_SPELL_KNOWN
			_G.ITEM_SPELL_TRIGGER_ONUSE = "Use:"
			_G.ITEM_SPELL_KNOWN         = "Already known"
		end)
		after_each(function()
			_G.ITEM_SPELL_TRIGGER_ONUSE, _G.ITEM_SPELL_KNOWN = savedUse, savedKnown
		end)

		local function syntheticProfDB()
			ns2._profDB = {
				GetRecipeItem            = function() return nil, false end,
				GetSyntheticRecipeScroll = function()
					return { prefix = "Plans: ", professionID = 165,
					         useText = "Teaches you how to craft a Barbaric Shoulders." }
				end,
			}
			env.setRecipeDB({ [165] = { [NO_SCROLL] = {
				name = "Barbaric Shoulders", requiredSkill = 200,
			} } })
		end

		it("prefixes the teaches sentence with the localized Use:", function()
			-- The stored sentence is only the verb phrase; the game renders
			-- "Use: " in front of it. Taken from ITEM_SPELL_TRIGGER_ONUSE rather
			-- than hard-coded, so it is not an English-only fix.
			syntheticProfDB()
			local tab = tabWith(recipes(1), 0)
			hover(tab, entryFor(NO_SCROLL))
			local joined = table.concat(calls.lines, "\n")
			local usePrefix = _G.ITEM_SPELL_TRIGGER_ONUSE or "Use:"
			assert.is_truthy(joined:find(usePrefix .. " Teaches you how to craft", 1, true))
		end)

		it("says Already known when THIS character knows the recipe", function()
			syntheticProfDB()
			local tab = tabWith(recipes(1), 0)
			hover(tab, entryFor(NO_SCROLL, {
				crafters = { { name = "You", isYou = true, online = true } },
			}))
			local joined = table.concat(calls.lines, "\n")
			assert.is_truthy(joined:find(_G.ITEM_SPELL_KNOWN or "Already known", 1, true))
		end)

		it("does NOT say it when only an ALT knows the recipe", function()
			-- The game makes this claim about the character reading the scroll,
			-- not the account. Alts are tagged "You (Name)" without `isYou`, so
			-- keying on the tag rather than the flag would get this wrong.
			syntheticProfDB()
			local tab = tabWith(recipes(1), 0)
			hover(tab, entryFor(NO_SCROLL, {
				crafters = { { name = "You (Otherguy)", online = true } },
			}))
			local joined = table.concat(calls.lines, "\n")
			assert.is_nil(joined:find(_G.ITEM_SPELL_KNOWN or "Already known", 1, true))
		end)

		it("reds the requirement when this character cannot meet it", function()
			-- The one thing the line exists to say. In white it reads as
			-- satisfied whether or not it is.
			syntheticProfDB()
			local gdb = ns:GetGuildDb()
			gdb.skills = { [ns:GetCharacterKey()] = { [165] = { skillRank = 100 } } }
			local tab = tabWith(recipes(1), 0)
			hover(tab, entryFor(NO_SCROLL))
			local colour = calls.colours["Requires Leatherworking (200)"]
			assert.is_truthy(colour, "the requirement line was never drawn")
			assert.equal(1, colour.r)
			assert.is_true(colour.g < 0.5, "an unmet requirement must be red, not white")
		end)

		-- NOT COVERED, stated rather than quietly skipped: that the crafted
		-- item's own "Requires <Prof> (N)" is dropped when it repeats the line
		-- we put at the top. Two different facts wear identical text there —
		-- ours is the skill to LEARN the recipe, the item's is the skill to USE
		-- what it makes — and printing both reads as a bug.
		--
		-- Reaching it needs the item-scrape path, which needs a scraper tooltip
		-- fixture (GetItemScraper + the TOGPMItemScraperTextLeft* fontstrings)
		-- this harness does not have. The suppression is verified by reading
		-- the loop, not by a test.

		it("orders them requirement, known, use — as the game does", function()
			syntheticProfDB()
			local tab = tabWith(recipes(1), 0)
			hover(tab, entryFor(NO_SCROLL, {
				crafters = { { name = "You", isYou = true, online = true } },
			}))
			local joined = table.concat(calls.lines, "\n")
			local req   = joined:find("Requires Leatherworking (200)", 1, true)
			local known = joined:find(_G.ITEM_SPELL_KNOWN or "Already known", 1, true)
			local use   = joined:find("Teaches you how to craft", 1, true)
			assert.is_truthy(req and known and use)
			assert.is_true(req < known, "the requirement must come before Already known")
			assert.is_true(known < use, "Already known must come before the Use line")
		end)
	end)
end)
