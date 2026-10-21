-- Vendor BUY and SELL on EVERY item tooltip, crafting or not.
--
-- The feature exists because nobody else does both halves. Auctionator and
-- Leatrix Plus each have a setting for vendor SELL price on all items; TSM shows
-- sell inside its own block; ATT shows neither; the game never shows buy, and
-- shows sell only on Retail or at an open vendor on Classic (our sell row then
-- stands down). None of them shows what a vendor CHARGES. Buy and sell together is
-- the pair a player reasons with, and we already hold both.
--
-- THE RULE THIS FILE PINS: the vendor block is independent of the recipe block.
-- Roasted Quail is not a recipe scroll and most of the game is not a recipe, so
-- a vendor section that only rendered alongside crafting data would be invisible
-- on almost everything — which is exactly what the addon did before v1.0.7, when
-- the only vendor row lived inside `AppendRecipeDetails` and answered for the
-- teaching SCROLL rather than the item in front of you.
--
-- The two numbers come from different places and neither is a single lookup:
--   * SELL  — `Price.GetVendorSell`, two tiers: `GetItemInfo`'s eleventh return,
--             then LibItemDB's static `GetVendorSellPrice`. The client tier is
--             nil on a cache-cold item; the static one has no such state.
--   * BUY   — `Price.GetVendorBuy`, LibItemDB's `GetVendorBuyPrice` (Auctionator's
--             vendor cache, the merchant capture, then the static base price --
--             all three tiers the library's since v1.1.0).

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local SCROLL = 12656
local QUAIL  = 8952          -- an ordinary consumable: no recipe, no scroll

local ns, IL, Ace, realGetItemDB, realGetVendorBuy, savedEnum

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
	ns.sourceDB = {}
	ns._recipeItemIndex = nil
	-- Captured EVERY time, not once in setup: most cases below replace this to
	-- steer the buy price, and the real one must go back before the next case.
	-- The first draft restored it in only the one test that saved it, so the
	-- stub leaked forward and the last case in the file asserted against this
	-- file's own fake instead of the real function — passing would have been
	-- worse than the failure it actually produced.
	realGetVendorBuy = realGetVendorBuy or ns.Price.GetVendorBuy
	ns.Price.GetVendorBuy = realGetVendorBuy
	-- DEFAULT TO "NO ItemDB", explicitly, and never leave it to chance. The whole
	-- suite shares one Lua state, so another spec file loading the real
	-- LibItemDB-1.0 leaves it registered in LibStub — and `ns:GetItemDB()`
	-- resolves lazily through LibStub, so a nil here would silently hand these
	-- cases the SHIPPED sell-price table for Roasted Quail. The cache-cold cases
	-- below assert an ABSENT row; against the real library they would fail, or
	-- worse, pass for the wrong reason depending on spec order.
	ns._itemDB = false
	-- Cases below install a SellPrice line type; after_each puts the real one
	-- back even when a case raises halfway.
	savedEnum = _G.Enum
end)

after_each(function()
	ns.sourceDB = {}
	ns._recipeItemIndex = nil
	ns.GetItemDB = realGetItemDB
	ns._itemDB   = nil
	ns.Price.GetVendorBuy = realGetVendorBuy
	Ace.db.profile.tooltipVendorBuy  = nil
	Ace.db.profile.tooltipVendorSell = nil
	Ace.db.profile.tooltipRecipeDetails = nil
	_G.Enum = savedEnum
end)

local function withSellPriceEnum()
	_G.Enum = { TooltipDataLineType = { SellPrice = 11 } }
end

--- A fresh GameTooltip with the dedup flags clear, as a real hover would have.
local function tip()
	local t = _G.GameTooltip
	t:ClearLines()
	t._togpmVendorBlock = nil
	t._togpmRecipeBlock = nil
	t._togpmGameSell    = nil
	t._togpmBranded     = nil
	t._togpmAppended    = nil
	return t
end

