-- Load order must not be able to break the shared-helper aliases. Audit finding 6.
--
-- THE BUG THIS EXISTS FOR. Deduplicating small helpers into `addon.UI.*`
-- (findings 1 and 3) was the right fix, but it was written as a FILE-SCOPE
-- CAPTURE in seven places:
--
--     local Brand = addon.UI.Brand      -- reads the value ONCE, as the file loads
--
-- That turned "these files are independent" into "SharedWidgets.lua must load
-- before six others", recorded nowhere but a comment. Move SharedWidgets below any
-- consumer and every alias in that file is nil at capture time, then raises on
-- first use — loud, total, and a long way from the TOC line that caused it.
--
-- TWO GUARDS, because they fail differently and one does not imply the other:
--
--   1. NO FILE-SCOPE CAPTURES. The real fix, and the only one that removes the
--      class rather than asserting against it: resolve inside a wrapper
--      (`local function Brand(t) return addon.UI.Brand(t) end`) and load order
--      stops mattering for these helpers entirely. This guard is what stops the
--      capture shape coming back — it is cheaper to write than to notice.
--   2. THE TOC ORDERING STILL HOLDS. Guard 1 makes the aliases safe; it does NOT
--      make everything safe. `addon.UI` must still exist before a tab's functions
--      RUN, and other file-scope reads of shared tables are a live shape here. So
--      the ordering is asserted directly, in every TOC, the way ClassicCalendar's
--      tocorder_spec does. ClassicCalendar shipped a real defect of this class —
--      LibDBIcon listed without the LibDataBroker it hard-requires, erroring on
--      every load and invisible in development because another installed addon
--      registered the library first.
--
-- Note this file reads SOURCE and TOC TEXT rather than loading anything: the
-- failure is about the order files load in, which a loaded module cannot observe.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path

local TOCS = {
	"TOGProfessionMaster.toc",
	"TOGProfessionMaster_TBC.toc",
	"TOGProfessionMaster_Wrath.toc",
	"TOGProfessionMaster_Cata.toc",
	"TOGProfessionMaster_Mists.toc",
}

local function read(path)
	local f = assert(io.open(path, "r"), "missing file: " .. path)
	local body = f:read("*a")
	f:close()
	return body
end

--- Source with comments removed, so prose describing a capture does not read as
--- one. Same idiom as recipegate_spec.
local function code(path)
	local body = read(path)
	body = body:gsub("%-%-%[%[.-%]%]", " ")
	body = body:gsub("%-%-[^\n]*", " ")
	return body
end

--- The .lua files a TOC loads, in order, lowercased with forward slashes.
local function tocFiles(path)
	local out = {}
	for line in read(path):gmatch("[^\r\n]+") do
		line = line:match("^%s*(.-)%s*$")
		if line ~= "" and not line:match("^#") and line:lower():match("%.lua$") then
			out[#out + 1] = line:gsub("\\", "/"):lower()
		end
	end
	return out
end

local function indexOf(list, name)
	for i = 1, #list do
		if list[i] == name then return i end
	end
	return nil
end

describe("no GUI file captures a shared helper at file scope", function()
	-- Enumerated by reading the directory, NOT by listing the files known to
	-- have had the problem: the point is to catch the NEXT one. A grep for the
	-- seven known sites would pass forever while an eighth was added.
	local function guiFiles()
		local out = {}
		local p = io.popen('ls GUI/*.lua 2>/dev/null || dir /b GUI\\*.lua 2>nul')
		if p then
			for line in p:lines() do
				line = line:match("^%s*(.-)%s*$")
				if line ~= "" then
					out[#out + 1] = line:match("GUI/") and line or ("GUI/" .. line)
				end
			end
			p:close()
		end
		return out
	end

	it("finds the GUI sources to check", function()
		-- Guards the guard: an empty list would make every assertion below
		-- vacuous, which is the silently-passing-test failure mode.
		assert.is_true(#guiFiles() >= 8,
			"expected to enumerate the GUI sources; got " .. #guiFiles())
	end)

	it("uses a call-time wrapper, never `local X = addon.UI.Y`", function()
		local offenders = {}
		for _, path in ipairs(guiFiles()) do
			for line in code(path):gmatch("[^\r\n]+") do
				-- File scope only: a capture INSIDE a function (indented) is
				-- resolved per call and is exactly the safe shape.
				local name = line:match("^local%s+([%w_]+)%s*=%s*addon%.UI%.[%w_]+%s*$")
				if name then
					offenders[#offenders + 1] = path .. " -> local " .. name
				end
			end
		end
		table.sort(offenders)
		assert.equal("", table.concat(offenders, " | "),
			"file-scope capture of addon.UI.* makes SharedWidgets' TOC position "
			.. "load-bearing; wrap it instead: local function f(x) return addon.UI.F(x) end")
	end)
end)

describe("every TOC loads SharedWidgets before the tabs that use it", function()
	-- The consumers, by the helper each one reaches for. Listed explicitly rather
	-- than derived, so adding a tab that uses addon.UI without adding it here is
	-- caught by the sweep below instead of silently skipped.
	local CONSUMERS = {
		"gui/browsertab.lua",
		"gui/cooldownstab.lua",
		"gui/missingrecipestab.lua",
		"gui/craftingtab.lua",
		"gui/ahprofittab.lua",
		"gui/guildtab.lua",
		"gui/settings.lua",
	}

	for _, toc in ipairs(TOCS) do
		it(toc .. " puts SharedWidgets first", function()
			local files = tocFiles(toc)
			local shared = indexOf(files, "gui/sharedwidgets.lua")
			assert.is_not_nil(shared, toc .. " does not load GUI/SharedWidgets.lua at all")

			local late = {}
			for _, consumer in ipairs(CONSUMERS) do
				local at = indexOf(files, consumer)
				-- A TOC legitimately need not carry every tab; only order the
				-- ones it does load.
				if at and at < shared then late[#late + 1] = consumer end
			end
			table.sort(late)
			assert.equal("", table.concat(late, " | "),
				toc .. " loads these before GUI/SharedWidgets.lua")
		end)
	end

	it("the sweep — every file reading addon.UI is in the CONSUMERS list", function()
		-- Stops CONSUMERS going stale. If a new tab starts using addon.UI and
		-- nobody adds it above, this fails rather than quietly not checking it.
		local missing = {}
		local files = tocFiles(TOCS[1])
		for _, path in ipairs(files) do
			if path:match("^gui/") and path ~= "gui/sharedwidgets.lua" then
				local body = code(path)
				if body:match("addon%.UI%.") then
					local listed = false
					for _, c in ipairs(CONSUMERS) do
						if c == path then listed = true break end
					end
					if not listed then missing[#missing + 1] = path end
				end
			end
		end
		table.sort(missing)
		assert.equal("", table.concat(missing, " | "),
			"these read addon.UI but are not in the CONSUMERS ordering check")
	end)
end)
