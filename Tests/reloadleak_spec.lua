-- Reloading a module lets the previous copy go.
--
-- Every spec file loads the modules it tests afresh (env.loadModule in its
-- setup), while the addon core, Ace3 and the suite libraries are loaded ONCE
-- for the whole run. Anything a module hands one of those once-loaded objects
-- -- a callback, a listener, a frame parented somewhere permanent -- keeps that
-- module's whole previous copy alive, with every frame it built. WoWAPITesting
-- measured the cost on 2026-09-30 (thread 83f92459): the suite's heap climbed
-- from 4.5 MB to 377-720 MB, ~20,600 frames stayed alive, and ~85% of the run
-- was full garbage collections paying for them.
--
-- Each case loads a module (drawing it, for a tab), reloads it, collects, and
-- asserts the first copy is gone. A failure names the module being held.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns

setup(function()
	ns = env.initDb()
	-- The real LibItemDB, with its callback registry: AHScanner registers on it,
	-- and a stub has no registry to hold anything (the full-suite failure of
	-- 2026-10-01 only appeared after another spec had installed the real one).
	env.priceDB()
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
end)

before_each(function()
	env.installFrames()
	env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	ns.Print = function() end
end)

--- The shortest chain of references from the globals (and the Lua registry) to
--- `target`, as a readable path, or nil when nothing reaches it. Walks table
--- keys and values, metatables, function upvalues and environments -- the ways
--- one Lua object holds another. Weak tables are skipped, since they hold
--- nothing. Used only to make a failure below say WHAT holds the old copy.
local function pathTo(target)
	---@type table<any, table|false>
	local seen = { [target] = false }
	local queue, head = {}, 1
	local function push(obj, from, label)
		local t = type(obj)
		if (t == "table" or t == "function" or t == "userdata") and seen[obj] == nil then
			seen[obj] = { from = from, label = label }
			queue[#queue + 1] = obj
		end
		if obj == target and seen[target] == false then
			seen[target] = { from = from, label = label }
		end
	end
	push(_G, nil, "_G")
	push(debug.getregistry(), nil, "registry")
	while head <= #queue and not seen[target] do
		local obj = queue[head]; head = head + 1
		local t = type(obj)
		if t == "table" then
			local mt = getmetatable(obj)
			local mode = type(mt) == "table" and rawget(mt, "__mode") or nil
			if mt then push(mt, obj, "<metatable>") end
			local weakK = mode and tostring(mode):find("k")
			local weakV = mode and tostring(mode):find("v")
			for k, v in next, obj do
				if not weakK then push(k, obj, "<key>") end
				if not weakV then push(v, obj, "." .. tostring(k)) end
			end
		elseif t == "function" then
			local i = 1
			while true do
				local name, v = debug.getupvalue(obj, i)
				if not name then break end
				push(v, obj, "<upvalue " .. name .. ">")
				i = i + 1
			end
			local fenv = getfenv(obj)
			if fenv ~= _G then push(fenv, obj, "<env>") end
		end
	end
	if not seen[target] then return nil end
	local parts, node = {}, target
	while node and seen[node] do
		table.insert(parts, 1, seen[node].label)
		node = seen[node].from
	end
	return table.concat(parts, " -> ")
end

--- Load `path`, optionally draw what it exposes as ns[field], then load it
--- again and report whether the first copy survived a full collection, and if
--- it did, the chain that holds it.
local function survivesReload(path, field, draw)
	env.loadModule(path)
	local held = setmetatable({}, { __mode = "v" })
	held[1] = ns[field]
	assert.is_table(held[1], "the module did not publish ns." .. field)
	if draw then env.drawTab(held[1]) end
	env.loadModule(path)
	assert.are_not.equal(held[1], ns[field], "the reload did not replace ns." .. field)
	-- The next example's reset: a fresh UIParent and frame registry, as every
	-- spec's before_each installs. Frames parked on the OLD UIParent go with it.
	env.installFrames()
	collectgarbage("collect")
	collectgarbage("collect")
	if held[1] == nil then return false end
	return true, pathTo(held[1]) or "(no path found from _G or the registry)"
end

--- Load `path` twice and return every namespace table the second load REPLACED
--- that is still alive after a reset and a full collection, as "ns.<key> held
--- by: <path>" lines. Not tied to one field: a module may publish several
--- tables (Crafting publishes an engine and a queue), and any of them is a leak.
local function replacedSurvivors(path)
	env.loadModule(path)
	local before = {}
	for k, v in pairs(ns) do
		if type(v) == "table" then before[k] = v end
	end
	-- A reset between the loads, as between two spec files: the harness
	-- replaces a hook re-made from the same line only across a reset (pin
	-- 515873b); within one reset both stay, as two hooks would in game.
	env.installFrames()
	env.loadModule(path)
	local held = setmetatable({}, { __mode = "v" })
	local keys = {}
	for k, old in pairs(before) do
		if ns[k] ~= old then
			keys[#keys + 1] = k
			held[k] = old
		end
		-- Dropped as we go: a strong copy here would hold what is being tested.
		before[k] = nil
	end
	env.installFrames()
	collectgarbage("collect")
	collectgarbage("collect")
	local out = {}
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do
		if held[k] ~= nil then
			out[#out + 1] = "ns." .. tostring(k) .. " held by: "
				.. (pathTo(held[k]) or "(no path found from _G or the registry)")
		end
	end
	return out, #keys
end

describe("a reloaded module lets every table it replaced go", function()
	-- Every TOC file that publishes a table and loads in this env, tabs
	-- excluded (drawn and covered below). The heap still reached ~334 MB after
	-- the tab holders were fixed (2026-10-01), so the rest of the growth is in
	-- something a tab does not cover.
	for _, path in ipairs({
		"Scanner.lua",
		"Modules/HashManager.lua",
		"Modules/ReagentWatch.lua",
		"Modules/SyncLog.lua",
		"Modules/CommTest.lua",
		"Modules/AHScanner.lua",
		"Modules/Price.lua",
		"Modules/CooldownAlerts.lua",
		"Modules/Crafting/CraftingEngine.lua",
		"Modules/Crafting/CraftQueue.lua",
		"GUI/MinimapButton.lua",
		"GUI/MainWindow.lua",
		"GUI/SharedWidgets.lua",
		"GUI/ReagentTracker.lua",
		"GUI/Settings.lua",
		"Tooltip.lua",
	}) do
		it(path, function()
			local alive, replaced = replacedSurvivors(path)
			assert.equal("", table.concat(alive, " | "),
				path .. ": " .. #alive .. " of " .. replaced .. " replaced table(s) survived a reload")
		end)
	end
end)

describe("a reloaded tab lets its previous copy go", function()
	for _, case in ipairs({
		{ "GUI/BrowserTab.lua",        "BrowserTab" },
		{ "GUI/CooldownsTab.lua",      "CooldownsTab" },
		{ "GUI/MissingRecipesTab.lua", "MissingRecipesTab" },
		{ "GUI/GuildTab.lua",          "GuildTab" },
		{ "GUI/AHProfitTab.lua",       "AHProfitTab" },
		{ "GUI/CraftingTab.lua",       "CraftingTab" },
	}) do
		it(case[2] .. ", after drawing", function()
			local alive, path = survivesReload(case[1], case[2], true)
			assert.is_false(alive, case[2] .. " is still alive after a reload, held by: " .. tostring(path))
		end)
	end
end)
