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

local ns, GUI

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
end)

before_each(function()
	-- installFrames() INSTEAD of install(): install() ends in wow.reset(),
	-- which puts the hollow frame back and every assertion below would then be
	-- measuring a no-op that returns nothing.
	env.installFrames()
	GUI = env.aceGUI()
end)

-- GUI.DetachPool was removed in v1.1.3 (LAGW adoption step 7): no tab keeps a
-- raw row pool any more. Every list is a library RowList parked through
-- GUI.ParkList, whose host goes back to UIParent through the library's
-- AttachRawFrames when the draw's group is released.

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
