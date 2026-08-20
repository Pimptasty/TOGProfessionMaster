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
		-- WHISPER is deliberately NOT echoed by the harness (nor by the server:
		-- a whisper to yourself does not come back as an addon message), so the
		-- whisper probe is the unanswered one whatever the group channels do.
		ns:RunCommTest()
		waitForReport()
		assert.is_truthy(output():find("NO REPLY", 1, true))
	end)

	it("blames the core when the guild echo never arrives", function()
		-- The decisive verdict: a guild addon message that does not echo back
		-- to its own sender means the server is dropping guild addon traffic.
		--
		-- The broken core has to be BUILT now. Since harness 813f3d2 the env
		-- echoes GUILD/OFFICER/PARTY/RAID/INSTANCE_CHAT addon messages back to
		-- the sender, as a working server does, so "nothing echoes offline" is
		-- no longer the ambient state. This assertion used to pass because the
		-- env happened to be broken in the same way the Whitemane core is, not
		-- because the tool diagnosed anything. `echoGroupMessages` is the switch
		-- the harness ships for exactly this case; wow.reset() puts it back.
		wow.echoGroupMessages = false
		ns:RunCommTest()
		waitForReport()
		wow.echoGroupMessages = true
		assert.is_truthy(output():find("BROKEN", 1, true))
	end)

	it("does NOT blame the core once the echo does arrive", function()
		-- The other half, unreachable while the env never echoed: on a healthy
		-- core the raw GUILD probe answers itself, and the verdict has to say so
		-- rather than condemning the server.
		ns:RunCommTest()
		waitForReport()
		assert.is_falsy(output():find("BROKEN", 1, true))
		assert.is_truthy(output():find("GUILD addon relay works", 1, true))
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
		--
		-- This assertion used to read `is_falsy(... "AceComm GUILD does not")`,
		-- and it was checking the wrong string against a world that could not
		-- happen. With no echo in the env the raw GUILD probe was ALWAYS
		-- unanswered, so the verdict this test is named for -- "GUILD addon
		-- relay appears BROKEN", which does blame the core -- was the one being
		-- printed, and the old assertion sailed past it. Since harness 813f3d2
		-- the raw probe echoes, so the real question is reachable: with the
		-- AceComm send lost, the verdict must exonerate the server and point at
		-- the queue.
		aceSendYielding(nil, "lost")
		ns:RunCommTest()
		waitForReport()
		assert.is_falsy(output():find("BROKEN", 1, true))
		assert.is_truthy(output():find("not the server", 1, true))
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
