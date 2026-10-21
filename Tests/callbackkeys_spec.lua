-- Every subscriber to an addon event is heard, not just the last one.
--
-- CallbackHandler keys a registration by its `self` and a second registration
-- under the same `self` REPLACES the first (Ace3 CallbackHandler-1.0.lua:126-129).
-- `addon:RegisterCallback(event, fn)` passes the addon as `self`, so two modules
-- doing that for one event share one slot. That is how MainWindow's
-- GUILD_DATA_UPDATED handler, registered at OnEnable, silently replaced
-- BrowserTab's, registered at load: the Professions recipe cache stopped
-- re-warming on guild data changes and served the 8 s warm until /reload (Peer
-- Review H1, inbox 95fc14a4). Each module now registers as itself.
--
-- Drives the real modules and the real OnEnable, so the registrations under
-- test are the shipped ones.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/SyncLog.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/ReagentWatch.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Crafting/CraftQueue.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	env.loadModule("GUI/BrowserTab.lua")
	env.loadModule("GUI/CooldownsTab.lua")
	env.loadModule("GUI/MissingRecipesTab.lua")
	env.loadModule("GUI/CraftingTab.lua")
end)

describe("GUILD_DATA_UPDATED after the real OnEnable", function()
	local saved, warmed, queued

	before_each(function()
		env.installFrames()
		env.resetDb()
		-- minimap_spec hooks the minimap button onto OnEnable in a full run, and
		-- LibDBIcon refuses a second Register of one name; its own answer is a
		-- fresh copy per run (sisterguild_spec does the same).
		if env.libs.loaded["LibDBIcon-1.0"] then env.libs.fresh("LibDBIcon-1.0") end
		warmed, queued = 0, 0
		saved = {
			Warm         = ns.BrowserTab.Warm,
			QueueRefresh = ns.MainWindow.QueueRefresh,
			activeTab    = ns.MainWindow.activeTab,
			NewTimer     = _G.C_Timer.NewTimer,
		}
		ns.BrowserTab.Warm = function() warmed = warmed + 1 end
		ns.MainWindow.QueueRefresh = function() queued = queued + 1 end
		ns.MainWindow.activeTab = "browser"
		-- The re-warm is debounced on a timer; run it at once so the count says
		-- whether it was scheduled at all.
		_G.C_Timer.NewTimer = function(_, fn)
			---@diagnostic disable-next-line: missing-parameter
			fn()
			return { Cancel = function() end }
		end
		ns.lib:OnEnable()
	end)

	after_each(function()
		ns.BrowserTab.Warm = saved.Warm
		ns.MainWindow.QueueRefresh = saved.QueueRefresh
		ns.MainWindow.activeTab = saved.activeTab
		_G.C_Timer.NewTimer = saved.NewTimer
	end)

	it("re-warms the Professions cache AND refreshes the window on a recipe change", function()
		ns.callbacks:Fire("GUILD_DATA_UPDATED", "Bob-Testrealm", { recipes = true })
		assert.equal(1, warmed, "BrowserTab's re-warm was replaced by another subscriber")
		assert.equal(1, queued, "MainWindow's refresh did not run")
	end)
end)

describe("TOGPM's LibGuildRoster subscriptions are keyed by TOGPM", function()
	-- `lib:RegisterCallback(event, fn)` keys the slot by the LIBRARY, a slot any
	-- other addon doing the same would share and overwrite (Peer Review M1).
	local events = { "OnMemberOnline", "OnRosterReady", "OnMemberLeft", "OnMemberJoined",
	                 "OnSisterConfigChanged", "OnSisterRosterUpdated", "OnGuildTagsChanged" }

	setup(function()
		if env.libs.loaded["LibDBIcon-1.0"] then env.libs.fresh("LibDBIcon-1.0") end
		ns.lib:OnEnable()
	end)

	for _, ev in ipairs(events) do
		it(ev .. " is registered as the addon, not the library", function()
			local GR = LibStub("LibGuildRoster-1.0")
			local byOwner = GR.callbacks.events[ev]
			assert.is_function(byOwner[ns])
			assert.is_nil(rawget(byOwner, GR))
		end)
	end
end)

describe("each module's addon-event subscription is its own", function()
	-- One slot per subscriber: the registry's key for each event must be the
	-- module, never the addon itself, so a second subscriber cannot evict it.
	local cases = {
		{ "AH_OPEN_STATE_CHANGED", function() return ns.GUI end },
		{ "AH_SCAN_COMPLETE",      function() return ns.GUI end },
		{ "SYNC_SENT",             function() return ns.SyncLog end },
		{ "SYNC_RECV",             function() return ns.SyncLog end },
		{ "SYNC_REQ",              function() return ns.SyncLog end },
		{ "SYNC_VER",              function() return ns.SyncLog end },
	}
	for _, c in ipairs(cases) do
		it(c[1] .. " is keyed by its module, not the addon", function()
			local byOwner = ns.callbacks.events[c[1]]
			assert.is_function(byOwner[c[2]()])
			assert.is_nil(rawget(byOwner, ns))
		end)
	end
end)
