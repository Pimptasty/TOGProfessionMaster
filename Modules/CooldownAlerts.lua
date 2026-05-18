-- TOG Profession Master — Cooldown-Ready Alerts
-- Per-row "!" alarm on the Cooldowns tab. When the user arms a row, a chat
-- message + sound fires the moment that cooldown becomes ready on one of
-- their own characters. Mirrors the shopping-list crafter-alert UX (gold "!"
-- toggle on each row) but uses a different chat color (cyan) and sound
-- (AlarmClockWarning) so the two alerts are immediately distinguishable.
--
-- Data model:
--   Ace.db.char.cooldownAlerts[key] = {
--       charKey   = "Toby-Dwarf",
--       label     = "Transmute",
--       groupKind = "transmute" | "group:<groupKey>" | nil,
--       spellId   = <number>,        -- only used when groupKind == nil
--   }
-- The key is built by GetKey(row); the metadata captures everything we need
-- to look up the effective expiry at check time WITHOUT requiring the GUI
-- (BuildRows) to have run — so the timer can do its job whether the
-- Cooldowns tab is open or not.
--
-- Dedup is held in memory only (CA._lastFiredAt[key] = serverTime). The
-- timestamp doubles as the dedup gate AND the re-fire clock — when the
-- user has set a reminder interval (profile.cooldownAlertReminderMinutes),
-- Check() re-fires the alert every N minutes while the cooldown stays
-- ready. nil means "never fired this ready window." On login we pre-stamp
-- every currently-ready alert with now() so we don't spam on UI reload.

local _, addon = ...
local Ace = addon.lib
local L   = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

local CA = {}
addon.CooldownAlerts = CA

