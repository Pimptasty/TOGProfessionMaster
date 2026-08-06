-- The Cooldowns tab as it is actually drawn, and the group popup behind it.
--
-- `cooldownrows_spec.lua` covers the row PIPELINE — what BuildRows emits. This
-- one covers what a player then SEES: DrawRow (440 lines) and ShowGroupPopup
-- (360 more), neither of which had ever executed outside the game. That is
-- where the row's real decisions live — the readiness colour, "You" versus a
-- guildmate's name, the online/offline shade, whether a group row is clickable
-- at all, and whether the popup tells you you can afford to mail the reagent.
--
-- Everything here asserts on the text and colour that ends up in a fontstring,
-- not on how many widgets got made. A widget count passes just as happily when
-- every row says the wrong thing.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, CD, gdb, data, frames, L
local ME    = "Testchar-Testrealm"
local ALT   = "Testalt-Testrealm"
local MATE  = "Bob-Testrealm"
local NOW   = 100000
local HOUR  = 3600

-- Colour prefixes DrawRow paints the time column with. Named here so a test
-- reads as the rule it is checking rather than as a hex literal.
local GREEN, YELLOW, ORANGE, RED = "|cff00ff00", "|cffffff00", "|cffff8800", "|cffff2200"

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	CD = env.loadModule("GUI/CooldownsTab.lua").CooldownsTab
	L  = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
end)

before_each(function()
	frames = env.installFrames()
	env.serverTime = NOW
	gdb = env.resetDb()
	env.roster({
		{ name = "Testchar", isOnline = true },
		{ name = "Bob",      isOnline = true },
	})
	env.setRecipeDB({})
	data = ns:GetCooldownData()

	-- The tab remembers its filters and its open popup on the module table, so
	-- state left by one test would silently change the next one's rows.
	CD._readyOnly, CD._viewMode = false, "guild"
	CD._filterProfId, CD._filterCd = 0, "all"
	CD._sortCol, CD._sortAsc = nil, nil
	if CD._groupPopup then CD._groupPopup:Hide(); CD._groupPopup = nil end
end)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

local function give(charKey, spellId, expiresAt)
	gdb.cooldowns[charKey] = gdb.cooldowns[charKey] or {}
	gdb.cooldowns[charKey][spellId] = expiresAt
end

--- A whitelisted single-spell cooldown that carries a reagent, so the reagent /
--- [AH] / [Bank] / mail half of the row is exercised too.
local function singleWithReagent()
	for spellId in pairs(data.cooldowns) do
		if not data.transmutes[spellId]
		   and not (data.groupBySpell and data.groupBySpell[spellId])
		   and not (data.multiReagents and data.multiReagents[spellId])
		   and data.reagents[spellId] then
			return spellId, data.reagents[spellId].id
		end
	end
end

local function anyTransmute()
	for spellId in pairs(data.transmutes) do return spellId end
end

