-- addon.ItemLink — the one implementation of clicking and hovering an item.
--
-- This exists because there were THREE, and they were not equivalent:
--
--   HandleModifiedItemClick(link)   Cooldowns, Crafting, AH Profit
--   ChatEdit_InsertLink(link)       Browser x3, Reagent Tracker, Compat
--   editBox:Insert(link)            Missing Recipes, Shopping List
--
-- They are not equivalent, and that is the point. `HandleModifiedItemClick` is
-- Blizzard's own router: it asks `IsModifiedClick("CHATLINK")` and
-- `IsModifiedClick("DRESSUP")` rather than hard-coding shift and ctrl, and it
-- routes to the social frame, the auction-house search box or an open macro when
-- one of those has focus. The other two check shift directly, so a rebound link
-- modifier did nothing on seven of the ten surfaces.
--
-- CORRECTION: an earlier version of this header claimed `ChatEdit_InsertLink`
-- does not exist on Classic Era. It does -- `CVars.lua:912` documents
-- `loadDeprecationFallbacks` defaulting to "1", so the fallback globals load on
-- a stock client. The unification is a behaviour fix, not a crash fix.
--
-- These specs stub the Blizzard routers deliberately rather than asking the
-- harness for them: what is under test is WHICH router this addon reaches for,
-- and that can only be asserted by watching them.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, IL, saved, calls

local LINK = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	IL = ns.ItemLink
end)