-- In-memory dedup / re-fire clock. Distinct from Ace.db.char.cooldownAlerts
-- (which holds the user's "armed" set) so we can re-arm across sessions
-- without bloating SavedVariables with a flag that always flips back
-- anyway. Values are GetServerTime() timestamps of the most recent fire
-- for that key; nil = never fired in the current ready window.
CA._lastFiredAt = {}

-- Tick cadence for the readiness scan. 30s matches Scanner's broadcast
-- debounce and is fine-grained enough that a player crafting on cooldown
-- expiry won't be left waiting more than half a minute for the ping.
local CHECK_INTERVAL = 30

-- ---------------------------------------------------------------------------
-- Key + metadata helpers
-- ---------------------------------------------------------------------------

--- Build a stable alertKey from a Cooldowns tab row.
-- Three flavors mirror BuildRows' row shapes: transmute group, generic
-- group (Mooncloth, Salt Shaker, etc.), and single-spell row.
function CA:GetKey(row)
    if not row or not row.charKey then return nil end
    if row.isTransmuteGroup then
        return row.charKey .. ":transmute"
    elseif row.isGroup and row.group and row.group.groupKey then
        return row.charKey .. ":group:" .. row.group.groupKey
    elseif row.spellId then
        return row.charKey .. ":spell:" .. row.spellId
    end
    return nil
end

--- Build the persisted metadata for a row.  Captured at toggle time so
--- the check loop never has to re-walk BuildRows.
function CA:BuildMetadata(row)
    if not row or not row.charKey then return nil end
    local meta = {
        charKey = row.charKey,
        label   = row.cdName or "",
    }
    if row.isTransmuteGroup then
        meta.groupKind = "transmute"
    elseif row.isGroup and row.group and row.group.groupKey then
        meta.groupKind = "group:" .. row.group.groupKey
    else
        meta.spellId = row.spellId
    end
    return meta
end

--- Return true if the given row currently has an alert armed.
function CA:IsArmed(row)
    local key = self:GetKey(row)
    if not key then return false end
    return Ace.db.char.cooldownAlerts[key] ~= nil
end

-- ---------------------------------------------------------------------------
-- Expiry resolution
-- ---------------------------------------------------------------------------

--- Resolve the effective expiry timestamp for an armed alert.
-- For groups we walk the static cooldown catalogue (data.transmutes /
-- data.groupBySpell) and pick the latest expiry among any spell that
-- belongs to the group — matches BuildRows' "max of group members" logic
-- so a row showing "12h" alerts at the same moment the user sees it
-- count down to 0.
local function GetEffectiveExpiry(meta)
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.cooldowns then return nil end
    local charCds = gdb.cooldowns[meta.charKey]
    if not charCds then return nil end

    local data = addon:GetCooldownData()
    if meta.groupKind == "transmute" then
        if not (data and data.transmutes) then return nil end
        local latest
        for spellId in pairs(data.transmutes) do
            local expiry = charCds[spellId]
            if expiry and (not latest or expiry > latest) then
                latest = expiry
            end
        end
        return latest
    elseif type(meta.groupKind) == "string" and meta.groupKind:sub(1, 6) == "group:" then
        if not (data and data.groupBySpell) then return nil end
        local targetGroupKey = meta.groupKind:sub(7)
        local latest
        for spellId, expiry in pairs(charCds) do
            local group = data.groupBySpell[spellId]
            if group and group.groupKey == targetGroupKey then
                if not latest or expiry > latest then latest = expiry end
            end
        end
        return latest
    else
        return charCds[meta.spellId]
    end
end

-- ---------------------------------------------------------------------------
-- Zone gating
-- ---------------------------------------------------------------------------

--- "Protected zone" = any instance: raid, dungeon, battleground, arena, or
--- scenario. Capital cities and other sanctuaries are NOT protected — the
--- user wants cooldown pings to fire normally when AFK in town. The alert
--- check uses this to skip alerts when the user has the suppression
--- setting on and is somewhere a "ding!" would be unwelcome (mid-pull,
--- mid-BG, etc.).
function CA:IsInProtectedZone()
    return IsInInstance and IsInInstance() or false
end

-- ---------------------------------------------------------------------------
-- Alert fire
-- ---------------------------------------------------------------------------

local function FireAlert(meta)
    if not meta then return end
    local shortName = meta.charKey:match("^(.-)%-") or meta.charKey
    local label     = meta.label and meta.label ~= "" and meta.label or L["Transmute"] or "Cooldown"
    addon:Print(string.format(L["AlertCooldownReady"], shortName, label))

    -- SOUNDKIT.ALARMCLOCKWARNING_3 (5274) — distinct ding from the
    -- crafter-online alert's PlaySound(878). Skipped while suppressed.
    PlaySound(5274)
end

-- ---------------------------------------------------------------------------
-- The check loop
-- ---------------------------------------------------------------------------

--- Walk every armed alert, fire whichever just transitioned to ready or
--- is due for a recurring reminder, and clear the dedup clock for any
--- whose cooldown has been re-cast.
function CA:Check()
    local armed = Ace.db.char.cooldownAlerts
    if not armed or not next(armed) then return end

    -- Cleanup pass: drop entries whose character is no longer recognised
    -- as own-account. Happens when the user purges data or a former alt
    -- is detached from the account-chars table. Without this, stale
    -- entries would silently never fire (no match in gdb.cooldowns) but
    -- also never get removed.
    for key, meta in pairs(armed) do
        if type(meta) ~= "table" or not meta.charKey
           or not addon:IsMyCharacter(meta.charKey) then
            armed[key] = nil
            self._lastFiredAt[key] = nil
        end
    end

    if not next(armed) then return end

    local suppress = Ace.db.profile.cooldownAlertSuppressProtected
                 and self:IsInProtectedZone()
    local reminderMin = tonumber(Ace.db.profile.cooldownAlertReminderMinutes) or 0
    local reminderSec = reminderMin > 0 and reminderMin * 60 or 0
    local now = GetServerTime()

    for key, meta in pairs(armed) do
        local expiry = GetEffectiveExpiry(meta)
        if expiry then
            if expiry <= now then
                -- READY. First fire happens when _lastFiredAt is nil.
                -- Subsequent fires happen only if the user set a reminder
                -- interval and enough time has elapsed since the last
                -- fire. Either way, suppress in instances still wins —
                -- the user hears nothing until they leave.
                local lastAt = self._lastFiredAt[key]
                local due    = (lastAt == nil)
                            or (reminderSec > 0 and (now - lastAt) >= reminderSec)
                if due and not suppress then
                    FireAlert(meta)
                    self._lastFiredAt[key] = now
                end
            else
                -- Cooldown is running — clear the clock so the next
                -- expiry transition fires a fresh first alert and the
                -- reminder cadence restarts from there.
                self._lastFiredAt[key] = nil
            end
        end
        -- expiry == nil → no recorded cooldown for this spell yet
        -- (player never cast it on this client). Skip silently;
        -- nothing to alert on until a real expiry shows up.
    end
end

-- ---------------------------------------------------------------------------
-- GUI-facing toggle
-- ---------------------------------------------------------------------------

--- Flip the alert state for a row. Called from the Cooldowns tab "!" click.
-- When newly armed AND the cooldown is currently ready, fires an immediate
-- alert (and marks it as already-fired) so the user gets a confirmation
-- ping. Returns the new armed state.
function CA:Toggle(row)
    local key = self:GetKey(row)
    if not key then return false end
    if not addon:IsMyCharacter(row.charKey) then return false end

    local store = Ace.db.char.cooldownAlerts
    if store[key] then
        store[key] = nil
        self._lastFiredAt[key] = nil
        return false
    end

    local meta = self:BuildMetadata(row)
    store[key] = meta
    -- Immediate-fire behaviour: if the cooldown is already ready, ping
    -- right away so the user knows the alarm is wired up. Instance
    -- suppression still applies — when suppressed we deliberately leave
    -- the clock UNSET so the pending alert fires the moment the user
    -- leaves the instance (matches Check()'s behaviour for cooldowns
    -- that became ready while already inside an instance). The reminder
    -- cadence then starts from whichever wall-clock time the first fire
    -- actually landed on.
    local suppress = Ace.db.profile.cooldownAlertSuppressProtected
                 and self:IsInProtectedZone()
    local expiry   = GetEffectiveExpiry(meta)
    local now      = GetServerTime()
    if expiry and expiry <= now and not suppress then
        FireAlert(meta)
        self._lastFiredAt[key] = now
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Event wiring
-- ---------------------------------------------------------------------------

-- On login, stamp every currently-ready armed alert with "now" so the
-- next Check() pass doesn't blast the user with a wall of pings on UI
-- reload. The reminder interval then restarts from login — no immediate
-- re-fire, but the user gets the regular cadence afterwards. Real
-- future-ready transitions still fire normally (lastFiredAt stays nil
-- and Check() picks them up the moment they tick to 0).
Ace:RegisterEvent("PLAYER_LOGIN", function()
    local armed = Ace.db.char.cooldownAlerts
    if not armed then return end
    local now = GetServerTime()
    for key, meta in pairs(armed) do
        if type(meta) == "table" then
            local expiry = GetEffectiveExpiry(meta)
            if expiry and expiry <= now then
                CA._lastFiredAt[key] = now
            end
        end
    end
end)

-- Start the readiness scan. ScheduleRepeatingTimer fires on the main
-- thread well after Ace.db is ready (called from OnEnable below).
function CA:Start()
    if self._timerStarted then return end
    self._timerStarted = true
    Ace:ScheduleRepeatingTimer(function() CA:Check() end, CHECK_INTERVAL)
end

-- Kick the scan off once Ace.db.char is reachable. OnEnable runs after
-- AceDB:New is done, so Ace.db.char.cooldownAlerts is guaranteed to
-- exist by the time the first tick fires.
Ace:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    CA:Start()
end)
