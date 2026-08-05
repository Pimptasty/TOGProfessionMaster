-- The two GUI helpers that exist because AceGUI RECYCLES widgets, and what
-- rides along on a recycled one leaks into whatever addon gets it next.
--
-- Both were written after the fact, from bugs that only show up in someone
-- else's UI: pooled rows still parented to a released widget appearing inside
-- another addon's window, and a raw frame script overwriting the constructor's
-- own dispatcher so the next owner's SetCallback never fires. Neither is
-- reachable by a logic spec — they are statements about frame parentage and
-- script tables — so until the harness grew `env/frames.lua` they had no
-- coverage at all.
--
-- These run against the REAL AceGUI-3.0 and the rich widget layer, so
-- `SetParent` really re-parents, `GetScript` really returns what was set, and
-- AceGUI's real Release/Create pooling is what hands the widget back.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, GUI, frames

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
end)

before_each(function()
	-- installFrames() INSTEAD of install(): install() ends in wow.reset(),
	-- which puts the hollow frame back and every assertion below would then be
	-- measuring a no-op that returns nothing.
	frames = env.installFrames()
	GUI = env.aceGUI()
end)

--- A tab's virtual-scroll row pool: raw frames parented to an AceGUI widget's
--- content frame, exactly as BrowserTab and CooldownsTab build them.
local function newPool(parent, count)
	local pool = {}
	for i = 1, count do
		local row = CreateFrame("Frame", nil, parent)
		row:SetSize(400, 20)
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -20 * (i - 1))
		row:Show()
		pool[i] = row
	end
	return pool
end

describe("GUI.DetachPool", function()
	it("orphans every pooled row onto UIParent", function()
		local group = GUI:Create("SimpleGroup")
		local pool  = newPool(group.content, 5)

		-- Precondition, asserted rather than assumed: without it a passing
		-- detach test could be passing because nothing was ever attached.
		for _, row in ipairs(pool) do
			assert.equal(group.content, row:GetParent())
		end

		ns.GUI.DetachPool(pool)

		for _, row in ipairs(pool) do
			assert.equal(UIParent, row:GetParent())
			assert.is_false(row:IsShown())
			-- Unanchored, so it cannot be dragged along by the old parent's
			-- geometry if the widget is repositioned by its next owner.
			assert.is_nil(row:GetLeft())
		end
	end)

	it("keeps the frames in the pool for the next attach", function()
		-- Raw frames are session-lifetime and never GC'd; detaching must orphan
		-- them, not discard them, or every tab switch leaks a new pool.
		local group = GUI:Create("SimpleGroup")
		local pool  = newPool(group.content, 3)
		local first = pool[1]

		ns.GUI.DetachPool(pool)

		assert.equal(3, #pool)
		assert.equal(first, pool[1])
	end)

	it("takes a single frame as well as a pool", function()
		-- MainWindow's help "i" icon: one CreateFrame parented to the AceGUI
		-- Frame, no pool, same cleanup required.
		local group = GUI:Create("SimpleGroup")
		local icon  = CreateFrame("Frame", nil, group.content)
		icon:SetSize(16, 16)
		icon:SetPoint("TOPRIGHT", group.content, "TOPRIGHT", 0, 0)
		icon:Show()

		ns.GUI.DetachPool(icon)

		assert.equal(UIParent, icon:GetParent())
		assert.is_false(icon:IsShown())
	end)

	it("does nothing when handed nil", function()
		assert.has_no.errors(function() ns.GUI.DetachPool(nil) end)
	end)

	it("survives a hole in the pool array", function()
		local group = GUI:Create("SimpleGroup")
		local pool  = newPool(group.content, 2)
		pool[3] = false   -- a slot a tab cleared without shrinking the array
		assert.has_no.errors(function() ns.GUI.DetachPool(pool) end)
		assert.equal(UIParent, pool[1]:GetParent())
	end)

	it("leaves nothing of ours on the widget AceGUI hands out next", function()
		-- The actual bug this helper exists for. Release the group and take it
		-- back out of the pool: the rows must not still be riding on it.
		local group = GUI:Create("SimpleGroup")
		local pool  = newPool(group.content, 4)
		ns.GUI.DetachPool(pool)
		GUI:Release(group)

		local recycled = GUI:Create("SimpleGroup")
		for _, row in ipairs(pool) do
			assert.is_not.equal(recycled.content, row:GetParent())
		end
	end)
end)

describe("AceGUIFrameScripts", function()
	it("installs the script on the widget's own frame", function()
		local group = GUI:Create("SimpleGroup")
		local hits  = 0

		ns.AceGUIFrameScripts(group, {
			OnMouseDown = function(_, button) hits = button end,
		})

		group.frame:GetScript("OnMouseDown")(group.frame, "RightButton")
		assert.equal("RightButton", hits)
	end)

	it("RESTORES the prior script on release, rather than nilling it", function()
		-- The whole reason the helper exists. Many AceGUI constructors install
		-- their own dispatcher on the frame; nilling it on release both leaks
		-- into the next owner and breaks that widget's SetCallback.
		local group = GUI:Create("SimpleGroup")
		local prior = function() end
		group.frame:SetScript("OnMouseDown", prior)

		ns.AceGUIFrameScripts(group, { OnMouseDown = function() end })
		assert.is_not.equal(prior, group.frame:GetScript("OnMouseDown"))

		GUI:Release(group)
		assert.equal(prior, group.frame:GetScript("OnMouseDown"))
	end)

	it("clears a script that had no prior handler", function()
		local group = GUI:Create("SimpleGroup")
		-- AceGUI hands widgets back out of a pool, so this one may carry a
		-- script an earlier test legitimately RESTORED. Establish the
		-- precondition rather than assume it — asserting it would be testing
		-- the pool's contents, not this helper.
		group.frame:SetScript("OnMouseDown", nil)
		assert.is_nil(group.frame:GetScript("OnMouseDown"))

		ns.AceGUIFrameScripts(group, { OnMouseDown = function() end })
		GUI:Release(group)

		assert.is_nil(group.frame:GetScript("OnMouseDown"))
	end)

	it("does not fire for the next owner of a recycled widget", function()
		-- Pool recycling, end to end through AceGUI's own Release/Create.
		local group, fired = GUI:Create("SimpleGroup"), false
		ns.AceGUIFrameScripts(group, {
			OnMouseDown = function() fired = true end,
		})
		GUI:Release(group)

		local recycled = GUI:Create("SimpleGroup")
		local handler  = recycled.frame:GetScript("OnMouseDown")
		if handler then handler(recycled.frame, "LeftButton") end
		assert.is_false(fired)
	end)

	it("restores every event it was given, not just the first", function()
		local group = GUI:Create("SimpleGroup")
		local a, b = function() end, function() end
		group.frame:SetScript("OnMouseDown", a)
		group.frame:SetScript("OnMouseUp", b)

		ns.AceGUIFrameScripts(group, {
			OnMouseDown = function() end,
			OnMouseUp   = function() end,
		})
		GUI:Release(group)

		assert.equal(a, group.frame:GetScript("OnMouseDown"))
		assert.equal(b, group.frame:GetScript("OnMouseUp"))
	end)

	it("ignores a widget with no frame, and a nil script table", function()
		assert.has_no.errors(function() ns.AceGUIFrameScripts(nil, {}) end)
		assert.has_no.errors(function() ns.AceGUIFrameScripts({}, {}) end)
		assert.has_no.errors(function() ns.AceGUIFrameScripts(GUI:Create("SimpleGroup"), nil) end)
	end)
end)