before_each(function()
	env.installFrames()
	env.resetDb()

	calls = { handled = {}, chatFrameUtil = {}, deprecated = {}, inserted = {},
	          compareShown = 0, compareHidden = 0 }

	saved = {
		HandleModifiedItemClick      = _G.HandleModifiedItemClick,
		ChatFrameUtil                = _G.ChatFrameUtil,
		ChatEdit_InsertLink          = _G.ChatEdit_InsertLink,
		ChatEdit_GetActiveWindow     = _G.ChatEdit_GetActiveWindow,
		IsModifiedClick              = _G.IsModifiedClick,
		GameTooltip_ShowCompareItem  = _G.GameTooltip_ShowCompareItem,
		GameTooltip_HideShoppingTooltips = _G.GameTooltip_HideShoppingTooltips,
		IsShiftKeyDown               = _G.IsShiftKeyDown,
	}

	-- Baseline: the router present and the older paths cleared, so a test that
	-- cares which one we reach for starts from a clean slate. This is a FIXTURE
	-- choice, not a claim about the client — Classic Era does ship
	-- `ChatEdit_InsertLink` (see the correction in the header). Tests that need
	-- it re-install it themselves.
	_G.HandleModifiedItemClick = function(link)
		calls.handled[#calls.handled + 1] = link
		return true
	end
	_G.ChatFrameUtil       = nil
	_G.ChatEdit_InsertLink = nil
	_G.ChatEdit_GetActiveWindow = function() return nil end
	_G.IsModifiedClick     = function() return false end
	_G.IsShiftKeyDown      = function() return false end
	_G.GameTooltip_ShowCompareItem      = function() calls.compareShown  = calls.compareShown  + 1 end
	_G.GameTooltip_HideShoppingTooltips = function() calls.compareHidden = calls.compareHidden + 1 end

	IL.EndHover(nil)
end)

after_each(function()
	for k, v in pairs(saved) do _G[k] = v end
end)

-- ---------------------------------------------------------------------------

describe("Click — which router it reaches for", function()
	it("uses Blizzard's own HandleModifiedItemClick", function()
		assert.is_true(IL.Click(LINK))
		assert.same({ LINK }, calls.handled)
	end)

	it("passes the link through untouched, colour codes and all", function()
		IL.Click(LINK)
		assert.equal(LINK, calls.handled[1])
	end)

	it("reports whether the click was consumed", function()
		_G.HandleModifiedItemClick = function() return false end
		assert.is_false(IL.Click(LINK))
	end)

	it("does nothing, and does not raise, without a link", function()
		assert.is_false(IL.Click(nil))
		assert.equal(0, #calls.handled)
	end)

	it("prefers the router even when the deprecated global is available", function()
		-- CORRECTED. This spec used to assert `ChatEdit_InsertLink` is nil on
		-- Classic Era, on my reading that it lives behind
		-- `GetCVarBool("loadDeprecationFallbacks")`. It does live there — but
		-- `CVars.lua:912` gives that CVar a documented default of "1", so the
		-- fallback globals load on a stock client and the global EXISTS. This
		-- addon has 14 unguarded calls to it that have always worked in game.
		--
		-- So the property worth pinning is not absence, it is PREFERENCE: the
		-- two are not equivalent, and we must reach for the router.
		-- `ChatEdit_InsertLink` is a straight alias for ChatFrameUtil.InsertLink:
		-- it ignores the player's CHATLINK/DRESSUP bindings and offers no
		-- ctrl-click dressing room.
		_G.ChatEdit_InsertLink = function(l)
			calls.deprecated[#calls.deprecated + 1] = l; return true
		end
		assert.is_true(IL.Click(LINK))
		assert.same({ LINK }, calls.handled)
		assert.equal(0, #calls.deprecated)
	end)

	it("does not consult the shift key itself", function()
		-- HandleModifiedItemClick honours the player's CHATLINK binding, which
		-- is not necessarily shift. Testing the key here would re-break it for
		-- anyone who has rebound it.
		local asked = false
		_G.IsShiftKeyDown = function() asked = true; return false end
		IL.Click(LINK)
		assert.is_false(asked)
		assert.equal(1, #calls.handled)
	end)
end)

describe("Click — the fallback chain on a client without the router", function()
	before_each(function()
		_G.HandleModifiedItemClick = nil
		_G.IsShiftKeyDown = function() return true end
	end)

	it("prefers ChatFrameUtil.InsertLink, which is what Classic Era actually has", function()
		_G.ChatFrameUtil = { InsertLink = function(l)
			calls.chatFrameUtil[#calls.chatFrameUtil + 1] = l; return true
		end }
		assert.is_true(IL.Click(LINK))
		assert.same({ LINK }, calls.chatFrameUtil)
	end)

	it("falls back to the deprecated alias only when nothing better exists", function()
		_G.ChatEdit_InsertLink = function(l)
			calls.deprecated[#calls.deprecated + 1] = l; return true
		end
		assert.is_true(IL.Click(LINK))
		assert.same({ LINK }, calls.deprecated)
	end)

	it("falls back last to the active edit box", function()
		_G.ChatEdit_GetActiveWindow = function()
			return { Insert = function(_, l) calls.inserted[#calls.inserted + 1] = l end }
		end
		assert.is_true(IL.Click(LINK))
		assert.same({ LINK }, calls.inserted)
	end)

	it("respects the shift key on the fallback path, where nothing else can", function()
		-- Without the router there is no binding to consult, so this branch is
		-- the one place a raw modifier check is correct.
		_G.IsShiftKeyDown = function() return false end
		_G.ChatFrameUtil = { InsertLink = function(l)
			calls.chatFrameUtil[#calls.chatFrameUtil + 1] = l; return true
		end }
		assert.is_false(IL.Click(LINK))
		assert.equal(0, #calls.chatFrameUtil)
	end)

	it("gives up quietly when the client offers nothing", function()
		assert.is_false(IL.Click(LINK))
	end)
end)

describe("WantsCompare", function()
	it("is true while the compare modifier is held", function()
		_G.IsModifiedClick = function(what) return what == "COMPAREITEMS" end
		assert.is_true(IL.WantsCompare())
	end)

	it("asks for COMPAREITEMS specifically, not for any modifier", function()
		local asked = {}
		_G.IsModifiedClick = function(what) asked[#asked + 1] = what; return false end
		IL.WantsCompare()
		assert.same({ "COMPAREITEMS" }, asked)
	end)

	it("is true when the player has pinned comparisons on via the CVar", function()
		env.wow.cvars.alwaysCompareItems = "1"
		assert.is_true(IL.WantsCompare())
	end)

	it("is false with neither", function()
		assert.is_false(IL.WantsCompare())
	end)
end)

describe("SyncCompare", function()
	it("shows the comparison when it is wanted", function()
		_G.IsModifiedClick = function() return true end
		assert.is_true(IL.SyncCompare({}))
		assert.equal(1, calls.compareShown)
	end)

	it("hides it when it is not", function()
		assert.is_false(IL.SyncCompare({}))
		assert.equal(1, calls.compareHidden)
		assert.equal(0, calls.compareShown)
	end)

	it("does not raise without a tooltip", function()
		assert.is_false(IL.SyncCompare(nil))
	end)
end)

describe("hold-to-compare", function()
	-- The behaviour the request actually asked for: press the modifier while
	-- ALREADY hovering. Blizzard's own frames evaluate the modifier once, when
	-- the tooltip is built, so without a modifier watcher the comparison only
	-- appears if the key was down before the mouse arrived.
	local tip

	before_each(function()
		tip = { _shown = true, IsShown = function(self) return self._shown end }
	end)

	it("re-evaluates when the modifier is pressed during the hover", function()
		IL.BeginHover(tip)
		assert.equal(0, calls.compareShown)

		_G.IsModifiedClick = function() return true end
		env.frames.fireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		assert.equal(1, calls.compareShown)
	end)

	it("takes the comparison away again when the modifier is released", function()
		_G.IsModifiedClick = function() return true end
		IL.BeginHover(tip)
		assert.equal(1, calls.compareShown)

		_G.IsModifiedClick = function() return false end
		env.frames.fireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
		assert.is_true(calls.compareHidden > 0)
	end)

	it("stops listening once the mouse leaves", function()
		IL.BeginHover(tip)
		IL.EndHover(tip)
		_G.IsModifiedClick = function() return true end
		env.frames.fireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		assert.equal(0, calls.compareShown)
	end)

	it("ignores a modifier press for a tooltip that is no longer showing", function()
		-- A row can be released without OnLeave firing (tab switch, window
		-- close). Updating a hidden tooltip would pop a stray comparison.
		IL.BeginHover(tip)
		tip._shown = false
		_G.IsModifiedClick = function() return true end
		env.frames.fireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
		assert.equal(0, calls.compareShown)
	end)

	it("tracks only the most recent hover", function()
		local first  = { IsShown = function() return true end }
		local second = { IsShown = function() return true end }
		IL.BeginHover(first)
		IL.BeginHover(second)
		assert.equal(second, IL._Hovered().tip)
	end)
end)

describe("Tooltip — which frame a curated surface draws into", function()
	local private = { name = "private" }

	it("always uses the caller's private frame when it has one", function()
		-- No longer conditional. The `useStockItemTooltips` setting this used to
		-- consult was deleted: it promised "the game's standard tooltip" for a
		-- recipe, and the game has no such thing — a trade-skill recipe is a
		-- spell, and the only stock recipe tooltips are index-based and valid
		-- only while the profession window is open.
		assert.equal(private, IL.Tooltip(private))
	end)

	it("uses the stock tooltip for a caller with no private frame", function()
		assert.equal(_G.GameTooltip, IL.Tooltip(nil))
	end)
end)

describe("RecipeTooltipSource — which branch a recipe takes", function()
	local ALCHEMY, SPELL, SCROLL = 171, 17187, 12656

	local function profDB(t) ns._profDB = t end

	before_each(function() ns._profDB = nil end)
	-- and after: the cache is session-long, so a leftover stub reaches later
	-- spec FILES, not just later tests.
	after_each(function() ns._profDB = nil end)

	it("says item when a real teaching scroll exists", function()
		profDB({ GetRecipeItem = function(_, id)
			return id == SPELL and SCROLL or nil, false
		end })
		local kind, payload = IL.RecipeTooltipSource(ALCHEMY, SPELL)
		assert.equal("item", kind)
		assert.equal(SCROLL, payload)
	end)

	it("says synthetic when none exists, and hands back the descriptor", function()
		profDB({
			GetRecipeItem = function() return nil, false end,
			GetSyntheticRecipeScroll = function(_, id)
				if id ~= SPELL then return nil end
				return { name = "Plans: Thing", prefix = "Plans: ", professionID = 164,
				         requiredSkill = 200, isSynthetic = true }
			end,
		})
		local kind, rec = IL.RecipeTooltipSource(ALCHEMY, SPELL)
		assert.equal("synthetic", kind)
		assert.equal("Plans: Thing", rec.name)
		assert.is_true(rec.isSynthetic)
	end)

	it("never hands back an item id on the synthetic branch", function()
		-- The upstream constraint, mirrored here so OUR side cannot start
		-- inventing one either. A fabricated id is what eventually reaches
		-- GetItemInfo or an auction search and fails silently.
		profDB({
			GetRecipeItem = function() return nil, false end,
			GetSyntheticRecipeScroll = function()
				return { prefix = "Plans: ", professionID = 164, isSynthetic = true }
			end,
		})
		local _, rec = IL.RecipeTooltipSource(ALCHEMY, SPELL)
		assert.is_nil(rec.itemID)
		assert.is_nil(rec.itemId)
		assert.is_nil(rec.id)
	end)

	it("takes exactly one branch — the two sources are complements", function()
		-- ItemDB's builder asserts the partition on every run. If both ever
		-- answered for one recipe, the real item must win: it is the only one
		-- that produces a genuine tooltip.
		profDB({
			GetRecipeItem = function() return SCROLL, false end,
			GetSyntheticRecipeScroll = function() error("must not be consulted") end,
		})
		assert.equal("item", (IL.RecipeTooltipSource(ALCHEMY, SPELL)))
	end)

	it("returns nothing for a skill-rank book, which is not a recipe", function()
		profDB({
			GetRecipeItem = function() return 16083, true end,
			GetSyntheticRecipeScroll = function() error("must not be consulted") end,
		})
		assert.is_nil((IL.RecipeTooltipSource(ALCHEMY, 7732)))
	end)

	it("returns nothing when neither source knows the recipe", function()
		profDB({ GetRecipeItem = function() return nil, false end,
		         GetSyntheticRecipeScroll = function() return nil end })
		assert.is_nil((IL.RecipeTooltipSource(ALCHEMY, SPELL)))
	end)

	it("survives an ItemDB too old for the synthetic table", function()
		profDB({ GetRecipeItem = function() return nil, false end })   -- MINOR < 18
		assert.is_nil((IL.RecipeTooltipSource(ALCHEMY, SPELL)))
	end)

	it("does not raise without a recipe id", function()
		assert.is_nil((IL.RecipeTooltipSource(ALCHEMY, nil)))
	end)
end)

describe("SetItem", function()
	local tip, seen

	before_each(function()
		seen = {}
		tip = {
			SetHyperlink = function(_, l) seen.link = l end,
			SetItemByID  = function(_, id) seen.id = id end,
			IsShown      = function() return true end,
		}
	end)

	it("prefers the link, which carries enchants and the quality colour", function()
		assert.is_true(IL.SetItem(tip, LINK, 2589))
		assert.equal(LINK, seen.link)
		assert.is_nil(seen.id)
	end)

	it("falls back to the item id when there is no link", function()
		assert.is_true(IL.SetItem(tip, nil, 2589))
		assert.equal(2589, seen.id)
	end)

	it("builds an item: link when the client has no SetItemByID", function()
		tip.SetItemByID = nil
		assert.is_true(IL.SetItem(tip, nil, 2589))
		assert.equal("item:2589", seen.link)
	end)

	it("reports failure when given neither, rather than showing an empty tooltip", function()
		assert.is_false(IL.SetItem(tip, nil, nil))
		assert.is_nil(seen.link)
		assert.is_nil(seen.id)
	end)

	it("registers the hover, so the comparison follows the modifier", function()
		IL.SetItem(tip, LINK)
		assert.equal(tip, IL._Hovered().tip)
	end)

	it("does not raise without a tooltip", function()
		assert.is_false(IL.SetItem(nil, LINK))
	end)
end)
