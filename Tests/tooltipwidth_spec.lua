-- Tooltip WIDTH — the two regressions of 2026-08-08, in opposite directions.
--
-- `Tests/tooltipwrapflag_spec.lua` sweeps our SOURCE for the wrap flag. It is a
-- text search and it cannot see either failure this file pins:
--
--   * it is blind to a THIRD PARTY drawing into a tooltip we own, which is what
--     made the recipe tooltip too WIDE (ATT's breadcrumb, unwrapped);
--   * and it would have happily passed the fix that made it too NARROW, because
--     wrapping every line including the title is exactly what "every line passes
--     the flag" asks for.
--
-- Both shipped. The second only surfaced because the user looked at it.
--
-- These are behavioural instead, using the harness width oracle delivered in
-- `3ec5737` (Tests/HARNESS_CONTRACT.md, raised after a session in which every
-- width claim made offline was wrong). `frames.setStringWidth` declares what a
-- string measures, and `GameTooltip:GetWidth()` is a function of the lines:
--   * a WRAPPING line contributes nothing — it constrains no width;
--   * a double line costs left + tooltipDoubleGap + right;
--   * the result is floored by SetMinimumWidth.
--
-- The pixel numbers are the harness's own arbitrary geometry, NOT Blizzard's.
-- What is being asserted is the arithmetic's SHAPE — that an unwrapped long line
-- widens the frame and a wrapped one does not — which is the logic both bugs got
-- wrong. Do not read these numbers as client behaviour.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local SPELL_ID, CRAFTED_ID = 3967, 4394

-- Long enough that it would visibly stretch a tooltip, short enough to read.
-- The real one measured 583.1px against a 603.6px frame in game.
local BREADCRUMB = "ATT > Zone > Kalimdor > Tanaris > Professions > Engineering"
local TITLE      = "Schematic: Advanced Target Dummy"

local ns, IL, frames
local real = {}

setup(function()
	ns = env.initDb()
	frames = env.installFrames()
	env.loadModule("GUI/SharedWidgets.lua")
	IL = ns.ItemLink
	real.Bank, real.Price, real.GetItemDB = ns.Bank, ns.Price, ns.GetItemDB
end)

before_each(function()
	frames = env.installFrames()
	env.resetDb()
	-- Declared widths are reset per file by the harness, so they are stated here
	-- rather than assumed to survive from another spec.
	frames.setStringWidth(BREADCRUMB, 580)
	frames.setStringWidth(TITLE, 300)
	ns.Bank, ns.Price = nil, nil
	ns.GetItemDB = function() return nil end
end)

-- Put back what this file blanks. `ns` is the ONE addon table the whole suite
-- shares, so anything left nil here is still nil in every LATER spec file — and
-- only a full-suite run shows it. Leaving `ns.GetItemDB` stubbed to nil took out
-- two `vendorprices_spec` cases whose subject is the LibItemDB fallback, with no
-- visible connection to this file; both passed when this file ran alone.
after_each(function()
	ns.Bank, ns.Price, ns.GetItemDB = real.Bank, real.Price, real.GetItemDB
end)

--- A fresh GameTooltip with nothing on it.
local function newTip()
	local tip = _G.GameTooltip
	tip:ClearLines()
	return tip
end

describe("an unwrapped line sets the frame — which is the whole mechanism", function()
	it("a long UNWRAPPED line widens the tooltip", function()
		local tip = newTip()
		tip:AddLine(TITLE)
		local narrow = tip:GetWidth()

		tip:AddLine(BREADCRUMB)
		assert.is_true(tip:GetWidth() > narrow)
	end)

	it("the SAME line wrapped does not widen it", function()
		-- Cause and effect, the way round the five-hour misdiagnosis had them.
		local tip = newTip()
		tip:AddLine(TITLE)
		local narrow = tip:GetWidth()

		tip:AddLine(BREADCRUMB, nil, nil, nil, true)
		assert.equal(narrow, tip:GetWidth())
	end)

	it("a tooltip whose EVERY line wraps derives no width at all", function()
		-- The too-narrow bug, stated as arithmetic. Nothing claims a natural
		-- width, so there is nothing for the frame to size to and it falls back
		-- to the bare preset — which in game rendered the item name on two lines.
		local tip = newTip()
		tip:AddLine(TITLE, nil, nil, nil, true)
		tip:AddLine(BREADCRUMB, nil, nil, nil, true)
		assert.equal(0, tip:GetWidth())
	end)

	it("leaving the title unwrapped is what gives it one back", function()
		local tip = newTip()
		tip:AddLine(TITLE)
		tip:AddLine(BREADCRUMB, nil, nil, nil, true)
		assert.is_true(tip:GetWidth() > 0)
	end)
end)

describe("the shim is what stops a third party setting our width", function()
	it("WITHOUT it, a foreign unwrapped line widens the tooltip", function()
		-- This is the shipped bug: LibItemDB hands the tooltip to ATT's renderer,
		-- ATT omits the flag on breadcrumbs, and the frame follows.
		local tip = newTip()
		tip:AddLine(TITLE)
		local narrow = tip:GetWidth()

		ns.GetItemDB = function()
			-- Third parameter named so the stub's arity matches the real
			-- `lib:AttachExternalRecipeInfo(tooltip, spellID)`.
			return { AttachExternalRecipeInfo = function(_, tt, _spellID)
				tt:AddLine(BREADCRUMB)
			end }
		end
		-- Call the bridge directly, bypassing the shim, to prove the premise
		-- rather than assume it.
		local idb = ns:GetItemDB()
		idb:AttachExternalRecipeInfo(tip, SPELL_ID)
		assert.is_true(tip:GetWidth() > narrow)
	end)

	it("WITH it, the identical call leaves the width alone", function()
		local tip = newTip()
		tip:AddLine(TITLE)
		local narrow = tip:GetWidth()

		ns.GetItemDB = function()
			-- Third parameter named so the stub's arity matches the real
			-- `lib:AttachExternalRecipeInfo(tooltip, spellID)`.
			return { AttachExternalRecipeInfo = function(_, tt, _spellID)
				tt:AddLine(BREADCRUMB)
			end }
		end
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)

		assert.equal(narrow, tip:GetWidth())
	end)

	it("and the line is still THERE — it wraps, it is not dropped", function()
		-- A width fix that silently loses the content would pass the assertion
		-- above and be worse than the bug.
		local tip = newTip()
		ns.GetItemDB = function()
			-- Third parameter named so the stub's arity matches the real
			-- `lib:AttachExternalRecipeInfo(tooltip, spellID)`.
			return { AttachExternalRecipeInfo = function(_, tt, _spellID)
				tt:AddLine(BREADCRUMB)
			end }
		end
		IL.AppendIntegrations(tip, SPELL_ID, CRAFTED_ID)

		local found = false
		for _, line in ipairs(tip._lines or {}) do
			if line.left == BREADCRUMB then found = true end
		end
		assert.is_true(found)
	end)
end)

describe("a double line costs BOTH halves, not the wider one", function()
	it("sums left + gap + right", function()
		-- Got wrong in front of the user as max(left, right), which understated
		-- every double line in the width probe's report.
		frames.setStringWidth("Requires", 100)
		frames.setStringWidth("Engineering (185)", 200)

		local tip = newTip()
		tip:AddDoubleLine("Requires", "Engineering (185)")
		local expected = 100 + frames.tooltipDoubleGap + 200 + frames.tooltipPadding * 2
		assert.equal(expected, tip:GetWidth())
	end)

	it("so a double line can beat a longer single one", function()
		frames.setStringWidth("Requires", 100)
		frames.setStringWidth("Engineering (185)", 200)
		frames.setStringWidth("a single line", 250)

		local tip = newTip()
		tip:AddLine("a single line")
		local single = tip:GetWidth()

		tip:AddDoubleLine("Requires", "Engineering (185)")
		assert.is_true(tip:GetWidth() > single)
	end)
end)
