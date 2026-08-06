-- CraftingTab:ScrollToRow — putting a selected recipe on screen.
--
-- Pure geometry over a real AceGUI ScrollFrame, and the first thing in this
-- addon's virtual-scroll code that has ever been testable: it needs
-- GetHeight() to return what was set, which the hollow frame model could not
-- do. Every branch here is an off-by-one waiting to happen — scroll up with
-- context, scroll down with context, clamp at both ends, and do nothing at all
-- when the row is already visible (which, if it fired anyway, would yank the
-- list under the user every time they clicked a row).
--
-- Row height is 16 and AceGUI's scroll value is a 0..1000 fraction of the
-- scrollable range, so the arithmetic below is stated in those terms rather
-- than recomputed from the source.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, GUI, CT

local ROW  = 16     -- ROW_HEIGHT in GUI/CraftingTab.lua
local VIEW = 100    -- visible height
local TALL = 500    -- content height; scrollable range is TALL - VIEW = 400

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/CraftingTab.lua")
	CT = ns.CraftingTab
end)

before_each(function()
	env.installFrames()
	GUI = env.aceGUI()
end)

--- A scroll widget sized so the maths has something real to work on, plus a
--- reader for whatever scroll value the code asked for.
---
--- SetScroll is overridden on the INSTANCE and restored by the caller: AceGUI
--- keeps ScrollFrame methods as instance fields and does not reset them on
--- release, so leaving it would follow the pooled widget into its next owner.
--- That is the same hazard Tests/gui_scroll_spec.lua covers for LayoutFinished.
local function fixture(opts)
	opts = opts or {}
	local scroll = GUI:Create("ScrollFrame")
	scroll.scrollframe:SetHeight(opts.view or VIEW)
	scroll.content:SetHeight(opts.total or TALL)

	local status = scroll.status or scroll.localstatus
	status.offset = opts.offset or 0

	-- Record EVERY SetScroll call and read the FIRST one. This matters: AceGUI
	-- wires the scrollbar's OnValueChanged back into SetScroll, and the slider
	-- clamps to its own 0..1000 range — so the last value seen is the
	-- scrollbar's re-clamp, not what ScrollToRow computed. Reading it made two
	-- of these tests assert AceGUI's clamping rather than the addon's, and both
	-- survived deleting the addon's clamp entirely.
	local calls = {}
	local origSetScroll = scroll.SetScroll
	scroll.SetScroll = function(_, v) calls[#calls + 1] = v end

	return {
		tab     = { _scroll = scroll },
		value   = function() return calls[1] end,
		release = function()
			scroll.SetScroll = origSetScroll
			GUI:Release(scroll)
		end,
	}
end

describe("ScrollToRow", function()
	it("does nothing when everything already fits on screen", function()
		local f = fixture({ total = 50 })
		CT.ScrollToRow(f.tab, 3)
		assert.is_nil(f.value())
		f.release()
	end)

	it("does nothing when the row is already fully visible", function()
		-- Row 2 spans 16..32 with 0..100 on screen. Scrolling here would jerk
		-- the list every time the user clicked a recipe they could already see.
		local f = fixture({ offset = 0 })
		CT.ScrollToRow(f.tab, 2)
		assert.is_nil(f.value())
		f.release()
	end)

	it("scrolls down far enough to show a row below the viewport", function()
		-- Row 20 spans 304..320. Bringing its bottom into a 100-high view and
		-- leaving two rows of context puts the target at 320-100+32 = 252,
		-- which is 252/400 of the range.
		local f = fixture({ offset = 0 })
		CT.ScrollToRow(f.tab, 20)
		assert.equal(252 / 400 * 1000, f.value())
		f.release()
	end)

	it("scrolls up to a row above the viewport", function()
		-- Row 6 spans 80..96, scrolled past at offset 200. Target is its top
		-- less two rows of context: 80-32 = 48.
		local f = fixture({ offset = 200 })
		CT.ScrollToRow(f.tab, 6)
		assert.equal(48 / 400 * 1000, f.value())
		f.release()
	end)

	it("never asks to scroll above the top", function()
		-- Row 1's context rows would put the target at -32.
		local f = fixture({ offset = 200 })
		CT.ScrollToRow(f.tab, 1)
		assert.equal(0, f.value())
		f.release()
	end)

	it("never asks to scroll past the bottom", function()
		-- Row 31 spans 480..496; the target would exceed the 400 range.
		local f = fixture({ offset = 0 })
		CT.ScrollToRow(f.tab, 31)
		assert.equal(1000, f.value())
		f.release()
	end)

	it("moves the scrollbar as well as the content", function()
		-- Both, or the thumb ends up disagreeing with what is on screen.
		local f = fixture({ offset = 0 })
		local scroll = f.tab._scroll
		local barValue
		local origSetValue = scroll.scrollbar and scroll.scrollbar.SetValue
		if scroll.scrollbar then
			scroll.scrollbar.SetValue = function(_, v) barValue = v end
		end
		CT.ScrollToRow(f.tab, 20)
		assert.equal(f.value(), barValue)
		if scroll.scrollbar then scroll.scrollbar.SetValue = origSetValue end
		f.release()
	end)

	it("ignores a call before the list exists", function()
		assert.has_no.errors(function() CT.ScrollToRow({}, 5) end)
		assert.has_no.errors(function() CT.ScrollToRow({ _scroll = {} }, 5) end)
	end)

	it("ignores a nil row index", function()
		local f = fixture({})
		assert.has_no.errors(function() CT.ScrollToRow(f.tab, nil) end)
		assert.is_nil(f.value())
		f.release()
	end)
end)
