-- GUI/Settings.lua — the options table, and the handlers that mean something.
--
-- Most of that file is a declarative AceConfig table, and most of its get/set
-- pairs are straight passthroughs not worth a test each. Two things here ARE
-- worth it:
--
--   * That the whole table passes AceConfigRegistry's OWN validator. That is
--     the same check the game runs before drawing the panel, over 908 lines of
--     options — a missing `type`, a mistyped key or a nil name anywhere in it
--     means the Settings panel throws when a player opens it, and nothing else
--     in this suite would notice.
--
--   * The handful of handlers with real semantics: the two defaults expressed
--     as `~= false` / `== true` (get those backwards and the addon changes
--     behaviour for everyone on upgrade), the scale coercion, and guild mode,
--     whose `get` must report the LIVE library state rather than the saved one
--     so the checkbox cannot lie about what the addon is actually doing.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")
local ace = require("env.ace")

local ns, options, savedDb

--- Find an option by key anywhere in the tree; the grouping is presentation
--- and a spec should not break when a toggle moves between tabs.
local function opt(key, node)
	node = node or options
	for k, v in pairs(node.args or {}) do
		if k == key then return v end
		if type(v) == "table" and v.args then
			local found = opt(key, v)
			if found then return found end
		end
	end
	return nil
end

setup(function()
	ns = env.initDb()
	-- Settings.lua looks AceConfig up silently, so without this the whole
	-- registration is skipped and the table never exists to be tested.
	ace.load("AceConfig-3.0", "AceConfigDialog-3.0")
	env.loadModule("GUI/Settings.lua")

	-- Registration is hooked onto OnInitialize, which initDb has already run —
	-- so it has to run once more for the hook to fire. That hands the addon a
	-- second AceDB object; the original is restored in teardown so no later
	-- spec file inherits it.
	savedDb = ns.lib.db
	ns.lib:OnInitialize()

	local registry = LibStub("AceConfigRegistry-3.0")
	options = registry:GetOptionsTable("TOGProfessionMaster")("dialog", "AceConfigDialog-3.0")
end)

teardown(function()
	if savedDb then ns.lib.db = savedDb end
end)

before_each(function()
	env.installFrames()
	env.resetDb()
end)

describe("the options table", function()
	it("passes AceConfigRegistry's own validation", function()
		-- GetOptionsTable(...)(...) validates on the way out and errors on a
		-- malformed entry, so reaching this line at all is the assertion. This
		-- is what the game does before drawing the panel.
		assert.is_truthy(options)
		assert.equal("group", options.type)
		assert.is_truthy(next(options.args))
	end)

	it("gives every input option both a getter and a setter", function()
		-- A toggle with no setter renders and silently does nothing.
		local inputs = { toggle = true, range = true, select = true, input = true }
		local checked, missing = 0, {}
		local function walk(node, path)
			for k, v in pairs(node.args or {}) do
				if type(v) == "table" then
					if inputs[v.type] then
						checked = checked + 1
						if not (v.get and v.set) then
							missing[#missing + 1] = path .. "." .. k
						end
					end
					walk(v, path .. "." .. k)
				end
			end
		end
		walk(options, "")
		assert.same({}, missing)
		-- Guard against the walk silently finding nothing and passing.
		assert.is_true(checked > 10)
	end)
end)

describe("defaults that change behaviour on upgrade", function()
	it("leaves crafting hands-off ON for someone who has never touched it", function()
		-- Expressed as `~= false`, so nil means on. Inverted, the addon would
		-- start taking over the crafting UI of every existing user.
		ns.lib.db.profile.craftingHandsOff = nil
		assert.is_true(opt("craftingHandsOff").get())
	end)

	it("respects an explicit opt-out of hands-off", function()
		opt("craftingHandsOff").set(nil, false)
		assert.is_false(opt("craftingHandsOff").get())
	end)

	it("keeps the Crafting tab visible for someone who has never touched it", function()
		-- The mirror case: `== true`, so nil means "do not hide".
		ns.lib.db.profile.hideCraftingTab = nil
		assert.is_false(opt("hideCraftingTab").get())
	end)

	it("hides the Crafting tab only when explicitly asked", function()
		opt("hideCraftingTab").set(nil, true)
		assert.is_true(opt("hideCraftingTab").get())
	end)
end)

describe("window scale", function()
	it("reports 1 when nothing has been chosen", function()
		ns.lib.db.profile.windowScale = nil
		assert.equal(1, opt("windowScale").get())
	end)

	it("reports 1 rather than a string a stale SavedVariables left behind", function()
		-- The value feeds arithmetic in ApplyScale; a string would error there.
		ns.lib.db.profile.windowScale = "1.2"
		assert.equal(1.2, opt("windowScale").get())
		ns.lib.db.profile.windowScale = "huge"
		assert.equal(1, opt("windowScale").get())
	end)

	it("round-trips a chosen scale", function()
		opt("windowScale").set(nil, 1.25)
		assert.equal(1.25, opt("windowScale").get())
	end)
end)

describe("UI language override", function()
	it("reports auto when unset", function()
		ns.lib.db.profile.uiLanguageOverride = nil
		assert.equal("auto", opt("uiLanguageOverride").get())
	end)
end)

describe("guild mode", function()
	local savedDS

	before_each(function()
		ns.Scanner = ns.Scanner or {}
		savedDS = ns.Scanner.DS
	end)

	after_each(function()
		ns.Scanner.DS = savedDS
	end)

	it("is hidden entirely when the loaded DeltaSync has no guild mode", function()
		-- Feature-detected: showing a toggle that cannot do anything is worse
		-- than not showing it.
		ns.Scanner.DS = {}
		assert.is_true(opt("guildMode").hidden())
	end)

	it("is shown when DeltaSync supports it", function()
		ns.Scanner.DS = { InitGuildMode = function() end }
		assert.is_false(opt("guildMode").hidden())
	end)

	it("reports the LIVE library state, not the saved one", function()
		-- The checkbox must match what the addon is actually doing; the saved
		-- value can disagree if a flip was rejected before init.
		ns.lib.db.realm.guildMode = false
		ns.Scanner.DS = { IsGuildMode = function() return true end }
		assert.is_true(opt("guildMode").get())
	end)

	it("falls back to the saved value when the library cannot answer", function()
		ns.lib.db.realm.guildMode = true
		ns.Scanner.DS = {}
		assert.is_true(opt("guildMode").get())
	end)

	it("flips the library AND writes the realm setting", function()
		-- Belt and braces on purpose: the write is what survives if the flip is
		-- rejected before DeltaSync has initialised.
		local flipped
		ns.Scanner.DS = { SetGuildMode = function(_, v) flipped = v end }
		opt("guildMode").set(nil, true)
		assert.is_true(flipped)
		assert.is_true(ns.lib.db.realm.guildMode)
	end)

	it("coerces a truthy value to a real boolean before storing it", function()
		ns.Scanner.DS = { SetGuildMode = function() end }
		opt("guildMode").set(nil, "yes")
		assert.is_true(ns.lib.db.realm.guildMode)
	end)
end)
