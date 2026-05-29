-- TOG Profession Master — Profession & Cooldown Scanner
-- Author: Pimptasty
--
-- Responsibilities:
--   • Listen for trade-skill / craft window events and scan the open profession.
--   • Scan all known profession cooldown spells on login and on window events.
--   • Store results in AceDB (factionrealm scope, keyed by "Name-Realm").
--   • Broadcast own data to the guild via DeltaSync-1.0.
--   • Receive and merge incoming guild-member data back into AceDB.

local _, addon = ...
local Ace = addon.lib   -- the AceAddon object created in TOGProfessionMaster.lua
local L   = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module object
-- ---------------------------------------------------------------------------

local Scanner = {}
addon.Scanner = Scanner

-- Hidden tooltip used to scrape reagent item links when the engine's
-- GetTradeSkillReagentItemLink / GetCraftReagentItemLink return nil — a known
-- Classic Era quirk where the link APIs silently fail even though the
-- equivalent SetTradeSkillItem / SetCraftItem tooltip APIs work fine.
local _reagentScraper
local function GetReagentScraper()
    if not _reagentScraper then
        _reagentScraper = CreateFrame("GameTooltip", "TOGPMReagentScraper", nil, "GameTooltipTemplate")
        _reagentScraper:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return _reagentScraper
end

-- ---------------------------------------------------------------------------
-- Module-scope merge helpers (reused by ScanTradeSkillInto, ScanCraftSkillInto,
-- and the v0.2.0 OnGuildDataReceived per-leaf merges).
-- ---------------------------------------------------------------------------

local function asString(v) return type(v) == "string" and v or nil end

-- Non-destructively merge an incoming reagent array into our existing one.
-- Preserves itemId/itemLink per-reagent when the incoming payload lacks them.
-- Returns nil when incoming is not a table so callers can preserve existing.
local function mergeReagents(existing, incoming)
    if type(incoming) ~= "table" then return nil end
    local byName = {}
    if type(existing) == "table" then
        for _, e in ipairs(existing) do
            if e.name then byName[e.name] = e end
        end
    end
    local merged = {}
    for i, inE in ipairs(incoming) do
        local entry = {
            name     = inE.name,
            count    = inE.count,
            itemId   = inE.itemId,
            itemLink = asString(inE.itemLink),
        }
        local prev = entry.name and byName[entry.name]
        if prev then
            if (not entry.itemId or entry.itemId == 0)
               and prev.itemId and prev.itemId > 0 then
                entry.itemId = prev.itemId
            end
            if not entry.itemLink and type(prev.itemLink) == "string"
               and prev.itemLink ~= "" then
                entry.itemLink = prev.itemLink
            end
        end
        merged[i] = entry
    end
    return merged
end

-- Returns a clean human-readable recipe name.  Classic Era's GetTradeSkillInfo
-- can return placeholder text like "? 10002" when the underlying item info
-- hasn't loaded into the client cache yet (typical for long-tail recipes the
-- player hasn't seen recently).  Item links always carry the real name in
-- their [...] field, even when the trade-skill window hasn't loaded the item
-- name — so when the raw name is one of those placeholders, extract from
-- itemLink (preferred) or recipeLink.  Falls through to the raw value if
-- nothing better is available.
local function isBogusName(n)
    if type(n) ~= "string" or n == "" then return true end
    -- "? 10002", "?10002", "? " — Classic Era placeholder forms
    if n:match("^%?") then return true end
    return false
end

-- True when a name looks like a Blizzard internal/dev/placeholder string
-- that should never reach the player. Used to catch the spell-id / item-id
-- namespace collision in MergeCraftersIntoGdb and BackfillBogusRecipeNames:
-- GetItemInfo(spellId) sometimes returns a real (but obsolete/QA) ItemSparse
-- entry whose ID happens to match a recipe's spellId. Example: spell 26926
-- = "Heavy Copper Ring" (Jewelcrafting); item 26926 = "59 TEST Green Shaman
-- Chest". Without this guard the stub gets cached with the TEST name and
-- every render shows it. Mirror of _OBSOLETE_NAME_PATTERNS in
-- tools/build_authoritative_data.py — keep the two in sync.
local function isObsoleteItemName(n)
    if type(n) ~= "string" or n == "" then return false end
    if n:find("%f[%w]TEST%f[%W]")       then return true end  -- "59 TEST ..."
    if n:find("%f[%w]QA%f[%W]")         then return true end
    if n:lower():find("%f[%w]deprecated%f[%W]") then return true end
    if n:lower():find("%f[%w]unused%f[%W]")     then return true end
    if n:lower():match("^zz")            then return true end  -- "ZZOLD Design: ..."
    if n:lower():find("%[ph%]", 1, true) then return true end  -- "Manual: ... [PH]"
    if n:lower():match("%s+old$")        then return true end  -- "Pattern: ... OLD"
    return false
end

