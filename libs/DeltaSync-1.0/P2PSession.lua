-- P2PSession.lua
-- Generalized P2P inventory-sync session manager for DeltaSync.
-- Ported from TOGBankClassic's P2PSession.lua (P2P-006 redesign).
--
-- Implements a broadcast / collect / dispatch loop so any peer with fresh data
-- can serve as a provider — no single "banker" bottleneck required.
--
--   Phase 1 (T+0):       lib:BroadcastItemHashes(myHashes) sends a hash-list-broadcast
--                         to GUILD via the OFFER channel and opens the collect window.
--   Phase 2 (T+0..W):    Peers whose data for any listed item is newer whisper back a
--                         hash-offer (also on the OFFER channel).
--   Phase 3 (T+W):        Dispatch: for each stale item pick the peer with the highest
--                         updatedAt, send a sync-request whisper (HANDSHAKE channel).
--   Phase 4 (handshake):  Peer replies sync-accept (has capacity → host callback fires
--                         to initiate data delivery) or sync-busy (at cap → next peer).
--
-- Host addon integration
-- ─────────────────────
-- Call lib:InitP2P(config) once, after lib:Initialize(), with:
--
--   config.collectWindow    number   seconds to accumulate offers (default 10)
--   config.maxActiveSessions number  concurrent inbound data streams (default 3)
--   config.maxActiveSends    number  concurrent outbound sends (default 3)
--   config.retryDelay        number  seconds between retry cycles (default 20)
--   config.catchUpDelay      number  seconds before re-broadcasting (default 45)
--   config.maxCatchUpCycles  number  max re-broadcast attempts (default 5)
--   config.deliveryTimeout   number  seconds to wait for data after accept (default 180)
--
--   config.getMyHashes()     → {itemKey → {hash, updatedAt}}
--       Return your full hash map so DeltaSync can build an offer for inbound
--       hash-list-broadcasts.
--
--   config.hasContent(itemKey)  → bool
--       Return true if you have full data for itemKey (used on sender side).
--
--   config.hasMissingItems()  → bool
--       Return true if you still need data from peers (drives catch-up logic).
--
--   config.onSyncAccepted(itemKey, sender)
--       Called when a peer accepted your sync-request.  Initiate data exchange
--       here.  Full post-accept sequence:
--         1. Send a QUERY (your current baseline) to the provider:
--                lib:RequestData(sender, myBaseline)
--         2. Provider's onDataRequest fires → it calls lib:SendData(you, myDelta, true)
--         3. Your onDataReceived fires → apply the payload, then call:
--                lib.p2p:OnItemCompleted(itemKey, sender)
--
-- When your data pipeline receives and applies data for an item you MUST call:
--   lib.p2p:OnItemCompleted(itemKey, sender)   — frees the session slot
-- If delivery fails:
--   lib.p2p:OnItemFailed(itemKey, reason)
--
-- On the SENDER side, call after the actual wire send completes:
--   lib.p2p:ReleaseSendSlot(requester)         — frees the outbound send slot immediately
-- (A safety timer auto-releases the slot after SEND_TIMEOUT seconds as a fallback.)

local MAJOR = "DeltaSync-1.0"
local lib   = LibStub and LibStub:GetLibrary(MAJOR, true)
if not lib then
    error("DeltaSync P2PSession: DeltaSync-1.0 must be loaded first")
    return
end

-- Preserve the sub-table across LibStub upgrades
lib.p2p = lib.p2p or {}
local P2P = lib.p2p

-- ─── Session state constants ──────────────────────────────────────────────────
local STATE = {
    DISPATCHED = "DISPATCHED",  -- sync-request sent, awaiting ACK
    ACTIVE     = "ACTIVE",      -- sync-accept received, data in-flight
    COMPLETE   = "COMPLETE",
    FAILED     = "FAILED",
}

