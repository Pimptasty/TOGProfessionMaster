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
-- @param peer   string  normalised "Name-Realm" of the other party ("guild" for a broadcast)
-- @param bytes  number  payload size in bytes (0 when unknown — sends get no wire size back)
-- @param detail string  optional: WHAT moved — itemKey, scoped player(s), or hash count.
--                       Shown in place of the byte column when the size is unknown, so a
--                       send reads "crafters:171 {Wrecker-Myzrael}" instead of a bare "0 B".
function SyncLog:Record(event, peer, bytes, detail)
    local log = addon.guildDb.global.syncLog
    table.insert(log, {
        ts     = time(),
        event  = event or "?",
        peer   = peer  or "?",
        bytes  = bytes or 0,
        detail = detail,
    })
    -- Trim to cap — remove oldest entries from the front
    while #log > LOG_CAP do
        table.remove(log, 1)
    end
    -- Notify the (optional) open Sync Log window so it can live-refresh.
    if addon.callbacks then addon.callbacks:Fire("SYNC_LOG_UPDATED") end
end

--- Return a copy of all entries, newest first.
function SyncLog:GetEntries()
    local log = addon.guildDb.global.syncLog
    local out = {}
    for i = #log, 1, -1 do
        out[#out + 1] = log[i]
    end
    return out
end

--- Clear all log entries.
function SyncLog:Clear()
    addon.guildDb.global.syncLog = {}
    if addon.callbacks then addon.callbacks:Fire("SYNC_LOG_UPDATED") end
end

-- ---------------------------------------------------------------------------
-- Hook Scanner events so they are recorded automatically
-- ---------------------------------------------------------------------------

-- Scanner fires these via addon.callbacks after each sync operation:
--   SYNC_SENT   (peer, bytes)
--   SYNC_RECV   (peer, bytes)
--   SYNC_REQ    (peer)
--   SYNC_VER    (peer)

addon:RegisterCallback("SYNC_SENT", function(_, peer, bytes, detail)
    SyncLog:Record("send", peer, bytes, detail)
end)

addon:RegisterCallback("SYNC_RECV", function(_, peer, bytes, detail)
    SyncLog:Record("recv", peer, bytes, detail)
end)

addon:RegisterCallback("SYNC_REQ", function(_, peer)
    SyncLog:Record("request", peer, 0)
end)

addon:RegisterCallback("SYNC_VER", function(_, peer)
    SyncLog:Record("version", peer, 0)
end)
