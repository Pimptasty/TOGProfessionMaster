-- The Professions tab's recipe list, and the tooltip a recipe row gets.
--
-- The list is a LibAceGUIWidgets RowList since v1.1.3. It used to be a
-- 35-frame pool with its own index and placement arithmetic, pinned by sixteen
-- specs here; that arithmetic is now the library's, with its own suite. What is
-- TOGPM's, and pinned below, is what the tab hands the list and how it asks for
-- things: one list for the session, the selection tint following the recipe in
-- the detail panel, the player's place kept through a redraw and dropped on a
-- new search, and the crafter column fitted to the cell's width.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, BT

local ALCHEMY = 171
local N       = 60      -- far more recipes than one screen shows

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	env.loadModule("GUI/BrowserTab.lua")
	BT = ns.BrowserTab
end)

--- N Alchemy recipes, each known by this character, named so the list's
--- name order is their number order.
local function populate()
	local gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	local meta, known = {}, {}
	for i = 1, N do
		local id   = 3000 + i
		local name = ("Recipe %02d"):format(i)
		env.spellsExist(id)
		meta[id]  = { name = name, icon = 1, reagents = {} }
		known[id] = { name = name, icon = 1, reagents = {},
		              crafters = { ["Testchar-Testrealm"] = ns:GetCurrentGuildTag() } }
	end
	env.setRecipeDB({ [ALCHEMY] = meta })
	gdb.recipes[ALCHEMY] = known
	gdb.skills["Testchar-Testrealm"] = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
end

before_each(function()
	env.installFrames()
	populate()
	ns.Print = function() end
	BT:InvalidateCache()
	BT._selectedProfId, BT._selectedProfs, BT._selectedTiers = 0, nil, nil
	BT._viewMode, BT._showAllRecipes, BT._searchText = "guild", false, ""
	BT._selectedEntry = nil
	ns.lib.db.char.shoppingList = {}
	ns.GUI.ListScroll.Set("browser", 0)
end)

