-- How the [TOGPM] tooltip lines get INVOKED, as opposed to what they say.
--
-- `tooltip_spec.lua` covers the content — who crafts this, the id footer. This
-- file covers the wiring underneath it, which was the whole of the uncovered
-- half of Tooltip.lua: three independent hook paths, a dedup shared between
-- them, and a deliberate two-second delay.
--
-- Worth its own file because a break here is invisible to every content spec.
-- AppendCrafters can be perfect and the addon still show nothing in game if
-- nobody calls it — a green suite over a dead feature. Each of the three
-- properties below is a bug this addon has already had, recorded in the source
-- comments; the specs exist so they cannot come back quietly.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")
local wow    = require("env.wow")
local frames = require("env.frames")

local ns, Ace, savedGlobals
local POTION = 118

--- A tooltip frame that records hooks and lines, standing in for GameTooltip and
--- friends. Deliberately hand-built rather than an env frame: what is under test
--- is which scripts and Show-hooks get attached, so they have to be observable.
local function fakeTooltip(name)
	local t = { _name = name, lines = {}, scripts = {}, showHooks = {} }
	t.AddLine    = function(_, text) t.lines[#t.lines + 1] = tostring(text) end
	t.HookScript = function(_, ev, fn) t.scripts[ev] = t.scripts[ev] or {}; table.insert(t.scripts[ev], fn) end
	t.Show       = function() end
	t.GetItem    = function() return t._itemName, t._itemLink end
	-- Enough of a tooltip to survive OTHER specs' deferred work. `advanceTime`
	-- runs every pending timer in the session, not just ours, so a layout
	-- callback queued by an earlier spec file lands on whatever GameTooltip is
	-- installed at that moment — this one. A minimal fake made AceGUI's TabGroup
	-- die on `GameTooltip:IsOwned` inside our own test.
	t.IsOwned    = function() return false end
	t.SetOwner   = function() end
	t.Hide       = function() end
	t.ClearLines = function() t.lines = {} end
	t.NumLines   = function() return #t.lines end
	t.IsShown    = function() return true end
	t.SetText    = function() end
	t.SetItem    = function(_, id)
		t._itemName, t._itemLink = "Item", "|cffffffff|Hitem:" .. id .. "|h[x]|h|r"
	end
	return t
end

local TOOLTIP_GLOBALS = { "GameTooltip", "ItemRefTooltip",
                          "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3" }

local function installTooltipFrames()
	local made = {}
	for _, n in ipairs(TOOLTIP_GLOBALS) do
		made[n] = fakeTooltip(n)
		_G[n] = made[n]
	end
	return made
end

--- Re-run Tooltip.lua's PLAYER_LOGIN registration against the current globals.
local function login()
	frames.fireEvent("PLAYER_LOGIN")
end

setup(function()
	ns = env.initDb()
	env.loadModule("Tooltip.lua")
	Ace = ns.lib
end)

before_each(function()
	env.install()
	local gdb = env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({
		[171] = { [2330] = { name = "Minor Healing Potion", craftedItemId = POTION, teaches = 2330 } },
	})
	gdb.recipes[171] = { [2330] = { crafters = { ["Bob-Testrealm"] = ns:GetCurrentGuildTag() } } }
	_G.GetItemInfo = function() return nil end
	Ace.db.profile.tooltipShowCrafters = true
	Ace.db.profile.tooltipShowIds      = false

	savedGlobals = {}
	for _, n in ipairs(TOOLTIP_GLOBALS) do savedGlobals[n] = _G[n] end
	savedGlobals.TooltipDataProcessor = _G.TooltipDataProcessor
end)

-- Put the real tooltip frames back. These are GLOBALS, not per-test state, and
-- the fakes here are deliberately minimal — no IsOwned, no SetOwner. Leaving one
-- behind broke AceGUI's TabGroup in a later spec FILE
-- (AceGUIContainer-TabGroup.lua:136 calls GameTooltip:IsOwned), miles from the
-- cause. Same rule the env follows: reinstall everything you own, every reset.
after_each(function()
	for _, n in ipairs(TOOLTIP_GLOBALS) do _G[n] = savedGlobals[n] end
	_G.TooltipDataProcessor = savedGlobals.TooltipDataProcessor
end)

-- ---------------------------------------------------------------------------

describe("which tooltip frames get hooked", function()
	it("hooks all five, not just GameTooltip", function()
		-- ItemRefTooltip is the one a CHAT LINK opens, and the ShoppingTooltips
		-- are the comparison panes. Missing them means the crafters line appears
		-- on a bag hover and vanishes on a linked item, which reads as the data
		-- being wrong rather than the hook being absent.
		local frames = installTooltipFrames()
		login()
		for name, tt in pairs(frames) do
			assert.is_truthy(tt.scripts["OnTooltipSetItem"],
				name .. " never got an OnTooltipSetItem hook")
		end
	end)

	it("hooks OnTooltipCleared too, on every frame", function()
		local frames = installTooltipFrames()
		login()
		for name, tt in pairs(frames) do
			assert.is_truthy(tt.scripts["OnTooltipCleared"], name .. " never got a cleared hook")
		end
	end)

	it("survives a client missing some of those frames", function()
		installTooltipFrames()
		_G.ShoppingTooltip2, _G.ShoppingTooltip3 = nil, nil
		assert.has_no.errors(login)
		assert.is_truthy(_G.GameTooltip.scripts["OnTooltipSetItem"])
	end)
end)

describe("the legacy hook registers UNCONDITIONALLY", function()
	it("is installed even when the modern path is available", function()
		-- THE TBC ANNIVERSARY BUG, and the reason the source says "register
		-- UNCONDITIONALLY (not in an else branch)". That client advertises
		-- TooltipDataProcessor — so a hasModern check passes — but never fires
		-- the PostCall on an item hover. Put this in an else and the entire
		-- tooltip extension goes silent there, with every content spec still
		-- green.
		local frames = installTooltipFrames()
		_G.TooltipDataProcessor = { AddTooltipPostCall = function() end }
		_G.Enum = _G.Enum or {}
		_G.Enum.TooltipDataType = { Item = 1 }
		login()
		assert.is_truthy(frames.GameTooltip.scripts["OnTooltipSetItem"],
			"legacy hook was skipped because the modern path looked available")
	end)

	it("registers the modern post-call when the client offers one", function()
		installTooltipFrames()
		local registered = {}
		_G.TooltipDataProcessor = {
			AddTooltipPostCall = function(kind, fn) registered[#registered + 1] = { kind, fn } end,
		}
		_G.Enum = _G.Enum or {}
		_G.Enum.TooltipDataType = { Item = 7 }
		login()
		assert.equal(1, #registered)
		assert.equal(7, registered[1][1])
	end)

	it("does not reach for the modern path when the client has none", function()
		installTooltipFrames()
		_G.TooltipDataProcessor = nil
		assert.has_no.errors(login)
		assert.is_truthy(_G.GameTooltip.scripts["OnTooltipSetItem"])
	end)

	it("appends through the modern post-call when it does fire", function()
		installTooltipFrames()
		local postCall
		_G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
		_G.Enum = _G.Enum or {}
		_G.Enum.TooltipDataType = { Item = 1 }
		login()
		assert.is_function(postCall)
		-- The tooltip must actually be showing the item: AppendCrafters
		-- re-verifies that before appending, because the append can be deferred
		-- and the player may have hovered off by then.
		_G.GameTooltip:SetItem(POTION)
		postCall(_G.GameTooltip, { id = POTION })
		assert.is_truthy(table.concat(_G.GameTooltip.lines, "\n"):find("Bob", 1, true))
	end)
end)

describe("the dedup that stops three paths tripling the lines", function()
	it("appends once when two paths fire for the same tooltip", function()
		installTooltipFrames()
		local postCall
		_G.TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
		_G.Enum = _G.Enum or {}
		_G.Enum.TooltipDataType = { Item = 1 }
		login()

		local tt = _G.GameTooltip
		tt:SetItem(POTION)
		postCall(tt, { id = POTION })
		for _, fn in ipairs(tt.scripts["OnTooltipSetItem"]) do fn(tt) end

		local hits = select(2, table.concat(tt.lines, "\n"):gsub("Bob", ""))
		assert.equal(1, hits)
	end)

	it("clears the flag so the NEXT item gets its lines", function()
		-- Without this the crafters line appears once per session and never
		-- again, which looks exactly like missing data.
		installTooltipFrames()
		login()
		local tt = _G.GameTooltip
		tt:SetItem(POTION)
		for _, fn in ipairs(tt.scripts["OnTooltipSetItem"]) do fn(tt) end
		assert.is_truthy(table.concat(tt.lines, "\n"):find("Bob", 1, true))

		for _, fn in ipairs(tt.scripts["OnTooltipCleared"]) do fn(tt) end
		tt.lines = {}
		for _, fn in ipairs(tt.scripts["OnTooltipSetItem"]) do fn(tt) end
		assert.is_truthy(table.concat(tt.lines, "\n"):find("Bob", 1, true))
	end)
end)

describe("the Show-hook fallback", function()
	it("is deferred, not registered immediately", function()
		-- DELIBERATE, and the reason is ordering rather than performance:
		-- hooksecurefunc fires in registration order, and TOGProfessionMaster
		-- loads before Wowhead_Looter alphabetically. Registering at once put
		-- our lines ABOVE Wowhead's instead of at the bottom of the chain —
		-- the reported TBC Anniversary complaint.
		installTooltipFrames()
		local hooked = 0
		local realHook = _G.hooksecurefunc
		_G.hooksecurefunc = function(...) hooked = hooked + 1; return realHook(...) end

		login()
		assert.equal(0, hooked, "Show-hook registered immediately; the ordering delay is gone")

		wow.advanceTime(3)
		assert.is_true(hooked > 0, "Show-hook never registered after the delay")
		_G.hooksecurefunc = realHook
	end)

	it("registers straight away on a client with no C_Timer", function()
		installTooltipFrames()
		local savedTimer = _G.C_Timer
		_G.C_Timer = nil
		local hooked = 0
		local realHook = _G.hooksecurefunc
		_G.hooksecurefunc = function(...) hooked = hooked + 1; return realHook(...) end

		login()
		assert.is_true(hooked > 0, "no deferral available, so it should have registered inline")

		_G.hooksecurefunc = realHook
		_G.C_Timer = savedTimer
	end)

	it("dedups on the ITEM ID, not on a truthy flag", function()
		-- A past bug, called out in the source. On the modern engine
		-- OnTooltipCleared may never fire between two tooltips, so a plain
		-- `if self._togpmAppended then return end` stayed set from the previous
		-- item and swallowed every hover after the first. Keying the check on
		-- the item id means a NEW item still appends.
		installTooltipFrames()
		login()
		wow.advanceTime(3)

		local tt = _G.GameTooltip
		tt._togpmAppended = 99999           -- a DIFFERENT item, flag still set
		tt:SetItem(POTION)
		tt:Show()
		assert.is_truthy(table.concat(tt.lines, "\n"):find("Bob", 1, true),
			"a stale flag from another item swallowed this one")
	end)

	it("stays quiet for a tooltip showing no item", function()
		installTooltipFrames()
		login()
		wow.advanceTime(3)
		local tt = _G.GameTooltip
		assert.has_no.errors(function() tt:Show() end)
		assert.equal(0, #tt.lines)
	end)
end)
