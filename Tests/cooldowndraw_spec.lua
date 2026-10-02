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
	-- `next` rather than a one-iteration `for`: "any key from this set".
	return (next(data.transmutes))
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

-- In game 2026-09-30: "attempt to index local 'anchorBelow' (a number value)"
-- from this exact click. select(2, GetInfo(id)) as the LAST argument handed the
-- dialog every return after the link; the 4th landed in anchorBelow.
describe("a cooldown row's [Bank] button", function()
	it("hands the [Bank] dialog exactly the item, its name and its link", function()
		local ITEM = 12359
		local LINK = "|Hitem:" .. ITEM .. "|h[Thorium Bar]|h"
		env.wow.items[ITEM] = { name = "Thorium Bar", link = LINK }
		env.drawTab(CD)
		local bank
		for _, col in ipairs(CD._rowList.columns) do
			if col.key == "bankBtn" then bank = col end
		end
		assert.is_truthy(bank, "the cooldown list has no [Bank] column")
		local got, saved = nil, ns.Bank.ShowRequestDialog
		ns.Bank.ShowRequestDialog = function(...) got = { n = select("#", ...), ... } end
		local ok, err = pcall(bank.onClick, { reagentItemId = ITEM })
		ns.Bank.ShowRequestDialog = saved
		assert.is_true(ok, tostring(err))
		assert.equal(3, got.n)
		assert.same({ ITEM, "Thorium Bar", LINK }, { got[1], got[2], got[3] })
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

	-- The popup's rows are a LibAceGUIWidgets RowList (popup._list) since v1.2.0.
	local function popupColumn(popup, key)
		for _, col in ipairs(popup._list.columns) do
			if col.key == key then return col end
		end
	end

	--- The reagent cell as drawn for the row that carries `name`, colour code and all.
	local function reagentCell(popup, name)
		local col = assert(popupColumn(popup, "reagent"))
		for _, row in ipairs(popup._list.data) do
			local text = col.format(nil, row)
			if text:find(name, 1, true) then return text end
		end
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
		local cell = reagentCell(popup, "Iron Bar")
		assert.is_truthy(cell)
		assert.equal("|cffa6a6a6Iron Bar|r", cell)
	end)

	it("whitens it once the reagent is in the viewer's bags", function()
		env.wow.items[IRON] = { name = "Iron Bar", link = "|Hitem:" .. IRON .. "|h" }
		env.wow.bags[0] = { slots = 1, [1] = { itemID = IRON, count = 5, link = "|Hitem:" .. IRON .. "|h" } }
		setUpTransmuteRow()
		local popup = openPopup()
		local cell = reagentCell(popup, "Iron Bar")
		assert.is_truthy(cell)
		assert.equal("|cffffffffIron Bar|r", cell)
	end)

	-- One mail per COOLDOWN (v1.1.0). A two-reagent transmute draws a row per
	-- reagent -- each with its own [Bank] request -- but the mail button is on
	-- the first row only, and it carries every reagent of that transmute.
	describe("with a two-reagent transmute", function()
		local ARCANITE_RECIPE = 20201   -- Recipe: Transmute Arcanite
		local THORIUM, CRYSTAL, ARCANITE = 12359, 12360, 12655

		local function setUpArcaniteRow()
			local t = assert(anyTransmute())
			env.wow.items[THORIUM]  = { name = "Thorium Bar",    stackCount = 20 }
			env.wow.items[CRYSTAL]  = { name = "Arcane Crystal", stackCount = 20 }
			env.wow.items[ARCANITE] = { name = "Arcanite Bar" }
			env.setRecipeDB({
				[171] = {
					[ARCANITE_RECIPE] = {
						name = "Transmute: Arcanite", icon = 1,
						teaches = t,
						reagents = { [THORIUM] = 1, [CRYSTAL] = 1 },
						craftedItemId = ARCANITE,
					},
				},
			})
			gdb.recipes[171] = {
				[ARCANITE_RECIPE] = {
					name = "Transmute: Arcanite",
					crafters = { [MATE] = ns:GetCurrentGuildTag() },
				},
			}
			give(MATE, t, NOW + HOUR)
			return t
		end

		-- The rows that draw the mail icon. Since v1.2.0 the mail button is the
		-- list's `mail` icon column: the icon shows on a row that carries a mail.
		local function mailButtons(popup)
			local col, out = assert(popupColumn(popup, "mail")), {}
			for _, row in ipairs(popup._list.data) do
				if col.icon(row) == "Interface\\Icons\\INV_Letter_15" then out[#out + 1] = row end
			end
			return out
		end

		it("draws a row per reagent but ONE mail button", function()
			setUpArcaniteRow()
			local popup = openPopup()
			local texts = popupText(popup)
			assert.is_truthy(anyMatching(texts, "Thorium Bar"))
			assert.is_truthy(anyMatching(texts, "Arcane Crystal"))
			assert.equal(1, #mailButtons(popup))
		end)

		it("draws each reagent white or grey by what the viewer's bags hold", function()
			-- One Thorium Bar carried, no Arcane Crystal: one can be sent, one not.
			env.wow.bags[0] = { slots = 1, [1] = { itemID = THORIUM, count = 1, link = "|Hitem:" .. THORIUM .. "|h" } }
			setUpArcaniteRow()
			local popup = openPopup()
			local col, seen = assert(popupColumn(popup, "reagent")), {}
			for _, row in ipairs(popup._list.data) do seen[#seen + 1] = col.format(nil, row) end
			assert.is_truthy(anyMatching(seen, "|cffffffffThorium Bar|r"))
			assert.is_truthy(anyMatching(seen, "|cffa6a6a6Arcane Crystal|r"))
		end)

		it("mails the cooldown from its mail icon, and only that row has one", function()
			env.wow.bags[0] = {
				slots = 4,
				[1] = { itemID = THORIUM, count = 1, link = "|Hitem:" .. THORIUM .. "|h" },
				[2] = { itemID = CRYSTAL, count = 1, link = "|Hitem:" .. CRYSTAL .. "|h" },
			}
			MailFrame:Show()
			_G.MailEditBox = { SetText = function() end }
			setUpArcaniteRow()
			local popup = openPopup()
			local mail = assert(popupColumn(popup, "mail"))
			local rows = mailButtons(popup)
			assert.equal(1, #rows)
			-- A row without the icon ignores the click and leaves it unhandled.
			for _, row in ipairs(popup._list.data) do
				if row ~= rows[1] then assert.is_nil(mail.onCellClick(row, 1, popup._list, "LeftButton")) end
			end
			assert.is_true(mail.onCellClick(rows[1], 1, popup._list, "LeftButton"))
			_G.MailEditBox = nil
			local onMail = {}
			for i = 1, ATTACHMENTS_MAX_SEND do
				local it = env.wow.sendMailItems[i]
				if it then onMail[it.itemID] = (onMail[it.itemID] or 0) + it.count end
			end
			assert.same({ [THORIUM] = 1, [CRYSTAL] = 1 }, onMail)
		end)

		-- In game 2026-09-30: "attempt to index local 'anchorBelow' (a number
		-- value)" from the [Bank] click. A bare select(2, GetInfo(id)) as the
		-- last argument handed the dialog every return after the link.
		it("hands the [Bank] dialog exactly the item, its name and its link", function()
			setUpArcaniteRow()
			env.wow.items[THORIUM].link = "|Hitem:" .. THORIUM .. "|h[Thorium Bar]|h"
			local popup = openPopup()
			local got, saved = nil, ns.Bank.ShowRequestDialog
			ns.Bank.ShowRequestDialog = function(...) got = { n = select("#", ...), ... } end
			local bank = assert(popupColumn(popup, "bankBtn"))
			for _, row in ipairs(popup._list.data) do
				if row.e.reagentId == THORIUM then bank.onClick(row) end
			end
			ns.Bank.ShowRequestDialog = saved
			assert.is_truthy(got)
			assert.equal(3, got.n)
			assert.same({ THORIUM, "Thorium Bar", "|Hitem:" .. THORIUM .. "|h[Thorium Bar]|h" },
				{ got[1], got[2], got[3] })
		end)

		it("builds no new frames when it is opened again", function()
			-- Up to v1.1.2 every open built a new shell, overlay and row frames,
			-- and WoW never frees a frame.
			setUpArcaniteRow()
			local popup, _, cdHit = openPopup()
			cdHit:GetScript("OnClick")(cdHit, "LeftButton")   -- close
			local made, realCreate = 0, _G.CreateFrame
			_G.CreateFrame = function(...) made = made + 1; return realCreate(...) end
			local ok, err = pcall(cdHit:GetScript("OnClick"), cdHit, "LeftButton")
			_G.CreateFrame = realCreate
			assert.is_true(ok, tostring(err))
			assert.equal(popup, CD._groupPopup)
			assert.is_true(popup:IsShown())
			assert.equal(0, made)
			assert.is_truthy(anyMatching(popupText(popup), "Arcane Crystal"))
		end)

		it("puts BOTH reagents on one mail when that button is clicked", function()
			env.wow.bags[0] = {
				slots = 4,
				[1] = { itemID = THORIUM, count = 1, link = "|Hitem:" .. THORIUM .. "|h" },
				[2] = { itemID = CRYSTAL, count = 1, link = "|Hitem:" .. CRYSTAL .. "|h" },
			}
			MailFrame:Show()
			-- The body box is the client's MailEditBox, not modelled by the
			-- harness; a one-method stand-in captures the text and is removed
			-- again below (not env-owned, so it would leak into later files).
			local body
			_G.MailEditBox = { SetText = function(_, t) body = t end }
			setUpArcaniteRow()
			local popup = openPopup()
			local mailRow = mailButtons(popup)[1]
			assert.is_true(popupColumn(popup, "mail").onCellClick(mailRow, 1, popup._list, "LeftButton"))
			_G.MailEditBox = nil
			local onMail = {}
			for i = 1, ATTACHMENTS_MAX_SEND do
				local it = env.wow.sendMailItems[i]
				if it then onMail[it.itemID] = (onMail[it.itemID] or 0) + it.count end
			end
			assert.same({ [THORIUM] = 1, [CRYSTAL] = 1 }, onMail)
			assert.equal("Bob", SendMailNameEditBox:GetText())
			-- The body names the PRODUCT, not the spell: "make Arcanite Bar",
			-- not "make Transmute: Arcanite" (the user's first in-game mail).
			assert.is_true(body:find("make Arcanite Bar", 1, true) ~= nil)
			assert.is_nil(body:find("make Transmute", 1, true))
		end)
	end)
end)
