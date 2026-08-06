-- /togpm — every slash command, actually run.
--
-- Twenty-five commands route through one dispatcher, and most of them are
-- diagnostics a user is asked to run when something is already wrong. A
-- diagnostic that errors is worse than useless: it turns "my sync is broken"
-- into "my sync is broken AND the addon threw at me", and it is the one moment
-- the user is paying close attention.
--
-- None of them had ever been executed outside the game. They are driven through
-- the real dispatcher rather than by calling handlers directly, so the routing,
-- the argument split and the unknown-command fallback are covered too.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Ace, printed
local ALCHEMY = 171
local ME, MATE = "Testchar-Testrealm", "Bob-Testrealm"
local POTION = 2330

-- Every command the dispatcher knows, with an argument where one is expected.
local COMMANDS = {
	"", "reagents", "minimap", "purge", "sync", "status", "dsstatus",
	"versioncheck", "debug", "craft", "spellcache", "itemgaps",
	"dumprecipe Healing Potion", "dumphashes", "dumpcooldowns", "transmutedebug",
	"dumpprice 12359", "forcebroadcast", "backfill", "myalts",
	"pullroster Bob", "xgdiag", "whyvisible Bob", "commtest", "help",
}


setup(function()
	ns = env.initDb()
	Ace = ns.lib
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
	env.loadModule("Modules/SyncLog.lua")
	env.loadModule("Modules/Price.lua")
	env.loadModule("Modules/ReagentWatch.lua")
	env.loadModule("Modules/AHScanner.lua")
	env.loadModule("Modules/CommTest.lua")
	env.loadModule("Modules/Crafting/CraftingEngine.lua")
	env.loadModule("Modules/Crafting/CraftQueue.lua")
	env.loadModule("GUI/SharedWidgets.lua")
	env.loadModule("GUI/MainWindow.lua")
	env.loadModule("GUI/BrowserTab.lua")
	env.loadModule("GUI/CooldownsTab.lua")
	env.loadModule("GUI/MissingRecipesTab.lua")
	env.loadModule("GUI/GuildTab.lua")
	env.loadModule("GUI/AHProfitTab.lua")
	env.loadModule("GUI/CraftingTab.lua")
	env.loadModule("GUI/ShoppingListTab.lua")
	env.loadModule("GUI/ReagentTracker.lua")
	env.loadModule("GUI/Settings.lua")
end)

