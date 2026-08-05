-- TOG Profession Master — Addon-comm diagnostic probe (CommTest)
-- =============================================================================
-- PURPOSE
--   Isolate *which* addon-message distributions a given server core actually
--   relays. On retail/Classic-Era this is a no-op control; on private Cata
--   cores (e.g. Whitemane "Maelstrom", 4.3.4 build 15595) some cores leave the
--   Cataclysm-era per-channel addon opcodes (CMSG_MESSAGECHAT_ADDON_GUILD,
--   _OFFICER, …) unhandled, so GUILD-distribution addon traffic is silently
--   dropped at the server. Our whole sync stack (DeltaSync → AceComm) broadcasts
--   over GUILD, so that single missing opcode presents as "comms don't work"
--   even though the addon loads fine.
--
--   This file is PURELY ADDITIVE — it sends its own tagged messages on its own
--   prefixes and never touches Scanner / DeltaSync / the live sync path. Safe to
--   ship to a tiny user base: if it errors or is never invoked, nothing else
--   changes.
--
-- HOW IT WORKS
--   Each probe sends a message tagged with a unique nonce, then a short listen
--   window collects CHAT_MSG_ADDON (raw path) and AceComm (wrapped path)
--   receipts. Addon messages on GUILD/PARTY/RAID/CHANNEL echo back to the
--   sender, so the GUILD self-echo alone proves (solo, no other players needed)
--   whether the core relays guild addon traffic.
--
-- USAGE
--   /togpm commtest              -- solo probes (GUILD self-echo, WHISPER→self,
--                                   CHANNEL self-echo, PARTY/RAID if grouped)
--   /togpm commtest Bob          -- additionally whisper-probe player "Bob"
--
--   Run it on your HOME realm first (control = everything PASS), then on the
--   private server (test). The diff pinpoints the broken distribution.
-- =============================================================================

local _, addon = ...
local Ace = addon.lib

-- ---------------------------------------------------------------------------
-- Cross-version API shims
--   * Cata 4.3.4 / Wrath / TBC / Vanilla 1.12  → bare global SendAddonMessage,
--     and RegisterAddonMessagePrefix does NOT exist (every CHAT_MSG_ADDON is
--     delivered regardless of prefix).
--   * Classic Era 1.15 / modern                → C_ChatInfo namespace, and the
--     prefix MUST be registered or receipts are filtered out client-side.
-- ---------------------------------------------------------------------------
local SendAddon =
    (C_ChatInfo and C_ChatInfo.SendAddonMessage) or _G.SendAddonMessage
local RegisterPrefix =
    C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix

local RAW_PREFIX = "TOGPMprobe"    -- raw SendAddonMessage path  (<= 16 chars)
local ACE_PREFIX = "TOGPMprobeA"   -- AceComm path               (<= 16 chars)
local PROBE_CHAN = "TOGPMprobechan" -- temp channel for the CHANNEL self-echo

local LISTEN_SECONDS = 8           -- collection window before the report prints

-- One run at a time. nil when idle.
local run = nil
local seq = 0                      -- monotonic nonce counter (avoids Math.random)

-- ---------------------------------------------------------------------------
-- Receipt capture
-- ---------------------------------------------------------------------------

-- Raw CHAT_MSG_ADDON listener (created lazily, reused across runs).
local rawFrame
-- Listen-window timer. We deliberately DO NOT use C_Timer here: the original
-- Cata 4.3.4 client (the environment we're diagnosing) has no C_Timer global,
-- so an OnUpdate-driven frame is the only timer guaranteed to exist everywhere.
local timerFrame

local function recordReceipt(message, channel, sender)
    if not run then return end
    -- message format: "<nonce>|<probeId>"
    local nonce = message and message:match("^([^|]+)|")
    if not nonce then return end
    local probe = run.byNonce[nonce]
    if not probe then return end
    if probe.recv then return end   -- first receipt wins
    probe.recv    = true
    probe.recvVia = channel or "?"
    probe.recvFrom = sender or "?"
    probe.recvAfter = (GetTime() - probe.sentAt) * 1000  -- ms
end

local function ensureRawListener()
    if rawFrame then return end
    rawFrame = CreateFrame("Frame")
    rawFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
        if prefix ~= RAW_PREFIX then return end   -- ignore everyone else's traffic
        recordReceipt(message, channel, sender)
    end)
end

-- ---------------------------------------------------------------------------
-- Probe construction + sending
-- ---------------------------------------------------------------------------

local function newNonce()
    seq = seq + 1
    return string.format("%d.%d", math.floor(GetTime() * 1000) % 1000000, seq)
