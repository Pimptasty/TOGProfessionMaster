-- GUI/MinimapButton.lua — the LDB launcher and its LibDBIcon registration.
--
-- Small file, three things worth pinning:
--
--   * the click routing, which is the only way most users open the addon;
--   * the tooltip, which is the only place those three bindings are written down;
--   * the db table handed to LibDBIcon, which was a real bug (v0.7.1). LibDBIcon
--     writes the new angle into that table when the user DRAGS the button, so
--     passing a throwaway local silently lost the position on every /reload.
--     It has to be the table that persists.
--
-- Runs against the REAL LibDataBroker-1.1 and LibDBIcon-1.0 from the standalone
-- LibDBIcon-1.0 addon in the sibling AddOns folder. Since v1.1.2 that addon is a
-- required dependency and TOGPM no longer embeds either library, so the sibling
-- copy is exactly what players run.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env  = require("env_togpm")
local libs = require("env.libs")

local ns, dataObj, opened

local function haveVendoredLibs()
	return libs.available("LibDBIcon-1.0")
end

setup(function()
	ns = env.initDb()
	-- The harness's own manifest entry (Adoption log 2026-09-25, d57d724) loads
	-- the standalone addon from AddOns/LibDBIcon-1.0 with its LibDataBroker, so
	-- no private registration is needed.
	if haveVendoredLibs() then
		libs.load("LibDBIcon-1.0")
		env.loadModule("GUI/MinimapButton.lua")
		dataObj = LibStub("LibDataBroker-1.1", true)
			and LibStub("LibDataBroker-1.1"):GetDataObjectByName("TOGProfessionMaster")
	end
end)

local saved

before_each(function()
	env.installFrames()
	if not dataObj then return end
	opened = {}
	-- Methods on the ADDON table: env.install() resets globals, not these, so a
	-- spec here would otherwise hand every later spec FILE a stubbed OpenBrowser.
	saved = { OpenBrowser = ns.OpenBrowser, OpenSettings = ns.OpenSettings,
	          OpenReagents = ns.OpenReagents, Print = ns.Print }
	ns.OpenBrowser  = function() opened.browser = true end
	ns.OpenSettings = function() opened.settings = true end
	ns.OpenReagents = function() opened.reagents = true end
	_G.IsShiftKeyDown = function() return false end
end)

after_each(function()
	for name, fn in pairs(saved or {}) do ns[name] = fn end
end)

describe("minimap launcher", function()
	it("registers an LDB launcher object", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		assert.equal("launcher", dataObj.type)
		assert.is_function(dataObj.OnClick)
		assert.is_function(dataObj.OnTooltipShow)
	end)

	it("opens the browser on a plain left-click", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		dataObj.OnClick(nil, "LeftButton")
		assert.is_true(opened.browser)
		assert.is_nil(opened.settings)
	end)

	it("opens settings on shift+left-click, not the browser", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		_G.IsShiftKeyDown = function() return true end
		dataObj.OnClick(nil, "LeftButton")
		assert.is_true(opened.settings)
		assert.is_nil(opened.browser)
	end)

	it("opens the shopping list on right-click", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		dataObj.OnClick(nil, "RightButton")
		assert.is_true(opened.reagents)
	end)

	it("ignores a button it has no binding for", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		dataObj.OnClick(nil, "MiddleButton")
		assert.same({}, opened)
	end)

	it("documents all three bindings in the tooltip", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		local lines = {}
		dataObj.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
		-- Title, blank, and one line per binding.
		assert.equal(5, #lines)
		assert.is_truthy(lines[1]:find("TOG Profession Master", 1, true))
	end)
end)

describe("LibDBIcon registration", function()
	-- SetupMinimapButton is a file-local, hooked onto Ace:OnEnable — so driving
	-- the real OnEnable is the only way in, and it is worth it: this is the
	-- v0.7.1 fix, and the failure it prevents (a dragged button snapping back on
	-- every /reload) is invisible until a user drags one.
	local function enable()
		-- LibDBIcon errors on a second Register of the same name, correctly — in
		-- game OnEnable runs once. A fresh copy per test is the honest way to run
		-- it repeatedly; SetupMinimapButton looks the library up through LibStub
		-- at call time, so it picks the new one up.
		libs.fresh("LibDBIcon-1.0")
		ns.lib:OnEnable()
	end

	it("hands LibDBIcon the table that PERSISTS, seeded from the legacy field", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.lib.db.profile.minimap       = nil     -- fresh profile
		ns.lib.db.profile.minimapPos    = 137     -- the pre-v0.7.1 field
		ns.lib.db.profile.minimapButton = true

		enable()

		local md = ns.lib.db.profile.minimap
		-- On the AceDB profile, so LibDBIcon's drag writes survive a reload.
		assert.is_truthy(md)
		assert.equal(137, md.minimapPos)
		assert.is_false(md.hide)
	end)

	it("defaults the angle when there is no legacy position either", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.lib.db.profile.minimap    = nil
		ns.lib.db.profile.minimapPos = nil
		enable()
		assert.equal(220, ns.lib.db.profile.minimap.minimapPos)
	end)

	it("does not overwrite a position the user has already dragged to", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.lib.db.profile.minimap    = { minimapPos = 12 }
		ns.lib.db.profile.minimapPos = 137
		enable()
		assert.equal(12, ns.lib.db.profile.minimap.minimapPos)
	end)

	it("mirrors the visibility setting into LibDBIcon's hide flag", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.lib.db.profile.minimap       = nil
		ns.lib.db.profile.minimapButton = false
		enable()
		assert.is_true(ns.lib.db.profile.minimap.hide)
	end)
end)

describe("ShowMinimapButton", function()
	it("turns the setting on so the button survives a reload", function()
		if not dataObj then return pending("LibDBIcon-1.0 addon not installed next to TOGPM") end
		ns.Print = function() end
		ns.lib.db.profile.minimapButton = false
		ns:ShowMinimapButton()
		assert.is_true(ns.lib.db.profile.minimapButton)
	end)
end)
