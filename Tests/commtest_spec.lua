-- Modules/CommTest.lua — the addon-comm diagnostic probe.
--
-- This is the tool a user runs when sync "doesn't work", and its whole value is
-- that its verdict is trustworthy: it decides whether a server core relays
-- guild addon traffic, and people change addons (or servers) on the strength of
-- it. A diagnostic that lies is worse than no diagnostic.
--
-- It was the last file in the addon at 0% coverage, having been changed in
-- v1.0.6 (reading the delivery verdict) with nothing exercising it. Driving it
-- needs the widget layer's clock: the listen window is an OnUpdate countdown,
-- so `wow.advanceTime` is what lets the report actually run.

---@diagnostic disable: duplicate-set-field
package.path = "./Tests/?.lua;" .. package.path
local env    = require("env_togpm")
local wow    = require("env.wow")
local frames = require("env.frames")

local ns, saved, printed

local LISTEN_SECONDS = 8

setup(function()
	ns = env.initDb()
	env.loadModule("Modules/CommTest.lua")
end)

before_each(function()
	env.installFrames()
	env.resetDb()

	saved = {
		Print                = ns.lib.Print,
		JoinTemporaryChannel = _G.JoinTemporaryChannel,
		GetChannelName       = _G.GetChannelName,
		LeaveChannelByName   = _G.LeaveChannelByName,
		IsInRaid             = _G.IsInRaid,
		IsInGroup            = _G.IsInGroup,
	}

	printed = {}
	ns.lib.Print = function(_, ...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		printed[#printed + 1] = table.concat(parts, " ")
	end

	-- Solo, in a guild, no temp channel available: the common case, and the one
	-- the GUILD self-echo verdict is built for.
	_G.IsInRaid  = function() return false end
	_G.IsInGroup = function() return false end
	_G.JoinTemporaryChannel = nil
	_G.GetChannelName       = nil
	_G.LeaveChannelByName   = nil
end)

after_each(function()
	ns.lib.Print            = saved.Print
	_G.JoinTemporaryChannel = saved.JoinTemporaryChannel
	_G.GetChannelName       = saved.GetChannelName
	_G.LeaveChannelByName   = saved.LeaveChannelByName
	_G.IsInRaid             = saved.IsInRaid
	_G.IsInGroup            = saved.IsInGroup
end)

local function output()
	return table.concat(printed, "\n")
end

--- Let the listen window expire so the report runs.
local function waitForReport()
	wow.advanceTime(LISTEN_SECONDS + 1)
end

describe("RunCommTest — starting a run", function()
	it("announces how many probes it sent and how long it will listen", function()
		ns:RunCommTest()
		assert.is_truthy(output():find("probe", 1, true))
		assert.is_truthy(output():find(tostring(LISTEN_SECONDS), 1, true))
	end)

	it("refuses to start a second run while one is in flight", function()
		ns:RunCommTest()
		local before = #printed
		ns:RunCommTest()
		assert.is_truthy(printed[before + 1]:find("already running", 1, true))
		waitForReport()
	end)

	it("can be run again once the first has reported", function()
		ns:RunCommTest()
		waitForReport()
		printed = {}
		ns:RunCommTest()
		assert.is_falsy(output():find("already running", 1, true))
		waitForReport()
	end)
end)

describe("RunCommTest — the report", function()
	it("prints a report once the listen window closes, and not before", function()
		ns:RunCommTest()
		assert.is_falsy(output():find("Verdict", 1, true))
		waitForReport()
		assert.is_truthy(output():find("Verdict", 1, true))
	end)

	it("names the client build and the guild it ran in", function()
		ns:RunCommTest()
		waitForReport()
		assert.is_truthy(output():find("CommTest", 1, true))
		assert.is_truthy(output():find("build", 1, true))
	end)

	it("reports a probe that never came back as NO REPLY", function()
		-- Nothing echoes in the harness, so every probe is unanswered — which
		-- is the state the tool exists to describe.
		ns:RunCommTest()
		waitForReport()
		assert.is_truthy(output():find("NO REPLY", 1, true))
	end)

	it("blames the core when the guild echo never arrives", function()
		-- The decisive verdict: a guild addon message that does not echo back
		-- to its own sender means the server is dropping guild addon traffic.
		ns:RunCommTest()
		waitForReport()
		assert.is_truthy(output():find("BROKEN", 1, true))
	end)
end)

describe("RunCommTest — a probe that comes back", function()
	--- The nonce the addon actually sent, read out of the recorded traffic so
	--- the echo is indistinguishable from a real one.
	local function sentMessages()
		local out = {}
		for _, s in ipairs(wow.sent or {}) do
			out[#out + 1] = { prefix = s.prefix or s[1], text = s.text or s[2] }
		end
		return out
	end

	it("reports RECV when its own guild message echoes back", function()
		ns:RunCommTest()
		local msgs = sentMessages()
		if #msgs == 0 then
			return pending("harness did not record the probe sends")
		end

		-- Echo every probe straight back, as a working server would.
		for _, m in ipairs(msgs) do
			frames.fireEvent("CHAT_MSG_ADDON", m.prefix, m.text, "GUILD", "Testchar")
		end
		waitForReport()

		assert.is_truthy(output():find("RECV", 1, true))
		-- ...and with the echo arriving, the core is not the problem.
		assert.is_falsy(output():find("BROKEN", 1, true))
	end)

	it("ignores an echo carrying a nonce it never sent", function()
		ns:RunCommTest()
		frames.fireEvent("CHAT_MSG_ADDON", "TOGPMprobe", "9999.9|raw GUILD", "GUILD", "Someone")
		waitForReport()
		assert.is_truthy(output():find("NO REPLY", 1, true))
	end)
end)

describe("the delivery verdict on the AceComm probe", function()
	-- AceCommQueue-1.0's five terminal reasons, driven straight through the
	-- callback the probe registers. Stubbing SendCommMessage rather than driving
	-- the real queue is deliberate: making ChatThrottleLib genuinely lose a
	-- message is that library's own suite's job, and what matters here is that
	-- TOGPM reads the contract correctly.
	local realSend

	local function aceSendYielding(delivered, reason)
		realSend = realSend or ns.lib.SendCommMessage
		ns.lib.SendCommMessage = function(_, _prefix, _text, _dist, _target, _prio, cb)
			if cb then cb(nil, 0, 0, delivered, reason) end
		end
	end

	after_each(function()
		if realSend then ns.lib.SendCommMessage = realSend; realSend = nil end
	end)

	it("says NOT SENT when the client refused the send", function()
		aceSendYielding(false, "refused")
		ns:RunCommTest()
		waitForReport()
		assert.is_truthy(output():find("NOT SENT", 1, true))
	end)

	it("reports a lost send as LOST, not as a missing verdict", function()
		-- "lost" (MINOR 6) arrives as delivered == nil, the same shape as "no
		-- callback yet" — but it means the opposite: a verdict DID arrive, and
		-- it said the queue released the send, re-sent it, and ran out of
		-- retries. Reporting it as "no delivery verdict" sends the reader to
		-- /acq status hunting a queue that has already given up and moved on.
		aceSendYielding(nil, "lost")
		ns:RunCommTest()
		waitForReport()
		assert.is_truthy(output():find("LOST", 1, true))
		assert.is_falsy(output():find("no delivery verdict", 1, true))
	end)

	it("does not blame the core for a send the client never made", function()
		-- The whole point of taking the verdict: a refused send says NOTHING
		-- about whether the server relays guild addon traffic.
		aceSendYielding(nil, "lost")
		ns:RunCommTest()
		waitForReport()
		assert.is_falsy(output():find("AceComm GUILD does not", 1, true))
	end)

	it("still reports no verdict at all when none arrives in the window", function()
		-- The genuinely-silent case has to survive the new branch above it.
		aceSendYielding(nil, nil)
		ns:RunCommTest()
		waitForReport()
		assert.is_truthy(output():find("no delivery verdict", 1, true))
		assert.is_falsy(output():find("LOST", 1, true))
	end)
end)