-- ─── Configurable defaults ────────────────────────────────────────────────────
P2P.COLLECT_WINDOW     = P2P.COLLECT_WINDOW     or 10
P2P.DISPATCH_TIMEOUT   = P2P.DISPATCH_TIMEOUT   or 15
P2P.DELIVERY_TIMEOUT   = P2P.DELIVERY_TIMEOUT   or 180  -- wait for data after sync-accept
P2P.SEND_TIMEOUT       = P2P.SEND_TIMEOUT       or 90   -- outbound-slot safety release
P2P.MAX_ACTIVE_SESSIONS= P2P.MAX_ACTIVE_SESSIONS or 3
P2P.MAX_ACTIVE_SENDS   = P2P.MAX_ACTIVE_SENDS   or 3
P2P.MAX_RETRY_CYCLES   = P2P.MAX_RETRY_CYCLES   or 5
P2P.RETRY_CYCLE_DELAY  = P2P.RETRY_CYCLE_DELAY  or 20
P2P.CATCH_UP_DELAY     = P2P.CATCH_UP_DELAY     or 45
P2P.MAX_CATCH_UP_CYCLES= P2P.MAX_CATCH_UP_CYCLES or 5

-- ─── Persistent state (survive LibStub reloads) ──────────────────────────────
P2P.sessions        = P2P.sessions        or {}  -- sessionId → session table
P2P.sessionsByItem  = P2P.sessionsByItem  or {}  -- itemKey → sessionId
P2P.offers          = P2P.offers          or {}  -- itemKey → [{peer,updatedAt,hash}]
P2P.activeSessions  = P2P.activeSessions  or 0
P2P.activeSends     = P2P.activeSends     or {}  -- peerName → count
P2P.pendingDispatch = P2P.pendingDispatch or {}
P2P.collectTimer    = nil
P2P.isCollecting    = false
P2P.catchUpTimer    = nil
P2P.catchUpCycles   = P2P.catchUpCycles   or 0

