-- The perf instrument: the clock it reads, the Warmer budget built on that
-- clock, the two sections that were NOT timed when the pause came back, and
-- the client profiler read-out that says whose pause it was.
--
-- The 2026-09-11 "lag on open" was measured offline at under 200 ms of Lua and
-- instrumented in game with /togpm perf. Then it came back, intermittent, at
-- 4-5 s. Nothing in the instrument could say whether that was this addon: the
-- Warmer tick and the sync merge -- the two things that run with no window
-- open -- recorded nothing, and no mark of ours can speak for another addon's
-- frame. These specs pin the repairs, each red against the code as it was:
--   * Perf.now reads GetTimePreciseSec, not debugprofilestop. The latter is one
--     global timer any addon may reset at any moment; a budget built on it
--     stops tripping the instant somebody does, and the Warmer then drains its
--     whole queue in one frame.
--   * A Warmer tick and a sync merge that run past Perf.SLOW_MS leave a mark.
--   * /togpm perf prints C_AddOnProfiler's per-addon worst frame.
--   * The stall watch (2026-09-12): the first printout from the chair named
--     WHOSE the 7.7 s frame was and could not say WHEN, because PeakTime is a
--     high-water mark and the counts carry no clock. Once a second the watch
--     compares the all-addon over-500-ms count to its last read; a rise is a
--     stall in that second and leaves a mark with the wall-clock time and the
--     addons whose own counts moved.

---@diagnostic disable: duplicate-set-field, redundant-return-value, redundant-parameter
package.path = "./Tests/?.lua;" .. package.path
local env = require("env_togpm")
local wow = require("env.wow")

local ns, Ace, S, P, Warmer, printed
local OWNER = "Bob-Testrealm"
local NOW   = 1000000

-- A clock under the spec's control: every Perf.now() read advances it by
-- `step` ms, so "how long a section took" is a number the spec chose rather
-- than how fast this machine ran the Lua.
local clock, step
local function installClock(msPerRead)
	clock, step = 0, msPerRead or 0
	_G.GetTimePreciseSec = function()
		clock = clock + step
		return clock / 1000
	end
end

