-- GuildCache.lua
-- Lightweight guild member presence cache for DeltaSync.
--
-- Populates lib.guildRoster via GUILD_ROSTER_UPDATE and exposes:
--
--   lib:NormalizeName(name)       → canonical "Name-Realm" string, or nil
--   lib:GetNormalizedPlayer()     → local player as "Name-Realm"
--   lib:IsPlayerOnline(name)      → bool; true if in guild and currently online
--   lib:IsInGuild(name)           → bool; true if member of the current guild
--   lib:GetOnlineGuildMembers()   → array of normalized names of online members
--
-- No banker, rank, or role concepts.  Peer eligibility is controlled by the
-- isValidPeer callback the host addon passes to lib:InitP2P().

local MAJOR = "DeltaSync-1.0"
local lib   = LibStub and LibStub:GetLibrary(MAJOR, true)
if not lib then
    error("DeltaSync GuildCache: DeltaSync-1.0 must be loaded first")
    return
end

-- Survive LibStub upgrades.
-- Format: normalizedName → {isOnline=bool, class=str, level=num, rank=str}
lib.guildRoster       = lib.guildRoster       or {}
lib._normalizedPlayer = lib._normalizedPlayer or nil

-- ─── Internal helper ──────────────────────────────────────────────────────────

local function GetCurrentRealm()
    return GetNormalizedRealmName and GetNormalizedRealmName() or ""
end

-- ─── Name Normalization ───────────────────────────────────────────────────────

--- Canonicalize a player name to "Name-Realm" form.
-- Handles bare names, fully-qualified names, and spacing variants ("Name - Realm").
-- @param name  string — raw name from WoW API, AceComm sender, or chat
-- @return      string "Name-Realm", or nil for empty / malformed input
function lib:NormalizeName(name)
    if not name or type(name) ~= "string" then return nil end

    -- Trim leading/trailing whitespace
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then return nil end

    -- Canonicalize hyphen spacing: "Name - Realm" / "Name- Realm" → "Name-Realm"
    trimmed = trimmed:gsub("%s*%-%s*", "-")

    -- If already has a non-empty realm suffix, return as-is
    local left, right = trimmed:match("^(.-)%-(.+)$")
    if left and right and left ~= "" and right ~= "" then
        return trimmed
    end

    -- Bare name — append current realm
    local realm = GetCurrentRealm()
    if realm ~= "" then
        return trimmed .. "-" .. realm
    end

    return trimmed
end

--- Return the local player's canonical "Name-Realm" string.
-- Cached after first successful derivation; invalidated on PLAYER_LOGIN.
function lib:GetNormalizedPlayer()
    if lib._normalizedPlayer then
        return lib._normalizedPlayer
    end
    local name  = UnitName and UnitName("player") or ""
    local realm = GetCurrentRealm()
    if name ~= "" and realm ~= "" then
        lib._normalizedPlayer = name .. "-" .. realm
        return lib._normalizedPlayer
    end
    return name
end

-- ─── Roster Rebuild ───────────────────────────────────────────────────────────

--- Rebuild the in-memory guild roster from the WoW API.
-- Called on GUILD_ROSTER_UPDATE and PLAYER_LOGIN.
-- GetGuildRosterInfo columns (Classic Era):
--   1=name, 2=rank, 3=rankIndex, 4=level, 5=classLocale,
--   6=zone, 7=note, 8=officerNote, 9=online, 10=status, 11=class(English)
function lib:_RebuildGuildRoster()
    local newRoster = {}
    local count     = 0

    if IsInGuild and IsInGuild() then
        local total = GetNumGuildMembers and GetNumGuildMembers() or 0
        for i = 1, total do
            local fullName, rank, _, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
            if fullName then
                local norm = lib:NormalizeName(fullName)
                if norm then
                    newRoster[norm] = {
                        isOnline = online == true,
                        class    = class,
                        level    = level,
                        rank     = rank,
                    }
                    count = count + 1
                end
            end
        end
    end

    lib.guildRoster = newRoster
    lib:Debug("INIT", "GuildCache rebuilt: %d member(s)", count)
end

-- ─── Public Queries ───────────────────────────────────────────────────────────

--- True if the named player is in the current guild AND currently online.
-- Triggers a lazy roster rebuild if the cache is empty (covers the brief window
-- before the first GUILD_ROSTER_UPDATE fires after login).
-- @param name  string — player name in any format
-- @return      bool
function lib:IsPlayerOnline(name)
    if not name then return false end
    local norm = lib:NormalizeName(name)
    if not norm then return false end

    local entry = lib.guildRoster[norm]
    if entry then
        return entry.isOnline == true
    end

    -- Cache miss — attempt a lazy rebuild
    if not next(lib.guildRoster) and IsInGuild and IsInGuild() then
        lib:_RebuildGuildRoster()
        entry = lib.guildRoster[norm]
    end

    return entry ~= nil and entry.isOnline == true
end

--- True if the named player is a member of the current guild.
-- When the roster cache is empty and we ARE in a guild, triggers a lazy rebuild.
-- When the roster cache is empty and we are NOT in a guild (or rebuild still
-- yields nothing), returns true — generic/non-guild use cases are not blocked.
-- @param name  string — player name in any format
-- @return      bool
function lib:IsInGuild(name)
    if not name then return false end
    local norm = lib:NormalizeName(name)
    if not norm then return false end

    -- Lazy rebuild when cache is empty but we are in a guild
    if not next(lib.guildRoster) and IsInGuild and IsInGuild() then
        lib:_RebuildGuildRoster()
    end

    -- If still empty (not in a guild, or very early login window), allow all peers
    -- so the library is usable in non-guild / PARTY / RAID contexts.
    if not next(lib.guildRoster) then return true end

    return lib.guildRoster[norm] ~= nil
end

--- Returns an array of normalized names for all currently online guild members.
-- @return  table (array of strings)
function lib:GetOnlineGuildMembers()
    local online = {}
    for norm, entry in pairs(lib.guildRoster) do
        if entry.isOnline then
            table.insert(online, norm)
        end
    end
    return online
end

-- ─── Event Watcher ────────────────────────────────────────────────────────────

if not lib._guildCacheFrame then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            -- Invalidate cached player name so it re-derives with the correct realm
            lib._normalizedPlayer = nil
        end
        lib:_RebuildGuildRoster()
    end)
    lib._guildCacheFrame = frame
end
