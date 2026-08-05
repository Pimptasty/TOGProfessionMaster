-- Modules/CooldownAlerts.lua — when the "your cooldown is ready" ding fires.
--
-- This is a state machine over persisted data, and every one of its rules is
-- about NOT annoying the player: fire once on the transition to ready, stay
-- quiet afterwards unless a reminder interval was asked for, say nothing at all
-- while the user is in an instance if they turned that on, and start over
-- cleanly once the cooldown is re-cast. Get any of those wrong and the addon
-- either nags every 30 seconds or never speaks — both silent failures, because
-- the code path only runs on a timer nobody watches.
--
-- Group rows resolve to the LATEST expiry among their member spells, matching
-- what the Cooldowns tab shows, so the ding lands the moment the row the user
-- is looking at reaches zero.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")

local ns, CA, gdb, saved, printed

local ME     = "Testchar-Testrealm"
local ALT    = "Alt-Testrealm"
local FOREIGN = "Someoneelse-Testrealm"

-- Two transmutes and one generic group ("mooncloth"), as the catalogue shapes them.
local TRANS_A, TRANS_B = 17187, 17559
local CLOTH_A, CLOTH_B = 18560, 18561
local SALT             = 15846

local NOW = 100000

setup(function()
	ns = env.initDb()
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/CooldownAlerts.lua")
	CA = ns.CooldownAlerts or ns.CA
end)