-- Host callbacks (populated by lib:InitP2P)
P2P.cb = P2P.cb or {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function Norm(name)
    return lib:NormalizeName(name) or name
end

local function Me()
    return lib:GetNormalizedPlayer()
end

local function MakeSessionId(itemKey)
    -- Millisecond precision prevents collisions on rapid back-to-back cycles.
    local ts = GetTime and math.floor(GetTime() * 1000) or 0
    return Me() .. ":" .. itemKey .. ":" .. tostring(ts)
end

local function Dbg(tag, fmt, ...)
    lib:Debug("P2P", tag .. " " .. string.format(fmt, ...))
end

-- ─── Init ─────────────────────────────────────────────────────────────────────

--- Initialize P2P session management.
-- Called by lib:InitP2P() — do not call directly.
-- @param config  see module header for fields
function P2P:Init(config)
    config = config or {}

    if config.collectWindow     then self.COLLECT_WINDOW      = config.collectWindow     end
    if config.maxActiveSessions then self.MAX_ACTIVE_SESSIONS = config.maxActiveSessions end
    if config.maxActiveSends    then self.MAX_ACTIVE_SENDS    = config.maxActiveSends    end
    if config.retryDelay        then self.RETRY_CYCLE_DELAY   = config.retryDelay        end
    if config.catchUpDelay      then self.CATCH_UP_DELAY      = config.catchUpDelay      end
    if config.maxCatchUpCycles  then self.MAX_CATCH_UP_CYCLES = config.maxCatchUpCycles  end
    if config.deliveryTimeout   then self.DELIVERY_TIMEOUT    = config.deliveryTimeout   end

    self.cb.getMyHashes    = config.getMyHashes    or function() return {} end
    self.cb.hasContent     = config.hasContent     or function() return false end
    self.cb.hasMissingItems= config.hasMissingItems or function() return false end
    self.cb.onSyncAccepted = config.onSyncAccepted or function() end
    -- isValidPeer: host addon decides whether a peer is eligible to participate.
    -- Defaults to lib:IsInGuild() — only current guild members can offer/request.
    -- Pass a custom function to use PARTY, RAID, or any other criteria.
    self.cb.isValidPeer    = config.isValidPeer    or function(name) return lib:IsInGuild(name) end

    Dbg("INIT", "P2PSession initialized (collectWindow=%ds, maxSessions=%d, maxSends=%d)",
        self.COLLECT_WINDOW, self.MAX_ACTIVE_SESSIONS, self.MAX_ACTIVE_SENDS)
end

-- ─── Catch-up ─────────────────────────────────────────────────────────────────

--- Schedule a full broadcast/collect/dispatch re-run after CATCH_UP_DELAY seconds.
-- Guards against double-scheduling and runaway loops.
-- @param reason  string label for debug output
function P2P:ScheduleCatchUp(reason)
    if self.catchUpTimer then return end

    self.catchUpCycles = (self.catchUpCycles or 0) + 1
    if self.catchUpCycles > self.MAX_CATCH_UP_CYCLES then
        Dbg("CATCHUP", "Max catch-up cycles (%d) reached (%s) — giving up",
            self.MAX_CATCH_UP_CYCLES, reason)
        self.catchUpCycles = 0
        return
    end

    if not self.cb.hasMissingItems() then
        Dbg("CATCHUP", "No missing items (%s) — catch-up not needed", reason)
        self.catchUpCycles = 0
        return
    end

    Dbg("CATCHUP", "Scheduling catch-up in %ds (%s, cycle %d/%d)",
        self.CATCH_UP_DELAY, reason, self.catchUpCycles, self.MAX_CATCH_UP_CYCLES)

    self.catchUpTimer = true  -- set before C_Timer.After in case it returns nil
    C_Timer.After(self.CATCH_UP_DELAY, function()
        P2P.catchUpTimer = nil
        if P2P.cb.hasMissingItems() then
            Dbg("CATCHUP", "Cycle %d: re-broadcasting item hashes", P2P.catchUpCycles)
            local hashes = P2P.cb.getMyHashes()
            lib:BroadcastItemHashes(hashes, "BULK")
        else
            Dbg("CATCHUP", "Cycle %d: all items present — done", P2P.catchUpCycles)
            P2P.catchUpCycles = 0
        end
    end)
end

-- ─── Collect window ───────────────────────────────────────────────────────────

--- Open (or extend) the offer collect window.
-- Called automatically by lib:BroadcastItemHashes().
-- @param myHashes  {itemKey → {hash, updatedAt}} — our broadcast payload (informational)
function P2P:BeginCollectWindow(myHashes) -- luacheck: ignore myHashes
    if self.isCollecting then
        -- Already open: reset the deadline so late arrivals still count.
        if self.collectTimer then self.collectTimer:Cancel() end
        self.collectTimer = C_Timer.After(self.COLLECT_WINDOW, function()
            P2P:Dispatch()
        end)
        Dbg("OFFER", "Collect window extended (%ds)", self.COLLECT_WINDOW)
        return
    end

    self.isCollecting = true
    self.offers       = {}
    self.collectTimer = C_Timer.After(self.COLLECT_WINDOW, function()
        P2P:Dispatch()
    end)
    Dbg("OFFER", "Collect window started (%ds)", self.COLLECT_WINDOW)
end

--- Called when we receive a hash-list-broadcast from a peer (OFFER channel, GUILD dist).
-- If we have newer data for any of their listed items, whisper them an offer.
-- @param sender  string: normalized sender name
-- @param items   {itemKey → {hash, updatedAt}} or nil
function P2P:OnHashListReceived(sender, items)
    if not items then return end
    local normSender = Norm(sender)

    -- Reject broadcasts from peers the host considers ineligible (e.g. not in guild).
    if not P2P.cb.isValidPeer(normSender) then
        Dbg("OFFER", "Hash list from %s ignored (isValidPeer=false)", normSender)
        return
    end

    local myHashes   = self.cb.getMyHashes()
    local offerItems = {}
    local count      = 0

    for itemKey, peerEntry in pairs(items) do
        local mine = myHashes[itemKey]
        if mine and (mine.updatedAt or 0) > (peerEntry.updatedAt or 0)
                and self.cb.hasContent(itemKey) then
            offerItems[itemKey] = { hash = mine.hash, updatedAt = mine.updatedAt }
            count = count + 1
        end
    end

    if count > 0 then
        Dbg("OFFER", "Offering %d item(s) to %s", count, normSender)
        lib:SendHashOffer(normSender, offerItems)
    end
end

--- Called when a hash-offer whisper arrives (OFFER channel, WHISPER dist).
-- Records the candidate during the collect window.
-- @param peerName  string: normalized sender name
-- @param items     {itemKey → {hash, updatedAt}} or nil
function P2P:OnOffer(peerName, items)
    if not items then return end
    local normPeer = Norm(peerName)

    if not self.isCollecting then
        Dbg("OFFER", "OnOffer from %s ignored (not collecting)", normPeer)
        return
    end

    -- Reject offers from peers the host considers ineligible.
    if not P2P.cb.isValidPeer(normPeer) then
        Dbg("OFFER", "OnOffer from %s ignored (isValidPeer=false)", normPeer)
        return
    end

    for itemKey, summary in pairs(items) do
        -- Skip items that already have an in-flight session.
        if not self.sessionsByItem[itemKey] then
            self.offers[itemKey] = self.offers[itemKey] or {}
            local entry = {
                peer      = normPeer,
                updatedAt = summary.updatedAt or 0,
                hash      = summary.hash      or 0,
            }
            -- Insert sorted descending by updatedAt so candidates[1] is always freshest.
            local inserted = false
            for i, existing in ipairs(self.offers[itemKey]) do
                if entry.updatedAt > existing.updatedAt then
                    table.insert(self.offers[itemKey], i, entry)
                    inserted = true
                    break
                end
            end
            if not inserted then
                table.insert(self.offers[itemKey], entry)
            end
            Dbg("OFFER", "  offer: %s from %s (updatedAt=%s)", itemKey, normPeer, tostring(summary.updatedAt))
        end
    end
end

-- ─── Dispatch ─────────────────────────────────────────────────────────────────

-- Pick the least-loaded untried peer from the candidate list.
local function PickPeer(candidates, triedPeers, peerLoad)
    local best, bestIdx = nil, nil
    local bestLoad      = math.huge
    for i, c in ipairs(candidates) do
        if not triedPeers[c.peer] then
            local load = peerLoad[c.peer] or 0
            if load < bestLoad then
                bestLoad = load
                best     = c.peer
                bestIdx  = i
            end
        end
    end
    return best, bestIdx
end

--- Fire at end of collect window: create sessions for each stale item.
function P2P:Dispatch()
    self.collectTimer = nil
    self.isCollecting = false

    local altList = {}
    for itemKey, offerList in pairs(self.offers) do
        if #offerList > 0 and not self.sessionsByItem[itemKey] then
            table.insert(altList, { itemKey = itemKey, candidates = offerList })
        end
    end

    if #altList == 0 then
        Dbg("DISPATCH", "No offers to dispatch")
        self:ScheduleCatchUp("no_offers")
        return
    end

    Dbg("DISPATCH", "Dispatching %d item(s)", #altList)
    self:DispatchList(altList)
end

--- Schedule sessions from a list, respecting the active-session cap.
function P2P:DispatchList(altList)
    local slots = self.MAX_ACTIVE_SESSIONS - self.activeSessions
    if slots <= 0 then
        Dbg("DISPATCH", "At cap (%d active) — queuing %d items", self.activeSessions, #altList)
        for _, item in ipairs(altList) do
            table.insert(self.pendingDispatch, item)
        end
        return
    end

    local peerLoad   = {}
    local dispatched = 0

    for _, item in ipairs(altList) do
        if self.sessionsByItem[item.itemKey] then
            -- Session was created between Dispatch() and DispatchList().
        elseif dispatched >= slots then
            table.insert(self.pendingDispatch, item)
        else
            local peer = PickPeer(item.candidates, {}, peerLoad)
            if peer then
                peerLoad[peer] = (peerLoad[peer] or 0) + 1
                local sid = MakeSessionId(item.itemKey)
                self.sessions[sid] = {
                    sessionId  = sid,
                    itemKey    = item.itemKey,
                    state      = STATE.DISPATCHED,
                    peer       = peer,
                    candidates = item.candidates,
                    triedPeers = { [peer] = true },
                    timers     = {},
                }
                self.sessionsByItem[item.itemKey] = sid
                self.activeSessions = self.activeSessions + 1
                self:SendSyncRequest(sid)
                dispatched = dispatched + 1
                Dbg("DISPATCH", "  → %s to %s (sid=%s)", item.itemKey, peer, sid)
            end
        end
    end
end

function P2P:SendSyncRequest(sessionId)
    local s = self.sessions[sessionId]
    if not s then return end

    lib:SendHandshake(s.peer, {
        type      = "sync-request",
        sessionId = sessionId,
        itemKey   = s.itemKey,
        requester = Me(),
    }, "NORMAL")

    -- Timeout: if no ACK arrives, advance to next candidate.
    local timeout = self.DISPATCH_TIMEOUT
    s.timers.dispatch = C_Timer.After(timeout, function()
        local live = P2P.sessions[sessionId]
        if live and live.state == STATE.DISPATCHED then
            Dbg("HANDSHAKE", "Dispatch timeout for %s/%s — next candidate", live.itemKey, live.peer)
            P2P:AdvanceCandidate(sessionId, "timeout")
        end
    end)
end

-- ─── ACK handling ─────────────────────────────────────────────────────────────

--- Provider accepted our sync-request.
function P2P:OnSyncAccept(sessionId, sender)
    local s = self.sessions[sessionId]
    if not s then
        Dbg("HANDSHAKE", "OnSyncAccept: unknown session %s from %s", tostring(sessionId), sender)
        return
    end
    if s.state ~= STATE.DISPATCHED then
        Dbg("HANDSHAKE", "OnSyncAccept: wrong state %s for %s", s.state, sessionId)
        return
    end

    if s.timers.dispatch then
        s.timers.dispatch:Cancel()
        s.timers.dispatch = nil
    end

    s.state = STATE.ACTIVE
    Dbg("HANDSHAKE", "ACTIVE: %s ← %s (activeSessions=%d)", s.itemKey, sender, self.activeSessions)

    -- Delivery watchdog in case peer accepts but data never arrives.
    -- Uses DELIVERY_TIMEOUT (180s default) — must exceed worst-case AceCommQueue drain
    -- time under load (observed ~70s at 3 concurrent sends; 180s gives safe headroom).
    s.timers.delivery = C_Timer.After(self.DELIVERY_TIMEOUT, function()
        local live = P2P.sessions[sessionId]
        if live and live.state == STATE.ACTIVE then
            Dbg("COMPLETE", "Delivery timeout for %s", live.itemKey)
            P2P:OnItemFailed(sessionId, "delivery_timeout")
        end
    end)

    -- Notify host addon to initiate data exchange (e.g. send state-summary to provider).
    self.cb.onSyncAccepted(s.itemKey, sender)
end

--- Provider is at capacity; try the next candidate.
function P2P:OnSyncBusy(sessionId, sender)
    local s = self.sessions[sessionId]
    if not s then return end
    Dbg("HANDSHAKE", "BUSY: %s from %s — advancing", s.itemKey, sender)
    self:AdvanceCandidate(sessionId, "busy")
end

--- Move to the next untried candidate, with retry-cycle logic.
function P2P:AdvanceCandidate(sessionId, reason)
    local s = self.sessions[sessionId]
    if not s then return end

    if s.timers.dispatch then
        s.timers.dispatch:Cancel()
        s.timers.dispatch = nil
    end

    local nextPeer = nil
    for _, candidate in ipairs(s.candidates) do
        if not s.triedPeers[candidate.peer] then
            nextPeer = candidate.peer
            break
        end
    end

    if not nextPeer then
        s.retryCount = (s.retryCount or 0) + 1
        if s.retryCount <= self.MAX_RETRY_CYCLES then
            Dbg("HANDSHAKE", "All candidates busy for %s (%s), retry %d/%d in %ds",
                s.itemKey, reason, s.retryCount, self.MAX_RETRY_CYCLES, self.RETRY_CYCLE_DELAY)
            s.triedPeers = {}  -- reset: allow all candidates to be retried
            s.state      = STATE.DISPATCHED
            s.timers.retry = C_Timer.After(self.RETRY_CYCLE_DELAY, function()
                local live = P2P.sessions[sessionId]
                if not live or live.state ~= STATE.DISPATCHED then return end
                local peer = PickPeer(live.candidates, live.triedPeers, {})
                if peer then
                    live.peer               = peer
                    live.triedPeers[peer]   = true
                    P2P:SendSyncRequest(sessionId)
                else
                    P2P:_FailSession(sessionId, "no_candidates_on_retry")
                end
            end)
        else
            Dbg("HANDSHAKE", "All candidates exhausted for %s (%s) after %d retry cycles",
                s.itemKey, reason, s.retryCount)
            self:_FailSession(sessionId, "no_candidates")
        end
        return
    end

    s.peer             = nextPeer
    s.triedPeers[nextPeer] = true
    s.state            = STATE.DISPATCHED
    self:SendSyncRequest(sessionId)
end

-- ─── Sender side ──────────────────────────────────────────────────────────────

--- Try to acquire an outbound send slot for a requester.
-- Returns true if under cap (slot incremented + safety timer set); false if at cap.
-- The host addon SHOULD call lib.p2p:ReleaseSendSlot(requester) when the actual
-- wire send completes (e.g. in the AceComm chunk-sent callback) so the slot is
-- freed immediately.  The safety timer fires after SEND_TIMEOUT seconds as a
-- fallback to prevent permanent leaks if ReleaseSendSlot is never called.
function P2P:TryAcquireSendSlot(requester)
    local total = 0
    for _, count in pairs(self.activeSends) do total = total + count end
    if total >= self.MAX_ACTIVE_SENDS then
        return false
    end
    self.activeSends[requester] = (self.activeSends[requester] or 0) + 1
    Dbg("HANDSHAKE", "TryAcquireSendSlot: acquired for %s (total=%d)", requester, total + 1)
    -- Safety release — fires after SEND_TIMEOUT if ReleaseSendSlot was never called.
    C_Timer.After(self.SEND_TIMEOUT, function()
        P2P:ReleaseSendSlot(requester, "timeout")
    end)
    return true
end

--- Release an outbound send slot for a requester.
-- Call this from your send-completion callback so the slot is freed as soon as
-- the wire send finishes, rather than waiting for the SEND_TIMEOUT safety timer.
-- Safe to call redundantly — the > 0 guard prevents underflow.
function P2P:ReleaseSendSlot(requester, reason)
    if (self.activeSends[requester] or 0) > 0 then
        self.activeSends[requester] = self.activeSends[requester] - 1
        Dbg("HANDSHAKE", "ReleaseSendSlot: %s (%s, remaining=%d)",
            requester, reason or "complete", self.activeSends[requester])
    end
end

--- Handle an inbound sync-request (we are the data provider).
-- Replies sync-accept if we have capacity and content; sync-busy otherwise.
-- @param sessionId  string
-- @param requester  string: normalized requester name
-- @param itemKey    string: key of the item requested
function P2P:HandleSyncRequest(sessionId, requester, itemKey)
    if not sessionId or not requester or not itemKey then return false end

    -- Verify we actually have content for this item (race guard).
    if not self.cb.hasContent(itemKey) then
        Dbg("HANDSHAKE", "HandleSyncRequest: no content for %s — busy to %s", itemKey, requester)
        lib:SendHandshake(requester, { type = "sync-busy", sessionId = sessionId }, "NORMAL")
        return false
    end

    -- Check outbound capacity via shared slot helper.
    if not self:TryAcquireSendSlot(requester) then
        local total = 0
        for _, count in pairs(self.activeSends) do total = total + count end
        Dbg("HANDSHAKE", "At send cap (%d) — busy to %s for %s", total, requester, itemKey)
        lib:SendHandshake(requester, { type = "sync-busy", sessionId = sessionId }, "NORMAL")
        return false
    end

    -- Accept — slot already acquired by TryAcquireSendSlot.
    lib:SendHandshake(requester, { type = "sync-accept", sessionId = sessionId }, "NORMAL")
    Dbg("HANDSHAKE", "Accepted %s for %s", itemKey, requester)
    return true
end

-- ─── Completion / failure ─────────────────────────────────────────────────────

--- Call this when data delivery for itemKey is confirmed complete.
-- Frees the active session slot and flushes any pending dispatches.
-- @param itemKey  string
-- @param sender   string: who delivered the data (for logging)
function P2P:OnItemCompleted(itemKey, sender)
    local sessionId = self.sessionsByItem[itemKey]
    if not sessionId then return end  -- not session-backed (legacy path)

    local s = self.sessions[sessionId]
    if not s then
        self.sessionsByItem[itemKey] = nil
        return
    end

    self:_CancelTimers(s)
    self.activeSessions          = math.max(0, self.activeSessions - 1)
    s.state                      = STATE.COMPLETE
    self.sessions[sessionId]     = nil
    self.sessionsByItem[itemKey] = nil
    Dbg("COMPLETE", "COMPLETE: %s from %s (activeSessions=%d)", itemKey, tostring(sender), self.activeSessions)

    self:_FlushPendingDispatch()
end

--- Call this when data delivery for itemKey failed permanently.
-- Schedules a catch-up broadcast and flushes pending dispatches.
-- Also used internally by AdvanceCandidate when candidates are exhausted.
-- @param sessionIdOrItemKey  may be a sessionId (internal) or itemKey (external)
-- @param reason              string
function P2P:OnItemFailed(sessionIdOrItemKey, reason)
    -- Accept either a session ID or an itemKey for external callers.
    local s = self.sessions[sessionIdOrItemKey]
    if not s then
        -- Treat as itemKey
        local sid = self.sessionsByItem[sessionIdOrItemKey]
        if sid then s = self.sessions[sid] end
    end
    if s then
        self:_FailSession(s.sessionId, reason)
    end
end

function P2P:_FailSession(sessionId, reason)
    local s = self.sessions[sessionId]
    if not s then return end

    self:_CancelTimers(s)
    self.activeSessions              = math.max(0, self.activeSessions - 1)
    local itemKey                    = s.itemKey
    s.state                          = STATE.FAILED
    self.sessions[sessionId]         = nil
    self.sessionsByItem[itemKey]     = nil
    Dbg("COMPLETE", "FAILED (%s): %s (activeSessions=%d)", reason, itemKey, self.activeSessions)

    self:ScheduleCatchUp("session_failed")
    self:_FlushPendingDispatch()
end

function P2P:_CancelTimers(s)
    for _, timer in pairs(s.timers or {}) do
        if timer and type(timer) == "table" and timer.Cancel then
            timer:Cancel()
        end
    end
    s.timers = {}
end

function P2P:_FlushPendingDispatch()
    local pending = self.pendingDispatch
    if not pending or #pending == 0 then return end
    self.pendingDispatch = {}
    self:DispatchList(pending)
end

-- ─── Query helpers ────────────────────────────────────────────────────────────

--- True if itemKey has an in-flight (DISPATCHED or ACTIVE) session.
function P2P:HasActiveSession(itemKey)
    local sessionId = self.sessionsByItem[itemKey]
    if not sessionId then return false end
    local s = self.sessions[sessionId]
    return s ~= nil and (s.state == STATE.DISPATCHED or s.state == STATE.ACTIVE)
end

-- ─── lib-level initializer ────────────────────────────────────────────────────

--- Initialize the P2P layer. Call once per addon, after lib:Initialize().
--
-- DESIGN NOTE — single-consumer constraint:
--   DeltaSync-1.0 is a single-consumer library. AceComm-3.0 registers prefixes
--   globally; calling lib:Initialize() a second time (from a different addon)
--   overwrites the first addon's prefix handlers and callbacks. As a consequence:
--   - Only ONE addon should call lib:Initialize() and lib:InitP2P() per session.
--   - If your addon ships DeltaSync as an embedded library (i.e. not in a shared
--     Libs/ folder), you are guaranteed not to collide with other addons.
--   - If you need truly independent sync channels for two addons, embed separate
--     copies with different MAJOR version strings (e.g. "MyAddon-DeltaSync-1.0").
--
-- @param config  see module header for field documentation
function lib:InitP2P(config)
    self.p2p = P2P
    P2P:Init(config)
end