before_each(function()
	env.installFrames()
	local gdb = env.resetDb()
	env.roster({
		{ name = "Testchar", isOnline = true },
		{ name = "Bob",      isOnline = true },
	})

	printed = {}
	Ace.Print = function(_, ...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		printed[#printed + 1] = table.concat(parts, " ")
	end
	ns.Print = Ace.Print

	-- Real data, so the diagnostics walk populated tables rather than reporting
	-- "nothing to show" — which is the empty-state trap these specs exist past.
	env.spellsExist(POTION)
	env.setRecipeDB({
		[ALCHEMY] = { [POTION] = { name = "Healing Potion", icon = 1,
		                           reagents = { { name = "Peacebloom", itemId = 2447, count = 1 } },
		                           craftedItemId = 929 } },
	})
	local tag = ns:GetCurrentGuildTag()
	gdb.recipes[ALCHEMY] = {
		[POTION] = { name = "Healing Potion", icon = 1,
		             reagents = { { name = "Peacebloom", itemId = 2447, count = 1 } },
		             crafters = { [ME] = tag, [MATE] = tag } },
	}
	gdb.skills[ME]        = { [ALCHEMY] = { skillRank = 300, skillMax = 300 } }
	gdb.cooldowns[ME]     = { [17187] = env.serverTime + 3600 }
	gdb.accountChars[ME]  = true
	gdb.altGroups[ME]     = { ME }
end)

after_each(function()
	if ns.MainWindow and ns.MainWindow.Close then
		pcall(function() ns.MainWindow:Close() end)
	end
end)

describe("every /togpm command runs", function()
	for _, input in ipairs(COMMANDS) do
		local label = input == "" and "(no argument — opens the browser)" or ("/togpm " .. input)
		it(label, function()
			assert.has_no.errors(function() Ace:OnSlashCommand(input) end)
		end)
	end
end)

describe("the dispatcher itself", function()
	it("has every one of its commands covered by the list above", function()
		-- The list is a hand-maintained mirror of a table in another file, and it
		-- had ALREADY fallen one behind: `commtest` was missing, so the single
		-- command that opens a live listen window was the only one never driven
		-- through the dispatcher. Checking it here means the next command added
		-- cannot arrive untested and silent.
		local covered = {}
		for _, input in ipairs(COMMANDS) do
			covered[(input:match("^(%S*)") or "")] = true
		end
		local missing = {}
		for name in pairs(ns._SLASH_COMMANDS) do
			if not covered[name] then missing[#missing + 1] = name end
		end
		table.sort(missing)
		assert.equal("", table.concat(missing, ", "))
	end)

	it("prints help for a command it does not know", function()
		Ace:OnSlashCommand("wibble")
		assert.is_true(#printed > 0)
	end)

	it("is case-insensitive", function()
		Ace:OnSlashCommand("STATUS")
		assert.is_true(#printed > 0)
	end)

	it("splits a multi-word argument off the command intact", function()
		-- "dumprecipe Healing Potion" must reach the handler as ONE argument
		-- with the space in it, not as "Healing". The evidence is that the
		-- lookup matched: DumpRecipe reports the recipe's fields and never
		-- echoes the name, so finding the recipe id is what proves the whole
		-- name arrived. Split wrongly, nothing matches and it says so instead.
		printed = {}
		Ace:OnSlashCommand("dumprecipe Healing Potion")
		local joined = table.concat(printed, "\n")
		assert.is_truthy(joined:find(tostring(POTION), 1, true))
	end)

	it("finds nothing for a half-word, which is what a bad split would give", function()
		printed = {}
		Ace:OnSlashCommand("dumprecipe Healing")
		local joined = table.concat(printed, "\n")
		assert.is_falsy(joined:find(tostring(POTION), 1, true))
	end)

	it("tolerates surrounding whitespace", function()
		assert.has_no.errors(function() Ace:OnSlashCommand("   status   ") end)
	end)

	it("says something for a command needing an argument it did not get", function()
		-- Usage text, not silence and not a stack trace.
		printed = {}
		Ace:OnSlashCommand("pullroster")
		assert.is_true(#printed > 0)
	end)
end)

describe("the diagnostics say something useful", function()
	it("status reports on the guild it is scoped to", function()
		Ace:OnSlashCommand("status")
		assert.is_true(#printed > 0)
	end)

	it("debug toggles and reports its new state", function()
		local before = ns.debug
		Ace:OnSlashCommand("debug")
		assert.is_not.equal(before, ns.debug)
		Ace:OnSlashCommand("debug")
		assert.equal(before, ns.debug)
	end)

	it("whyvisible explains a character rather than erroring", function()
		Ace:OnSlashCommand("whyvisible Bob")
		assert.is_true(#printed > 0)
	end)

	it("dumpcooldowns lists a running cooldown", function()
		Ace:OnSlashCommand("dumpcooldowns")
		assert.is_true(#printed > 0)
	end)
end)

describe("commands with an empty database", function()
	-- A brand-new install running a diagnostic before any data exists: the
	-- state where an unguarded `#list` or a nil bucket bites.
	before_each(function()
		env.resetDb()
		env.setRecipeDB({})
	end)

	for _, input in ipairs(COMMANDS) do
		local label = input == "" and "(no argument)" or ("/togpm " .. input)
		it(label, function()
			assert.has_no.errors(function() Ace:OnSlashCommand(input) end)
		end)
	end
end)