before_each(function()
	env.installFrames()
	gdb = env.resetDb()

	saved = {
		Print           = ns.Print,
		GetCooldownData = ns.GetCooldownData,
		IsInInstance    = _G.IsInInstance,
		PlaySound       = _G.PlaySound,
	}
	printed = {}
	ns.Print       = function(_, msg) printed[#printed + 1] = tostring(msg) end
	_G.IsInInstance = function() return false end
	_G.PlaySound    = function() end

	ns.GetCooldownData = function()
		return {
			transmutes   = { [TRANS_A] = true, [TRANS_B] = true },
			groupBySpell = {
				[CLOTH_A] = { groupKey = "mooncloth" },
				[CLOTH_B] = { groupKey = "mooncloth" },
			},
		}
	end

	-- Both characters are ours; the alert store only tracks own-account chars.
	gdb.accountChars[ME]  = true
	gdb.accountChars[ALT] = true
	gdb.cooldowns = {}

	env.serverTime = NOW
	ns.lib.db.char.cooldownAlerts = {}
	ns.lib.db.profile.cooldownAlertReminderMinutes  = 0
	ns.lib.db.profile.cooldownAlertSuppressProtected = false
	CA._lastFiredAt = {}
end)

after_each(function()
	ns.Print           = saved.Print
	ns.GetCooldownData = saved.GetCooldownData
	_G.IsInInstance    = saved.IsInInstance
	_G.PlaySound       = saved.PlaySound
end)

--- Arm an alert directly, as Toggle would have.
local function arm(key, meta)
	ns.lib.db.char.cooldownAlerts[key] = meta
end

local function cooldownOn(charKey, spellId, expiry)
	gdb.cooldowns[charKey] = gdb.cooldowns[charKey] or {}
	gdb.cooldowns[charKey][spellId] = expiry
end

describe("GetKey", function()
	it("keys a transmute group by character", function()
		assert.equal(ME .. ":transmute",
			CA:GetKey({ charKey = ME, isTransmuteGroup = true }))
	end)

	it("keys a generic group by its group key", function()
		assert.equal(ME .. ":group:mooncloth",
			CA:GetKey({ charKey = ME, isGroup = true, group = { groupKey = "mooncloth" } }))
	end)

	it("keys a single spell by its id", function()
		assert.equal(ME .. ":spell:" .. SALT, CA:GetKey({ charKey = ME, spellId = SALT }))
	end)

	it("refuses a row with nothing to key on", function()
		assert.is_nil(CA:GetKey(nil))
		assert.is_nil(CA:GetKey({ spellId = SALT }))          -- no character
		assert.is_nil(CA:GetKey({ charKey = ME }))            -- no spell or group
	end)
end)

describe("Check — the first ding", function()
	it("fires when the cooldown has expired", function()
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT, label = "Salt Shaker" })
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		assert.equal(1, #printed)
		assert.is_truthy(printed[1]:find("Testchar", 1, true))
	end)

	it("says nothing while the cooldown is still running", function()
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		cooldownOn(ME, SALT, NOW + 3600)
		CA:Check()
		assert.equal(0, #printed)
	end)

	it("says nothing for a cooldown that has never been recorded", function()
		-- The player has armed a row for a spell they have not cast on this
		-- client. Nothing to alert on, and it must not be treated as ready.
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		CA:Check()
		assert.equal(0, #printed)
	end)

	it("does nothing at all when no alert is armed", function()
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		assert.equal(0, #printed)
	end)
end)

describe("Check — not nagging", function()
	it("does not fire again on the next pass", function()
		-- Check() runs every 30s. Without the dedup clock this is a ding every
		-- 30 seconds until the player re-casts.
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		CA:Check()
		CA:Check()
		assert.equal(1, #printed)
	end)

	it("repeats once the reminder interval has elapsed", function()
		ns.lib.db.profile.cooldownAlertReminderMinutes = 10
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		assert.equal(1, #printed)

		env.serverTime = NOW + 9 * 60        -- not yet
		CA:Check()
		assert.equal(1, #printed)

		env.serverTime = NOW + 10 * 60       -- due
		CA:Check()
		assert.equal(2, #printed)
	end)

	it("starts over after the cooldown is re-cast", function()
		-- Craft it again and the clock resets, so the NEXT expiry gets a fresh
		-- first alert rather than being treated as already-announced.
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		assert.equal(1, #printed)

		cooldownOn(ME, SALT, NOW + 3600)     -- re-cast
		CA:Check()
		assert.equal(1, #printed)

		env.serverTime = NOW + 7200          -- ready again
		CA:Check()
		assert.equal(2, #printed)
	end)
end)

describe("Check — instance suppression", function()
	it("stays quiet in an instance when the setting is on", function()
		ns.lib.db.profile.cooldownAlertSuppressProtected = true
		_G.IsInInstance = function() return true end
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		assert.equal(0, #printed)
	end)

	it("still fires once the player leaves the instance", function()
		-- Suppressed must mean DEFERRED, not swallowed: the dedup clock is only
		-- set when the alert actually fires.
		ns.lib.db.profile.cooldownAlertSuppressProtected = true
		_G.IsInInstance = function() return true end
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		assert.equal(0, #printed)

		_G.IsInInstance = function() return false end
		CA:Check()
		assert.equal(1, #printed)
	end)

	it("fires in an instance when the setting is off", function()
		ns.lib.db.profile.cooldownAlertSuppressProtected = false
		_G.IsInInstance = function() return true end
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		assert.equal(1, #printed)
	end)

	it("fires in the open world with the setting on", function()
		ns.lib.db.profile.cooldownAlertSuppressProtected = true
		arm(ME .. ":spell:" .. SALT, { charKey = ME, spellId = SALT })
		cooldownOn(ME, SALT, NOW - 1)
		CA:Check()
		assert.equal(1, #printed)
	end)
end)

describe("Check — group rows use the LATEST member expiry", function()
	it("waits for the last transmute in the group", function()
		-- The tab shows the group counting down to its longest remaining
		-- member; the ding has to land at the same moment, not on the first.
		arm(ME .. ":transmute", { charKey = ME, groupKind = "transmute", label = "Transmute" })
		cooldownOn(ME, TRANS_A, NOW - 100)   -- ready
		cooldownOn(ME, TRANS_B, NOW + 600)   -- still running
		CA:Check()
		assert.equal(0, #printed)

		env.serverTime = NOW + 601
		CA:Check()
		assert.equal(1, #printed)
	end)

	it("does the same for a named group", function()
		arm(ME .. ":group:mooncloth",
			{ charKey = ME, groupKind = "group:mooncloth", label = "Mooncloth" })
		cooldownOn(ME, CLOTH_A, NOW - 100)
		cooldownOn(ME, CLOTH_B, NOW + 300)
		CA:Check()
		assert.equal(0, #printed)

		env.serverTime = NOW + 301
		CA:Check()
		assert.equal(1, #printed)
	end)

	it("ignores a spell that is not in the group", function()
		arm(ME .. ":group:mooncloth",
			{ charKey = ME, groupKind = "group:mooncloth" })
		cooldownOn(ME, CLOTH_A, NOW - 100)
		cooldownOn(ME, SALT,    NOW + 9999)   -- unrelated, must not hold it back
		CA:Check()
		assert.equal(1, #printed)
	end)
end)

describe("Check — stale entries", function()
	it("drops an alert for a character that is no longer ours", function()
		-- After a purge or an alt being detached, the entry would otherwise sit
		-- there forever: never firing (no cooldown data) and never cleaned up.
		arm(FOREIGN .. ":spell:" .. SALT, { charKey = FOREIGN, spellId = SALT })
		CA:Check()
		assert.is_nil(ns.lib.db.char.cooldownAlerts[FOREIGN .. ":spell:" .. SALT])
	end)

	it("drops a malformed entry", function()
		arm("junk", "not a table")
		arm("junk2", { label = "no charKey" })
		CA:Check()
		assert.is_nil(ns.lib.db.char.cooldownAlerts["junk"])
		assert.is_nil(ns.lib.db.char.cooldownAlerts["junk2"])
	end)

	it("keeps a valid entry for another of our own characters", function()
		arm(ALT .. ":spell:" .. SALT, { charKey = ALT, spellId = SALT })
		CA:Check()
		assert.is_truthy(ns.lib.db.char.cooldownAlerts[ALT .. ":spell:" .. SALT])
	end)
end)

describe("Toggle", function()
	it("arms and disarms a row", function()
		local row = { charKey = ME, spellId = SALT, cdName = "Salt Shaker" }
		assert.is_false(CA:IsArmed(row))
		CA:Toggle(row)
		assert.is_true(CA:IsArmed(row))
		CA:Toggle(row)
		assert.is_false(CA:IsArmed(row))
	end)

	it("refuses to arm someone else's character", function()
		-- You cannot be alerted about a cooldown you cannot cast.
		local row = { charKey = FOREIGN, spellId = SALT }
		assert.is_false(CA:Toggle(row))
		assert.is_false(CA:IsArmed(row))
	end)

	it("stores what the check loop needs, not the whole row", function()
		local row = { charKey = ME, spellId = SALT, cdName = "Salt Shaker" }
		CA:Toggle(row)
		local meta = ns.lib.db.char.cooldownAlerts[CA:GetKey(row)]
		assert.equal(ME, meta.charKey)
		assert.equal(SALT, meta.spellId)
		assert.equal("Salt Shaker", meta.label)
	end)
end)