end

-- Register a probe and send it. `send` is a function returning (ok, err); we
-- pcall it so a client-side rejection (e.g. not in a guild) is captured rather
-- than aborting the whole run.
--
-- `send` receives the probe table as its second argument so a sender that has a
-- delivery verdict available (the AceComm path — see the ace GUILD probe) can
-- record it. The raw-API probes ignore it: SendAddonMessage's return value is
-- the only signal there, and it is already covered by pcall.
local function addProbe(label, send)
    local nonce = newNonce()
    local probe = {
        label  = label,
        nonce  = nonce,
        sentAt = GetTime(),
    }
    run.probes[#run.probes + 1] = probe
    run.byNonce[nonce] = probe

    local ok, err = pcall(send, nonce .. "|" .. label, probe)
    probe.sentOk  = ok
    probe.sentErr = ok and nil or tostring(err)
    return probe
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------

local function pad(s, n)
    s = tostring(s)
    if #s >= n then return s end
    return s .. string.rep(" ", n - #s)
end

local function buildReport()
    local p = function(...) Ace:Print(...) end
    local _, _, _, build = GetBuildInfo()
    local ver = addon.isCata and "Cata" or addon.isMoP and "MoP"
        or addon.isWrath and "Wrath" or addon.isTBC and "TBC"
        or addon.isVanilla and "Vanilla" or "?"
    local guild = addon.GetGuildKey and addon:GetGuildKey() or nil

    p(("|cffFF8000TOGPM CommTest|r — build %s (%s)  guild: %s"):format(
        tostring(build), ver, guild or "|cff999999none|r"))

    local guildRawRecv, guildAceRecv, guildAceDelivered
    for _, probe in ipairs(run.probes) do
        local status
        if not probe.sentOk then
            status = "|cffff4444SENT-FAIL|r " .. (probe.sentErr or "")
        elseif probe.delivered == false or probe.reason == "rejected"
                or probe.reason == "error" then
            -- The message never reached the wire, so the server had nothing to
            -- relay. Reporting this as "NO REPLY" would blame the core for what
            -- the client did — the exact confusion this probe exists to resolve.
            status = ("|cffff4444NOT SENT|r  client refused it (%s)"):format(
                probe.reason or "refused")
        elseif probe.recv then
            status = ("|cff00ff00RECV|r  via %s from %s  (%dms)"):format(
                probe.recvVia, probe.recvFrom, probe.recvAfter or 0)
        elseif probe.wantsVerdict and probe.delivered == nil then
            -- Accepted by the queue, but no terminal callback inside the listen
            -- window. A blocked send queue looks exactly like this.
            status = "|cffff4444NO REPLY|r  (no delivery verdict either — check /acq status)"
        else
            status = "|cffff4444NO REPLY|r"
        end
        p("  " .. pad(probe.label, 18) .. status)
        if probe.label == "raw GUILD"     then guildRawRecv = probe.recv end
        if probe.label == "ace GUILD"     then
            guildAceRecv      = probe.recv
            guildAceDelivered = probe.delivered
        end
    end

    -- Verdict — focused on the GUILD hypothesis, since the live sync rides GUILD.
    p("|cffFF8000Verdict:|r")
    if not guild then
        p("  Not in a guild — GUILD probes were skipped. Join a guild and re-run for the decisive test.")
    elseif guildRawRecv == false then
        p("  |cffff4444GUILD addon relay appears BROKEN|r — your own guild addon")
        p("  message never echoed back. The server core is dropping guild addon")
        p("  traffic (the suspected Cata per-channel opcode gap). Sync over GUILD")
        p("  cannot work here; a WHISPER/CHANNEL fallback is needed.")
    elseif guildRawRecv and guildAceDelivered == false then
        p("  |cffffd100GUILD raw works; the client REFUSED the AceComm send|r — that")
        p("  message never reached the wire, so it says nothing about the core. Re-run")
        p("  in a moment; if it keeps happening, check |cffFF8000/acq status|r for a send")
        p("  queue that is blocked or counting refusals.")
    elseif guildRawRecv and guildAceRecv == false then
        p("  |cffffd100GUILD raw works but AceComm GUILD does not|r — the core relays")
        p("  guild addon messages, so the break is in the AceComm/queue/chunking")
        p("  wrapper, not the server. Investigate AceCommQueue under this core.")
    elseif guildRawRecv then
        p("  |cff00ff00GUILD addon relay works.|r If sync still fails, the cause is")
        p("  elsewhere (throttle, whisper restrictions, or higher-level logic).")
    end
    p("  WHISPER/CHANNEL results above show which fallback channels are viable.")
    p("Copy the lines above and paste them back to compare home vs. private server.")
end

-- ---------------------------------------------------------------------------
-- Cleanup
-- ---------------------------------------------------------------------------

local function finish()
    if not run then return end
    -- Stop listening.
    if rawFrame then rawFrame:UnregisterAllEvents() end
    if Ace.UnregisterComm then Ace:UnregisterComm(ACE_PREFIX) end
    -- Leave the temp channel we may have joined for the CHANNEL probe.
    if run.joinedChannel and LeaveChannelByName then
        LeaveChannelByName(PROBE_CHAN)
    end
    buildReport()
    run = nil
end

-- ---------------------------------------------------------------------------
-- Entry point — /togpm commtest [targetName]
-- ---------------------------------------------------------------------------

function addon:RunCommTest(args)
    if run then
        Ace:Print("|cffFF8000CommTest|r already running — wait for it to finish.")
        return
    end

    local target            -- optional whisper-probe peer name (nil when absent)
    if args then
        local t = strtrim(args)
        if t ~= "" then target = t end
    end

    run = { probes = {}, byNonce = {} }

    -- Register receivers for BOTH paths.
    ensureRawListener()
    rawFrame:RegisterEvent("CHAT_MSG_ADDON")
    if RegisterPrefix then
        RegisterPrefix(RAW_PREFIX)
        RegisterPrefix(ACE_PREFIX)
    end
    if Ace.RegisterComm then
        Ace:RegisterComm(ACE_PREFIX, function(_, message, distribution, sender)
            recordReceipt(message, distribution, sender)
        end)
    end

    local me = UnitName("player")

    -- ----- GUILD: the decisive probes (self-echo, no other players needed) ---
    if IsInGuild and IsInGuild() then
        addProbe("raw GUILD", function(msg)
            SendAddon(RAW_PREFIX, msg, "GUILD")
        end)
        if Ace.SendCommMessage then
            addProbe("ace GUILD", function(msg, probe)
                -- Take the delivery verdict (AceCommQueue-1.0 MINOR 5). Without
                -- it a send the CLIENT refused is indistinguishable from a
                -- message the SERVER failed to relay — both present as "NO
                -- REPLY", and this probe exists precisely to tell those apart.
                -- Fires once, for the whole message; may land after the listen
                -- window closes, in which case the fields stay nil and the
                -- report says the verdict never arrived.
                probe.wantsVerdict = true
                Ace:SendCommMessage(ACE_PREFIX, msg, "GUILD", nil, "NORMAL",
                    function(_, _, _, delivered, reason)
                        probe.delivered = delivered
                        probe.reason    = reason
                    end)
            end)
        end
    end

    -- ----- WHISPER: viability of a whisper-fanout fallback -------------------
    addProbe("raw WHISPER>self", function(msg)
        SendAddon(RAW_PREFIX, msg, "WHISPER", me)
    end)
    if target then
        addProbe("raw WHISPER>peer", function(msg)
            SendAddon(RAW_PREFIX, msg, "WHISPER", target)
        end)
    end

    -- ----- CHANNEL: viability of a hidden-channel fallback ------------------
    if JoinTemporaryChannel and GetChannelName then
        JoinTemporaryChannel(PROBE_CHAN)
        local id = GetChannelName(PROBE_CHAN)
        if id and id > 0 then
            run.joinedChannel = true
            addProbe("raw CHANNEL", function(msg)
                SendAddon(RAW_PREFIX, msg, "CHANNEL", id)
            end)
        end
    end

    -- ----- PARTY / RAID: only meaningful when grouped -----------------------
    if IsInRaid and IsInRaid() then
        addProbe("raw RAID", function(msg)
            SendAddon(RAW_PREFIX, msg, "RAID")
        end)
    elseif IsInGroup and IsInGroup() then
        addProbe("raw PARTY", function(msg)
            SendAddon(RAW_PREFIX, msg, "PARTY")
        end)
    end

    Ace:Print(("|cffFF8000CommTest|r — sent %d probe(s), listening %ds…")
        :format(#run.probes, LISTEN_SECONDS))

    -- OnUpdate countdown (no C_Timer dependency — see note at timerFrame decl).
    if not timerFrame then timerFrame = CreateFrame("Frame") end
    run.elapsed = 0
    timerFrame:SetScript("OnUpdate", function(f, delta)
        if not run then f:SetScript("OnUpdate", nil); return end
        run.elapsed = run.elapsed + delta
        if run.elapsed >= LISTEN_SECONDS then
            f:SetScript("OnUpdate", nil)
            finish()
        end
    end)
end
