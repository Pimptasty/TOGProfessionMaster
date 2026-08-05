-- addon.GUI.PersistentScroll.Acquire — the one function five tabs depend on.
--
-- Browser, Missing Recipes, Crafting, Profit Planner and the shopping list all
-- get their ScrollFrame from here, and all of them route their pooled-row
-- cleanup through its `onRelease`. If that wiring breaks, every tab leaks its
-- pool into whatever addon AceGUI recycles the widget into next — five bugs
-- from one line.
--
-- It also carries the LayoutFinished repair, which exists because of a real
-- regression: BrowserTab's virtual-scroll trick overrides the widget's
-- LayoutFinished with a no-op, AceGUI's ScrollFrame keeps methods as INSTANCE
-- fields, and the override therefore survives Release and follows the recycled
-- widget into the next tab — which then can't auto-size its content and loses
-- its scrollbar. Setting it to nil doesn't help either (no metatable fallback,
-- so safecall(nil) is a silent no-op with the same result); it has to be
-- RESTORED. That is only testable against real AceGUI pooling.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, GUI

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
end)

before_each(function()
	env.installFrames()
	GUI = env.aceGUI()
end)

--- A stand-in for a tab module. Acquire only needs a table to hang state on.
local function newTab()
	return {}
end

describe("PersistentScroll.Acquire", function()
	it("wires onRelease so releasing the scroll runs the tab's cleanup", function()
		-- The invariant every DetachPool call site depends on.
		local tab, detached = newTab(), false
		local scroll = ns.GUI.PersistentScroll.Acquire(tab, {
			key = "spec_release",
			onRelease = function() detached = true end,
		})

		GUI:Release(scroll)
		assert.is_true(detached)
	end)

	it("does not carry one tab's cleanup onto the next owner of the widget", function()
		-- AceGUI clears widget.events on release; this asserts we rely on that
		-- correctly rather than re-registering onto a pooled widget.
		local fired = 0
		local first = ns.GUI.PersistentScroll.Acquire(newTab(), {
			key = "spec_owner_a",
			onRelease = function() fired = fired + 1 end,
		})
		GUI:Release(first)
		assert.equal(1, fired)

		local second = ns.GUI.PersistentScroll.Acquire(newTab(), { key = "spec_owner_b" })
		GUI:Release(second)
		assert.equal(1, fired)
	end)

	it("is fine with no onRelease at all", function()
		local scroll = ns.GUI.PersistentScroll.Acquire(newTab(), { key = "spec_no_cb" })
		assert.has_no.errors(function() GUI:Release(scroll) end)
	end)

	it("repairs a LayoutFinished a previous owner overrode", function()
		-- The v0.3.x regression, end to end through AceGUI's real pool.
		local fresh = ns.GUI.PersistentScroll.Acquire(newTab(), { key = "spec_layout" })
		local classLayoutFinished = fresh.LayoutFinished
		assert.is_function(classLayoutFinished)

		-- BrowserTab's virtual-scroll trick, as it was written.
		fresh.LayoutFinished = function() end
		GUI:Release(fresh)

		local recycled = ns.GUI.PersistentScroll.Acquire(newTab(), { key = "spec_layout" })
		assert.equal(classLayoutFinished, recycled.LayoutFinished)
		GUI:Release(recycled)
	end)

	it("repairs a LayoutFinished a previous owner NILLED", function()
		-- Nilling looks like a fix and is not: there is no metatable fallback,
		-- so safecall(nil, ...) is a silent no-op and the content never sizes.
		local fresh = ns.GUI.PersistentScroll.Acquire(newTab(), { key = "spec_layout_nil" })
		local classLayoutFinished = fresh.LayoutFinished
		fresh.LayoutFinished = nil
		GUI:Release(fresh)

		local recycled = ns.GUI.PersistentScroll.Acquire(newTab(), { key = "spec_layout_nil" })
		assert.equal(classLayoutFinished, recycled.LayoutFinished)
		GUI:Release(recycled)
	end)

	it("hands back the saved position and zeroes the live one", function()
		-- Acquire must capture the saved value BEFORE the caller's FillRows can
		-- fire FixScroll, which writes scrollvalue=0 through the status table.
		local tab = newTab()
		local scroll = ns.GUI.PersistentScroll.Acquire(tab, { key = "spec_saved" })
		tab._scrollStatus.scrollvalue = 42
		tab._scrollStatus.offset      = 640
		GUI:Release(scroll)

		local scroll2, saved = ns.GUI.PersistentScroll.Acquire(tab, { key = "spec_saved" })
		assert.equal(42, saved)
		assert.equal(640, scroll2._persistOffset)
		-- Zeroed, so a synchronous FixScroll during FillRows writes harmless
		-- values rather than corrupting what we just captured.
		assert.equal(0, tab._scrollStatus.scrollvalue)
		assert.is_nil(tab._scrollStatus.offset)
		GUI:Release(scroll2)
	end)

	it("keeps each key's scroll position separate", function()
		-- Two tabs open in one session must not drag each other's list around.
		local a, b = newTab(), newTab()
		local sa = ns.GUI.PersistentScroll.Acquire(a, { key = "spec_key_a" })
		a._scrollStatus.scrollvalue = 10
		GUI:Release(sa)

		local sb = ns.GUI.PersistentScroll.Acquire(b, { key = "spec_key_b" })
		b._scrollStatus.scrollvalue = 99
		GUI:Release(sb)

		local _, savedA = ns.GUI.PersistentScroll.Acquire(a, { key = "spec_key_a" })
		assert.equal(10, savedA)
	end)

	it("persists a key's position in the character DB, not on the tab", function()
		-- A tab module is rebuilt freely; the position has to outlive it.
		local scroll = ns.GUI.PersistentScroll.Acquire(newTab(), { key = "spec_persist" })
		GUI:Release(scroll)
		local store = ns.lib.db.char.frames.scrollTabs
		assert.is_truthy(store["spec_persist"])
	end)

	it("still works for a caller that passes no key", function()
		-- Keyless callers get a per-tab status table rather than a stored one.
		local tab = newTab()
		local scroll = ns.GUI.PersistentScroll.Acquire(tab, {})
		assert.is_truthy(tab._scrollStatus)
		assert.equal(tab._scrollStatus, scroll.status or scroll.localstatus)
		GUI:Release(scroll)
	end)
end)
