-- WoW Forever character keys.
--
-- Discord report, 2026-11-08: on Forever no guildmate's professions ever
-- showed, on anyone's client, though every client was sending and receiving
-- (the status output read sends=24 rcvs=176). Forever names are regionally
-- unique "First Last" and carry no realm; UnitName's second return there is the
-- SURNAME. This addon keyed a character "First-Realm", which matches no roster
-- entry (LibGuildRoster keys Forever members "First Last"), and the receive
-- path's NormalizeName cut it to "First" -- so every guildmate's data was filed
-- under a name the roster gate rejects.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, Ace, gdb
local GR

setup(function()
	ns = env.initDb()
	Ace = ns.lib
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	env.loadModule("Scanner.lua")
end)

before_each(function()
	env.install()
	gdb = env.resetDb()
	GR = LibStub("LibGuildRoster-1.0")
end)

after_each(function()
	_G.RegionalUniqueNamesEnabled = nil
	env.installIdentity()
end)

local function onForever()
	_G.RegionalUniqueNamesEnabled = function() return true end
	_G.UnitName = function() return "Vishi", "Swaz" end
end

describe("GetCharacterKey", function()
	it("is Name-Realm on a client without regional names", function()
		assert.equal("Testchar-Testrealm", ns:GetCharacterKey())
	end)

	it("is the full name with no realm on WoW Forever", function()
		onForever()
		assert.equal("Vishi Swaz", ns:GetCharacterKey())
	end)

	it("spells the player exactly as the roster library keys them", function()
		onForever()
		assert.equal(GR:GetNormalizedPlayer(), ns:GetCharacterKey())
		-- And survives the receive path's normalisation unchanged, so an
		-- incoming payload's key and the roster agree.
		assert.equal(ns:GetCharacterKey(), GR:NormalizeName(ns:GetCharacterKey()))
	end)

	it("still builds an explicit name and realm as asked", function()
		onForever()
		assert.equal("Bob-Otherrealm", ns:GetCharacterKey("Bob", "Otherrealm"))
	end)
end)

describe("the old Forever key on login", function()
	it("leaves the account set and is queued for the roster-gated purge", function()
		onForever()
		local legacy = "Vishi" .. "-" .. env.DEFAULTS.realmName
		local ac = ns.guildDb.global.accountChars
		ac[legacy] = true
		assert.is_true(ac[legacy])
		Ace:OnPlayerEnteringWorld("PLAYER_ENTERING_WORLD", true, false)
		assert.is_nil(ac[legacy])
		assert.is_true(ac[ns:GetCharacterKey()])
		assert.is_true(gdb.pendingPurge[legacy])
	end)

	it("touches nothing on a client without regional names", function()
		local me = ns:GetCharacterKey()
		local ac = ns.guildDb.global.accountChars
		Ace:OnPlayerEnteringWorld("PLAYER_ENTERING_WORLD", true, false)
		assert.is_true(ac[me])
		assert.is_falsy(gdb.pendingPurge and gdb.pendingPurge[me])
	end)
end)
