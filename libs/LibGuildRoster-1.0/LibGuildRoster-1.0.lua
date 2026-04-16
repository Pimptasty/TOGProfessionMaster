--[[
    LibGuildRoster-1.0

    Tracks the WoW Classic guild roster with reliable wipe+rebuild semantics.
    Uses GUILD_ROSTER_UPDATE for full rebuilds and CHAT_MSG_SYSTEM for real-time
    online/offline/join/leave transitions. Retries up to MAX_RETRIES times at
    login to handle the window where GetNumGuildMembers() returns 0.

    All state is in-memory — nothing is persisted to SavedVariables. Stale
    ex-members are impossible because the roster is wiped on every rebuild.

    Callbacks (via CallbackHandler-1.0):
        OnRosterReady()         Fired once after the first successful full build.
        OnRosterUpdated()       Fired after every full rebuild.
        OnMemberOnline(name)    Fired when a member transitions to online.
        OnMemberOffline(name)   Fired when a member transitions to offline.
        OnMemberJoined(name)    Fired when a member joins the guild.
        OnMemberLeft(name)      Fired when a member leaves the guild.

    Public API:
        lib:IsInGuild(name)       -> boolean
        lib:IsOnline(name)        -> boolean
        lib:GetMember(name)       -> table|nil  { name, class, level, rankIndex, rankName, isOnline }
        lib:GetAllMembers()       -> array of "Name-Realm" strings
        lib:GetOnlineMembers()    -> array of "Name-Realm" strings currently online
--]]

local MAJOR, MINOR = "LibGuildRoster-1.0", 1
local lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

-- TBC+ renamed GuildRoster() → C_GuildInfo.GuildRoster(); fall back for Classic Era.
local RequestGuildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster

local CBH = LibStub("CallbackHandler-1.0")
lib.callbacks = lib.callbacks or CBH:New(lib)

-- Roster: { ["Name-Realm"] = { name, class, level, rankIndex, rankName, isOnline } }
lib.roster      = lib.roster or {}
lib.realmName   = lib.realmName or nil       -- cached, set on PLAYER_LOGIN
lib.initialized = lib.initialized or false   -- true after first successful build
lib.retryCount  = lib.retryCount or 0
lib.MAX_RETRIES = 5

-- Re-register events cleanly on upgrade
if lib.frame then
    lib.frame:UnregisterAllEvents()
else
    lib.frame = CreateFrame("Frame", "LibGuildRoster10Frame")
end
lib.frame:RegisterEvent("PLAYER_LOGIN")
lib.frame:RegisterEvent("GUILD_ROSTER_UPDATE")
lib.frame:RegisterEvent("CHAT_MSG_SYSTEM")
lib.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        lib:OnPlayerLogin()
    elseif event == "GUILD_ROSTER_UPDATE" then
        lib:OnGuildRosterUpdate()
    elseif event == "CHAT_MSG_SYSTEM" then
        lib:OnChatMsgSystem(...)
    end
end)

--- Get the connected-realm-aware normalized realm name.
-- Uses GetNormalizedRealmName() which returns the canonical cluster realm name,
-- matching what GetGuildRosterInfo() appends to cross-realm member names.
function lib:GetRealmName()
    if not self.realmName then
        self.realmName = GetNormalizedRealmName()
    end
    return self.realmName
end

--- Normalize a player name to "Name-Realm" format.
-- Matches TOGBank's NormalizePlayerName defensive guards:
--   - coerces to string, trims whitespace, rejects empty/unknown names
--   - canonicalizes hyphen spacing ("Name - Realm" -> "Name-Realm")
--   - appends the connected-realm name if none is present
-- @param name any
-- @return string|nil
function lib:NormalizeName(name)
    if not name then return nil end
    if type(name) ~= "string" then name = tostring(name) end

    -- Trim leading/trailing whitespace
    local trimmed = string.gsub(name, "^%s+", "")
    trimmed = string.gsub(trimmed, "%s+$", "")
    if trimmed == "" then return nil end

    -- Canonicalize hyphen spacing: "Name - Realm" or "Name- Realm" -> "Name-Realm"
    local normalized = string.gsub(trimmed, "%s*%-%s*", "-")

    -- Validate the Name and Realm parts when both are present
    local left, right = string.match(normalized, "^(.-)%-(.-)$")
    if left and right then
        if left == "" then return nil end
        if string.lower(left) == "unknown" then return "Unknown" end
        if right ~= "" then return normalized end
        -- has a trailing hyphen but no realm — treat as short name
        normalized = left
    end

    if string.lower(normalized) == "unknown" then return "Unknown" end

    -- Append connected-realm name
    return normalized .. "-" .. self:GetRealmName()
end

--- PLAYER_LOGIN: cache realm name and request an initial roster update.
function lib:OnPlayerLogin()
    self.realmName = GetNormalizedRealmName()
    if IsInGuild() then
        RequestGuildRoster()
    end
end

