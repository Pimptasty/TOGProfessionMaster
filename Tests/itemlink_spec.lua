-- addon.ItemLink — the one implementation of clicking and hovering an item.
--
-- This exists because there were THREE, and they were not equivalent:
--
--   HandleModifiedItemClick(link)   Cooldowns, Crafting, AH Profit
--   ChatEdit_InsertLink(link)       Browser x3, Reagent Tracker, Compat
--   editBox:Insert(link)            Missing Recipes, Shopping List
--
-- The middle one was a live bug, not just an inconsistency. `ChatEdit_InsertLink`
-- is NOT a Classic Era API: Blizzard defines it only inside
-- Blizzard_DeprecatedChatInfo, behind `GetCVarBool("loadDeprecationFallbacks")`,
-- as an alias for ChatFrameUtil.InsertLink. With that CVar off the global is
-- nil, so three call sites silently did nothing and three raised a nil-call
-- error at the click. The regression test for that is
-- "works on a client with no ChatEdit_InsertLink at all", below.
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

	-- A client that looks like Classic Era: the modern router is present, the
	-- deprecated alias is NOT.
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

	it("works on a client with no ChatEdit_InsertLink at all", function()
		-- The regression. Classic Era has no such global unless the
		-- deprecation-fallback CVar is on, and the old code either called it
		-- unguarded (error) or guarded it and silently did nothing.
		assert.is_nil(_G.ChatEdit_InsertLink)
		assert.is_true(IL.Click(LINK))
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

describe("Tooltip — curated versus stock", function()
	local private = { name = "private" }

	it("uses the caller's private frame by default", function()
		assert.equal(private, IL.Tooltip(private))
	end)

	it("uses the stock GameTooltip once the setting is on", function()
		ns.lib.db.profile.useStockItemTooltips = true
		assert.equal(_G.GameTooltip, IL.Tooltip(private))
	end)

	it("defaults to OFF, so nobody is opted into third-party tooltip hooks", function()
		-- The setting exists to let other addons' hooks fire on our rows. Those
		-- hooks are also what crash on recipe scrolls, which is why the private
		-- frame exists at all — so the default has to be the safe one.
		assert.is_not_true(ns.lib.db.profile.useStockItemTooltips)
		assert.equal(private, IL.Tooltip(private))
	end)

	it("uses the stock tooltip for a caller that has no private frame", function()
		assert.equal(_G.GameTooltip, IL.Tooltip(nil))
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
