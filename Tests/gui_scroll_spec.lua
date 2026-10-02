-- addon.GUI.ListScroll — where every tab's list keeps its scroll position.
--
-- Browser, Cooldowns, Crafting and the Profit Planner are library RowLists that
-- redraw on every guild sync; each reads its saved row offset before SetData and
-- writes it back from the list's onScroll, so a sync never throws the player
-- back to the top.
--
-- This file used to spec addon.GUI.PersistentScroll, the AceGUI ScrollFrame
-- helper the hand-built row pools used. v1.1.3 (LAGW adoption step 7) removed
-- it along with the last pool; its LayoutFinished repair and onRelease wiring
-- had no caller left to protect.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns

setup(function()
	ns = env.initDb()
	env.loadModule("GUI/SharedWidgets.lua")
end)

before_each(function()
	env.installFrames()
	env.resetDb()
end)

describe("ListScroll", function()
	it("reads back the offset a list wrote", function()
		ns.GUI.ListScroll.Set("spec_rows", 17)
		assert.equal(17, ns.GUI.ListScroll.Get("spec_rows"))
	end)

	it("reads 0 for a key nothing has written", function()
		assert.equal(0, ns.GUI.ListScroll.Get("spec_never_written"))
	end)

	it("keeps each key's scroll position separate", function()
		-- Two tabs open in one session must not drag each other's list around.
		ns.GUI.ListScroll.Set("spec_key_a", 10)
		ns.GUI.ListScroll.Set("spec_key_b", 99)
		assert.equal(10, ns.GUI.ListScroll.Get("spec_key_a"))
		assert.equal(99, ns.GUI.ListScroll.Get("spec_key_b"))
	end)

	it("persists a key's position in the character DB, not on the tab", function()
		-- A tab module is rebuilt freely; the position has to outlive it.
		ns.GUI.ListScroll.Set("spec_persist", 5)
		local store = ns.lib.db.char.frames.scrollTabs
		assert.equal(5, store["spec_persist"].rowOffset)
	end)

	it("does not read an older build's pixel offset as rows", function()
		-- The same key once held PersistentScroll's { scrollvalue, offset } in
		-- pixels; reading `offset` as a row count would jump hundreds of rows.
		ns.lib.db.char.frames = { scrollTabs = { spec_old = { scrollvalue = 500, offset = 640 } } }
		assert.equal(0, ns.GUI.ListScroll.Get("spec_old"))
	end)

	it("ignores a nil key", function()
		assert.has_no.errors(function() ns.GUI.ListScroll.Set(nil, 3) end)
		assert.equal(0, ns.GUI.ListScroll.Get(nil))
	end)
end)