--- Draw the tab and hand back every fontstring's text, in creation order.
local function drawAndReadText()
	local container = env.drawTab(CD)
	local out = {}
	for _, fs in ipairs(frames.findAll(container.frame, function(o)
		return o._type == "FontString"
	end)) do
		out[#out + 1] = fs:GetText() or ""
	end
	return out, container
end

local function joined(texts) return table.concat(texts, "\n") end

local function anyMatching(texts, needle)
	for _, t in ipairs(texts) do
		if t:find(needle, 1, true) then return t end
	end
end

-- ---------------------------------------------------------------------------

describe("the tab draws a row per cooldown", function()
	it("renders nothing but the empty-state label with no cooldowns at all", function()
		local texts = drawAndReadText()
		assert.is_truthy(anyMatching(texts, L["NoCooldownData"]))
	end)

	it("names the character a cooldown belongs to", function()
		local spellId = assert(singleWithReagent())
		give(MATE, spellId, NOW + HOUR)
		local texts = drawAndReadText()
		assert.is_truthy(anyMatching(texts, "Bob"))
		-- and the empty state is gone, which is the other half of the claim
		assert.is_nil(anyMatching(texts, L["NoCooldownData"]))
	end)

	it("draws one row per character rather than merging them", function()
		local spellId = assert(singleWithReagent())
		give(MATE, spellId, NOW + HOUR)
		give(ME,   spellId, NOW + HOUR)
		local texts = drawAndReadText()
		-- Neither is flagged as an account character here, so both render under
		-- their own names — the "You" substitution is a separate claim below.
		assert.is_truthy(anyMatching(texts, "Bob"))
		assert.is_truthy(anyMatching(texts, "Testchar"))
	end)
end)

describe("the readiness colour", function()
	-- Four bands, and the boundaries are the interesting part: a cooldown that
	-- is ready must not read as "1 second left", and one at 23h59m must not
	-- read the same as one at 25h.
	local function timeTextFor(secondsLeft)
		local spellId = assert(singleWithReagent())
		give(MATE, spellId, NOW + secondsLeft)
		local texts = drawAndReadText()
		for _, t in ipairs(texts) do
			for _, colour in ipairs({ GREEN, YELLOW, ORANGE, RED }) do
				if t:sub(1, #colour) == colour then return t, colour end
			end
		end
	end

	it("is green when the cooldown is already ready", function()
		local _, colour = timeTextFor(-1)
		assert.equal(GREEN, colour)
	end)

	it("is green exactly at expiry, not one band up", function()
		local _, colour = timeTextFor(0)
		assert.equal(GREEN, colour)
	end)

	it("is yellow under eight hours", function()
		local _, colour = timeTextFor(8 * HOUR - 1)
		assert.equal(YELLOW, colour)
	end)

	it("turns orange at eight hours exactly", function()
		local _, colour = timeTextFor(8 * HOUR)
		assert.equal(ORANGE, colour)
	end)

	it("stays orange just under a day", function()
		local _, colour = timeTextFor(24 * HOUR - 1)
		assert.equal(ORANGE, colour)
	end)

	it("turns red at a full day", function()
		local _, colour = timeTextFor(24 * HOUR)
		assert.equal(RED, colour)
	end)
end)

describe("whose cooldown it is", function()
	it("calls the logged-in character You", function()
		local spellId = assert(singleWithReagent())
		gdb.accountChars[ME] = true
		give(ME, spellId, NOW + HOUR)
		local texts = drawAndReadText()
		assert.is_truthy(anyMatching(texts, L["You"]))
	end)

	it("disambiguates an alt as You (AltName), not a bare You", function()
		-- Two of your own characters on the list is the case where a bare "You"
		-- twice is useless — you cannot tell which alt is ready.
		local spellId = assert(singleWithReagent())
		-- The alt has to be IN the guild too. Guild view scopes rows to roster
		-- members, so an alt in a different guild is dropped before it can be
		-- named — which is correct, and was my fixture being wrong, not the tab.
		env.roster({
			{ name = "Testchar", isOnline = true },
			{ name = "Testalt",  isOnline = true },
			{ name = "Bob",      isOnline = true },
		})
		gdb.accountChars[ME]  = true
		gdb.accountChars[ALT] = true
		give(ALT, spellId, NOW + HOUR)
		local texts = drawAndReadText()
		assert.is_truthy(anyMatching(texts, L["You"] .. " (Testalt)"))
	end)

	it("shades a guildmate who is offline differently from one who is on", function()
		local spellId = assert(singleWithReagent())
		env.roster({
			{ name = "Testchar", isOnline = true },
			{ name = "Bob",      isOnline = false },
		})
		give(MATE, spellId, NOW + HOUR)
		local offline = joined(drawAndReadText())

		env.roster({
			{ name = "Testchar", isOnline = true },
			{ name = "Bob",      isOnline = true },
		})
		local online = joined(drawAndReadText())

		assert.is_truthy(offline:find("|c" .. (ns.ColorOffline or "ffaaaaaa") .. "Bob", 1, true))
		assert.is_nil(online:find("|c" .. (ns.ColorOffline or "ffaaaaaa") .. "Bob", 1, true))
	end)

	it("credits an offline crafter's online alt by name", function()
		-- The point of the feature: Bob is offline but his alt Bobby is on, so
		-- you can still reach him. Showing a plain grey "Bob" would tell you to
		-- give up on a cooldown you can actually get at.
		local spellId = assert(singleWithReagent())
		env.roster({
			{ name = "Testchar", isOnline = true },
			{ name = "Bob",      isOnline = false },
			{ name = "Bobby",    isOnline = true },
		})
		gdb.altGroups[MATE] = { MATE, "Bobby-Testrealm" }
		give(MATE, spellId, NOW + HOUR)
		local texts = drawAndReadText()
		assert.is_truthy(anyMatching(texts, "Bobby (Bob)"))
	end)
end)

describe("group rows", function()
	it("marks a transmute group with the expand affordance", function()
		local t = assert(anyTransmute())
		give(MATE, t, NOW + HOUR)
		local texts = drawAndReadText()
		assert.is_truthy(anyMatching(texts, "[+] " .. L["Transmute"]))
	end)

	it("leaves a plain single cooldown without one", function()
		local spellId = assert(singleWithReagent())
		give(MATE, spellId, NOW + HOUR)
		local texts = drawAndReadText()
		assert.is_nil(anyMatching(texts, "[+] "))
	end)
end)

describe("the reagent column", function()
	it("shows the reagent's name once the client knows the item", function()
		local spellId, reagentId = singleWithReagent()
		assert.is_truthy(reagentId)
		env.wow.items[reagentId] = { name = "Felcloth", link = "|Hitem:" .. reagentId .. "|h" }
		give(MATE, spellId, NOW + HOUR)
		local texts = drawAndReadText()
		assert.is_truthy(anyMatching(texts, "Felcloth"))
	end)

	it("leaves it blank rather than printing a raw id while the item is uncached", function()
		-- An uncached item is the NORMAL state early in a session. Printing
		-- "14256" there would be worse than printing nothing.
		local spellId, reagentId = singleWithReagent()
		give(MATE, spellId, NOW + HOUR)
		local texts = drawAndReadText()
		assert.is_nil(anyMatching(texts, tostring(reagentId)))
	end)
end)

-- ---------------------------------------------------------------------------
-- The group popup
-- ---------------------------------------------------------------------------

describe("the transmute popup", function()
	local TRANSMUTE_RECIPE = 11479   -- Transmute: Iron to Gold
	local IRON, GOLD = 3575, 3577

	local function setUpTransmuteRow()
		local t = assert(anyTransmute())
		env.setRecipeDB({
			[171] = {
				[TRANSMUTE_RECIPE] = {
					name = "Transmute: Iron to Gold", icon = 1,
					teaches = t,
					reagents = { [IRON] = 1 },
					craftedItemId = GOLD,
				},
			},
		})
		gdb.recipes[171] = {
			[TRANSMUTE_RECIPE] = {
				name = "Transmute: Iron to Gold",
				crafters = { [MATE] = ns:GetCurrentGuildTag() },
			},
		}
		give(MATE, t, NOW + HOUR)
		return t
	end

	--- Draw, find the group row's clickable name cell, and click it.
	local function openPopup()
		local container = env.drawTab(CD)
		local cdHit
		for _, btn in ipairs(frames.findAll(container.frame, function(o)
			return o._type == "Button" and o:GetScript("OnClick")
		end)) do
			for _, region in ipairs(btn._regions or {}) do
				local txt = region.GetText and region:GetText()
				if txt and txt:find("[+] ", 1, true) then cdHit = btn end
			end
		end
		assert.is_truthy(cdHit)   -- precondition: the group row drew and is clickable
		cdHit:GetScript("OnClick")(cdHit, "LeftButton")
		return CD._groupPopup, container, cdHit
	end

	local function popupText(popup)
		local out = {}
		for _, fs in ipairs(frames.findAll(popup, function(o) return o._type == "FontString" end)) do
			out[#out + 1] = fs:GetText() or ""
		end
		return out
	end

	it("opens on a left click on the group row", function()
		setUpTransmuteRow()
		local popup = openPopup()
		assert.is_truthy(popup)
		assert.is_true(popup:IsShown())
	end)

	it("lists the transmute the character actually knows", function()
		setUpTransmuteRow()
		local popup = openPopup()
		assert.is_truthy(anyMatching(popupText(popup), "Transmute: Iron to Gold"))
	end)

	it("names the reagent when the client has the item", function()
		env.wow.items[IRON] = { name = "Iron Bar", link = "|Hitem:" .. IRON .. "|h" }
		setUpTransmuteRow()
		local popup = openPopup()
		assert.is_truthy(anyMatching(popupText(popup), "Iron Bar"))
	end)

	it("closes when the same row is clicked again", function()
		setUpTransmuteRow()
		local _, _, cdHit = openPopup()
		cdHit:GetScript("OnClick")(cdHit, "LeftButton")
		assert.is_nil(CD._groupPopup)
	end)

	it("closes when the click-outside overlay is used", function()
		setUpTransmuteRow()
		local popup = openPopup()
		local overlay = assert(popup._closeOnClick)
		overlay:GetScript("OnMouseDown")(overlay)
		assert.is_nil(CD._groupPopup)
		assert.is_false(popup:IsShown())
	end)

	it("greys the reagent when the viewer cannot afford to send it", function()
		-- The whole point of the colour: white means "you have these, you can
		-- mail them", grey means "you don't". Bags are empty here.
		env.wow.items[IRON] = { name = "Iron Bar", link = "|Hitem:" .. IRON .. "|h" }
		setUpTransmuteRow()
		local popup = openPopup()
		local lbl
		for _, fs in ipairs(frames.findAll(popup, function(o) return o._type == "FontString" end)) do
			if (fs:GetText() or "") == "Iron Bar" then lbl = fs end
		end
		assert.is_truthy(lbl)
		local r = lbl:GetTextColor()
		assert.is_true(r < 1)
	end)

	it("whitens it once the reagent is in the viewer's bags", function()
		env.wow.items[IRON] = { name = "Iron Bar", link = "|Hitem:" .. IRON .. "|h" }
		env.wow.bags[0] = { slots = 1, [1] = { itemID = IRON, count = 5, link = "|Hitem:" .. IRON .. "|h" } }
		setUpTransmuteRow()
		local popup = openPopup()
		local lbl
		for _, fs in ipairs(frames.findAll(popup, function(o) return o._type == "FontString" end)) do
			if (fs:GetText() or "") == "Iron Bar" then lbl = fs end
		end
		assert.is_truthy(lbl)
		local r = lbl:GetTextColor()
		assert.equal(1, r)
	end)
end)