local function lastMark()
	return P.marks[#P.marks]
end

setup(function()
	ns = env.initDb()
	Ace = ns.lib
	P = ns.Perf
	Warmer = ns.Warmer
	env.loadModule("Data/CooldownIds.lua")
	env.loadModule("Modules/HashManager.lua")
	S = env.loadModule("Scanner.lua").Scanner
end)

before_each(function()
	env.install()
	env.serverTime = NOW
	env.resetDb()
	env.roster({ { name = "Testchar", isOnline = true }, { name = "Bob", isOnline = true } })
	env.setRecipeDB({})
	S.DS = nil
	for i = #P.marks, 1, -1 do P.marks[i] = nil end
	-- env.install() dropped every pending timer, the stall ticker with them;
	-- the handle must go too or WatchStalls treats the watch as running.
	P.stallTicker = nil
	Warmer:Clear()
	installClock(0)

	printed = {}
	Ace.Print = function(_, ...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
		printed[#printed + 1] = table.concat(parts, " ")
	end
	ns.Print = Ace.Print
end)

after_each(function()
	_G.GetTimePreciseSec = nil
	_G.debugprofilestop  = nil
end)

describe("Perf.now", function()
	it("reads GetTimePreciseSec, in milliseconds, when the client has it", function()
		clock = 12500
		_G.debugprofilestop = function() return 1 end
		assert.equal(12500, P.now())
	end)

	it("falls back to debugprofilestop, then to GetTime, when it does not", function()
		_G.GetTimePreciseSec = nil
		_G.debugprofilestop = function() return 777 end
		assert.equal(777, P.now())
		_G.debugprofilestop = nil
		assert.equal(GetTime() * 1000, P.now())
	end)
end)

describe("Warmer frame budget", function()
	-- Queue `n` tasks that each yield once, counting how many have STARTED.
	local function queueYielding(n)
		local started = 0
		for _ = 1, n do
			Warmer:Queue(function()
				started = started + 1
				Warmer:Yield()
			end)
		end
		return function() return started end
	end

	it("stops resuming once the budget is spent, even with debugprofilestop reset to zero", function()
		-- Every read costs 5 ms; the budget is 4; so the check after the first
		-- resume is already over it.
		installClock(5)
		-- The shared timer, as it reads after another addon's debugprofilestart:
		-- a budget measured on this never trips.
		_G.debugprofilestop = function() return 0 end
		local started = queueYielding(5)
		wow.tickFrames(0.016)
		assert.equal(1, started())
		assert.equal(5, #Warmer._queue)
	end)

	it("drains the queue when the tasks fit the budget, and a quiet tick leaves no mark", function()
		local started = queueYielding(3)
		wow.tickFrames(0.016)   -- three resumes to the yield, three more to finish
		wow.tickFrames(0.016)
		assert.equal(3, started())
		assert.equal(0, #Warmer._queue)
		assert.equal(0, #P.marks)
	end)

	it("records a tick whose single resume ran past SLOW_MS", function()
		Warmer:Queue(function() clock = clock + 200 end)
		wow.tickFrames(0.016)
		local m = assert(lastMark())
		assert.equal("Background warm tick ran long", m.label)
		assert.is_true(m.ms >= 200)
		assert.is_truthy(m.detail:find("1 resumes", 1, true))
	end)
end)

describe("Sync merge timing", function()
	local function payload()
		return {
			charKey = OWNER,
			leaves  = { ["cooldown:" .. OWNER] = { data = { [17187] = NOW + 60 }, abs = 1, hash = 1, updatedAt = 9 } },
		}
	end

	it("leaves no mark for a merge under SLOW_MS", function()
		installClock(20)   -- entry + exit reads: 20 ms apart
		S:OnGuildDataReceived("Bob", payload())
		assert.equal(0, #P.marks)
	end)

	it("records a merge that ran past SLOW_MS, naming the sender and the leaf count", function()
		installClock(60)
		S:OnGuildDataReceived("Bob", payload())
		local m = assert(lastMark())
		assert.equal("Sync merge from Bob", m.label)
		assert.is_true(m.ms > P.SLOW_MS)
		assert.is_truthy(m.detail:find("1 leaves", 1, true))
	end)
end)

describe("Login path timing", function()
	-- The client's profiler charges an Ace addon's login work to whoever
	-- loaded Ace3 (OnEvent is blamed on the frame's creator, and AceEvent /
	-- AceAddon / AceTimer own one frame each), so TOGPM's login stages have to
	-- time themselves. Drive the real PLAYER_ENTERING_WORLD hook and the
	-- timers it schedules, with a clock that makes every stage look slow.
	local function labels()
		local out = {}
		for _, m in ipairs(P.marks) do out[m.label] = m.ms end
		return out
	end

	it("records the entering-world stage and each login timer once they run past SLOW_MS", function()
		installClock(60)
		Ace:OnPlayerEnteringWorld("PLAYER_ENTERING_WORLD", true, false)
		wow.advanceTime(5)
		local seen = labels()
		assert.is_truthy(seen["Login: DeltaSync init + first-load hash rebuild + name scrub"])
		assert.is_truthy(seen["Login +3s: reagent item-id backfill"])
		assert.is_truthy(seen["Login +4s: recipe-name backfill"])
		-- The +2 s scan timer is scheduled by Scanner:Init (OnEnable), which
		-- ran at boot; it is covered by the Scanner:Init case below.
	end)

	it("records the +2 s scan timer scheduled by Scanner:Init", function()
		installClock(60)
		S:Init()
		wow.advanceTime(3)
		assert.is_truthy(labels()["Login +2s: cooldown / specialization / gathering scans + hash broadcast"])
	end)

	it("records nothing when the stages are quick", function()
		Ace:OnPlayerEnteringWorld("PLAYER_ENTERING_WORLD", true, false)
		S:Init()
		wow.advanceTime(5)
		assert.equal(0, #P.marks)
	end)
end)

describe("/togpm perf and the client's profiler", function()
	local M

	before_each(function()
		M = Enum.AddOnProfilerMetric
	end)

	it("prints the whole-client, all-addon and own peaks, own hitch counts, and the top addons", function()
		env.profiler.application[M.PeakTime]      = 4300
		env.profiler.overall[M.PeakTime]          = 4200
		env.profiler.overall[M.CountTimeOver500Ms]  = 4
		env.profiler.overall[M.CountTimeOver1000Ms] = 3
		env.profiler.addons.TOGProfessionMaster = {
			[M.PeakTime] = 180, [M.CountTimeOver100Ms] = 2,
			[M.CountTimeOver500Ms] = 0, [M.CountTimeOver1000Ms] = 0,
		}
		env.profiler.addons.SomeOtherAddon = {
			[M.PeakTime] = 4200, [M.CountTimeOver500Ms] = 4, [M.CountTimeOver1000Ms] = 3,
		}
		Ace:OnSlashCommand("perf")
		local joined = table.concat(printed, "\n")
		assert.is_truthy(joined:find(
			"whole client 4300 | all addons together 4200 (frames over 500 / 1000 ms: 4 / 3) | TOGProfessionMaster 180 "
			.. "(its frames over 100 / 500 / 1000 ms: 2 / 0 / 0)", 1, true))
		-- The attribution caveat sits next to the list, so an "Ace3 1028 ms"
		-- line is never read as Ace3's own doing.
		assert.is_truthy(joined:find("CREATED the frame", 1, true))
		assert.is_truthy(joined:find("stall watch: not running", 1, true))
		-- Each top-five row carries its own hitch counts: a login frame gives
		-- every addon one big peak, and the counts are what separate that
		-- from an addon that keeps pausing.
		local other = joined:find("4200 ms  SomeOtherAddon  (frames over 500 / 1000 ms: 4 / 3)", 1, true)
		local ours  = joined:find("180 ms  TOGProfessionMaster  (frames over 500 / 1000 ms: 0 / 0)", 1, true)
		assert.is_truthy(other)
		assert.is_truthy(ours)
		assert.is_true(other < ours, "highest peak first")
	end)

	it("says so when the client has no profiler, and still prints the marks", function()
		_G.C_AddOnProfiler = nil
		P.mark("Tab draw: browser", 12)
		Ace:OnSlashCommand("perf")
		local joined = table.concat(printed, "\n")
		assert.is_truthy(joined:find("no addon profiler", 1, true))
		assert.is_truthy(joined:find("Tab draw: browser", 1, true))
	end)

	it("says so when the profiler is present but disabled", function()
		env.profiler.enabled = false
		Ace:OnSlashCommand("perf")
		assert.is_truthy(table.concat(printed, "\n"):find("no addon profiler", 1, true))
	end)
end)

describe("Stall watch", function()
	local M
	local function stall(name, count, peak)
		env.profiler.addons[name] = env.profiler.addons[name] or {}
		local a = env.profiler.addons[name]
		a[M.CountTimeOver500Ms] = (a[M.CountTimeOver500Ms] or 0) + count
		a[M.PeakTime] = math.max(a[M.PeakTime] or 0, peak)
		env.profiler.overall[M.CountTimeOver500Ms] = (env.profiler.overall[M.CountTimeOver500Ms] or 0) + count
		env.profiler.overall[M.PeakTime] = math.max(env.profiler.overall[M.PeakTime] or 0, peak)
	end

	before_each(function()
		M = Enum.AddOnProfilerMetric
		env.profiler.overall[M.CountTimeOver500Ms] = 0
		env.profiler.overall[M.PeakTime] = 0
	end)

	it("starts on PLAYER_ENTERING_WORLD, once, and /togpm perf says it is on", function()
		Ace:OnPlayerEnteringWorld("PLAYER_ENTERING_WORLD", true, false)
		local t = assert(P.stallTicker)
		Ace:OnPlayerEnteringWorld("PLAYER_ENTERING_WORLD", false, false)   -- a zone change
		assert.equal(t, P.stallTicker)
		Ace:OnSlashCommand("perf")
		assert.is_truthy(table.concat(printed, "\n"):find("stall watch: on", 1, true))
	end)

	it("does not start without a profiler, or without C_Timer", function()
		env.profiler.enabled = false
		P.WatchStalls()
		assert.is_nil(P.stallTicker)
		env.profiler.enabled = true
		local saved = _G.C_Timer
		_G.C_Timer = nil
		P.WatchStalls()
		assert.is_nil(P.stallTicker)
		_G.C_Timer = saved
	end)

	it("puts the login load on the clock: the first tick reports what accrued before the watch began", function()
		stall("AllTheThings", 1, 7675)
		stall("Ace3", 1, 1028)
		P.WatchStalls()
		wow.advanceTime(1)
		local m = assert(lastMark())
		assert.equal("Client stall: 2 frame(s) over 500 ms", m.label)
		assert.equal(7675, m.ms)
		assert.is_truthy(m.clock:match("^%d%d:%d%d:%d%d$"))
		assert.is_truthy(m.detail:find("accrued before the watch began", 1, true))
		assert.is_truthy(m.detail:find("AllTheThings x1 (its peak 7675 ms)", 1, true))
		assert.is_truthy(m.detail:find("Ace3 x1 (its peak 1028 ms)", 1, true))
		-- The printout carries the clock in front of every mark.
		Ace:OnSlashCommand("perf")
		assert.is_truthy(table.concat(printed, "\n"):find(m.clock .. "    7675 ms  Client stall", 1, true))
	end)

	it("is quiet while nothing stalls, then names only the addon whose count moved", function()
		stall("AllTheThings", 1, 7675)
		P.WatchStalls()
		wow.advanceTime(1)
		assert.equal(1, #P.marks)
		wow.advanceTime(30)
		assert.equal(1, #P.marks)
		-- A 5 s frame by an Ace addon: smaller than the 7.7 s login peak, so
		-- no high-water mark moves and only the counts can see it.
		stall("Ace3", 1, 5100)
		wow.advanceTime(1)
		assert.equal(2, #P.marks)
		local m = lastMark()
		assert.equal("Client stall: 1 frame(s) over 500 ms", m.label)
		assert.equal(P.STALL_MS, m.ms, "no new all-addon peak, so all that is known is the threshold")
		assert.is_falsy(m.detail:find("accrued", 1, true))
		assert.is_falsy(m.detail:find("AllTheThings", 1, true))
		assert.is_truthy(m.detail:find("Ace3 x1 (its peak 5100 ms)", 1, true))
	end)

	it("reports a new all-addon peak as the mark's ms, and says so when no addon's own count moved", function()
		P.WatchStalls()
		env.profiler.overall[M.CountTimeOver500Ms] = 1
		env.profiler.overall[M.PeakTime] = 9000
		wow.advanceTime(1)
		local m = assert(lastMark())
		assert.equal(9000, m.ms)
		assert.is_truthy(m.detail:find("no single addon's count moved", 1, true))
	end)
end)
