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
	-- SharedWidgets and MainWindow before Settings, mirroring the TOC — Settings
	-- binds addon.UI.Brand / addon.UI.Count at file scope, and the opacity
	-- slider reads its clamp from MainWindow.
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	-- The tracker's scale and opacity sliders read their clamps from it.
	env.loadModule("GUI/ReagentTracker.lua")
	env.loadModule("GUI/Settings.lua")

	-- Registration is hooked onto OnInitialize, which initDb has already run —
	-- so it has to run once more for the hook to fire. That hands the addon a
	-- second AceDB object; the original is restored in teardown so no later
	-- spec file inherits it.
	-- Guarded: settingsbleed_spec.lua performs the same re-init, and
	-- AddToBlizOptions raises on a second call with the same path. Whichever
	-- file the runner reaches first registers; the other reads what is there.
	local registry = LibStub("AceConfigRegistry-3.0")
	if not registry:GetOptionsTable("TOGProfessionMaster") then
		savedDb = ns.lib.db
		ns.lib:OnInitialize()
	end

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

describe("item tooltip: one toggle per line", function()
	-- The operator, 2026-10-10: "each thing that shows up on the link be it's own
	-- on/off setting". The vendor rows had no setting at all before this.
	local PARTS = { "tooltipShowCrafters", "tooltipShowIds",
	                "tooltipRecipeDifficulty", "tooltipRecipeSources", "tooltipRecipeUnlearned",
	                "tooltipVendorBuy", "tooltipVendorSell" }
	local RECIPE_PARTS = { tooltipRecipeDifficulty = true, tooltipRecipeSources = true,
	                       tooltipRecipeUnlearned = true }

	after_each(function()
		for _, key in ipairs(PARTS) do ns.lib.db.profile[key] = nil end
		ns.lib.db.profile.tooltipRecipeDetails = nil
	end)

	it("has a toggle for every line", function()
		for _, key in ipairs(PARTS) do
			local o = opt(key)
			assert.is_truthy(o, key .. " has no setting")
			assert.equal("toggle", o.type)
		end
	end)

	it("round-trips each new toggle and reads an untouched one as on", function()
		for key in pairs(RECIPE_PARTS) do
			ns.lib.db.profile[key] = nil
			assert.is_true(opt(key).get(), key)
			opt(key).set(nil, false)
			assert.is_false(ns.lib.db.profile[key], key)
			assert.is_false(opt(key).get(), key)
		end
		for _, key in ipairs({ "tooltipVendorBuy", "tooltipVendorSell" }) do
			opt(key).set(nil, false)
			assert.is_false(opt(key).get(), key)
			opt(key).set(nil, true)
			assert.is_true(ns.lib.db.profile[key], key)
		end
	end)

	it("reads a missing key as the shipped default: crafters on, IDs off", function()
		-- Each checkbox must agree with what the tooltip does when the key is
		-- missing. The IDs box used `~= false` and showed ticked over a hidden line.
		ns.lib.db.profile.tooltipShowCrafters = nil
		ns.lib.db.profile.tooltipShowIds      = nil
		assert.is_true(opt("tooltipShowCrafters").get())
		assert.is_false(opt("tooltipShowIds").get())
	end)

	it("greys out the recipe parts only while recipe details are Never", function()
		ns.lib.db.profile.tooltipRecipeDetails = "never"
		for key in pairs(RECIPE_PARTS) do assert.is_true(opt(key).disabled(), key) end
		ns.lib.db.profile.tooltipRecipeDetails = "always"
		for key in pairs(RECIPE_PARTS) do assert.is_false(opt(key).disabled(), key) end
		-- The vendor rows are not part of the recipe block.
		assert.is_nil(opt("tooltipVendorBuy").disabled)
		assert.is_nil(opt("tooltipVendorSell").disabled)
	end)
end)