local function extractNameFromLink(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("%[(.-)%]")
    if name and name ~= "" and not isBogusName(name) then return name end
    return nil
end

local function cleanRecipeName(rawName, itemLink, recipeLink)
    if not isBogusName(rawName) then return rawName end
    return extractNameFromLink(itemLink)
        or extractNameFromLink(recipeLink)
        or rawName
end

-- Broadcast state
Scanner._pendingBroadcast = false
Scanner._lastBroadcastAt  = 0
-- Hard minimum between guild broadcasts (seconds). Dynamically sized by
-- Scanner:ScheduleAddonUserRecount based on the number of guildmates running
-- the addon (sourced from a VersionCheck-1.0 batch). Linear scale clamped to
-- [3, 30]: small guilds (or solo testing) get a 3s floor so post-scan recipe
-- hashes propagate quickly; large active guilds with many addon users keep
-- the 30s ceiling to protect the GUILD addon-message channel from saturation.
-- Default of 30 is in effect until the first recount lands ~21s after PEW.
Scanner._broadcastSeconds = 30

-- DeltaSync + GuildCache LibStub handles (assigned in InitDeltaSync)
Scanner.DS         = nil
Scanner.GuildCache = nil

-- ---------------------------------------------------------------------------
-- English profession name → skill line ID
-- Used as a fallback for linked professions that aren't in GetProfessions().
-- Game-data facts; locale-specific servers share the same IDs but may have
-- different string keys.  Additional locale strings can be appended without
-- affecting logic.
-- ---------------------------------------------------------------------------

local PROF_NAME_TO_ID = {
    ["Alchemy"]        = 171,
    ["Blacksmithing"]  = 164,
    ["Cooking"]        = 185,
    ["Enchanting"]     = 333,
    ["Engineering"]    = 202,
    ["First Aid"]      = 129,
    ["Fishing"]        = 356,
    ["Herbalism"]      = 182,
    ["Inscription"]    = 773,
    ["Jewelcrafting"]  = 755,
    ["Leatherworking"] = 165,
    ["Mining"]         = 186,
    ["Skinning"]       = 393,
    ["Tailoring"]      = 197,
}

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- DeltaSync initialisation
-- Called on PLAYER_ENTERING_WORLD (initial login or UI reload only).
-- ---------------------------------------------------------------------------

function Scanner:InitDeltaSync()
    -- DeltaSync-1.0 and GuildCache-1.0 are declared as ## Dependencies in the
    -- .toc — version compatibility is the responsibility of the dependency
    -- declaration, not a runtime hardcoded version check here.
    local DS = LibStub("DeltaSync-1.0", true)
    if not DS then
        addon:DebugPrint("Scanner: DeltaSync-1.0 not found — guild sync disabled")
        return
    end

    local GuildCache = LibStub("GuildCache-1.0", true)
    if not GuildCache then
        addon:DebugPrint("Scanner: GuildCache-1.0 not found — guild sync disabled")
        return
    end

    DS:Initialize({
        -- Hand DeltaSync our AceAddon instance so its sends route through
        -- AceComm-3.0 + AceCommQueue-1.0 (embedded onto Ace at the addon
        -- bootstrap in TOGProfessionMaster.lua) instead of falling back to
        -- raw C_ChatInfo.SendAddonMessage. Without this, large chunked
        -- payloads can interleave under sync load and CRC-fail silently.
        aceAddon  = addon.lib,
        namespace = "TOGPmv3",   -- v0.7.0: bare crafters leaf, no recipemeta; was TOGPmv2 in v0.2-v0.6

        -- A guild member is asking us for data.  baseline carries the request
        -- type per the v0.2.0 protocol (see docs/v0.2.0-protocol.md §5):
        --   { type = "subhashes", parent = "guild:cooldowns" | "guild:accountchars" }
        --   { type = "leaf-data", keys  = { itemKey, ... } }
        -- We respond by broadcasting the requested data on GUILD/BULK so any
        -- peer with a stale hash for the same leaf merges for free.
        onDataRequest = function(sender, baseline)
            addon:DebugPrint("Scanner: onDataRequest ENTRY from", sender,
                "type=", baseline and baseline.type or "nil",
                "parent=", baseline and baseline.parent or "nil",
                "keys=", baseline and baseline.keys and #baseline.keys or 0)
            if type(baseline) ~= "table" then
                addon:DebugPrint("Scanner: onDataRequest from", sender, "with no baseline (legacy?), ignoring")
                return
            end
            if baseline.type == "subhashes" and baseline.parent then
                Scanner:BroadcastSubhashesToGuild(baseline.parent)
            elseif baseline.type == "leaf-data" and type(baseline.keys) == "table" then
                for _, itemKey in ipairs(baseline.keys) do
                    Scanner:BroadcastLeafToGuild(itemKey)
                end
            end
        end,

        -- Incoming guild-member data — either a leaf-data broadcast (one or
        -- more leaves with content) or a subhashes response.  Dispatch is
        -- inside OnGuildDataReceived based on the payload shape.
        onDataReceived = function(sender, data, bytes)
            addon:DebugPrint("Scanner: onDataReceived ENTRY from", sender,
                "bytes=", bytes or 0,
                "type=", data and data.type or "leaves",
                "charKey=", data and data.charKey or "nil")
            Scanner:OnGuildDataReceived(sender, data, bytes or 0)
        end,

        -- onVersionReceived: DeltaSync's own VERSION channel — not used by this
        -- addon (nothing calls DS:BroadcastVersion). Version checking is handled
        -- by VersionCheck-1.0 via a separate comm protocol.
    })

    self.DS         = DS
    self.GuildCache = GuildCache

    -- v0.2.0 hash migration: drop legacy v0.1.x leaf keys and ensure all
    -- expected v0.2.0 leaves exist.  Idempotent — safe to run on every PEW.
    -- Run inside a ScheduleTimer so gdb.lastScan has had a chance to populate
    -- (PEW currently stamps lastScan[myKey].accountchars synchronously, but
    -- profession + cooldown timestamps come from later scans; running this
    -- one tick later keeps the migration consistent with whatever's there).
    Ace:ScheduleTimer(function()
        local gdb = addon:GetGuildDb()
        if gdb then addon.HashManager:RebuildOnFirstLoad(DS, gdb) end
    end, 1)

    -- ── P2P catch-up sync (v0.2.0) ───────────────────────────────────────────
    -- L0 broadcast carries per-profession leaves (recipemeta + crafters) plus
    -- two roll-ups (guild:cooldowns, guild:accountchars).  Per-character leaves
    -- are drilled down on roll-up mismatch via a "subhashes" request.
    --
    -- onSyncAccepted: peer has different data for a leaf.  The flow:
    --   1. crafters:<profId> / recipemeta:<profId> mismatch → request the leaf
    --      data directly (it's already at L0 granularity).
    --   2. guild:cooldowns / guild:accountchars roll-up mismatch → request
    --      the per-character sub-hashes from the peer.  The receiver compares
    --      sub-hashes locally and requests individual cooldown:<charKey> /
    --      accountchars:<charKey> leaves.
    --   3. cooldown:<charKey> / accountchars:<charKey> direct mismatch (when
    --      a peer broadcasts these explicitly) → request leaf data.
    DS:InitP2P({
        -- DeltaSync defaults (3 sessions, 3 sends, 10s collect window) are
        -- tuned for small numbers of peers.  In active guilds with 30+ online
        -- members, we end up with the cap saturated by leaf fetches that
        -- back up while peers wait on each other's caps too — sync grinds
        -- to a halt for everything outside the first three slots.  Bump
        -- both inbound and outbound concurrency to 8 and stretch the
        -- collect window to 30s so we accumulate offers from more peers
        -- before picking one (gives a better chance of catching all the
        -- broadcasters that have what we want).
        maxActiveSessions = 8,
        maxActiveSends    = 8,
        collectWindow     = 30,

        getMyHashes = function()
            local gdb = addon:GetGuildDb()
            if not gdb then return {} end
            local HM = addon.HashManager
            HM:RebuildOnFirstLoad(DS, gdb)
            local map = HM:GetL0BroadcastMap(gdb)
            -- Pad placeholders so peers offer data for professions we have
            -- no local content for (Engineering / BS / LW / etc. on a char
            -- that only knows Enchanting + Tailoring etc.). Without this,
            -- the broadcaster-driven OFFER protocol leaves those keys
            -- silently un-synced. See HashManager:PadMissingProfessionPlaceholders.
            HM:PadMissingProfessionPlaceholders(DS, map)
            return map
        end,

        hasContent = function(itemKey)
            local gdb = addon:GetGuildDb()
            if not gdb then return false end
            return addon.HashManager:HasContent(gdb, itemKey)
        end,

        -- True when any online guildmate has no entry in our cooldown hash cache.
        hasMissingItems = function()
            local gdb = addon:GetGuildDb()
            if not gdb then return false end
            local me = GuildCache:GetNormalizedPlayer()
            for _, name in ipairs(GuildCache:GetOnlineGuildMembers()) do
                if name ~= me and not (gdb.hashes and gdb.hashes["cooldown:" .. name]) then
                    return true
                end
            end
            return false
        end,

        -- Leaf sync accepted: peer has data we need.  Request the appropriate
        -- payload type via baseline.type encoded in the QUERY message.
        --
        -- Online gate: skip if the peer went offline between their broadcast
        -- and this dispatch. DeltaSync has its own internal offline check
        -- but that races with GUILD_ROSTER_UPDATE propagation; gating here
        -- catches the common case where GuildCache has already seen the
        -- offline transition. Mirrors the TOGBankClassic pattern from
        -- DeltaComms.lua — every send site gets a guard before dispatch.
        onSyncAccepted = function(itemKey, sender)
            addon:DebugPrint("Scanner: onSyncAccepted itemKey=", itemKey, "sender=", sender)
            if Scanner.GuildCache and not Scanner.GuildCache:IsPlayerOnline(sender) then
                addon:DebugPrint("Scanner:   → skip RequestData — peer offline:", sender)
                return
            end
            if itemKey == "guild:cooldowns" or itemKey == "guild:accountchars" then
                -- Roll-up mismatch — ask for per-character sub-hashes.
                addon:DebugPrint("Scanner:   → sending subhashes RequestData to", sender)
                DS:RequestData(sender, { type = "subhashes", parent = itemKey })
            elseif itemKey:sub(1, 11) == "recipemeta:"
                or itemKey:sub(1, 9)  == "crafters:"
                or itemKey:sub(1, 9)  == "cooldown:"
                or itemKey:sub(1, 13) == "accountchars:" then
                addon:DebugPrint("Scanner:   → sending leaf-data RequestData to", sender, "for", itemKey)
                DS:RequestData(sender, { type = "leaf-data", keys = { itemKey } })
            else
                addon:DebugPrint("Scanner:   → UNRECOGNIZED itemKey shape, no QUERY sent")
            end
        end,
    })

    -- Kick off the first VersionCheck batch so the broadcast debounce can
    -- adapt to the number of guildmates running the addon (rather than the
    -- static 30s floor inherited at file load). Updates Scanner._broadcastSeconds
    -- 21 seconds after FireBatch returns; subsequent refreshes happen on the
    -- 10-min periodic tick.
    self:ScheduleAddonUserRecount()

    addon:DebugPrint("Scanner: DeltaSync initialized for", DS.namespace)
end

--- Fire a VersionCheck-1.0 batch and, 21 seconds later, set
--- Scanner._broadcastSeconds based on how many guildmates responded.
--- Linear scale clamped to [3, 30] so small guilds sync quickly and large
--- guilds stay channel-courteous. No-ops when VersionCheck isn't loaded.
function Scanner:ScheduleAddonUserRecount()
    local VC = LibStub and LibStub("VersionCheck-1.0", true)
    if not VC or type(VC.FireBatch) ~= "function" then
        addon:DebugPrint("Scanner: ScheduleAddonUserRecount — VersionCheck-1.0 not available")
        return
    end
    VC:FireBatch()
    -- VC10_REQ broadcasts to guild; peers reply via whisper (VC10_RSP) with
    -- up to 8s jitter; VC collects for 12s. 21s buffer captures every reply.
    Ace:ScheduleTimer(function()
        local hostEntry = VC.hosts and VC.hosts[addon.name]
        local responses = hostEntry and hostEntry.VersionResponses or {}
        local n = 1  -- count self
        for _ in pairs(responses) do n = n + 1 end
        Scanner._broadcastSeconds = math.max(3, math.min(30, n))
        addon:DebugPrint("Scanner: broadcast debounce set to",
            Scanner._broadcastSeconds .. "s for", n, "addon user(s) online")
    end, 21)
end

-- ---------------------------------------------------------------------------
-- Event wiring — hooked into the Ace lifecycle via hooksecurefunc
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Chat filter: swallow "No player named X is currently playing." spam
-- ---------------------------------------------------------------------------
-- The race window: a peer broadcasts hashes on the GUILD channel, then
-- logs out. Our addon (or DeltaSync's internal P2P logic) decides to
-- whisper them an OFFER / RequestData based on that broadcast. The
-- whisper hits the server, the server can't find the player, the server
-- replies with this system message, WoW prints it to the active chat
-- frame. A guild with active sync can produce this spam dozens of times
-- per logout event.
--
-- Mirrors the TOGBankClassic pattern in Modules/Events.lua:62-77 — fast
-- plain-text prefix check first (cheap on the high-volume CHAT_MSG_SYSTEM
-- stream which carries every guild login/logout/achievement message),
-- then the full pattern match only when the prefix matched. Suppresses
-- both quote variants ("No player named 'X'..." and "No player named
-- X...") and the "Player not found" alternate phrasing seen on some
-- clients.
--
-- Trade-off: a manual /w to a player who logged off ALSO won't show the
-- error — the TOGBank precedent accepted this because the addon itself
-- generates orders of magnitude more such errors than user typos do, and
-- the lack of a typing response in the chat window already signals the
-- failed send. If the player is in your guild the offline status is
-- visible in the guild roster anyway.
local _chatFilterInstalled = false
local function InstallChatFilter()
    if _chatFilterInstalled or not ChatFrame_AddMessageEventFilter then return end
    _chatFilterInstalled = true
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_self, _event, message)
        if not message then return false end
        if message:find("No player named ", 1, true) then
            if message:match("^No player named .+ is currently playing%.$") then
                return true  -- suppress
            end
        end
        if message:find("Player not found", 1, true) then
            return true  -- suppress
        end
        return false
    end)
end

function Scanner:Init()
    InstallChatFilter()

    -- Trade skill window (TBC+/Wrath/Cata/MoP — most professions)
    Ace:RegisterEvent("TRADE_SKILL_SHOW",   function() Scanner:OnTradeSkillEvent() end)
    Ace:RegisterEvent("TRADE_SKILL_UPDATE", function() Scanner:OnTradeSkillEvent() end)

    -- Craft window (Vanilla enchanting and weapon crafting)
    Ace:RegisterEvent("CRAFT_SHOW",   function() Scanner:OnCraftEvent() end)
    Ace:RegisterEvent("CRAFT_UPDATE", function() Scanner:OnCraftEvent() end)

    -- Item-based cooldowns (Salt Shaker in Vanilla leatherworking)
    Ace:RegisterEvent("BAG_UPDATE_COOLDOWN", function() Scanner:OnBagCooldownEvent() end)

    -- Trainer window. When a player opens a profession trainer, capture
    -- the EXACT ReqSkillRank Blizzard's server enforces for every offered
    -- spell (via GetTrainerServiceSkillReq). This is the authoritative
    -- "Requires Blacksmithing (N)" value — same data the trainer's
    -- tooltip displays — that emulator SQL doesn't have for apprentice-
    -- tier recipes and that DBC's MinSkillLineRank reports as the
    -- placeholder 1 for many recipes. One trainer visit captures every
    -- spell that trainer teaches in a single event; the data syncs
    -- guild-wide via DeltaSync (added in a follow-up patch) so a single
    -- player's trainer visit fills the requiredSkill gap for everyone.
    -- See gdb.trainerObservations table for the captured shape.
    Ace:RegisterEvent("TRAINER_SHOW",   function() Scanner:OnTrainerShow() end)
    -- TRAINER_UPDATE fires AFTER TRAINER_SHOW once the service list is
    -- actually populated. On this client GetNumTrainerServices() returns 0
    -- inside the TRAINER_SHOW handler — the services arrive one frame
    -- later via TRAINER_UPDATE. Both events route to the same handler;
    -- the handler is idempotent (existing entries refresh their
    -- observedAt timestamp rather than double-counting).
    Ace:RegisterEvent("TRAINER_UPDATE", function() Scanner:OnTrainerShow() end)

    -- Scan cooldowns on login after the server is ready
    Ace:ScheduleTimer(function()
        Scanner:ScanCooldowns()
        Scanner:DetectSpecializations()
        Scanner:ScheduleBroadcast()
        -- Kick off P2P catch-up: always broadcast on login so peers can compare
        -- hashes and offer fresher data. hasMissingItems() only checks for absent
        -- entries, not stale ones, so gating here would prevent refreshing
        -- cooldown data that changed while we were offline.
        local DS = Scanner.DS
        if DS and type(DS.BroadcastItemHashes) == "function" then
            local p2p = DS.p2p
            if p2p and p2p.cb then
                local hashes = type(p2p.cb.getMyHashes) == "function" and p2p.cb.getMyHashes() or {}
                DS:BroadcastItemHashes(hashes, "BULK")
            end
        end
    end, 2)

    -- v0.2.0 periodic catch-up tick: every 10 minutes, force a non-differential
    -- L0 hash broadcast.  Without this, an idle peer (no scans triggering
    -- broadcasts) never sends its hash list, so other peers never see its
    -- presence and can't push fresher data to it.  The 10-min cadence matches
    -- TOGBank's pattern and the v0.2.0-protocol.md design.
    Ace:ScheduleRepeatingTimer(function()
        -- Refresh the addon-user count so _broadcastSeconds tracks guild
        -- composition changes through the day. The new count lands ~21s
        -- after FireBatch returns and applies to the NEXT broadcast cycle;
        -- this tick uses whatever value was set by the previous recount.
        Scanner:ScheduleAddonUserRecount()
        Scanner._lastBroadcastHashes = nil  -- bypass differential check
        Scanner._lastBroadcastAt     = 0    -- bypass debounce
        Scanner:BroadcastHashes()
    end, 600)

    addon:DebugPrint("Scanner: Init complete")
end

-- Hook into Ace OnEnable so Init() runs after AceDB is ready.
hooksecurefunc(Ace, "OnEnable", function(_self)
    Scanner:Init()
end)

-- Hook into OnPlayerEnteringWorld to initialise DeltaSync once per session
-- and backfill any reagent rows missing itemId.  PEW guarantees guild + realm
-- info are populated, which the 2s post-OnEnable timer cannot — there we'd
-- silently bail when GetGuildDb() returned nil.
hooksecurefunc(Ace, "OnPlayerEnteringWorld", function(_self, _event, isInitialLogin, isReloadingUi)
    if isInitialLogin or isReloadingUi then
        Scanner:InitDeltaSync()
        -- One-time scrub of obsolete-marker names cached in gdb.recipes by
        -- pre-v0.5.5 versions of the addon (before the MergeCraftersIntoGdb /
        -- BackfillBogusRecipeNames / MergeRecipeMetaIntoGdb guards). Runs
        -- BEFORE the backfill schedule so the backfill sees the cleared
        -- names and repopulates them via GetSpellInfo. Without this, the
        -- guards prevent NEW pollution but the OLD pollution (Heavy Copper
        -- Ring stored as "59 TEST Green Shaman Chest", JC designs stored as
        -- "ZZOLD Design: ...", etc.) persists in SavedVariables forever.
        Scanner:ScrubObsoleteRecipeNames()
        -- Both backfills retry several times because GetItemInfo returns nil for
        -- items not yet in the client cache, and the cache fills lazily over the
        -- first ~couple minutes after login.  Each pass only logs when it
        -- actually had something to check, so silent retries don't spam chat.
        -- The reagent backfill's GetItemInfo call also kicks an async server-side
        -- load, so later passes pick up resolutions kicked by earlier passes.
        Ace:ScheduleTimer(function() Scanner:BackfillReagentItemIds()    end, 3)
        Ace:ScheduleTimer(function() Scanner:BackfillBogusRecipeNames()  end, 4)
        Ace:ScheduleTimer(function() Scanner:BackfillReagentItemIds()    end, 30)
        Ace:ScheduleTimer(function() Scanner:BackfillBogusRecipeNames()  end, 30)
        Ace:ScheduleTimer(function() Scanner:BackfillReagentItemIds()    end, 120)
        Ace:ScheduleTimer(function() Scanner:BackfillBogusRecipeNames()  end, 120)
    end
end)

-- Override the ForceSync stub from the main file.
function addon:ForceSync()
    Scanner:ScanCooldowns()
    Scanner._lastBroadcastAt = 0          -- bypass debounce
    Scanner._lastBroadcastHashes = nil    -- force full hash list (no diff)
    Scanner:BroadcastHashes()
    addon:Print(L["SlashForceSyncSent"])
end

-- /togpm status — dump comm/sync diagnostic snapshot to chat.
function addon:PrintStatus()
    local sep = "|cffaaaaaa----------------------------------------|r"
    addon:Print("|cffda8cffTOG Profession Master — Status|r")
    addon:Print(sep)

    -- ── DeltaSync ────────────────────────────────────────────────────────────
    local DS = Scanner.DS
    if not DS then
        addon:Print("|cffff4444DeltaSync: NOT initialized|r")
        addon:Print("  └ Scanner.DS is nil — was PLAYER_ENTERING_WORLD missed?")
    else
        addon:Print("|cff00ff00DeltaSync: initialized|r  namespace=" .. tostring(DS.namespace))
        -- External DeltaSync no longer exposes useAceComm/useAceCommQueue as
        -- direct fields; pull them from GetCommStats() and add the LibStub
        -- MINOR + a P2P-enabled flag while we're at it.
        local stats = (DS.GetCommStats and DS:GetCommStats()) or {}
        addon:Print("  aceComm="     .. tostring(stats.useAceComm or false)
            .. "  registered=" .. tostring(stats.registered or false)
            .. "  p2p="        .. tostring(stats.p2pEnabled or false)
            .. "  guildCache=" .. tostring(Scanner.GuildCache ~= nil))

        -- Communication prefixes (7 channels)
        if DS.prefixes then
            local pList = {}
            for k, v in pairs(DS.prefixes) do
                table.insert(pList, k .. "=" .. v)
            end
            table.sort(pList)
            addon:Print("  Prefixes: " .. table.concat(pList, "  "))
        end
    end

    addon:Print(sep)

    -- ── Guild ────────────────────────────────────────────────────────────────
    local guildKey = addon:GetGuildKey()
    addon:Print("Guild key: " .. (guildKey or "|cffff4444(not in a guild)|r"))

    local gdb = addon:GetGuildDb()
    if gdb then
        local memberCount, profCount, cdCount = 0, 0, 0
        for _ in pairs(gdb.guildData  or {}) do memberCount = memberCount + 1 end
        for _ in pairs(gdb.recipes    or {}) do profCount   = profCount   + 1 end
        for _ in pairs(gdb.cooldowns  or {}) do cdCount     = cdCount     + 1 end
        addon:Print("  Stored members=" .. memberCount
            .. "  profession buckets=" .. profCount
            .. "  cooldown members=" .. cdCount)
        addon:Print("  Hash cache entries: " ..
            (function()
                local n = 0
                for _ in pairs(gdb.hashes or {}) do n = n + 1 end
                return n
            end)())
    else
        addon:Print("  |cffff4444No guild DB available|r")
    end

    addon:Print(sep)

    -- ── Online roster ────────────────────────────────────────────────────────
    -- PrintStatus runs on `addon` (function addon:PrintStatus), but the
    -- GuildCache handle is stashed on Scanner — reach across explicitly.
    local GuildCache = Scanner.GuildCache
    if GuildCache then
        local online = GuildCache:GetOnlineGuildMembers()
        addon:Print("Online guild members: " .. #online)
        for _, name in ipairs(online) do
            local inGdb = gdb and gdb.guildData and gdb.guildData[name]
            addon:Print("  " .. name .. (inGdb and "" or "  |cffff4444(no data)|r"))
        end
    end

    addon:Print(sep)

    -- ── P2P state ─────────────────────────────────────────────────────────────
    if DS and DS.p2p then
        local p2p = DS.p2p
        local totalSends = 0
        for _, c in pairs(p2p.activeSends or {}) do totalSends = totalSends + c end
        addon:Print("P2P  active sessions=" .. (p2p.activeSessions or 0)
            .. "  active sends=" .. totalSends
            .. "  collecting=" .. tostring(p2p.isCollecting or false)
            .. "  catchUpCycles=" .. (p2p.catchUpCycles or 0))

        -- List in-flight sessions
        local sessions = p2p.sessions or {}
        local count = 0
        for _ in pairs(sessions) do count = count + 1 end
        if count > 0 then
            addon:Print("  Active sessions:")
            for sid, s in pairs(sessions) do
                addon:Print(("    [%s] %s → %s (%s)"):format(
                    s.state or "?", s.itemKey or "?", s.peer or "?", sid))
            end
        else
            addon:Print("  No active P2P sessions")
        end
    else
        addon:Print("P2P: not initialized")
    end

    addon:Print(sep)

    -- ── Broadcast debounce ───────────────────────────────────────────────────
    local lastBc  = Scanner._lastBroadcastAt or 0
    local elapsed = (GetServerTime() - lastBc)
    addon:Print("Last broadcast: "
        .. (lastBc > 0 and (elapsed .. "s ago") or "never")
        .. "  debounce=" .. Scanner._broadcastSeconds .. "s")

    -- ── Sync log summary ─────────────────────────────────────────────────────
    local log = addon.guildDb and addon.guildDb.global.syncLog or {}
    local sends, recvs = 0, 0
    for _, e in ipairs(log) do
        if e.event == "send" then sends = sends + 1
        elseif e.event == "recv" then recvs = recvs + 1 end
    end
    addon:Print("Sync log: " .. #log .. " entries  sends=" .. sends .. "  recvs=" .. recvs)
    addon:Print(sep)
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

function Scanner:OnTradeSkillEvent()
    if UnitAffectingCombat("player") then return end

    local isLinked, linkedPlayer = IsTradeSkillLinked()
    if isLinked then
        -- Only store linked data if the player is a guildmate.
        if linkedPlayer and self.GuildCache then
            local normKey = self.GuildCache:NormalizeName(linkedPlayer)
            if normKey and self.GuildCache:IsInGuild(normKey) then
                self:ScanTradeSkillInto(normKey, true)
            end
        end
        return
    end

    -- Always scan into whichever bucket the player's current guild key maps
    -- to. When guildless, addon:GetGuildDb() falls back to the synthetic
    -- NoGuildBucketKey bucket so the data is still captured for the local
    -- "My Characters" view. ScheduleBroadcast → BroadcastHashes guards on
    -- addon:GetGuildKey() so no-guild data never reaches the wire.
    local charKey = addon:GetCharacterKey()
    self:ScanTradeSkillInto(charKey, false)
    self:ScanCooldowns()
    self:DetectSpecializations()
    self:ScheduleBroadcast()
end

function Scanner:OnCraftEvent()
    if UnitAffectingCombat("player") then return end

    local charKey = addon:GetCharacterKey()
    self:ScanCraftSkillInto(charKey)
    self:ScanCooldowns()
    self:ScheduleBroadcast()
end

--- Capture trainer-service skill requirements on TRAINER_SHOW.
--- For each spell offered by the trainer (regardless of whether the player
--- can currently afford / has already learned it), record:
---   reqSkill   : the literal ReqSkillRank from GetTrainerServiceSkillReq —
---                same value as the "Requires Tailoring (100)" tooltip line
---                the trainer shows. AUTHORITATIVE; matches what Blizzard's
---                server enforces.
---   moneyCost  : copper cost to learn the spell (bonus signal; future UI)
---   profId     : the trainer's profession skill line, derived from
---                GetTrainerServiceSkillLine when present, else nil. Useful
---                for cross-checking against the recipe's profession.
---   observedBy : char key that captured this observation
---   observedAt : server UNIX timestamp
---
--- Stored under gdb.trainerObservations[spellId] = { ... }. Schema lives
--- top-level (peer to gdb.recipes etc.) so the table is grep-able in the
--- SavedVariables file — easy for the maintainer to find and dump when
--- promoting community observations into the shipped recipe DB.
---
--- v0.5.6: local capture only. Sync via DeltaSync added in a follow-up
--- so we can validate the capture shape against real trainer interactions
--- before plumbing it onto the wire.
function Scanner:OnTrainerShow()
    -- Always-on chat ping so we can confirm the event fires in the
    -- field, even before captures show up. Removed/quieted in a later
    -- patch once the capture pipeline is verified end-to-end.
    addon:DebugPrint("Scanner: TRAINER_SHOW/UPDATE fired (Scanner:OnTrainerShow)")
    if not GetNumTrainerServices then
        addon:DebugPrint("  GetNumTrainerServices unavailable on this client")
        return
    end
    local gdb = addon:GetGuildDb()
    if not gdb then
        addon:DebugPrint("  GetGuildDb returned nil (not in a guild?)")
        return
    end
    if not gdb.trainerObservations then gdb.trainerObservations = {} end

    local charKey = addon:GetCharacterKey()
    local now     = GetServerTime and GetServerTime() or time()
    local n       = GetNumTrainerServices() or 0
    if n == 0 then return end  -- pre-population fire, nothing to do
    local captured, updated, refreshed, skipped_header, skipped_no_spell = 0, 0, 0, 0, 0

    for i = 1, n do
        local name, _, svcType = GetTrainerServiceInfo(i)
        if not name or svcType == "header" then
            skipped_header = skipped_header + 1
        else
            local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
            -- TBC's GetTrainerServiceItemLink returns the CRAFTED-ITEM link
            -- (|Hitem:N|h[Name]|h|r), not the spell link — the function is
            -- literally named "ItemLink". Extract item ID, then reverse-
            -- lookup to the recipe spell via addon.recipeDB[*][*].craftedItemId
            -- (added in v0.5.5 from SpellEffect[Effect=24]). Also accept
            -- spell:/enchant: as legacy formats for any client that uses
            -- the older link shape (Vanilla CRAFT_SHOW path, etc.).
            local spellId  = link and (tonumber(link:match("enchant:(%d+)"))
                                    or tonumber(link:match("Hspell:(%d+)"))
                                    or tonumber(link:match("spell:(%d+)")))
            local itemId   = link and tonumber(link:match("Hitem:(%d+)"))
            if not spellId and itemId and addon.recipeDB then
                -- Walk every profession's recipe table to find the spell
                -- whose craftedItemId matches the trainer's offered item.
                -- O(profession-size) but only fires once per trainer
                -- service (~60 per trainer visit) so it's negligible.
                for _, profRecipes in pairs(addon.recipeDB) do
                    for sid, data in pairs(profRecipes) do
                        if data.craftedItemId == itemId then
                            spellId = sid
                            break
                        end
                    end
                    if spellId then break end
                end
            end
            if not spellId and name and addon.recipeDB then
                -- Name-based fallback. Enchanting recipes apply effects
                -- directly to items rather than producing an item, so
                -- 84% of enchant entries in our recipeDB have no
                -- craftedItemId. The trainer service's name
                -- ("Enchant Cloak - Lesser Shadow Resistance", etc.)
                -- still matches the spell name in our recipeDB exactly.
                -- Use that to find the spell ID. Only kicks in when both
                -- prior lookups (spell-link regex, itemId reverse-lookup)
                -- missed, so it's a clean third-tier fallback.
                for _, profRecipes in pairs(addon.recipeDB) do
                    for sid, data in pairs(profRecipes) do
                        if data.name == name then
                            spellId = sid
                            break
                        end
                    end
                    if spellId then break end
                end
            end
            if not spellId then
                skipped_no_spell = skipped_no_spell + 1
                if skipped_no_spell <= 3 then
                    local raw = tostring(link):gsub("|", "||")
                    addon:DebugPrint(("  [skip] svc %d name=%q type=%q itemId=%s link=%s"):format(
                        i, tostring(name), tostring(svcType), tostring(itemId), raw))
                end
            else
                local reqSkill = 0
                if GetTrainerServiceSkillReq then
                    -- API returns (reqSkillName, reqSkillRank) — the skill
                    -- name first ("Blacksmithing"/etc.), the numeric rank
                    -- second. Previous code captured only the first return
                    -- and got the string, failing the type check and
                    -- shipping reqSkill=0 for every observation.
                    local _, reqSkillRank = GetTrainerServiceSkillReq(i)
                    if type(reqSkillRank) == "number" then reqSkill = reqSkillRank end
                end
                local moneyCost = 0
                if GetTrainerServiceCost then
                    local c = GetTrainerServiceCost(i)
                    if type(c) == "number" then moneyCost = c end
                end
                local profId
                if GetTrainerServiceSkillLine then
                    local sl = GetTrainerServiceSkillLine(i)
                    if type(sl) == "number" then profId = sl end
                end
                local existing = gdb.trainerObservations[spellId]
                local entry = {
                    reqSkill   = reqSkill,
                    moneyCost  = moneyCost,
                    profId     = profId,
                    observedBy = charKey,
                    observedAt = now,
                }
                if not existing then
                    gdb.trainerObservations[spellId] = entry
                    captured = captured + 1
                elseif existing.reqSkill ~= reqSkill or existing.moneyCost ~= moneyCost then
                    gdb.trainerObservations[spellId] = entry
                    updated = updated + 1
                else
                    existing.observedAt = now
                    refreshed = refreshed + 1
                end
            end
        end
    end

    local total = 0
    for _ in pairs(gdb.trainerObservations) do total = total + 1 end
    -- Full diagnostic stays on DebugPrint (visible with /togpm debug).
    -- The one-line summary on captures stays user-facing — small,
    -- informative, fires once per trainer visit (the early no-services
    -- fires now return at the top so they don't print at all).
    addon:DebugPrint(("Scanner: trainerObs captured=%d updated=%d refreshed=%d skipped(header)=%d skipped(no-spell)=%d total=%d"):format(
        captured, updated, refreshed, skipped_header, skipped_no_spell, total))
    if captured > 0 or updated > 0 then
        addon:Print(("Trainer scan: %d new, %d updated (%d total recorded)"):format(captured, updated, total))
    end
end

function Scanner:OnBagCooldownEvent()
    if not addon.isVanilla then return end
    -- BAG_UPDATE_COOLDOWN fires for every item that gains/loses a cooldown, which
    -- happens constantly in play (potions, food, engineering items, etc.).
    -- We only care about the Salt Shaker, and only when its state actually changes.
    local data   = addon:GetCooldownData()
    local itemId = data and data.saltShakerItem
    if not itemId then return end

    -- Skip entirely if the player doesn't own a Salt Shaker.
    local count = GetItemCount and GetItemCount(itemId, true) or 0
    if not count or count == 0 then return end

    local gdb     = addon:GetGuildDb()
    local charKey = addon:GetCharacterKey()
    if not gdb or not charKey then return end

    local prevExpiry = gdb.cooldowns[charKey] and gdb.cooldowns[charKey][itemId]
    self:ScanCooldowns()
    local newExpiry = gdb.cooldowns[charKey] and gdb.cooldowns[charKey][itemId]

    if newExpiry ~= prevExpiry then
        self:ScheduleBroadcast()
    end
end

-- ---------------------------------------------------------------------------
-- Profession scanning — TradeSkill frame
-- ---------------------------------------------------------------------------

--- Build a name → spellId lookup from the player's spellbook.
-- GetSpellInfo() does not return spellID on Classic Era clients (that return
-- value was added in retail patch 7.1).  GetSpellBookItemInfo() always returns
-- the spellID as its 2nd value and works on all Classic builds.
-- Only covers spells the local player knows; linked scans get spellId = nil.
function Scanner:BuildSpellNameCache()
    local cache = {}
    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for j = 1, numSpells do
            local idx = offset + j
            local _, spellId = GetSpellBookItemInfo(idx, "spell")
            if spellId then
                local spellName = GetSpellInfo(spellId)
                if spellName then
                    cache[spellName] = spellId
                end
            end
        end
    end
    return cache
end

--- Scan the currently open trade-skill window and store the result in AceDB.
-- @param charKey   "Name-Realm" string for the character being scanned
-- @param isLinked  true when viewing another player's linked trade skill
function Scanner:ScanTradeSkillInto(charKey, _isLinked)
    -- v0.7.0: isLinked no longer matters — we don't store metadata so the
    -- "build local spellbook cache for non-linked scans" branch is gone.
    local skillName, _, skillRank, skillMax = GetTradeSkillLine()
    if not skillName or skillName == "UNKNOWN" then return end

    local profId = self:ResolveProfessionId(skillName)
    if not profId then
        addon:DebugPrint("Scanner: unrecognised profession name:", skillName)
        return
    end

    -- v0.7.0: collect ONLY recipe IDs. Recipe metadata (name / icon / reagents /
    -- itemLink) lives in the shipped addon.recipeDB and is looked up at render
    -- time. The SV stores nothing but the crafter set per recipe, keyed by tag.
    local recipeIds = {}
    local total = GetNumTradeSkills()
    for i = 1, total do
        local _, tradeSkillType = GetTradeSkillInfo(i)
        if tradeSkillType == "optimal" or tradeSkillType == "medium"
        or tradeSkillType == "easy"    or tradeSkillType == "trivial" then
            local recipeId = self:ExtractTradeSkillId(i)
            if recipeId then recipeIds[recipeId] = true end
        end
    end

    local gdb = addon:GetGuildDb()
    if not gdb then return end
    self:MergeRecipesIntoGdb(gdb, charKey, profId, skillRank, skillMax, recipeIds)

    -- Stamp the content-derived scan time used by HashManager.
    if not gdb.lastScan[charKey] then gdb.lastScan[charKey] = {} end
    gdb.lastScan[charKey][profId] = GetServerTime()

    -- Invalidate the per-profession recipe hash.
    local DS = self.DS
    if DS then
        addon.HashManager:InvalidateProfession(DS, gdb, profId)
    end

    local count = 0; for _ in pairs(recipeIds) do count = count + 1 end
    addon:DebugPrint("Scanner: scanned", skillName, "for", charKey, "—", count, "recipes")
end

--- Merge a freshly-scanned recipe-id set into the flat recipe DB.
--- v0.7.0: no metadata stored — just the crafter set per recipe, tagged with
--- the local player's current guild. The shipped addon.recipeDB carries name,
--- icon, reagents, etc., looked up at display time by recipeId.
---
--- @param recipeIds  table  set { [recipeId] = true } of recipes this char knows
function Scanner:MergeRecipesIntoGdb(gdb, charKey, profId, skillRank, skillMax, recipeIds)
    if not gdb.recipes then gdb.recipes = {} end
    if not gdb.skills  then gdb.skills  = {} end

    -- Skill rank/max.
    if not gdb.skills[charKey] then gdb.skills[charKey] = {} end
    gdb.skills[charKey][profId] = { skillRank = skillRank or 0, skillMax = skillMax or 300 }

    -- Compute the current guild tag once. Tag is "personal" when guildless,
    -- so own scans on a no-guild alt still get stored (and visible to that
    -- alt's owner via the My Characters view).
    local tag = addon:GetCurrentGuildTag()

    -- Remove charKey from any existing recipe's crafter set for this prof
    -- (covers recipes the character has unlearned since the last scan).
    if not gdb.recipes[profId] then
        gdb.recipes[profId] = {}
    else
        for _, rd in pairs(gdb.recipes[profId]) do
            if rd.crafters then rd.crafters[charKey] = nil end
        end
    end

    -- Add charKey + tag to each known recipe.
    -- v0.7.1: on Vanilla / Classic Hardcore, ExtractTradeSkillId returns
    -- the crafted item ID (Hitem:N links) rather than the spell ID; the
    -- addon.recipeDB is keyed by spell ID universally. Remap item-IDs to
    -- spell-IDs here so storage lands at the key everything else reads
    -- from. addon.recipeDB on other clients (TBC+) keys directly by spell
    -- and the lookup is a no-op (profMeta[recipeId] hits, no remap).
    local profMeta = addon.recipeDB and addon.recipeDB[profId]
    for recipeId in pairs(recipeIds) do
        local effectiveId = recipeId
        if profMeta and not profMeta[recipeId] then
            local spellId = addon:GetSpellIdForCraftedItem(profId, recipeId)
            if spellId then effectiveId = spellId end
        end
        local rd = gdb.recipes[profId][effectiveId]
        if not rd then
            rd = { crafters = {} }
            gdb.recipes[profId][effectiveId] = rd
        end
        if not rd.crafters then rd.crafters = {} end
        rd.crafters[charKey] = tag
    end
end

--- Extract a numeric recipe key from a trade-skill row.
-- Returns id, isSpell where isSpell=true means id is a spell/enchant ID,
-- false means id is the crafted item ID.
function Scanner:ExtractTradeSkillId(index)
    -- Retail / modern Classic: recipe link always has enchant:SPELLID.
    local link = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(index)
    if link then
        local id = tonumber(link:match("enchant:(%d+)"))
        if id then return id, true end
    end
    -- Classic Era: GetTradeSkillItemLink returns enchant:SPELLID for Enchanting,
    -- or item:ITEMID (the crafted product) for all other professions.
    link = GetTradeSkillItemLink(index)
    if link then
        local id = tonumber(link:match("enchant:(%d+)"))
        if id then return id, true end
        id = tonumber(link:match("item:(%d+)"))
        if id then return id, false end
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- Profession scanning — Craft frame (Vanilla enchanting / weapon crafting)
-- ---------------------------------------------------------------------------

function Scanner:ScanCraftSkillInto(charKey)
    if not GetCraftDisplaySkillLine then return end

    -- v0.7.5: GetCraftDisplaySkillLine on Vanilla returns (name, rank, maxRank).
    -- v0.7.4 and earlier only read the name and hardcoded skillRank=0,
    -- skillMax=300 into MergeRecipesIntoGdb. That broke the v0.7.4 "Can
    -- learn now" filter for every Vanilla Enchanter: gdb.skills[charKey][333]
    -- recorded skillRank=0, the filter compared every recipe's requiredSkill
    -- against 0, every requiredSkill > 0 → every Enchanting recipe hidden.
    local skillName, skillRank, skillMax = GetCraftDisplaySkillLine()
    if not skillName then return end

    local profId = self:ResolveProfessionId(skillName)
    if not profId then
        addon:DebugPrint("Scanner: unrecognised craft skill:", skillName)
        return
    end

    -- v0.7.0: recipe IDs only — metadata lives in the shipped addon.recipeDB.
    local recipeIds = {}
    local total = GetNumCrafts and GetNumCrafts() or 0
    for i = 1, total do
        local _, _, craftType = GetCraftInfo(i)
        if craftType == "optimal" or craftType == "medium"
        or craftType == "easy"    or craftType == "trivial" then
            local link    = GetCraftItemLink and GetCraftItemLink(i)
            local spellId = link and tonumber(link:match("enchant:(%d+)"))
            if spellId then recipeIds[spellId] = true end
        end
    end

    local gdb = addon:GetGuildDb()
    if not gdb then return end
    self:MergeRecipesIntoGdb(gdb, charKey, profId, skillRank or 0, skillMax or 300, recipeIds)

    -- Stamp content-derived scan time for hash leaves.
    if not gdb.lastScan[charKey] then gdb.lastScan[charKey] = {} end
    gdb.lastScan[charKey][profId] = GetServerTime()

    -- Invalidate the per-profession recipe hash.
    local DS = self.DS
    if DS then
        addon.HashManager:InvalidateProfession(DS, gdb, profId)
    end

    local count = 0; for _ in pairs(recipeIds) do count = count + 1 end
    addon:DebugPrint("Scanner: scanned craft", skillName, "for", charKey, "—", count, "recipes")
end

-- ---------------------------------------------------------------------------
-- Profession ID resolution
-- Primary path: match the open window's name against GetProfessions() entries.
-- Fallback: static English name map (covers linked professions and all locales
-- where the skill name happens to match the English key).
-- ---------------------------------------------------------------------------

function Scanner:ResolveProfessionId(name)
    if not name then return nil end

    -- Walk the character's own profession slots first.
    local slots = { GetProfessions() }
    for _, idx in ipairs(slots) do
        if idx then
            local pName, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
            if pName == name then
                return skillLine
            end
        end
    end

    -- Fall back to the static English map.
    return PROF_NAME_TO_ID[name]
end

-- ---------------------------------------------------------------------------
-- Cooldown-remaining helper (mirrors ProfessionCooldown GetCooldownLeftOnItem)
-- Handles the WoW GetTime() 2^32 ms (~49.7-day) rollover.
-- ---------------------------------------------------------------------------

local function GetCooldownLeft(start, duration)
    if start < GetTime() then
        return (start + duration) - GetTime()
    end
    -- Post-rollover case: start is from the previous epoch.
    local luaTime     = time()
    local startupTime = luaTime - GetTime()
    local cdTime      = (2 ^ 32) / 1000 - start
    local cdStartTime = startupTime - cdTime
    return (cdStartTime + duration) - luaTime
end

-- ---------------------------------------------------------------------------
-- Profession-spec detection
--
-- Walks IsSpellKnown on each known spec spell ID and records which spec
-- (if any) this character has for each profession. Result lands in
-- gdb.specializations[charKey][profId] = specSpellId, then piggybacks the
-- crafters: leaf on the next sync (see BuildLeafPayload / OnGuildDataReceived).
--
-- Detection catalog covers TBC-introduced specs (Vanilla had no profession
-- specs in the bonus-output sense; Cata 4.0.1 removed the proc system).
-- Engineering Gnomish/Goblin gate exclusive recipes but currently have no
-- bonus-output mapping — they're kept here so the detection table is
-- complete for future use (e.g. spec-aware recipe filtering).
-- ---------------------------------------------------------------------------

local SPEC_SPELLS = {
    [171] = { 28677, 28682, 28683 },   -- Alchemy: Potion Master / Elixir Master / Transmutation Master
    [202] = { 20219, 20222 },          -- Engineering: Gnomish / Goblin
    [197] = { 26797, 26801, 26802 },   -- Tailoring: Mooncloth / Shadoweave / Spellfire
}

function Scanner:DetectSpecializations()
    local charKey = addon:GetCharacterKey()
    local gdb     = addon:GetGuildDb()
    if not gdb then return end
    if not gdb.specializations then gdb.specializations = {} end

    local specs = {}
    for profId, spellList in pairs(SPEC_SPELLS) do
        for _, spellId in ipairs(spellList) do
            if IsSpellKnown and IsSpellKnown(spellId, false) then
                specs[profId] = spellId
                break
            end
        end
    end
    gdb.specializations[charKey] = specs
end

-- ---------------------------------------------------------------------------
-- Cooldown scanning
-- ---------------------------------------------------------------------------

function Scanner:ScanCooldowns()
    local charKey = addon:GetCharacterKey()
    local gdb     = addon:GetGuildDb()
    if not gdb then return end
    local now     = GetServerTime()

    -- Augment the transmute catalogue from the alchemy recipe DB.  This
    -- self-heals for clients (Classic Era Anniversary, locale variants)
    -- where the actual transmute spell IDs differ from VANILLA_TRANSMUTES.
    -- Idempotent; cheap; runs every scan so newly-learned transmutes from
    -- guildmate broadcasts get picked up too.
    addon:RefreshTransmuteCatalogueFromRecipes()
    local data    = addon:GetCooldownData()

    if not gdb.cooldowns[charKey] then gdb.cooldowns[charKey] = {} end
    local stored = gdb.cooldowns[charKey]

    -- ---- Transmutes --------------------------------------------------------
    -- All transmutes share one cooldown bucket. Iterate every known transmute
    -- spell ID to find the one currently active, then store the shared expiry
    -- under every transmute the player knows so the cooldowns tab can show
    -- exactly which transmutes they have.
    --
    -- Why we don't gate on IsSpellKnown: on Classic Era, IsSpellKnown returns
    -- false for transmute spell IDs (see docs/bugs.md DATA-004), so the gate
    -- silently blocks both the active-CD store and the Ready seed. Instead we
    -- determine "known transmutes" from the alchemy recipe DB (recipe entries
    -- carry spellId from the spellbook scan) and always include the spell that
    -- was actually found on cooldown so the active CD shows even on first
    -- login before any trade-skill scan has populated recipes.

    local transmuteExpiry, activeTransmuteId = nil, nil
    for spellId in pairs(data.transmutes) do
        local start, duration = GetSpellCooldown(spellId)
        if start and start > 0 and duration and duration > 1.5 then
            local remaining = (start + duration) - GetTime()
            if remaining > 0 and remaining < 691200 then
                transmuteExpiry   = math.floor(now + remaining)
                activeTransmuteId = spellId
                break
            end
        end
    end

    local knownTransmutes = {}
    local alchemyRecipes  = gdb.recipes and gdb.recipes[171]
    if alchemyRecipes then
        for _, rd in pairs(alchemyRecipes) do
            if rd.crafters and rd.crafters[charKey]
            and rd.spellId and data.transmutes[rd.spellId] then
                knownTransmutes[rd.spellId] = true
            end
        end
    end
    if activeTransmuteId then
        knownTransmutes[activeTransmuteId] = true
    end

    for spellId in pairs(data.transmutes) do
        if knownTransmutes[spellId] or IsSpellKnown(spellId, false) then
            if transmuteExpiry then
                stored[spellId] = transmuteExpiry
            elseif not stored[spellId] or (stored[spellId] - now) > 691200 then
                stored[spellId] = now - 1  -- seed as Ready
            end
        end
    end

    -- ---- Non-transmute cooldowns -------------------------------------------

    for spellId in pairs(data.cooldowns) do
        local start, duration = GetSpellCooldown(spellId)
        if start and start > 0 and duration and duration > 1.5 then
            local remaining = GetCooldownLeft(start, duration)
            if remaining > 0 and remaining < 2592000 then
                stored[spellId] = math.floor(now + remaining)
            end
            -- If remaining <= 0 the GCD fired; leave the existing stored entry alone
            -- so "Ready" state (past timestamp) is preserved.
        else
            -- Spell is not on CD.  Seed "Ready" if the character knows it.
            if not stored[spellId] or (stored[spellId] - now) > 2592000 then
                if IsSpellKnown(spellId, false) then
                    stored[spellId] = now - 1  -- past timestamp means Ready
                end
            end
        end
    end

    -- ---- Salt Shaker (Vanilla Leatherworking item) -------------------------

    if addon.isVanilla then
        self:ScanSaltShaker(stored, now, data.saltShakerItem)
    end

    gdb.syncTimes[charKey] = now

    -- Stamp content-derived scan time for v0.2.0 cooldown:<charKey> leaf.
    if not gdb.lastScan[charKey] then gdb.lastScan[charKey] = {} end
    gdb.lastScan[charKey].cooldowns = now

    -- Update the per-member cooldown hash and the guild:cooldowns roll-up.
    local DS = self.DS
    if DS then
        addon.HashManager:InvalidateCharCooldowns(DS, gdb, charKey)
    end

    addon:DebugPrint("Scanner: cooldown scan complete for", charKey)
end

-- Walk every recipe's reagent table and resolve missing itemId via
-- GetItemInfoInstant(name).  Needed because pre-v0.1.5 scans (and scans on
-- builds where GetTradeSkillReagentItemLink returns nil) stored reagents
-- with neither itemLink nor itemId, breaking the bank-stock lookup and
-- reagent-watch features that key off the item ID.
--
-- Recovery sources, in order:
--   1. itemLink → tonumber(...:match("item:(%d+)"))      (instant, cache-free)
--   2. GetItemInfoInstant(name)                          (instant, cache-only)
--   3. GetItemInfo(name)                                 (cache + lazy fetch:
--      kicks the client to load the item.  Returns nil on this call but the
--      load resolves async; subsequent backfill retries pick it up via path 2.)
--
-- Scheduled with retries (4s/30s/120s post-PEW) so async loads kicked in pass 1
-- have a chance to resolve in pass 2/3.
function Scanner:BackfillReagentItemIds()
    if not GetItemInfoInstant then
        addon:Print("|cffff4444Backfill: GetItemInfoInstant unavailable|r")
        return
    end
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.recipes then
        addon:Print("|cffff4444Backfill: no guild DB available|r")
        return
    end

    local checked, fixed, missed = 0, 0, 0
    for _, profRecipes in pairs(gdb.recipes) do
        for _, rd in pairs(profRecipes) do
            if type(rd.reagents) == "table" then
                for _, rg in ipairs(rd.reagents) do
                    if not rg.itemId or rg.itemId == 0 then
                        checked = checked + 1
                        if type(rg.itemLink) == "string" then
                            rg.itemId = tonumber(rg.itemLink:match("item:(%d+)"))
                        end
                        if (not rg.itemId or rg.itemId == 0) and rg.name then
                            rg.itemId = (GetItemInfoInstant(rg.name))
                        end
                        if (not rg.itemId or rg.itemId == 0) and rg.name and GetItemInfo then
                            -- Cache-loading variant: returns nil on this call if
                            -- the item isn't cached yet, but issues a server-side
                            -- load.  Next retry picks up the result via the
                            -- GetItemInfoInstant path above once the load resolves.
                            local _, link = GetItemInfo(rg.name)
                            if type(link) == "string" then
                                rg.itemId = tonumber(link:match("item:(%d+)"))
                                if not rg.itemLink or rg.itemLink == "" then
                                    rg.itemLink = link
                                end
                            end
                        end
                        if rg.itemId and rg.itemId > 0 then
                            fixed = fixed + 1
                        else
                            missed = missed + 1
                        end
                    end
                end
            end
        end
    end
    -- Only log when something was actually checked, so silent retry passes
    -- don't spam chat after the data is fully healed.
    if checked > 0 then
        addon:Print(("Backfill: checked=%d fixed=%d missed=%d"):format(checked, fixed, missed))
    end
end

--- One-time PEW scrub: clear any rd.name in gdb.recipes that's a Blizzard
--- internal / dev / QA / placeholder string (TEST / ZZOLD / DEPRECATED /
--- UNUSED / [PH] / OLD-suffix). These got cached by pre-v0.5.5 versions of
--- the addon when MergeCraftersIntoGdb's stub creation called
--- `GetItemInfo(recipeId)` with what was actually a spell ID — and the
--- item-ID namespace collides with the spell-ID namespace for many recipes
--- (e.g. spell 26926 = Heavy Copper Ring; item 26926 = "59 TEST Green
--- Shaman Chest"), so the stub got stamped with the wrong name and persisted
--- in SavedVariables. Clearing the name (rather than overwriting it here)
--- lets BackfillBogusRecipeNames run next and populate it from GetSpellInfo
--- — which is now guarded against the same collision. Also clears stale
--- itemLink/icon when they look item-id-derived, so the next backfill picks
--- up the spell icon instead.
function Scanner:ScrubObsoleteRecipeNames()
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.recipes then return end
    local scrubbed = 0
    for _, profRecipes in pairs(gdb.recipes) do
        for _, rd in pairs(profRecipes) do
            if isObsoleteItemName(rd.name) then
                rd.name     = nil
                rd.icon     = nil      -- was likely the obsolete item's icon
                rd.itemLink = nil      -- was likely a link to the obsolete item
                scrubbed    = scrubbed + 1
            end
        end
    end
    if scrubbed > 0 then
        addon:Print(("Scrubbed %d obsolete recipe names (TEST/ZZOLD/DEPRECATED/[PH]) from cache"):format(scrubbed))
    end
end

--- Walk gdb.recipes once and recover any missing or placeholder recipe metadata.
--- Two failure modes this fixes:
---   1. Classic Era's GetTradeSkillInfo returns "? <id>" placeholder strings when
---      the item info hasn't loaded into the client cache yet.
---   2. MergeCraftersIntoGdb creates {crafters={}} stubs when a crafters:<profId>
---      leaf arrives before the matching recipemeta:<profId> leaf — leaving the
---      recipe with crafters but no name/icon/links.
--- Recovery sources, in order: existing itemLink/recipeLink [...] field, then
--- GetItemInfo(recipeId) for item-keyed recipes, then GetSpellInfo for spells.
--- Run once on PEW after BackfillReagentItemIds.  Idempotent.
function Scanner:BackfillBogusRecipeNames()
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.recipes then return end
    local checked, fixed = 0, 0
    for _, profRecipes in pairs(gdb.recipes) do
        for recipeId, rd in pairs(profRecipes) do
            local needsName = isBogusName(rd.name)
            if needsName then
                checked = checked + 1
                local clean = cleanRecipeName(rd.name, rd.itemLink, rd.recipeLink)
                if not isBogusName(clean) then
                    rd.name = clean
                end
            end
            -- Item-keyed recipe (most professions): recipeId IS the crafted item
            -- ID, so GetItemInfo gives us name + icon + a real itemLink.
            -- Reject the result when it matches a Blizzard internal/dev/QA name
            -- (TEST / ZZOLD / DEPRECATED / [PH] / OLD) — the item-ID namespace
            -- collides with the spell-ID namespace for some recipes (e.g. spell
            -- 26926 = Heavy Copper Ring; item 26926 = "59 TEST Green Shaman
            -- Chest"), and we don't want the test name leaking into the UI.
            if isBogusName(rd.name) and rd.isSpell ~= true and type(recipeId) == "number" then
                local nm, link, _, _, _, _, _, _, _, icon = GetItemInfo(recipeId)
                if nm and not isObsoleteItemName(nm) then
                    rd.name     = rd.name     and not isBogusName(rd.name)     and rd.name     or nm
                    rd.icon     = rd.icon     or icon
                    rd.itemLink = rd.itemLink or link
                end
            end
            -- Spell-keyed recipe (enchanting / craft frame): try GetSpellInfo.
            -- Run regardless of the isSpell flag because (a) GetSpellInfo
            -- returns nil for non-spell IDs so there are no false positives,
            -- and (b) stubs created by MergeCraftersIntoGdb when crafters:<pid>
            -- arrives before recipemeta:<pid> leave isSpell/spellId both unset.
            -- Without this fallback, Enchanting recipeIds (which ARE the
            -- enchant spell ID) stay as "? <id>" forever — /togpm backfill
            -- can't fix them because the spell branch never runs. When the
            -- lookup succeeds we backfill isSpell + spellId so future tooltip
            -- resolution in BrowserTab uses SetSpellByID instead of falling
            -- through to "item:<id>" (which produces "Retrieving item
            -- information" for spell-only IDs).
            if isBogusName(rd.name) and type(recipeId) == "number" and GetSpellInfo then
                local sid = rd.spellId or recipeId
                local nm, _, icon = GetSpellInfo(sid)
                if nm then
                    rd.name    = nm
                    rd.icon    = rd.icon or icon
                    rd.isSpell = true
                    rd.spellId = rd.spellId or sid
                end
            end
            if needsName and not isBogusName(rd.name) then
                fixed = fixed + 1
            end
        end
    end
    if checked > 0 then
        addon:Print(("Recipe-name backfill: checked=%d fixed=%d"):format(checked, fixed))
    end
end

function Scanner:ScanSaltShaker(stored, now, itemId)
    local start, duration
    if C_Container and C_Container.GetItemCooldown then
        start, duration = C_Container.GetItemCooldown(itemId)
    end

    if start and start > 0 and duration and duration > 1.5 then
        local remaining = GetCooldownLeft(start, duration)
        if remaining > 0 and remaining < 345600 then
            stored[itemId] = math.floor(now + remaining)
            return
        end
    end

    -- Not on cooldown (or bogus value). Seed to Ready if player owns item (incl. bank).
    if not stored[itemId] or (stored[itemId] - now) > 691200 then
        local count = GetItemCount and GetItemCount(itemId, true) or 0
        if count and count > 0 then
            stored[itemId] = now - 1
        end
    end
end

-- ---------------------------------------------------------------------------
-- Broadcast helpers
-- ---------------------------------------------------------------------------

--- Schedule a debounced broadcast (0.5 s coalesce window).
function Scanner:ScheduleBroadcast()
    if self._pendingBroadcast then return end
    self._pendingBroadcast = true
    Ace:ScheduleTimer(function()
        self._pendingBroadcast = false
        self:BroadcastHashes()
    end, 0.5)
end

--- v0.2.0 — Broadcast our L0 leaf-hash list to the guild.
-- Differential: only sends leaves whose (hash, updatedAt) tuple has changed
-- since our last broadcast.  Steady-state broadcasts are typically empty (no
-- entries) when no local content has changed; in that case we skip the send
-- entirely.  Suppressed by debounce within self._broadcastSeconds.
function Scanner:BroadcastHashes()
    local DS = self.DS
    if not DS then return end
    -- Belt-and-suspenders: never broadcast no-guild data. addon:GetGuildDb()
    -- now falls back to a synthetic NoGuildBucketKey bucket when guildless,
    -- so this guard is what keeps that bucket's contents off the wire.
    if not addon:GetGuildKey() then return end

    local now = GetServerTime()
    if (now - self._lastBroadcastAt) < self._broadcastSeconds then
        addon:DebugPrint("Scanner: broadcast suppressed (debounce)")
        return
    end

    local gdb = addon:GetGuildDb()
    if not gdb then return end

    local current = addon.HashManager:GetL0BroadcastMap(gdb)
    -- Pad placeholders so peers offer data for professions we have no
    -- local content for. See HashManager:PadMissingProfessionPlaceholders.
    addon.HashManager:PadMissingProfessionPlaceholders(DS, current)
    local last    = self._lastBroadcastHashes or {}
    local delta   = {}
    local count   = 0
    for k, v in pairs(current) do
        local prev = last[k]
        if not prev or prev.hash ~= v.hash or prev.updatedAt ~= v.updatedAt then
            delta[k] = v
            count = count + 1
        end
    end
    if count == 0 then
        addon:DebugPrint("Scanner: no hash changes — broadcast skipped")
        return
    end

    DS:BroadcastItemHashes(delta, "BULK")
    -- Snapshot the FULL current map (not just delta) so future broadcasts
    -- diff against everything we've ever broadcast, not just the last delta.
    self._lastBroadcastHashes = current
    self._lastBroadcastAt = now
    addon:DebugPrint("Scanner: broadcast", count, "leaf hashes")
    if addon.callbacks then
        addon.callbacks:Fire("SYNC_SENT", "guild", count)
    end
end

--- v0.2.0 — Broadcast a single leaf's data to the guild on the DATA channel.
-- Called in response to a leaf-data request from a peer.  All peers on the
-- guild channel see the broadcast; any with stale data for the same leaf
-- merges via OnGuildDataReceived.
function Scanner:BroadcastLeafToGuild(itemKey)
    local DS = self.DS
    if not DS then return end
    if not addon:GetGuildKey() then return end  -- never broadcast no-guild data
    local payload = self:BuildLeafPayload(itemKey)
    if not payload then
        addon:DebugPrint("Scanner: BroadcastLeafToGuild — no content for", itemKey)
        return
    end
    DS:BroadcastData(payload, "GUILD", "BULK")
    if DS.p2p then
        DS.p2p:OnItemCompleted(itemKey, addon:GetCharacterKey())
    end
    addon:DebugPrint("Scanner: broadcast leaf", itemKey)
    if addon.callbacks then
        addon.callbacks:Fire("SYNC_SENT", "guild", itemKey)
    end
end

--- v0.2.0 — Broadcast a sub-hash list for a roll-up parent.
-- Called in response to a subhashes request.  Receiver compares per-character
-- hashes locally and follows up with leaf-data requests for differing leaves.
function Scanner:BroadcastSubhashesToGuild(parentItemKey)
    local DS = self.DS
    if not DS then return end
    if not addon:GetGuildKey() then return end  -- never broadcast no-guild data
    local gdb = addon:GetGuildDb()
    if not gdb then return end
    local HM = addon.HashManager

    local subhashes
    if parentItemKey == "guild:cooldowns" then
        subhashes = HM:GetCooldownLevelMap(gdb)
    elseif parentItemKey == "guild:accountchars" then
        subhashes = HM:GetAccountCharsLevelMap(gdb)
    else
        addon:DebugPrint("Scanner: BroadcastSubhashesToGuild — unknown parent", parentItemKey)
        return
    end

    local payload = {
        charKey   = addon:GetCharacterKey(),
        guildKey  = addon:GetGuildKey(),
        timestamp = GetServerTime(),
        type      = "subhashes",
        parent    = parentItemKey,
        subhashes = subhashes,
    }
    DS:BroadcastData(payload, "GUILD", "BULK")
    addon:DebugPrint("Scanner: broadcast subhashes for", parentItemKey)
end

--- v0.2.0 — Build a wire payload containing one leaf's data.
-- Returns nil when the local player has no content for itemKey.
function Scanner:BuildLeafPayload(itemKey)
    local gdb = addon:GetGuildDb()
    if not gdb then return nil end
    local now = GetServerTime()

    local payload = {
        charKey   = addon:GetCharacterKey(),
        guildKey  = addon:GetGuildKey(),
        timestamp = now,
        leaves    = {},
    }
    local lastScanOut = {}
    local entry = gdb.hashes and gdb.hashes[itemKey] or nil

    if itemKey:sub(1, 9) == "cooldown:" then
        local owner  = itemKey:sub(10)
        local bucket = gdb.cooldowns and gdb.cooldowns[owner]
        if not bucket or not next(bucket) then return nil end
        -- Convert absolute expiresAt → relative remaining for the wire.
        local cdRel = {}
        for spellId, expiresAt in pairs(bucket) do
            local remaining = expiresAt - now
            cdRel[spellId] = remaining > 0 and remaining or 0
        end
        payload.leaves[itemKey] = {
            data      = cdRel,
            hash      = entry and entry.hash      or 0,
            updatedAt = entry and entry.updatedAt or 0,
        }
        local ls = gdb.lastScan and gdb.lastScan[owner]
        if ls and ls.cooldowns then
            lastScanOut[owner] = { cooldowns = ls.cooldowns }
        end

    elseif itemKey:sub(1, 13) == "accountchars:" then
        local owner = itemKey:sub(14)
        -- v0.7.0: per-broadcaster alt-group arrays live under altClaims to
        -- avoid colliding with the boolean-flag accountChars set.
        local group = gdb.altClaims and gdb.altClaims[owner]
        if not group or #group == 0 then return nil end
        payload.leaves[itemKey] = {
            data      = group,
            hash      = entry and entry.hash      or 0,
            updatedAt = entry and entry.updatedAt or 0,
        }
        local ls = gdb.lastScan and gdb.lastScan[owner]
        if ls and ls.accountchars then
            lastScanOut[owner] = { accountchars = ls.accountchars }
        end

    -- v0.7.0: recipemeta: leaf removed entirely. All recipe metadata (name,
    -- icon, reagents, links) lives in the shipped addon.recipeDB and is looked
    -- up by recipeId at display time. The receiver never needs name/icon over
    -- the wire — they have it locally.

    elseif itemKey:sub(1, 9) == "crafters:" then
        local profId = tonumber(itemKey:sub(10))
        if not profId or not gdb.recipes or not gdb.recipes[profId] then return nil end
        -- v0.7.0: bare {[recipeId] = {[charKey] = true}}. Per-crafter guild tag
        -- is NOT shipped — receivers compute it locally from their current
        -- guild context (inbound data always arrived through the receiver's
        -- own guild channel, so all crafters in the payload share the
        -- receiver's current guild tag at receive time).
        local crafters = {}
        local hasCrafters = false
        for recipeId, rd in pairs(gdb.recipes[profId]) do
            if rd.crafters and next(rd.crafters) then
                local set = {}
                for ck, v in pairs(rd.crafters) do
                    if v then set[ck] = true end
                end
                if next(set) then
                    crafters[recipeId] = set
                    hasCrafters = true
                end
            end
        end
        if not hasCrafters then return nil end
        payload.leaves[itemKey] = {
            data      = crafters,
            hash      = entry and entry.hash      or 0,
            updatedAt = entry and entry.updatedAt or 0,
        }
        -- Include skill ranks for everyone who crafts in this profession.
        if gdb.skills then
            local skillsOut = {}
            for ck, charSkills in pairs(gdb.skills) do
                local s = charSkills[profId]
                if s then
                    skillsOut[ck] = { skillRank = s.skillRank, skillMax = s.skillMax }
                end
            end
            if next(skillsOut) then payload.skills = { [profId] = skillsOut } end
        end
        -- Include profession-spec (TBC alchemy / tailoring) for everyone in
        -- this profession. Drives the bonus-output indicator on the Cooldowns
        -- tab. Same opportunistic-piggyback model as skills above — propagates
        -- on the next crafters: leaf transfer rather than triggering its own
        -- broadcast on spec acquisition (which is a one-time event per char).
        if gdb.specializations then
            local specsOut = {}
            for ck, charSpecs in pairs(gdb.specializations) do
                local sid = charSpecs[profId]
                if sid then specsOut[ck] = sid end
            end
            if next(specsOut) then payload.specializations = { [profId] = specsOut } end
        end
        if gdb.lastScan then
            for _, rd in pairs(gdb.recipes[profId]) do
                for ck in pairs(rd.crafters or {}) do
                    local ls = gdb.lastScan[ck]
                    if ls and ls[profId] then
                        if not lastScanOut[ck] then lastScanOut[ck] = {} end
                        lastScanOut[ck][profId] = ls[profId]
                    end
                end
            end
        end

    else
        return nil
    end

    if next(lastScanOut) then payload.lastScan = lastScanOut end
    return payload
end

-- ---------------------------------------------------------------------------
-- Receive & merge guild data
-- ---------------------------------------------------------------------------

--- Rebuild gdb.altGroups (denormalized lookup) from gdb.altClaims
--- (per-broadcaster authoritative).
--- Each member of any group gets a pointer to the same group array.
function Scanner:RebuildAltGroups(gdb)
    gdb.altGroups = {}
    for _, group in pairs(gdb.altClaims or {}) do
        if type(group) == "table" then
            for _, member in ipairs(group) do
                gdb.altGroups[member] = group
            end
        end
    end
end

--- Merge recipe metadata for one profession (incoming from a recipemeta:<profId>
--- leaf payload).  Preserves richest non-nil per field.  Reagents merge per
--- entry via mergeReagents so peers with partial reagent data don't wipe
--- richer data on receive.  Crafters set is left untouched — that lives in
--- the crafters:<profId> leaf.
function Scanner:MergeRecipeMetaIntoGdb(gdb, profId, meta)
    if type(meta) ~= "table" then return end
    if not gdb.recipes[profId] then gdb.recipes[profId] = {} end
    local profRecipes = gdb.recipes[profId]
    for recipeId, rd in pairs(meta) do
        if type(rd) == "table" then
            -- Cross-guildmate poison containment: if the sender's gdb is
            -- still carrying a Blizzard internal/dev/QA name (TEST / ZZOLD /
            -- DEPRECATED / [PH]) from a pre-v0.5.5 stub, do NOT propagate it
            -- into ours. Treat the incoming name as missing — the local
            -- BackfillBogusRecipeNames pass will populate from GetSpellInfo.
            -- Without this guard, ONE poisoned client's broadcast re-infects
            -- everyone via MergeRecipeMetaIntoGdb every time they sync.
            local incomingName = rd.name
            if isObsoleteItemName(incomingName) then incomingName = nil end
            local existing = profRecipes[recipeId]
            if not existing then
                profRecipes[recipeId] = {
                    name       = cleanRecipeName(incomingName, rd.itemLink, rd.recipeLink),
                    icon       = rd.icon,
                    isSpell    = rd.isSpell and true or false,
                    spellId    = rd.spellId,
                    itemLink   = asString(rd.itemLink),
                    recipeLink = asString(rd.recipeLink),
                    reagents   = mergeReagents(nil, rd.reagents),
                    crafters   = {},
                }
            else
                -- Self-heal: if the stored name is a "? <id>" placeholder OR
                -- an obsolete-marker leftover from a pre-v0.5.5 cache, replace
                -- it with whatever the new payload (or our existing links)
                -- can produce.
                if isBogusName(existing.name) or isObsoleteItemName(existing.name) then
                    local clean = cleanRecipeName(incomingName,
                        rd.itemLink   or existing.itemLink,
                        rd.recipeLink or existing.recipeLink)
                    if not isBogusName(clean) and not isObsoleteItemName(clean) then
                        existing.name = clean
                    else
                        existing.name = nil  -- let backfill repopulate via GetSpellInfo
                    end
                elseif incomingName and not existing.name then
                    existing.name = incomingName
                end
                if rd.icon    and not existing.icon    then existing.icon    = rd.icon    end
                if rd.isSpell ~= nil and existing.isSpell == nil then existing.isSpell = rd.isSpell and true or false end
                if rd.spellId and not existing.spellId then existing.spellId = rd.spellId end
                if asString(rd.itemLink)   and not existing.itemLink   then existing.itemLink   = rd.itemLink   end
                if asString(rd.recipeLink) and not existing.recipeLink then existing.recipeLink = rd.recipeLink end
                if type(rd.reagents) == "table" then
                    local merged = mergeReagents(existing.reagents, rd.reagents)
                    if merged then existing.reagents = merged end
                end
            end
        end
    end
end

--- Merge incoming crafters set for one profession into gdb.recipes[profId].
--- @param senderClaimsOwnScan  true if the sender authoritatively claims this
---                             is their own scan output for this profession.
---                             Triggers wipe-then-re-add for the sender's
---                             charKey so unlearned recipes get removed.
---                             Relayed data (false) is union-add only.
function Scanner:MergeCraftersIntoGdb(gdb, profId, crafters, senderKey, senderClaimsOwnScan)
    if type(crafters) ~= "table" then return end
    if not gdb.recipes[profId] then gdb.recipes[profId] = {} end
    local profRecipes = gdb.recipes[profId]

    -- Hide recipes the local addon DB doesn't know about (sender's addon is
    -- newer / has SoD content we don't ship yet). We could store them as
    -- unknown rows, but the UI hides them anyway — no point bloating the DB.
    local localProfDB = addon.recipeDB and addon.recipeDB[profId]

    -- Receiver-side guild tag: inbound DeltaSync data always arrives via our
    -- own guild channel, so every crafter in the payload gets tagged with
    -- the current player's guild tag (or PersonalTag if guildless, though
    -- that case shouldn't reach the wire — broadcasts gate on a real guild).
    local tag = addon:GetCurrentGuildTag()

    if senderClaimsOwnScan and senderKey then
        for _, rd in pairs(profRecipes) do
            if rd.crafters then rd.crafters[senderKey] = nil end
        end
    end

    for recipeId, ckSet in pairs(crafters) do
        if type(ckSet) == "table" then
            -- v0.7.1: peers running on Vanilla (or v0.7.0 pre-key-fix on
            -- HC) may broadcast crafter sets keyed by crafted-item-ID
            -- instead of spell-ID. Resolve to spell-ID before storing so
            -- the cross-reference with addon.recipeDB works.
            local effectiveId = recipeId
            if localProfDB and not localProfDB[recipeId] then
                local spellId = addon:GetSpellIdForCraftedItem(profId, recipeId)
                if spellId then effectiveId = spellId end
            end
            if not localProfDB or localProfDB[effectiveId] then
                local existing = profRecipes[effectiveId]
                if not existing then
                    existing = { crafters = {} }
                    profRecipes[effectiveId] = existing
                end
                if not existing.crafters then existing.crafters = {} end
                for ck, v in pairs(ckSet) do
                    if v and type(ck) == "string" then existing.crafters[ck] = tag end
                end
            end
        end
    end
end

--- v0.2.0 — Called by DeltaSync when a peer's broadcast or whisper arrives.
-- Two payload shapes are accepted:
--   1. Subhashes response: { type = "subhashes", parent = ..., subhashes = ... }
--      Receiver compares per-character hashes locally and follows up with
--      leaf-data requests for each differing leaf.
--   2. Leaf-data broadcast: { leaves = { itemKey = { data, hash, updatedAt } } }
--      Receiver runs content-aware merge per leaf type.
function Scanner:OnGuildDataReceived(sender, data, bytes)
    addon:DebugPrint("Scanner: OnGuildDataReceived ENTRY sender=", sender, "bytes=", bytes or 0)
    if not data or type(data) ~= "table" then
        addon:DebugPrint("Scanner: BAIL — malformed data from", sender)
        return
    end

    local senderKey = data.charKey
    if not senderKey or type(senderKey) ~= "string" then
        addon:DebugPrint("Scanner: BAIL — no charKey in payload from", sender)
        return
    end

    local DS         = self.DS
    local GuildCache = self.GuildCache
    if GuildCache then
        senderKey = GuildCache:NormalizeName(senderKey) or senderKey
    end

    -- Ignore echoes of our own broadcast.
    if senderKey == addon:GetCharacterKey() then
        addon:DebugPrint("Scanner: BAIL — own echo from", sender, "(senderKey=", senderKey, ")")
        return
    end

    if not addon:GetGuildKey() then
        addon:DebugPrint("Scanner: BAIL — no guild key (not in a guild?) sender=", sender)
        return
    end
    local gdb = addon:GetGuildDb()
    if not gdb then
        addon:DebugPrint("Scanner: BAIL — no gdb sender=", sender)
        return
    end
    local now = GetServerTime()

    -- ── Subhashes response ─────────────────────────────────────────────────
    -- Peer broadcast their per-character sub-hashes for a roll-up parent.
    -- Compare locally, request individual leaves we differ on.
    if data.type == "subhashes" and type(data.subhashes) == "table" then
        local localHashes = gdb.hashes or {}
        local toRequest = {}
        for itemKey, peerEntry in pairs(data.subhashes) do
            if type(peerEntry) == "table" and peerEntry.hash then
                local mine = localHashes[itemKey]
                if not mine or mine.hash ~= peerEntry.hash then
                    toRequest[#toRequest + 1] = itemKey
                end
            end
        end
        if #toRequest > 0 and DS and DS.RequestData then
            -- Online gate (mirrors onSyncAccepted above): peer may have
            -- gone offline between sending us their subhashes and our
            -- follow-up leaf-data request landing on the wire.
            if Scanner.GuildCache and not Scanner.GuildCache:IsPlayerOnline(sender) then
                addon:DebugPrint("Scanner:   → skip leaf-data RequestData — peer offline:", sender)
            else
                DS:RequestData(sender, { type = "leaf-data", keys = toRequest })
            end
        end
        -- Complete the parent session.  Without this, P2P keeps the parent
        -- itemKey (e.g., "guild:cooldowns") in ACTIVE state until the
        -- session timeout fires (~180s), which clogs the maxActiveSessions
        -- slot and blocks dispatch of any new sessions — including the
        -- per-character leaves we just requested.  The subhashes response
        -- IS the completion of the parent's request; child leaf sessions
        -- are tracked separately and complete on their own data arrival.
        if DS and DS.p2p and data.parent then
            DS.p2p:OnItemCompleted(data.parent, sender)
        end
        if addon.callbacks then
            addon.callbacks:Fire("SYNC_RECV", sender, bytes or 0)
        end
        addon:DebugPrint("Scanner: received", #toRequest, "differing subhashes for",
            data.parent, "from", sender)
        return
    end

    -- ── Leaf-data merge ────────────────────────────────────────────────────
    if type(data.leaves) ~= "table" then
        addon:DebugPrint("Scanner: payload from", sender, "has neither subhashes nor leaves")
        return
    end

    -- Merge incoming lastScan timestamps first (max wins).  HashManager reads
    -- these when computing content-derived updatedAt for invalidated leaves.
    if type(data.lastScan) == "table" then
        for ck, scopes in pairs(data.lastScan) do
            if type(ck) == "string" and type(scopes) == "table" then
                if not gdb.lastScan[ck] then gdb.lastScan[ck] = {} end
                for scope, ts in pairs(scopes) do
                    if type(ts) == "number" then
                        local existing = gdb.lastScan[ck][scope] or 0
                        if ts > existing then gdb.lastScan[ck][scope] = ts end
                    end
                end
            end
        end
    end

    local touchedAltGroups = false
    local touchedProfessions = {}

    for itemKey, leafEntry in pairs(data.leaves) do
        if type(leafEntry) == "table" then
            local leafData = leafEntry.data

            if itemKey:sub(1, 9) == "cooldown:" then
                local owner = itemKey:sub(10)
                if not gdb.cooldowns[owner] then gdb.cooldowns[owner] = {} end
                if type(leafData) == "table" then
                    for spellId, remaining in pairs(leafData) do
                        if type(remaining) == "number" and remaining >= 0 and remaining < 2592000 then
                            local newExpiry = now + remaining
                            local existing = gdb.cooldowns[owner][spellId]
                            if not existing or newExpiry > existing then
                                gdb.cooldowns[owner][spellId] = newExpiry
                            end
                        end
                    end
                end
                if DS then addon.HashManager:InvalidateCharCooldowns(DS, gdb, owner) end
                if DS and DS.p2p then DS.p2p:OnItemCompleted(itemKey, sender) end

            elseif itemKey:sub(1, 13) == "accountchars:" then
                local owner = itemKey:sub(14)
                if type(leafData) == "table" then
                    if not gdb.altClaims then gdb.altClaims = {} end
                    if owner == senderKey then
                        -- Authoritative replace for the broadcaster's own group.
                        local arr = {}
                        for _, ck in ipairs(leafData) do
                            if type(ck) == "string" then arr[#arr + 1] = ck end
                        end
                        table.sort(arr)
                        gdb.altClaims[owner] = arr
                    else
                        -- Relay: union add to existing.
                        if not gdb.altClaims[owner] then gdb.altClaims[owner] = {} end
                        local seen = {}
                        for _, ck in ipairs(gdb.altClaims[owner]) do seen[ck] = true end
                        for _, ck in ipairs(leafData) do
                            if type(ck) == "string" and not seen[ck] then
                                gdb.altClaims[owner][#gdb.altClaims[owner] + 1] = ck
                                seen[ck] = true
                            end
                        end
                        table.sort(gdb.altClaims[owner])
                    end
                    touchedAltGroups = true
                end
                if DS then addon.HashManager:InvalidateAccountChars(DS, gdb, owner) end
                if DS and DS.p2p then DS.p2p:OnItemCompleted(itemKey, sender) end

            -- v0.7.0: recipemeta: leaf removed (metadata lives in shipped
            -- addon.recipeDB, not synced). Receivers ignore inbound recipemeta:
            -- payloads from any straggler peer that wasn't aware of the change;
            -- the namespace bump TOGPmv2 → TOGPmv3 means v0.6.x clients can't
            -- reach our OnGuildDataReceived in the first place.

            elseif itemKey:sub(1, 9) == "crafters:" then
                local profId = tonumber(itemKey:sub(10))
                if profId then
                    -- Sender is claiming an authoritative own-scan if they
                    -- include a skills entry for themselves at this profId.
                    local senderClaimsOwnScan =
                        type(data.skills) == "table"
                        and type(data.skills[profId]) == "table"
                        and data.skills[profId][senderKey] ~= nil
                    self:MergeCraftersIntoGdb(gdb, profId, leafData,
                        senderKey, senderClaimsOwnScan)
                    -- Skills (per-charKey rank/max) ride along on crafters payloads.
                    if type(data.skills) == "table"
                       and type(data.skills[profId]) == "table" then
                        for ck, sk in pairs(data.skills[profId]) do
                            if type(sk) == "table" and type(ck) == "string" then
                                if not gdb.skills[ck] then gdb.skills[ck] = {} end
                                local existing = gdb.skills[ck][profId]
                                local incomingRank = sk.skillRank or 0
                                if not existing
                                   or incomingRank > (existing.skillRank or 0) then
                                    gdb.skills[ck][profId] = {
                                        skillRank = incomingRank,
                                        skillMax  = sk.skillMax or 300,
                                    }
                                end
                            end
                        end
                    end
                    -- Specializations (per-charKey spec spell ID) also ride along.
                    -- Last-write-wins is fine — a character's spec changes ~once
                    -- ever (or never), so divergence between peers is transient.
                    if type(data.specializations) == "table"
                       and type(data.specializations[profId]) == "table" then
                        if not gdb.specializations then gdb.specializations = {} end
                        for ck, sid in pairs(data.specializations[profId]) do
                            if type(ck) == "string" and type(sid) == "number" then
                                if not gdb.specializations[ck] then gdb.specializations[ck] = {} end
                                gdb.specializations[ck][profId] = sid
                            end
                        end
                    end
                    touchedProfessions[profId] = true
                end
                if DS and DS.p2p then DS.p2p:OnItemCompleted(itemKey, sender) end
            end
        end
    end

    -- Rebuild altGroups derived view if any accountchars leaf was merged.
    if touchedAltGroups then self:RebuildAltGroups(gdb) end

    -- Recompute hashes for any professions touched (covers both recipemeta
    -- and crafters leaves; InvalidateProfession handles both leaves at once).
    if DS then
        for profId in pairs(touchedProfessions) do
            addon.HashManager:InvalidateProfession(DS, gdb, profId)
        end
    end

    -- Record sync time so /togpm status reflects "we heard from this peer".
    if type(data.timestamp) == "number" then
        gdb.syncTimes[senderKey] = data.timestamp
    end

    addon:DebugPrint("Scanner: merged leaves from", sender, "(", bytes or 0, "bytes)")

    if addon.callbacks then
        addon.callbacks:Fire("SYNC_RECV", sender, bytes or 0)
        addon.callbacks:Fire("GUILD_DATA_UPDATED", senderKey)
    end
end