local function textOf(t)
	local out = {}
	for i = 1, t:NumLines() do
		local line = t:GetLine(i)
		out[#out + 1] = tostring(line and line.left)
	end
	return table.concat(out, "\n")
end

--- Give the client a cached item with a known sellPrice (11th return).
local function cacheItem(id, sellPrice)
	env.wow.items[id] = { name = "Item " .. id, link = "|Hitem:" .. id .. "|h",
	                      quality = 1, level = 1, sellPrice = sellPrice }
end

describe("vendor prices render on an ordinary item with no crafting at all", function()
	it("shows both rows for an item that is neither a recipe nor a scroll", function()
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		local text = textOf(t)
		assert.is_truthy(text:find("Buy", 1, true),  "no buy row")
		assert.is_truthy(text:find("Sell", 1, true), "no sell row")
	end)

	it("brands itself when it is the ONLY thing we contribute", function()
		-- On plain loot the recipe block renders nothing, so without this the
		-- player sees a bare "Vendor" heading from an unidentified addon.
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		IL.AppendVendorPrices(t, QUAIL)
		assert.is_truthy(textOf(t):find("UPM", 1, true))
	end)

	it("does NOT brand itself when anything else already did", function()
		-- Two TOGPM labels on one tooltip reads as two addons. The crafters line,
		-- the IDs line and the recipe block all set this one flag.
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		t._togpmBranded = true
		IL.AppendVendorPrices(t, QUAIL)
		local _, count = textOf(t):gsub("UPM", "")
		assert.equal(0, count)
	end)

	it("one label when the crafters line and the vendor block both render", function()
		-- Peer Review's reproduction: a crafted reagent with a guild crafter and
		-- a vendor price used to carry "[TOGPM] Bob" AND a "TOGPM" heading.
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		t:AddLine("[UPM] Bob")
		t._togpmBranded = true                  -- as the crafters line leaves it
		IL.AppendVendorPrices(t, QUAIL)
		local _, count = textOf(t):gsub("UPM", "")
		assert.equal(1, count)
		assert.is_true(t._togpmBranded)
	end)
end)

describe("each row appears only when its number is real", function()
	it("omits BUY for an item no vendor sells", function()
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return nil end
		local t = tip()
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		local text = textOf(t)
		assert.is_nil(text:find("Buy", 1, true))
		assert.is_truthy(text:find("Sell", 1, true))
	end)

	it("omits SELL for a cache-cold item with no ItemDB to fall back to", function()
		-- GetItemInfo returns nil for an item the client has not seen, and with
		-- ItemDB absent there is no second source. Omitting is the honest
		-- behaviour; rendering 0c would claim a vendor pays nothing.
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		local text = textOf(t)
		assert.is_truthy(text:find("Buy", 1, true))
		assert.is_nil(text:find("Sell", 1, true))
	end)

	it("STILL shows SELL for a cache-cold item when ItemDB carries it", function()
		-- The v1.0.7 fix, and the case the whole two-tier ladder exists for. The
		-- row used to be blank on exactly the tooltips that matter most: an item
		-- the player has never seen, on a fresh login, browsing someone else's
		-- profession list. It looked correct in every manual test because you had
		-- just looked at the item.
		--
		-- Note this is the SAME hover that fails above — the only difference is
		-- that LibItemDB answers — so the pair pins the fallback rather than the
		-- happy path.
		ns.Price.GetVendorBuy = function() return nil end
		ns._itemDB = { GetVendorSellPrice = function(_, id)
			if id == QUAIL then return 1250 end
		end }
		local t = tip()
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		local text = textOf(t)
		assert.is_truthy(text:find("Sell", 1, true), "the static tier did not render")
		-- Compared against `Price.Money` rather than a literal "12s 50c": the
		-- helper switches to the client's coin textures when `GetCoinTextureString`
		-- exists, so a hardcoded string would pin the harness's formatting rather
		-- than the number that reached the row.
		assert.is_truthy(text:find(ns.Price.Money(1250), 1, true),
			"wrong number from the static tier")
	end)

	it("treats a zero sellPrice as no answer", function()
		-- 0 is what the client reports for an item a vendor will not buy at all.
		cacheItem(QUAIL, 0)
		ns.Price.GetVendorBuy = function() return nil end
		local t = tip()
		assert.is_false(IL.AppendVendorPrices(t, QUAIL))
		assert.equal("", textOf(t))
	end)

	it("adds nothing when neither number is available", function()
		ns.Price.GetVendorBuy = function() return nil end
		local t = tip()
		assert.is_false(IL.AppendVendorPrices(t, QUAIL))
		assert.equal("", textOf(t))
	end)
end)

describe("the block is opt-out and rendered once", function()
	it("adds nothing with both rows switched off", function()
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		Ace.db.profile.tooltipVendorBuy  = false
		Ace.db.profile.tooltipVendorSell = false
		local t = tip()
		assert.is_false(IL.AppendVendorPrices(t, QUAIL))
		assert.equal("", textOf(t))
	end)

	it("the buy toggle hides only the buy row", function()
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		Ace.db.profile.tooltipVendorBuy = false
		local t = tip()
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		local text = textOf(t)
		assert.is_nil(text:find("Buy", 1, true))
		assert.is_truthy(text:find("Sell", 1, true))
	end)

	it("the sell toggle hides only the sell row", function()
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		Ace.db.profile.tooltipVendorSell = false
		local t = tip()
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		local text = textOf(t)
		assert.is_truthy(text:find("Buy", 1, true))
		assert.is_nil(text:find("Sell", 1, true))
	end)

	it("does not look up a row that is switched off", function()
		-- The buy ladder can ask Auctionator, and this runs on every hover.
		cacheItem(QUAIL, 2000)
		local asked = false
		ns.Price.GetVendorBuy = function() asked = true; return 8000 end
		Ace.db.profile.tooltipVendorBuy = false
		IL.AppendVendorPrices(tip(), QUAIL)
		assert.is_false(asked)
	end)

	it("writes no heading when the only available row is switched off", function()
		-- A sell-only item with the sell row off must not leave a bare "TOGPM".
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return nil end
		Ace.db.profile.tooltipVendorSell = false
		local t = tip()
		assert.is_false(IL.AppendVendorPrices(t, QUAIL))
		assert.equal("", textOf(t))
	end)

	it("renders once per hover even though three hook paths reach it", function()
		-- Modern post-call, legacy OnTooltipSetItem and the Show fallback can all
		-- fire for a single hover; two price blocks is always a bug.
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		assert.is_false(IL.AppendVendorPrices(t, QUAIL))
		local _, count = textOf(t):gsub("Buy", "")
		assert.equal(1, count)
	end)

	it("renders for a DIFFERENT item even if the last item's flag survived", function()
		-- The dedup is per item. A flag left over from the previous hover (no
		-- OnTooltipCleared in between) must not blank the vendor block for the
		-- next item -- it renders on nearly everything, so that would be loud.
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		t._togpmVendorBlock = SCROLL
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
	end)

	it("clears its flag on OnTooltipCleared so the next hover renders", function()
		-- GameTooltip is reused for every hover in the game. A flag that outlived
		-- the item would show this block once per session — and because it fires
		-- on nearly every item, that is a far more visible failure than the
		-- recipe block's equivalent.
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		IL.AppendVendorPrices(t, QUAIL)
		ns.Tooltip._OnTooltipCleared(t)
		assert.is_nil(t._togpmVendorBlock)
		t:ClearLines()
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
	end)
end)

describe("the sell row stands down when the game printed its own", function()
	-- Classic's client adds "Sell Price:" via OnTooltipAddMoney while a vendor
	-- is open, Retail on every item via a SellPrice data line. Ours on top was
	-- the same number twice.

	it("drops SELL but keeps BUY after the game's OnTooltipAddMoney", function()
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return 8000, "vendor-static" end
		local t = tip()
		ns.Tooltip._OnTooltipAddMoney(t)
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		local text = textOf(t)
		assert.is_truthy(text:find("Buy", 1, true), "buy row lost")
		assert.is_nil(text:find("Sell", 1, true), "sell row duplicated the game's")
	end)

	it("adds nothing when sell was the only number and the game has it", function()
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return nil end
		local t = tip()
		ns.Tooltip._OnTooltipAddMoney(t)
		assert.is_false(IL.AppendVendorPrices(t, QUAIL))
		assert.equal("", textOf(t))
	end)

	it("a game-sell flag left from item A does not hide item B's sell row", function()
		-- Peer Review T1: the flag holds the ITEM the game priced. Where Cleared
		-- does not run between hovers, a bare true used to suppress every later
		-- item's sell row.
		cacheItem(QUAIL, 2000)
		ns.Price.GetVendorBuy = function() return nil end
		local t = tip()
		t._togpmGameSell = SCROLL                -- the previous item's
		assert.is_true(IL.AppendVendorPrices(t, QUAIL))
		assert.is_truthy(textOf(t):find("Sell", 1, true))
	end)

	it("the modern post-call assigns the flag per item, clearing a stale one", function()
		withSellPriceEnum()
		local t = tip()
		ns.Tooltip._OnItemPostCall(t, { id = SCROLL, lines = { { type = 11 } } })
		assert.equal(SCROLL, t._togpmGameSell)
		ns.Tooltip._OnItemPostCall(t, { id = QUAIL, lines = { { type = 0 } } })
		assert.is_nil(t._togpmGameSell)
	end)

	it("the post-call keeps a flag OnTooltipAddMoney set for the same item", function()
		local saved = _G.Enum
		_G.Enum = { TooltipDataLineType = { SellPrice = 11 } }
		local t = tip()
		t._togpmGameSell = QUAIL
		ns.Tooltip._OnItemPostCall(t, { id = QUAIL, lines = {} })
		_G.Enum = saved
		assert.equal(QUAIL, t._togpmGameSell)
	end)

	it("a post-call with no item id still records the game's sell line", function()
		local saved = _G.Enum
		_G.Enum = { TooltipDataLineType = { SellPrice = 11 } }
		local t = tip()
		ns.Tooltip._OnItemPostCall(t, { lines = { { type = 11 } } })
		_G.Enum = saved
		assert.is_true(t._togpmGameSell)
	end)

	it("forgets the game's sell line on OnTooltipCleared", function()
		local t = tip()
		ns.Tooltip._OnTooltipAddMoney(t)
		ns.Tooltip._OnTooltipCleared(t)
		assert.is_nil(t._togpmGameSell)
	end)

	it("recognises Retail's SellPrice data line, and only that", function()
		local saved = _G.Enum
		_G.Enum = { TooltipDataLineType = { SellPrice = 11 } }
		local has = ns.Tooltip._DataHasSellPrice
		local ok1 = has({ lines = { { type = 0 }, { type = 11 } } })
		local ok2 = has({ lines = { { type = 0 } } })
		local ok3 = has(nil)
		_G.Enum = saved
		assert.is_true(ok1)
		assert.is_false(ok2)
		assert.is_false(ok3)
	end)
end)

describe("Price.GetVendorBuy is one implementation, shared", function()
	it("is what Price.Get falls back to", function()
		-- Extracted from inside Price.Get in v1.0.7 so the tooltip could ask for
		-- a vendor price specifically. If these diverge, a tooltip and a
		-- cost-to-craft can quote different vendor prices for the same item.
		assert.is_function(ns.Price.GetVendorBuy)
		local seen
		-- No manual restore: before_each/after_each own that now.
		ns.Price.GetVendorBuy = function(id) seen = id; return 4242, "vendor-static" end
		local got = ns.Price.Get(SCROLL)
		assert.equal(SCROLL, seen, "Price.Get no longer routes through GetVendorBuy")
		assert.equal(4242, got)
	end)

	it("answers nil for a non-number", function()
		assert.is_nil(ns.Price.GetVendorBuy("nope"))
		assert.is_nil(ns.Price.GetVendorBuy(nil))
	end)
end)

describe("Price.GetVendorSell is a two-tier ladder, client first", function()
	-- Added in v1.0.7 alongside the wiring. Every case here drives the accessor
	-- DIRECTLY rather than through the tooltip, because the tier order is the
	-- thing worth pinning and a tooltip assertion cannot tell which tier answered.

	it("prefers the client's own number over the static table", function()
		-- Both derive from the same DBC field so they agree in practice — but the
		-- client value is the one that reflects THIS client, and putting the
		-- static table first would silently make a shipped data file authoritative
		-- over the game. Distinct numbers here so the winner is identifiable.
		cacheItem(QUAIL, 2000)
		ns._itemDB = { GetVendorSellPrice = function() return 9999 end }
		local price, source = ns.Price.GetVendorSell(QUAIL)
		assert.equal(2000, price)
		assert.equal("vendor-sell-client", source)
	end)

	it("falls through to LibItemDB when the client has nothing", function()
		env.wow.items[QUAIL] = nil
		ns._itemDB = { GetVendorSellPrice = function() return 9999 end }
		local price, source = ns.Price.GetVendorSell(QUAIL)
		assert.equal(9999, price)
		assert.equal("vendor-sell-static", source)
	end)

	it("treats zero from EITHER tier as no answer", function()
		-- 0 is a real value for an item no vendor buys. It must not fall through
		-- as though the tier were absent, and must never render as a price.
		cacheItem(QUAIL, 0)
		ns._itemDB = { GetVendorSellPrice = function() return 0 end }
		assert.is_nil(ns.Price.GetVendorSell(QUAIL))
	end)

	it("degrades quietly against a LibItemDB that predates the API", function()
		-- FEATURE-DETECTED ON THE METHOD, not on a MINOR. A player's installed
		-- ItemDB can lag the repo — ItemDB says so themselves in their contract
		-- response — and against one without the method this must answer nil, not
		-- error on a nil call inside a tooltip hook.
		env.wow.items[QUAIL] = nil
		ns._itemDB = { GetVendorBasePrice = function() return 500 end }   -- MINOR 21-era
		assert.is_nil(ns.Price.GetVendorSell(QUAIL))
	end)

	it("survives a LibItemDB that throws", function()
		-- pcall-wrapped for the same reason tier 2c of GetVendorBuy is: this is a
		-- cross-addon call on a tooltip hook, and an error here takes down every
		-- tooltip in the game, not just ours.
		env.wow.items[QUAIL] = nil
		ns._itemDB = { GetVendorSellPrice = function() error("boom") end }
		assert.is_nil(ns.Price.GetVendorSell(QUAIL))
	end)

	it("answers nil for a non-number", function()
		assert.is_nil(ns.Price.GetVendorSell("nope"))
		assert.is_nil(ns.Price.GetVendorSell(nil))
	end)
end)