--- GUILD_ROSTER_UPDATE: wipe and rebuild the full roster from scratch.
-- Retries up to MAX_RETRIES times if the API returns 0 members (login race).
function lib:OnGuildRosterUpdate()
    if not IsInGuild() then
        wipe(self.roster)
        self.initialized = false
        return
    end

    local total = GetNumGuildMembers()

    -- Retry if the guild roster API is not ready yet (common at login)
    if total == 0 and self.retryCount < self.MAX_RETRIES then
        self.retryCount = self.retryCount + 1
        RequestGuildRoster()
        return
    end

    self.retryCount = 0

    -- Snapshot previous online state before wipe for transition detection
    local wasOnline = {}
    for name, member in pairs(self.roster) do
        wasOnline[name] = member.isOnline
    end

    -- Wipe and rebuild from scratch — no stale entries possible
    wipe(self.roster)
    for i = 1, total do
        local name, rankName, rankIndex, level, _, _, _, _, isOnline, _, classFileName = GetGuildRosterInfo(i)
        if name then
            local norm = self:NormalizeName(name)
            if norm then
                self.roster[norm] = {
                    name      = norm,
                    class     = classFileName,
                    level     = level or 1,
                    rankIndex = rankIndex,
                    rankName  = rankName,
                    isOnline  = isOnline or false,
                }
            end
        end
    end

    local wasInitialized = self.initialized
    self.initialized = true

    -- OnRosterReady fires once on the first successful build
    if not wasInitialized then
        self.callbacks:Fire("OnRosterReady")
    end

    self.callbacks:Fire("OnRosterUpdated")

    -- Only fire OnMemberOnline for transitions on subsequent rebuilds.
    -- The first build silently establishes state (matching TOGBank's approach).
    -- CHAT_MSG_SYSTEM is the primary driver of real-time online/offline transitions;
    -- this loop only catches members who came online between two roster rebuilds
    -- (e.g., WoW fires GUILD_ROSTER_UPDATE again mid-session due to a guild change).
    if wasInitialized then
        for name, member in pairs(self.roster) do
            if member.isOnline and not wasOnline[name] then
                self.callbacks:Fire("OnMemberOnline", name)
            end
        end
    end
end

--- CHAT_MSG_SYSTEM: handle real-time guild state transitions.
-- Primary method for online/offline tracking between full rebuilds.
-- @param message string
function lib:OnChatMsgSystem(message)
    if not message or message == "" then return end

    -- "[Name] has come online."
    local onlineName = message:match("^%[?(.-)%]? has come online%.$")
    if onlineName then
        local norm = self:NormalizeName(onlineName)
        if norm and self.roster[norm] and not self.roster[norm].isOnline then
            self.roster[norm].isOnline = true
            self.callbacks:Fire("OnMemberOnline", norm)
        end
        return
    end

    -- "[Name] has gone offline."
    local offlineName = message:match("^%[?(.-)%]? has gone offline%.$")
    if offlineName then
        local norm = self:NormalizeName(offlineName)
        if norm and self.roster[norm] and self.roster[norm].isOnline then
            self.roster[norm].isOnline = false
            self.callbacks:Fire("OnMemberOffline", norm)
        end
        return
    end

    -- "[Name] has joined the guild." — trigger full rebuild to add them
    if message:match("^%[?(.-)%]? has joined the guild%.$") then
        RequestGuildRoster()
        return
    end

    -- "[Name] has left the guild." / "[Name] has been kicked out of the guild."
    local leftName = message:match("^%[?(.-)%]? has left the guild%.$")
        or message:match("^%[?(.-)%]? has been kicked out of the guild%.$")
    if leftName then
        local norm = self:NormalizeName(leftName)
        if norm and self.roster[norm] then
            self.roster[norm] = nil
            self.callbacks:Fire("OnMemberLeft", norm)
        end
        return
    end
end

--- Check if a player is currently a guild member.
-- O(1) lookup once initialized. Falls back to a linear scan before the first
-- full rebuild completes (covers the brief window at login).
-- @param name string - short name or "Name-Realm"
-- @return boolean
function lib:IsInGuild(name)
    local norm = self:NormalizeName(name)
    if not norm then return false end

    if self.initialized then
        return self.roster[norm] ~= nil
    end

    -- Fallback: roster not yet built — scan GetGuildRosterInfo directly
    if not IsInGuild() then return false end
    for i = 1, GetNumGuildMembers() do
        local rosterName = GetGuildRosterInfo(i)
        if rosterName and self:NormalizeName(rosterName) == norm then
            return true
        end
    end
    return false
end

--- Check if a guild member is currently online.
-- @param name string - short name or "Name-Realm"
-- @return boolean
function lib:IsOnline(name)
    local norm = self:NormalizeName(name)
    if not norm then return false end
    local member = self.roster[norm]
    return member ~= nil and member.isOnline == true
end

--- Get the full member data table, or nil if not in guild.
-- @param name string - short name or "Name-Realm"
-- @return table|nil { name, class, level, rankIndex, rankName, isOnline }
function lib:GetMember(name)
    local norm = self:NormalizeName(name)
    if not norm then return nil end
    return self.roster[norm]
end

--- Get an array of all current guild member names (Name-Realm format).
-- @return table
function lib:GetAllMembers()
    local result = {}
    for name in pairs(self.roster) do
        table.insert(result, name)
    end
    return result
end

--- Get an array of currently online guild member names (Name-Realm format).
-- @return table
function lib:GetOnlineMembers()
    local result = {}
    for name, member in pairs(self.roster) do
        if member.isOnline then
            table.insert(result, name)
        end
    end
    return result
end