describe("the recipe list", function()
	it("hands the filtered recipes to one list that outlives the redraw", function()
		local container = env.drawTab(BT)
		local list, host = BT._rowList, BT._rowListHost
		assert.is_truthy(list)
		assert.equal(N, #BT._recipes)
		assert.equal(BT._recipes, list.data)
		assert.equal("Recipe 01", list.data[1].name)
		-- The fixture must give the list room, or the scroll specs below pass
		-- for the wrong reason.
		local vis = list.visibleRowCount or 0
		assert.is_true(vis > 5 and vis < N - 10, "visible rows: " .. vis)

		BT:Draw(container)
		assert.equal(list, BT._rowList)
		assert.equal(host, BT._rowListHost)
		assert.equal(BT._recipes, list.data)
	end)

	it("sits left of the detail panel, inside the tab", function()
		env.drawTab(BT)
		local host = BT._rowListHost
		local _, relTo, relPoint = host:GetPoint(2)
		assert.equal(BT._detailOuter, relTo)
		assert.equal("BOTTOMLEFT", relPoint)
		assert.equal(BT._listSection.content, BT._detailOuter:GetParent())
	end)

	it("shows a clicked recipe in the detail panel and tints its row", function()
		env.drawTab(BT)
		local e = BT._recipes[5]
		BT._rowList.onRowClick(e, 5, BT._rowList, "LeftButton")
		assert.equal(e, BT._selectedEntry)
		assert.equal(e, BT._rowList:GetSelected())
	end)

	it("keeps the tint on the same recipe when a rewarm rebuilds the list", function()
		-- A guild-data rewarm builds new tables for the same recipes, so the
		-- selection has to be matched by id, not by identity.
		env.drawTab(BT)
		local e = BT._recipes[7]
		BT:DrawDetail(e)
		BT:InvalidateCache()
		BT:RefreshList()
		assert.are_not.equal(e, BT._recipes[7])
		assert.equal(e.id, BT._rowList:GetSelected().id)
	end)

	it("clears the tint when the detail panel is cleared", function()
		env.drawTab(BT)
		BT:DrawDetail(BT._recipes[3])
		BT:ClearDetail()
		assert.is_nil(BT._rowList:GetSelected())
	end)

	it("ignores a right click", function()
		env.drawTab(BT)
		BT._rowList.onRowClick(BT._recipes[2], 2, BT._rowList, "RightButton")
		assert.is_nil(BT._selectedEntry)
	end)

	it("puts the list back where it was on the next draw", function()
		local container = env.drawTab(BT)
		BT._rowList:SetScrollOffset(17)
		assert.equal(17, ns.GUI.ListScroll.Get("browser"))
		BT:Draw(container)
		assert.equal(17, BT._rowList:GetScrollOffset())
	end)

	it("starts a new search at the top", function()
		env.drawTab(BT)
		BT._rowList:SetScrollOffset(20)
		BT._searchText = "Recipe"
		BT:RefreshList()
		assert.equal(0, BT._rowList:GetScrollOffset())
	end)

	it("hides the list under the hint when a search matches nothing", function()
		env.drawTab(BT)
		BT._searchText = "no recipe is called this"
		BT:RefreshList()
		assert.is_nil(BT._recipes)
		assert.is_false(BT._rowListHost:IsShown())
	end)

	it("hands the host back to UIParent when the tab is released", function()
		local container = env.drawTab(BT)
		assert.is_truthy(BT._listSection)
		container:ReleaseChildren()
		assert.equal(UIParent, BT._rowListHost:GetParent())
		assert.is_false(BT._rowListHost:IsShown())
		assert.equal(UIParent, BT._detailOuter:GetParent())
		assert.is_nil(BT._listSection)
	end)
end)

--- A tab instance of its own for the tooltip specs below, so nothing they set
--- leaks into the shared tab. The arguments are ignored: the tooltip is drawn
--- straight from an entry, with no list behind it.
local function tabWith(...) return setmetatable({}, { __index = BT }) end   -- luacheck: ignore 212
local function recipes(...) end                                               -- luacheck: ignore 212

describe("the crafter column", function()
	local fit = function(...) return BT._fitCrafterText(...) end
	local function crafters(n)
		local out = {}
		for i = 1, n do out[i] = { name = "C" .. i, online = true } end
		return out
	end
	-- One unit of width per visible character, colour codes stripped.
	local function measure(s)
		return #(s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
	end
	local ON, OFF, YOU = "|cffffffff", "|cffaaaaaa", "|cffDA8CFF"
	local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

	it("is empty with nobody to list", function()
		assert.equal("", fit({}, 100, measure, ON, OFF, YOU))
		assert.equal("", fit(nil, 100, measure, ON, OFF, YOU))
	end)

	it("shows two names and a count before the list has a width", function()
		assert.equal("C1, C2 +3", plain(fit(crafters(5), nil, measure, ON, OFF, YOU)))
		assert.equal("C1, C2 +3", plain(fit(crafters(5), 0, nil, ON, OFF, YOU)))
	end)

	it("fits as many names as the cell's width allows", function()
		-- "C1, C2, C3 +2" is 13 wide; "C1, C2, C3, C4 +1" is 17.
		assert.equal("C1, C2, C3 +2", plain(fit(crafters(5), 15, measure, ON, OFF, YOU)))
		assert.equal("C1, C2, C3, C4, C5", plain(fit(crafters(5), 100, measure, ON, OFF, YOU)))
	end)

	it("always shows one name, even when it does not fit", function()
		assert.equal("C1 +4", plain(fit(crafters(5), 2, measure, ON, OFF, YOU)))
	end)

	it("colours you, online and offline crafters apart", function()
		local text = fit({ { name = "You", isYou = true }, { name = "Bob", online = true },
		                   { name = "Al" } }, 100, measure, ON, OFF, YOU)
		assert.equal(YOU .. "You|r, " .. ON .. "Bob|r, " .. OFF .. "Al|r", text)
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

	-- The list calls this from the row's OnEnter, with the row frame as owner.
	local function hover(tab, entry)
		tab:ShowRowTooltip(entry, CreateFrame("Frame"))
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

	it("names a reagent the cache had not seen when the list was built, in the Reagents line", function()
		-- The third draw site of the 2026-09-11 "Item #15417" report. The entry's
		-- reagent table was built cold (placeholder inside, exactly as
		-- GetRecipeReagents left it); the hover must resolve it, not print it.
		ns2._profDB = { GetRecipeItem = function() return nil, false end,
		                GetSyntheticRecipeScroll = function() return nil end }
		ns2._itemDB = { GetName = function(_, id) return id == 15417 and "Devilsaur Leather" or nil end }
		local tab = tabWith(recipes(1), 0)
		hover(tab, entryFor(NO_SCROLL, {
			reagents = { { itemId = 15417, count = 8, name = "Item #15417" } },
		}))
		local joined = table.concat(calls.lines, "\n")
		assert.is_truthy(joined:find("Devilsaur Leather (8)", 1, true))
		assert.is_nil(joined:find("Item #15417", 1, true))
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
