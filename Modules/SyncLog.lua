-- TOG Profession Master — Sync Log
-- Feature 15: ring buffer of recent sync events (capped at 200).
--
-- Entry format: { ts = number, event = string, peer = string, bytes = number }
--
-- Events fired by Scanner.lua are recorded here via SyncLog:Record().
-- The Settings panel calls SyncLog:GetEntries() to populate the scroll list.

local _, addon = ...
local Ace = addon.lib

local LOG_CAP = 200

local SyncLog = {}
addon.SyncLog = SyncLog

-- ---------------------------------------------------------------------------
-- Write
-- ---------------------------------------------------------------------------

--- Record a sync event.
-- @param event  string  e.g. "send", "recv", "request", "version"
-- @param peer   string  normalised "Name-Realm" of the other party
-- @param bytes  number  payload size in bytes (0 if unknown)
function SyncLog:Record(event, peer, bytes)
    local log = Ace.db.global.syncLog
    table.insert(log, {
        ts    = time(),
        event = event or "?",
        peer  = peer  or "?",
        bytes = bytes or 0,
    })
    -- Trim to cap — remove oldest entries from the front
    while #log > LOG_CAP do
        table.remove(log, 1)
    end
end

--- Return a copy of all entries, newest first.
function SyncLog:GetEntries()
    local log = Ace.db.global.syncLog
    local out = {}
    for i = #log, 1, -1 do
        out[#out + 1] = log[i]
    end
    return out
end

--- Clear all log entries.
function SyncLog:Clear()
    Ace.db.global.syncLog = {}
end

-- ---------------------------------------------------------------------------
-- Hook Scanner events so they are recorded automatically
-- ---------------------------------------------------------------------------

-- Scanner fires these via addon.callbacks after each sync operation:
--   SYNC_SENT   (peer, bytes)
--   SYNC_RECV   (peer, bytes)
--   SYNC_REQ    (peer)
--   SYNC_VER    (peer)

addon:RegisterCallback("SYNC_SENT", function(_, peer, bytes)
    SyncLog:Record("send", peer, bytes)
end)

addon:RegisterCallback("SYNC_RECV", function(_, peer, bytes)
    SyncLog:Record("recv", peer, bytes)
end)

addon:RegisterCallback("SYNC_REQ", function(_, peer)
    SyncLog:Record("request", peer, 0)
end)

addon:RegisterCallback("SYNC_VER", function(_, peer)
    SyncLog:Record("version", peer, 0)
end)
