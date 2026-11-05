-- The system-message filter that hides the "No player named X is currently
-- playing." spam the sync's own whispers to logged-off guildmates produce.
--
-- Player report, 2026-11-05 (Retail): chat payloads can arrive as secret
-- values, which type() still calls "string" but which error when indexed. The
-- filter runs on every system message, so it must pass a secret one through
-- untouched rather than call :find on it.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local S, filter

setup(function()
	env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	S = env.loadModule("Scanner.lua").Scanner
	env.install()
	env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true } })
	S.DS = nil
	_G.ChatFrame_AddMessageEventFilter = function(event, fn)
		if event == "CHAT_MSG_SYSTEM" then filter = fn end
	end
	S:Init()
end)

after_each(function()
	_G.issecretvalue = nil
end)

describe("the CHAT_MSG_SYSTEM filter", function()
	it("is installed by Init", function()
		assert.is_function(filter)
	end)

	it("hides the offline-whisper error in both phrasings", function()
		assert.is_true(filter(nil, "CHAT_MSG_SYSTEM", "No player named 'Bob' is currently playing."))
		assert.is_true(filter(nil, "CHAT_MSG_SYSTEM", "Player not found."))
	end)

	it("lets every other system message through", function()
		assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", "Testchar has come online."))
		assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", "No player named here, just chat."))
		assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", nil))
	end)

	it("lets a secret message through without indexing it", function()
		local secret = "No player named 'Bob' is currently playing."
		_G.issecretvalue = function(v) return v == secret end
		assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", secret))
	end)
end)
