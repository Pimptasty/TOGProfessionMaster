-- Chat lines carry the brand, not the internal addon name (v1.7.0).
--
-- AceConsole's Print prefixes every line with the AceAddon name,
-- "TOGProfessionMaster", which stays because saved data and sync are keyed by
-- it. The operator saw that prefix on every line of "/upm help" after the
-- rebrand, so TOGProfessionMaster.lua replaces Print/Printf with a "UPM:"
-- prefix in the brand colour. These examples pin that, and that the env puts
-- the real Print back after a spec replaces it.

---@diagnostic disable: duplicate-set-field, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Ace, said, savedFrame

setup(function()
	ns = env.initDb()
	Ace = ns.lib
end)

before_each(function()
	env.resetDb()
	savedFrame = _G.DEFAULT_CHAT_FRAME
	said = {}
	_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) said[#said + 1] = msg end }
end)

after_each(function()
	_G.DEFAULT_CHAT_FRAME = savedFrame
end)

local PREFIX = "|c" .. "ffFF8000" .. "UPM|r: "

describe("Print", function()
	it("prefixes the line with UPM in the brand colour", function()
		Ace:Print("hello", 42)
		assert.are.equal(1, #said)
		assert.are.equal("|c" .. (ns.BrandColor or "ffFF8000") .. "UPM|r: hello 42", said[1])
		assert.are.equal(PREFIX .. "hello 42", said[1])
	end)

	it("never shows the internal addon name", function()
		Ace:Print("x")
		assert.is_nil(said[1]:find("TOGProfessionMaster", 1, true))
	end)

	it("writes to a chat frame passed as the first argument", function()
		local other = {}
		local frame = { AddMessage = function(_, msg) other[#other + 1] = msg end }
		Ace:Print(frame, "to the other frame")
		assert.are.equal(0, #said)
		assert.are.same({ PREFIX .. "to the other frame" }, other)
	end)

	it("is what addon:Print uses", function()
		ns:Print("via the addon")
		assert.are.same({ PREFIX .. "via the addon" }, said)
	end)
end)

describe("Printf", function()
	it("formats, then prefixes", function()
		Ace:Printf("%d of %s", 3, "five")
		assert.are.same({ PREFIX .. "3 of five" }, said)
	end)

	it("formats to a chat frame passed first", function()
		local other = {}
		local frame = { AddMessage = function(_, msg) other[#other + 1] = msg end }
		Ace:Printf(frame, "%s!", "hi")
		assert.are.equal(0, #said)
		assert.are.same({ PREFIX .. "hi!" }, other)
	end)
end)

describe("/upm help", function()
	it("lists every command as /upm and says /togpm still works", function()
		Ace:PrintHelp()
		assert.is_true(#said > 3)
		local note = 0
		for _, line in ipairs(said) do
			assert.are.equal(PREFIX, line:sub(1, #PREFIX))
			if line:find("/togpm still works the same as /upm", 1, true) then
				note = note + 1
			elseif line:find("/", 1, true) then
				assert.is_truthy(line:find("  /upm", 1, true), line)
				assert.is_nil(line:find("/togpm", 1, true), line)
			end
		end
		assert.are.equal(1, note)
	end)
end)

describe("the env reset", function()
	it("puts the real Print back after a spec replaces it", function()
		Ace.Print = function() end
		Ace.Printf = function() end
		env.resetDb()
		Ace:Printf("%s", "restored")
		assert.are.same({ PREFIX .. "restored" }, said)
	end)
end)