describe("the old single vendor-price key migrates to the two rows", function()
	after_each(function()
		local p = ns.lib.db.profile
		p.tooltipVendorPrices, p.tooltipVendorBuy, p.tooltipVendorSell = nil, nil, nil
	end)

	it("carries an opt-out onto both rows and drops the old key", function()
		ns.lib.db.profile.tooltipVendorPrices = false
		ns:MigrateVendorPriceToggles()
		assert.is_false(ns.lib.db.profile.tooltipVendorBuy)
		assert.is_false(ns.lib.db.profile.tooltipVendorSell)
		assert.is_nil(ns.lib.db.profile.tooltipVendorPrices)
	end)

	it("leaves both rows on for a player who never turned it off", function()
		ns.lib.db.profile.tooltipVendorPrices = true
		ns:MigrateVendorPriceToggles()
		assert.is_true(ns.lib.db.profile.tooltipVendorBuy)
		assert.is_true(ns.lib.db.profile.tooltipVendorSell)
		assert.is_nil(ns.lib.db.profile.tooltipVendorPrices)
	end)

	it("migrates a profile the player switches to after login", function()
		-- OnInitialize only migrates the profile active at login; a second
		-- profile with the old key off must not come back with both rows on.
		local db = ns.lib.db
		local original = db:GetCurrentProfile()
		db.sv.profiles = db.sv.profiles or {}
		db.sv.profiles["TOGPM-spec-other"] = { tooltipVendorPrices = false }
		db:SetProfile("TOGPM-spec-other")
		local buy, sell, legacy = db.profile.tooltipVendorBuy, db.profile.tooltipVendorSell,
		                          db.profile.tooltipVendorPrices
		db:SetProfile(original)
		db:DeleteProfile("TOGPM-spec-other", true)
		assert.is_false(buy)
		assert.is_false(sell)
		assert.is_nil(legacy)
	end)

	it("does nothing before the profile exists", function()
		local saved = ns.lib.db
		ns.lib.db = nil
		assert.has_no.errors(function() ns:MigrateVendorPriceToggles() end)
		ns.lib.db = saved
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

describe("background opacity", function()
	it("is a percentage slider from 20% to 100%", function()
		local o = opt("windowOpacity")
		assert.equal("range", o.type)
		assert.is_true(o.isPercent)
		assert.equal(0.2, o.min)
		assert.equal(1,   o.max)
	end)

	it("reports fully opaque when nothing has been chosen", function()
		ns.lib.db.profile.windowOpacity = nil
		assert.equal(1, opt("windowOpacity").get())
	end)

	it("round-trips a chosen opacity", function()
		opt("windowOpacity").set(nil, 0.6)
		assert.equal(0.6, opt("windowOpacity").get())
	end)

	it("clamps a stale or absurd saved value into range rather than erroring", function()
		ns.lib.db.profile.windowOpacity = "0.05"
		assert.equal(0.2, opt("windowOpacity").get())
		ns.lib.db.profile.windowOpacity = 7
		assert.equal(1, opt("windowOpacity").get())
		ns.lib.db.profile.windowOpacity = "solid"
		assert.equal(1, opt("windowOpacity").get())
	end)
end)

describe("Reagent Tracker scale and background opacity", function()
	local RT, applied, realScale, realOpacity

	before_each(function()
		RT = ns.ReagentTracker
		applied = {}
		-- The methods live on RT itself, so put the real ones back afterwards.
		realScale, realOpacity = RT.ApplyScale, RT.ApplyOpacity
		RT.ApplyScale   = function() applied[#applied + 1] = "scale" end
		RT.ApplyOpacity = function() applied[#applied + 1] = "opacity" end
	end)

	after_each(function()
		RT.ApplyScale, RT.ApplyOpacity = realScale, realOpacity
		local p = ns.lib.db.profile
		p.trackerScale, p.trackerOpacity = nil, nil
	end)

	it("offers opacity from 0% (no background) to 100%", function()
		local o = opt("trackerOpacity")
		assert.equal("range", o.type)
		assert.is_true(o.isPercent)
		assert.equal(0, o.min)
		assert.equal(1, o.max)
	end)

	it("offers scale from 50% to 150%", function()
		local o = opt("trackerScale")
		assert.equal("range", o.type)
		assert.equal(0.5, o.min)
		assert.equal(1.5, o.max)
	end)

	it("reports 100% for both when nothing has been chosen", function()
		assert.equal(1, opt("trackerOpacity").get())
		assert.equal(1, opt("trackerScale").get())
	end)

	it("saves a chosen opacity and applies it to the open tracker", function()
		opt("trackerOpacity").set(nil, 0)
		assert.equal(0, ns.lib.db.profile.trackerOpacity)
		assert.equal(0, opt("trackerOpacity").get())
		assert.same({ "opacity" }, applied)
	end)

	it("saves a chosen scale and applies it to the open tracker", function()
		opt("trackerScale").set(nil, 1.25)
		assert.equal(1.25, ns.lib.db.profile.trackerScale)
		assert.equal(1.25, opt("trackerScale").get())
		assert.same({ "scale" }, applied)
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

-- ---------------------------------------------------------------------------
-- Everything below was unreached until 2026-10-16 (Peer Review F4, thread
-- bf2313d2: Settings.lua at 72%). Each block drives a handler that does
-- something a player would notice if it broke.
-- ---------------------------------------------------------------------------

local wow = env.wow
local L   = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

--- Swap fields on a table for one example; `restore()` puts every one back,
--- including the ones that were nil.
local function swap(target, fields)
	local saved = {}
	for k, v in pairs(fields) do saved[k] = { target[k] } ; target[k] = v end
	return function()
		for k, box in pairs(saved) do target[k] = box[1] end
	end
end

describe("without AceConfig the panel is skipped, not broken", function()
	it("returns before building anything and says why in debug", function()
		local said
		local restoreNs  = swap(ns, { DebugPrint = function(_, msg) said = msg end })
		local restoreLib = swap(LibStub.libs, { ["AceConfig-3.0"] = false })
		local ok, err = pcall(env.loadModule, "GUI/Settings.lua")
		restoreLib()
		restoreNs()
		assert.is_true(ok, tostring(err))
		assert.is_truthy(said and said:find("settings panel disabled", 1, true))
	end)
end)

describe("display setters with side effects", function()
	it("shows and hides the minimap icon through LibDBIcon", function()
		local calls = {}
		local icon = {
			Show = function(_, name) calls[#calls + 1] = "show:" .. name end,
			Hide = function(_, name) calls[#calls + 1] = "hide:" .. name end,
		}
		local restore = swap(LibStub.libs, { ["LibDBIcon-1.0"] = icon })
		opt("minimapButton").set(nil, false)
		local hidden = ns.lib.db.profile.minimapButton
		opt("minimapButton").set(nil, true)
		restore()
		assert.is_false(hidden)
		assert.is_true(ns.lib.db.profile.minimapButton)
		assert.same({ "hide:TOGProfessionMaster", "show:TOGProfessionMaster" }, calls)
	end)

	-- The hint was translated in every locale and never printed until v1.7.0,
	-- so a player who hid the button had no pointer to /upm minimap.
	it("says how to bring the minimap button back when it is hidden, and only then", function()
		local said, savedPrint = {}, ns.Print
		ns.Print = function(_, msg) said[#said + 1] = msg end
		local restore = swap(LibStub.libs, { ["LibDBIcon-1.0"] = { Show = function() end, Hide = function() end } })
		local ok, err = pcall(function()
			opt("minimapButton").set(nil, false)
			opt("minimapButton").set(nil, true)
		end)
		restore()
		ns.Print = savedPrint
		assert(ok, err)
		assert.same({ L["MinimapHidden"] }, said)
		assert.is_truthy(said[1]:find("/upm minimap", 1, true))
	end)

	it("saves the minimap choice even with LibDBIcon absent", function()
		local restore = swap(LibStub.libs, { ["LibDBIcon-1.0"] = false })
		opt("minimapButton").set(nil, false)
		restore()
		assert.is_false(ns.lib.db.profile.minimapButton)
	end)

	it("forgets the saved profession filter when persistence is turned off", function()
		ns.lib.db.profile.savedProfFilter = 171
		opt("persistProfFilter").set(nil, true)
		assert.equal(171, ns.lib.db.profile.savedProfFilter)
		opt("persistProfFilter").set(nil, false)
		assert.is_false(ns.lib.db.profile.persistProfFilter)
		assert.equal(0, ns.lib.db.profile.savedProfFilter)
	end)

	it("applies a UI language at once and tells the player to reload", function()
		local applied, printed = 0, nil
		local restore = swap(ns, {
			ApplyLocaleOverride = function() applied = applied + 1 end,
			Print = function(_, msg) printed = msg end,
		})
		opt("uiLanguageOverride").set(nil, "deDE")
		restore()
		assert.equal("deDE", ns.lib.db.profile.uiLanguageOverride)
		assert.equal(1, applied)
		assert.equal(L["SettingsUILangReloadHint"], printed)
		ns.lib.db.profile.uiLanguageOverride = nil
	end)
end)

describe("crafter-alert pickers preview what they pick", function()
	after_each(function()
		local p = ns.lib.db.profile
		p.crafterAlertSound, p.crafterAlertVisual = nil, nil
	end)

	it("plays the chosen sound", function()
		local played
		local restore = swap(_G, { PlaySound = function(id) played = id end })
		opt("crafterAlertSound").set(nil, 8960)
		restore()
		assert.equal(8960, ns.lib.db.profile.crafterAlertSound)
		assert.equal(8960, played)
	end)

	it("fires the chosen visual with the online banner", function()
		local style, banner
		local restore = swap(ns, { FireCrafterAlertVisual = function(_, s, b) style, banner = s, b end })
		opt("crafterAlertVisual").set(nil, "taskbar")
		restore()
		assert.equal("taskbar", ns.lib.db.profile.crafterAlertVisual)
		assert.equal("taskbar", style)
		assert.equal(L["AlertCrafterOnlineBanner"], banner)
	end)

	it("still saves the visual when there is nothing to preview it with", function()
		local restore = swap(ns, { FireCrafterAlertVisual = false })
		opt("crafterAlertVisual").set(nil, "flashRed")
		restore()
		assert.equal("flashRed", ns.lib.db.profile.crafterAlertVisual)
	end)
end)

describe("cooldown reminder interval: empty, off, or 0-1440 whole minutes", function()
	local o

	before_each(function() o = opt("cooldownAlertReminderMinutes") end)
	after_each(function() ns.lib.db.profile.cooldownAlertReminderMinutes = nil end)

	it("shows off as an empty field and a value as its number", function()
		ns.lib.db.profile.cooldownAlertReminderMinutes = 0
		assert.equal("", o.get())
		ns.lib.db.profile.cooldownAlertReminderMinutes = 30
		assert.equal("30", o.get())
	end)

	it("accepts empty, off and whole minutes in range", function()
		assert.is_true(o.validate(nil, ""))
		assert.is_true(o.validate(nil, " OFF "))
		assert.is_true(o.validate(nil, "0"))
		assert.is_true(o.validate(nil, "1440"))
	end)

	it("refuses fractions, words and anything out of range", function()
		local bad = L["SettingsCooldownReminderInvalid"]
		assert.equal(bad, o.validate(nil, "2.5"))
		assert.equal(bad, o.validate(nil, "soon"))
		assert.equal(bad, o.validate(nil, "-1"))
		assert.equal(bad, o.validate(nil, "1441"))
	end)

	it("saves off as 0 and a number as whole minutes, clamped", function()
		o.set(nil, "45")
		assert.equal(45, ns.lib.db.profile.cooldownAlertReminderMinutes)
		o.set(nil, "off")
		assert.equal(0, ns.lib.db.profile.cooldownAlertReminderMinutes)
		o.set(nil, "12.9")
		assert.equal(12, ns.lib.db.profile.cooldownAlertReminderMinutes)
		o.set(nil, "-5")
		assert.equal(0, ns.lib.db.profile.cooldownAlertReminderMinutes)
		o.set(nil, "9000")
		assert.equal(1440, ns.lib.db.profile.cooldownAlertReminderMinutes)
	end)

	it("leaves the saved value alone for input that is not a number", function()
		ns.lib.db.profile.cooldownAlertReminderMinutes = 20
		o.set(nil, "soon")
		assert.equal(20, ns.lib.db.profile.cooldownAlertReminderMinutes)
	end)
end)

describe("TBC phase and debug", function()
	it("redraws Missing Recipes at once when it is the open tab", function()
		local redrawn = 0
		local restoreNs = swap(ns, { MissingRecipesTab = { RefreshList = function() redrawn = redrawn + 1 end } })
		local restoreMw = swap(ns.MainWindow, { activeTab = "missing" })
		opt("tbcAnniversaryPhase").set(nil, 2)
		ns.MainWindow.activeTab = "browser"
		opt("tbcAnniversaryPhase").set(nil, 3)
		restoreMw()
		restoreNs()
		assert.equal(3, ns.lib.db.profile.tbcAnniversaryPhase)
		assert.equal(1, redrawn)
		ns.lib.db.profile.tbcAnniversaryPhase = nil
	end)

	it("switches debug output on for the running addon too", function()
		local was = ns.debug
		opt("debug").set(nil, true)
		local live = ns.debug
		opt("debug").set(nil, false)
		ns.debug = was
		assert.is_true(live)
		assert.is_false(ns.lib.db.profile.debug)
	end)
end)

describe("the purge buttons", function()
	local ME = "Testchar-Testrealm"
	local gdb, printed, invalidated, queued, restore

	before_each(function()
		gdb = ns:GetGuildDb()
		printed, invalidated, queued = {}, 0, 0
		restore = {
			swap(ns, {
				Print      = function(_, msg) printed[#printed + 1] = msg end,
				BrowserTab = { InvalidateCache = function() invalidated = invalidated + 1 end },
			}),
			swap(ns.MainWindow, { QueueRefresh = function() queued = queued + 1 end }),
		}
	end)

	after_each(function()
		for i = #restore, 1, -1 do restore[i]() end
	end)

	it("wipes the guild's data and this character's lists, then redraws", function()
		gdb.recipes[171] = { [2330] = { crafters = { [ME] = 1 } } }
		gdb.cooldowns[ME] = { [1] = 99 }
		ns.lib.db.char.shoppingList = { { id = 1 } }
		opt("purgeGuildData").func()
		assert.same({}, gdb.recipes)
		assert.same({}, gdb.cooldowns)
		assert.same({}, ns.lib.db.char.shoppingList)
		assert.same({ L["MsgGuildDataPurged"] }, printed)
		assert.equal(1, invalidated)
		assert.equal(1, queued)
	end)

	--- Our character in every table the purge clears, beside someone else's.
	local function seedBoth()
		gdb.recipes[171] = { [2330] = { crafters = { [ME] = 1, ["Bob-Testrealm"] = 1 } } }
		for _, t in ipairs({ "skills", "guildData", "cooldowns", "syncTimes", "specializations", "factions" }) do
			gdb[t] = gdb[t] or {}
			gdb[t][ME], gdb[t]["Bob-Testrealm"] = { x = 1 }, { x = 1 }
		end
		gdb.hashes = gdb.hashes or {}
		for _, leaf in ipairs({ "cooldown:", "skills:", "professions:", "accountchars:" }) do
			gdb.hashes[leaf .. ME] = { hash = 1 }
		end
	end

	it("removes only this character, and drops its leaves through HashManager", function()
		seedBoth()
		local dropped = {}
		local undo = swap(ns, { HashManager = { DropOrphanLeaf = function(_, _, _, key) dropped[#dropped + 1] = key end } })
		local undoDS = swap(ns.Scanner, { DS = {} })
		opt("purgeMyData").func()
		undoDS()
		undo()
		assert.is_nil(gdb.recipes[171][2330].crafters[ME])
		assert.is_truthy(gdb.recipes[171][2330].crafters["Bob-Testrealm"])
		assert.is_nil(gdb.cooldowns[ME])
		assert.is_truthy(gdb.cooldowns["Bob-Testrealm"])
		assert.same({ "cooldown:" .. ME, "skills:" .. ME, "professions:" .. ME, "accountchars:" .. ME }, dropped)
		assert.same({ L["MsgOwnDataPurged"] }, printed)
		assert.equal(1, invalidated)
		assert.equal(1, queued)
	end)

	it("clears this character's leaf hashes directly when sync is not running", function()
		seedBoth()
		local undoDS = swap(ns.Scanner, { DS = false })
		opt("purgeMyData").func()
		undoDS()
		for _, leaf in ipairs({ "cooldown:", "skills:", "professions:", "accountchars:" }) do
			assert.is_nil(gdb.hashes[leaf .. ME], leaf)
		end
	end)

	it("clears the sync log", function()
		local cleared = 0
		local undo = swap(ns, { SyncLog = { Clear = function() cleared = cleared + 1 end } })
		opt("clearLogBtn").func()
		undo()
		assert.equal(1, cleared)
	end)
end)

describe("the Cross-Guild tab", function()
	local restore

	before_each(function()
		ns.Scanner = ns.Scanner or {}
		restore = {}
	end)

	after_each(function()
		for i = #restore, 1, -1 do restore[i]() end
	end)

	it("hands an edited allied-guild list to the library", function()
		local got
		restore[#restore + 1] = swap(ns, { SetSisterGuilds = function(_, v) got = v end })
		opt("sisterGuilds").set(nil, "Alpha\nBeta")
		assert.equal("Alpha\nBeta", got)
	end)

	it("Sync now gossips the list and relays the held rosters", function()
		local calls = {}
		restore[#restore + 1] = swap(ns.Scanner, { GuildRoster = {
			BroadcastSisterConfig  = function() calls[#calls + 1] = "config" end,
			BroadcastSisterRosters = function() calls[#calls + 1] = "rosters" end,
		} })
		opt("syncConfigBtn").func()
		assert.same({ "config", "rosters" }, calls)
	end)

	it("Refresh re-renders without error", function()
		assert.has_no.errors(function() opt("diagRefresh").func() end)
	end)

	it("pulls a roster from the trimmed name, and ignores a blank one", function()
		local peers = {}
		restore[#restore + 1] = swap(ns, { PullSisterRoster = function(_, p) peers[#peers + 1] = p end })
		opt("pullInput").set(nil, "  Bob  ")
		opt("pullInput").set(nil, "   ")
		assert.same({ "Bob" }, peers)
		assert.equal("", opt("pullInput").get())
	end)

	describe("the diagnostics", function()
		--- Run /togpm xgdiag and return everything it printed, joined.
		local function diag()
			local out = {}
			local undo = swap(_G, { print = function(s) out[#out + 1] = s end })
			local ok, err = pcall(ns.PrintCrossGuildDiagnostics, ns)
			undo()
			assert.is_true(ok, tostring(err))
			return table.concat(out, "\n")
		end

		it("says plainly when neither library is loaded", function()
			restore[#restore + 1] = swap(ns.Scanner, { DS = false, GuildRoster = false })
			local text = diag()
			assert.is_truthy(text:find("DeltaSync: |cffff4040not loaded|r", 1, true))
			assert.is_truthy(text:find("LibGuildRoster: |cffff4040not loaded|r", 1, true))
			assert.is_truthy(text:find("(roster library unavailable)", 1, true))
		end)

		it("says when the library knows no rosters yet", function()
			restore[#restore + 1] = swap(ns.Scanner, { DS = {}, GuildRoster = {
				GetKnownRosters = function() return {} end,
			} })
			local text = diag()
			assert.is_truthy(text:find("DeltaSync: loaded", 1, true))
			assert.is_truthy(text:find("(none yet)", 1, true))
		end)

		it("lists allied guilds, splits a sister's crafters by roster, and shows persisted rosters", function()
			local gdb = ns:GetGuildDb()
			local SISTER = "sistertag"
			gdb.guildRegistry = gdb.guildRegistry or {}
			gdb.guildRegistry[SISTER] = { name = "Sister Guild" }
			gdb.recipes[171] = { [2330] = { crafters = {
				["Ann-Testrealm"]    = SISTER,
				["Orphan-Testrealm"] = SISTER,
			} } }
			restore[#restore + 1] = swap(ns, { GetSisterGuilds = function() return { "Sister Guild" } end })
			restore[#restore + 1] = swap(ns.Scanner, { DS = {}, GuildRoster = {
				GetSisterGuildNames  = function() return {} end,
				IsSisterSyncAvailable = function() return true end,
				GetHomeGuildKey      = function() return "A-Home" end,
				GetKnownRosters      = function() return { "A-Home", "A-Sister" } end,
				GetRoster            = function() return { x = true } end,
				IsInAnyRoster        = function(_, ck) return ck == "Ann-Testrealm" end,
				GetSisterDb          = function() return { sisterRosters = {
					["A-Sister"] = { members = { "a", "b" }, fedAt = 0 },
					["A-Bad"]    = "junk",
				} } end,
			} })
			local text = diag()
			assert.is_truthy(text:find("sister sync: |cff00ff00up|r", 1, true))
			assert.is_truthy(text:find("A-Sister |cffffd100(sister)|r", 1, true))
			assert.is_truthy(text:find("\n  Sister Guild\n", 1, true))
			assert.is_truthy(text:find("Sister Guild  \226\128\148  2 crafters (1 in roster, |cffff6060" ..
				"1 orphaned|r)", 1, true))
			assert.is_truthy(text:find("e.g. Orphan-Testrealm", 1, true))
			assert.is_truthy(text:find("A-Sister  \226\128\148  2 members (fed " .. date("%H:%M:%S", 0) .. ")", 1, true))
			assert.is_truthy(text:find("A-Bad  \226\128\148  0 members (fed ?)", 1, true))
		end)
	end)
end)

describe("opening Settings re-lays the dialog once skins have run", function()
	local APP = "TOGProfessionMaster"
	local AceDialog, passes, undo

	--- AceConfigDialog:Close is DEFERRED: it marks the app and releases the
	--- window on the dialog's next OnUpdate. One frame of the harness clock
	--- runs it; until then the window is still in OpenFrames and OpenSettings
	--- would toggle it closed instead of opening it.
	local function closeNow()
		if AceDialog.OpenFrames[APP] then AceDialog:Close(APP) end
		wow.advanceTime(0.05)
	end

	before_each(function()
		AceDialog = LibStub("AceConfigDialog-3.0")
		-- Another spec file can leave the dialog open.
		closeNow()
		-- The two deferred passes are captured and run by hand. Only timers
		-- scheduled from GUI/Settings.lua count: Ace3's Slider constructor
		-- schedules its own font workaround (AceGUIWidget-Slider.lua:276) for
		-- every slider it builds new, so a run of this file alone, with no
		-- pooled sliders yet, saw 6 timers where a whole-suite run saw 2.
		passes = {}
		undo = swap(_G, { C_Timer = { After = function(delay, fn)
			local src = debug.getinfo(2, "S").short_src or ""
			if src:find("GUI/Settings.lua", 1, true) then passes[#passes + 1] = { delay, fn } end
		end } })
	end)

	after_each(function()
		undo()
		closeNow()
	end)

	it("lays every widget out again on both deferred passes", function()
		ns:OpenSettings()
		local f = assert(AceDialog.OpenFrames[APP])
		assert.equal(2, #passes)
		assert.equal(0, passes[1][1])
		assert.equal(0.2, passes[2][1])
		local real, laid = f.DoLayout, 0
		-- Counted per pass, not exactly: a child's layout can lay its parent out
		-- again, so one pass may call the window's DoLayout more than once.
		f.DoLayout = function(...) laid = laid + 1 return real(...) end
		passes[1][2]()
		local first = laid
		passes[2][2]()
		f.DoLayout = real
		assert.is_true(first > 0)
		assert.is_true(laid > first)
	end)

	it("does nothing when the dialog closed before the pass ran", function()
		ns:OpenSettings()
		assert.is_truthy(AceDialog.OpenFrames[APP])
		ns:OpenSettings()
		wow.advanceTime(0.05)
		assert.is_nil(AceDialog.OpenFrames[APP])
		assert.equal(2, #passes)
		assert.has_no.errors(function() passes[1][2]() end)
	end)
end)

-- The sync-log window is created once and kept for the session (a file-level
-- local in Settings.lua), so every example here works on the same window.
describe("the sync-log window", function()
	local AceGUI = LibStub("AceGUI-3.0")
	local win, created, entries, restoreLog

	local function line(e)
		local n = tonumber(e.bytes) or 0
		return string.format("%s  %-7s  %9s  %-18s  %s", date("%Y-%m-%d %H:%M:%S", e.ts), e.event,
			n > 0 and (n .. " B") or "-", e.peer, e.detail or (type(e.bytes) == "string" and e.bytes) or "")
	end

	local function text() return win._editbox:GetText() end
	local function title() return win.titletext:GetText() end

	before_each(function()
		entries = {
			{ ts = 0, event = "send", bytes = 120, peer = "Bob", detail = "guild" },
			{ ts = 0, event = "recv", bytes = "cooldown:Bob-Testrealm", peer = "Bob" },
		}
		restoreLog = swap(ns, { SyncLog = { GetEntries = function() return entries end } })
		if not win then
			local realCreate = AceGUI.Create
			created = 0
			AceGUI.Create = function(self, kind)
				local w = realCreate(self, kind)
				if kind == "Frame" then created = created + 1; win = win or w end
				return w
			end
			local ok, err = pcall(ns.OpenSyncLog, ns)
			AceGUI.Create = realCreate
			assert.is_true(ok, tostring(err))
		else
			ns:OpenSyncLog()
		end
		assert.is_truthy(win)
	end)

	after_each(function()
		ns:SetSyncLogPaused(false)
		restoreLog()
	end)

	it("lists every entry as plain, aligned text, legacy entries included", function()
		assert.equal(line(entries[1]) .. "\n" .. line(entries[2]), text())
		assert.equal(L["SyncLogTitle"], title())
		assert.equal(1, created)
		assert.equal(5, #win._hdrFS)
		assert.equal("Time", win._hdrFS[1]:GetText())
		assert.equal(L["SyncLogPause"], win._pauseBtn:GetText())
	end)

	it("reopens the same window, refreshed, rather than building another", function()
		win:Hide()
		entries[#entries + 1] = { ts = 0, event = "send", bytes = 0, peer = "Cat" }
		ns:OpenSyncLog()
		assert.equal(1, created)
		assert.is_true(win.frame:IsShown())
		assert.is_truthy(text():find(line(entries[3]), 1, true))
	end)

	it("says so when the log is empty, or the log module is missing", function()
		entries = {}
		ns:RefreshSyncLog()
		assert.equal(L["SyncLogNoEntries"], text())
		ns.SyncLog = nil
		ns:RefreshSyncLog()
		assert.equal(L["SyncLogModuleMissing"], text())
	end)

	it("puts back anything typed into it, and leaves a selection alone", function()
		local edit = win._editbox.editBox
		local before = text()
		edit:SetText("typed")
		edit:Fire("OnTextChanged", false)
		assert.equal("typed", edit:GetText())
		edit:Fire("OnTextChanged", true)
		assert.equal(before, edit:GetText())
	end)

	it("Pause freezes the view and counts what arrives; Resume catches it up", function()
		win._pauseBtn:Click()
		assert.equal(L["SyncLogResume"], win._pauseBtn:GetText())
		local frozen = text()
		entries[#entries + 1] = { ts = 0, event = "send", bytes = 9, peer = "Dee" }
		ns.callbacks:Fire("SYNC_LOG_UPDATED")
		wow.flushTimers()
		assert.equal(frozen, text())
		assert.equal(L["SyncLogTitle"] .. string.format(L["SyncLogPausedNote"], 1), title())
		win._pauseBtn:Click()
		assert.equal(L["SyncLogPause"], win._pauseBtn:GetText())
		assert.equal(L["SyncLogTitle"], title())
		assert.is_truthy(text():find(line(entries[3]), 1, true))
	end)

	it("refreshes live, once per burst, while open", function()
		entries[#entries + 1] = { ts = 0, event = "recv", bytes = 7, peer = "Eve" }
		ns.callbacks:Fire("SYNC_LOG_UPDATED")
		ns.callbacks:Fire("SYNC_LOG_UPDATED")
		assert.is_falsy(text():find("Eve", 1, true))
		wow.advanceTime(0.31)
		wow.flushTimers()
		assert.is_truthy(text():find(line(entries[3]), 1, true))
	end)

	it("ignores updates while closed", function()
		win:Hide()
		local was = text()
		entries[#entries + 1] = { ts = 0, event = "recv", bytes = 7, peer = "Fay" }
		ns.callbacks:Fire("SYNC_LOG_UPDATED")
		wow.flushTimers()
		assert.equal(was, text())
	end)
end)
