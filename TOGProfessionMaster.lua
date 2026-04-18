-- TOG Profession Master
-- Author: Pimptasty
-- Guild profession browser, cooldown tracker, and reagent planner for Classic WoW.

local addonName, addon = ...

-- ---------------------------------------------------------------------------
-- Addon global
-- Other files access the addon via the upvalue `addon` (from `...`) or via
-- the global `TOGPM` which is set below for any external callers.
-- ---------------------------------------------------------------------------
TOGPM       = TOGPM or {}
TOGPM.addon = addon
addon.name  = addonName

-- UI colors — change here to update everywhere.
addon.BrandColor       = "ffFF8000"   -- Legendary quality orange (Thunderfury)
addon.ColorYou         = addon.BrandColor  -- same as brand color for the current player's name
addon.ColorCrafter     = "ffaaaaaa"   -- muted gray for other crafters
addon.ColorOnline      = "ffffffff"   -- white for online guild members
addon.ColorOffline     = "ff888888"   -- dark gray for offline guild members

-- Version (resolved from .toc, works on all Classic builds)
local _GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
addon.Version = _GetAddOnMetadata(addonName, "Version") or "dev"

-- ---------------------------------------------------------------------------
-- AceAddon
-- Mixin order: AceConsole for slash, AceEvent for WoW events, AceTimer for
-- deferred work, AceComm + AceSerializer needed by DeltaSync.
-- ---------------------------------------------------------------------------
local Ace = LibStub("AceAddon-3.0"):NewAddon(
    addonName,
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0",
    "AceComm-3.0",
    "AceSerializer-3.0"
)
addon.lib = Ace

-- Custom callback bus used by Scanner.lua and Modules/SyncLog.lua.
-- CallbackHandler-1.0 ships with Ace3 so it is always available.
addon.callbacks = LibStub("CallbackHandler-1.0"):New(addon)

-- Convenient shorthand used throughout the addon files.
-- `addon.lib:RegisterEvent(...)` → Ace's event system.
-- `addon.lib:Print(...)` → prefixed chat output.

-- ---------------------------------------------------------------------------
-- AceDB schema
-- Guild data lives in `db.global` (account-wide) so all characters on the
-- same account share one copy, regardless of which realm they are on.
-- The composite key "Faction-GuildName" (built by GetGuildKey) segregates
-- guilds cleanly. The realm is intentionally omitted — all realms in a
-- connected-realm cluster share the same guild roster, so including the realm
-- would create separate buckets for the same guild. Guild names cannot contain
-- hyphens in WoW, so "Faction-GuildName" is unambiguous.
-- Per-character UI state lives in `db.char`.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- AceDB schema — split into two SavedVariables:
--   TOGPM_GuildDB   : guild-wide data (global scope, shared across characters)
--   TOGPM_Settings  : per-user settings and per-character UI state
-- ---------------------------------------------------------------------------
local GUILD_DB_DEFAULTS = {
    global = {
        -- All guild-specific data.
        -- Key format: "Alliance-Grobbulus-Knights of TOG"
        -- guildDb.global.guilds[compositeKey] = {
        --   recipes[profId][recipeId] = { name, icon, isSpell, crafters={["Name-Realm"]=true} }
        --   skills["Name-Realm"][profId] = { skillRank, skillMax }
        --   guildData       = { ["Name-Realm"] = {} }  -- membership index only
        --   cooldowns       = { ["Name-Realm"] = { [spellId] = expiresAt } }
        --   syncTimes       = { ["Name-Realm"] = timestamp }
        --   specializations = { ["Name-Realm"] = { [profId] = spellId } }
        --   factions        = { ["Name-Realm"] = "Alliance"|"Horde" }
        --   altGroups       = { ["Name-Realm"] = {"Name-Realm", "Alt-Realm", ...} }
        -- }
        guilds = {},
        -- Account-wide set of all own characters that have ever logged in with
        -- this addon.  Key = "Name-Realm", value = true.
        -- Used to mark crafters as "you" in the UI across all your alts.
        accountChars = {},
        -- Sync log ring buffer — capped at 200 entries by Modules/SyncLog.lua
        -- Each entry: { ts, event, peer, bytes }
        syncLog = {},
    },
}

local SETTINGS_DEFAULTS = {
    profile = {
        -- UI
        minimapButton   = true,
        minimapPos      = 220,   -- LibDBIcon angle in degrees
        mailReadyOnly   = false,
        debug           = false,
    },
    char = {
        -- Shopping list: [spellId] = { quantity = N }
        shoppingList    = {},

        -- Reagent watch list: [itemId] = true
        reagentWatch    = {},

        -- Shopping list alert flags: [spellId] = true
        shoppingAlerts  = {},

        -- Window positions / sizes saved by AceGUI.
        frames          = {},
    },
}

-- ---------------------------------------------------------------------------
-- Slash commands (registered in OnEnable once AceConsole is ready)
-- ---------------------------------------------------------------------------
local SLASH_COMMANDS = {
    [""]             = "OpenBrowser",
    ["reagents"]     = "OpenReagents",
    ["minimap"]      = "ShowMinimapButton",
    ["purge"]        = "OpenPurge",
    ["sync"]         = "ForceSync",
    ["status"]       = "PrintStatus",
    ["versioncheck"] = "PrintVersionCheck",
    ["debug"]        = "ToggleDebug",
    ["spellcache"]   = "DumpSpellCache",
    ["help"]         = "PrintHelp",
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function Ace:OnInitialize()
    -- Set up SavedVariables via AceDB (two separate SVs).
    -- TOGPM_Settings: profile (UI prefs) and char (shopping list, reagent watch, frames)
    self.db       = LibStub("AceDB-3.0"):New("TOGPM_Settings", SETTINGS_DEFAULTS, true)
    -- TOGPM_GuildDB: global guild-wide data (recipes, skills, cooldowns, sync log)
    addon.guildDb = LibStub("AceDB-3.0"):New("TOGPM_GuildDB", GUILD_DB_DEFAULTS, true)

    -- Restore debug flag from profile so DebugPrint works before OnEnable.
    addon.debug = self.db.profile.debug

    -- Register with VersionCheck-1.0 so we participate in guild version
    -- broadcasts.  VersionCheck fires after PLAYER_ENTERING_WORLD so the
    -- guild channel is available by the time it broadcasts.
    local VC = LibStub("VersionCheck-1.0", true)
    if VC then
        VC:Enable(self)
    end

    addon:DebugPrint("OnInitialize complete. Version:", addon.Version)
end

function Ace:OnEnable()
    -- Slash command: /togpm [subcommand]
    self:RegisterChatCommand("togpm", "OnSlashCommand")

    -- Core events.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_LOGOUT",         "OnPlayerLogout")

    addon:DebugPrint("OnEnable complete.")
end

-- ---------------------------------------------------------------------------
-- Event handlers (stubs — filled in by later modules)
-- ---------------------------------------------------------------------------

function Ace:OnPlayerEnteringWorld(event, isInitialLogin, isReloadingUi)
    addon:DebugPrint("PLAYER_ENTERING_WORLD", "login:", isInitialLogin, "reload:", isReloadingUi)

    -- Register this character in the account-wide accountChars table.
    -- Done here (not OnInitialize) because GetNormalizedRealmName() returns ""
    -- before PLAYER_ENTERING_WORLD fires.
    local myKey = addon:GetCharacterKey()
    local ac = addon.guildDb.global.accountChars
    ac[myKey] = true
    -- Self-heal: remove any stale "Name-" key (empty realm) written by older code.
    local staleName = UnitName("player")
    if staleName and ac[staleName .. "-"] then
        ac[staleName .. "-"] = nil
    end

    -- Migrate old "Faction-Realm-GuildName" guild buckets to the new
    -- "Faction-GuildName" format so connected-realm peers share one bucket.
    local newKey = addon:GetGuildKey()
    if newKey then
        local g = addon.guildDb.global.guilds
        local dst = addon:GetGuildDb()  -- creates/returns the new bucket
        local toMigrate = {}
        for key in pairs(g) do
            if key ~= newKey and addon:NormalizeGuildKey(key) == newKey then
                table.insert(toMigrate, key)
            end
        end
        for _, key in ipairs(toMigrate) do
            local src = g[key]
            -- recipes: profId → recipeId → {crafters, ...}
            for profId, recipes in pairs(src.recipes or {}) do
                if not dst.recipes[profId] then dst.recipes[profId] = {} end
                for recipeId, rd in pairs(recipes) do
                    if not dst.recipes[profId][recipeId] then
                        dst.recipes[profId][recipeId] = rd
                    else
                        local drd = dst.recipes[profId][recipeId]
                        if not drd.crafters then drd.crafters = {} end
                        for ck, ci in pairs(rd.crafters or {}) do
                            if not drd.crafters[ck] then drd.crafters[ck] = ci end
                        end
                    end
                end
            end
            -- Flat char-keyed tables: copy if destination has no entry.
            for _, field in ipairs({"skills","guildData","cooldowns","specializations","factions","altGroups"}) do
                if src[field] then
                    if not dst[field] then dst[field] = {} end
                    for ck, v in pairs(src[field]) do
                        if not dst[field][ck] then dst[field][ck] = v end
                    end
                end
            end
            -- syncTimes: take the newer timestamp.
            for ck, ts in pairs(src.syncTimes or {}) do
                if not dst.syncTimes[ck] or ts > dst.syncTimes[ck] then
                    dst.syncTimes[ck] = ts
                end
            end
            g[key] = nil
            addon:DebugPrint("Migrated guild bucket", key, "→", newKey)
        end
    end

    -- Modules hook into this via AceEvent on their own tables.
end

function Ace:OnPlayerLogout()
    -- Flush any pending state to AceDB before the session ends.
    addon:DebugPrint("PLAYER_LOGOUT")
end

-- ---------------------------------------------------------------------------
-- Slash command dispatcher
-- ---------------------------------------------------------------------------

function Ace:OnSlashCommand(input)
    local trimmed = strtrim(input or "")
    local cmd, args = trimmed:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    local handler = SLASH_COMMANDS[cmd]
    if handler and addon[handler] then
        addon[handler](addon, args)
    elseif handler and Ace[handler] then
        Ace[handler](Ace, args)
    else
        Ace:PrintHelp()
    end
end

-- ---------------------------------------------------------------------------
-- Slash command handlers (stubs — UI modules override these)
-- ---------------------------------------------------------------------------

function addon:OpenBrowser()    addon:DebugPrint("OpenBrowser — UI not yet loaded") end
function addon:OpenReagents()   addon:DebugPrint("OpenReagents — UI not yet loaded") end
function addon:ShowMinimapButton() addon:DebugPrint("ShowMinimapButton — UI not yet loaded") end
function addon:OpenPurge()      addon:DebugPrint("OpenPurge — UI not yet loaded") end
function addon:ForceSync()      addon:DebugPrint("ForceSync — sync not yet loaded") end

--- /togpm spellcache — dump the spellbook name→id cache to chat for debugging.
function addon:DumpSpellCache()
    local cache = addon.Scanner:BuildSpellNameCache()
    local count = 0
    for name, id in pairs(cache) do
        count = count + 1
    end
    Ace:Print("Spellbook cache: " .. count .. " entries")
    if count == 0 then
        Ace:Print("|cffff4444No entries — spellbook may be empty or API unavailable|r")
    else
        -- Print first 10 as a sample
        local i = 0
        for name, id in pairs(cache) do
            i = i + 1
            if i > 10 then
                Ace:Print("  ... (" .. (count - 10) .. " more)")
                break
            end
            Ace:Print("  [" .. id .. "] " .. name)
        end
    end
end

function addon:ToggleDebug(args)
    local arg = strtrim(args or ""):lower()
    if arg == "on" then
        addon.debug = true
    elseif arg == "off" then
        addon.debug = false
    else
        addon.debug = not addon.debug
    end
    Ace.db.profile.debug = addon.debug
    Ace:Print("Debug output " .. (addon.debug and "|cff00ff00enabled|r" or "|cffff4444disabled|r"))
end

--- /togpm versioncheck — broadcast version check and print responses.
function addon:PrintVersionCheck()
    local VC = LibStub and LibStub:GetLibrary("VersionCheck-1.0", true)
    if not VC then
        Ace:Print("|cffff4444VersionCheck-1.0 library not available|r")
        return
    end
    local hostEntry = VC.hosts and VC.hosts[addonName]
    if not hostEntry then
        Ace:Print("|cffff4444" .. addonName .. " not registered with VersionCheck-1.0|r")
        return
    end
    -- FireBatch broadcasts VC10_REQ to guild; peers reply via whisper (VC10_RSP)
    -- with up to 8s jitter; VC collects for 12s. Wait 21s to capture all responses.
    VC:FireBatch()
    Ace:Print("Version check broadcast sent — waiting 21 seconds for responses...")
    C_Timer.After(21, function()
        local myVersion = addon.Version or "dev"
        local myPlayer  = addon:GetCharacterKey()
        local responses = hostEntry.VersionResponses or {}
        local list = {}
        for sender, version in pairs(responses) do
            table.insert(list, { name = sender, version = tostring(version) })
        end
        table.sort(list, function(a, b)
            local cmp = VC:CompareVersion(b.version, a.version)
            if cmp ~= 0 then return cmp > 0 end
            return a.name < b.name
        end)
        Ace:Print("Version check: " .. #list .. " guild member(s) responded")
        Ace:Print("  " .. myPlayer .. ": " .. myVersion .. " (you)")
        for _, entry in ipairs(list) do
            Ace:Print("  " .. entry.name .. ": " .. entry.version)
        end
        if #list == 0 then
            Ace:Print("  No responses received.")
        end
    end)
end

function Ace:PrintHelp()
    self:Print("|cffda8cffTOG Profession Master|r — commands:")
    self:Print("  /togpm              — open profession browser")
    self:Print("  /togpm reagents     — open missing reagents")
    self:Print("  /togpm minimap      — show minimap button")
    self:Print("  /togpm purge        — open purge dialog")
    self:Print("  /togpm sync         — force full guild re-sync")
    self:Print("  /togpm status       — dump sync/comm diagnostic info")
    self:Print("  /togpm versioncheck — check addon versions across guild")
    self:Print("  /togpm debug        — toggle debug output")
    self:Print("  /togpm help         — show this list")
end

-- ---------------------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------------------

function addon:Print(...)
    Ace:Print(...)
end

function addon:DebugPrint(...)
    if not addon.debug then return end
    local t = date("%H:%M:%S")
    Ace:Print("|cffaaaaff[DEBUG " .. t .. "]|r", ...)
end

-- Build a stable character key used as the primary identifier throughout.
-- Format: "Name-NormalizedRealm" — GetNormalizedRealmName() is the same for
-- all realms in a connected-realm cluster, so cross-realm guild mates share
-- consistent keys.
function addon:GetCharacterKey(name, realm)
    local r = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    return (name or UnitName("player")) .. "-" .. r
end

-- Return a composite guild key: "Faction-GuildName".
-- Realm is intentionally omitted — connected-realm clusters share one guild
-- roster, so including the realm would splinter one guild into many buckets.
-- Guild names in WoW cannot contain hyphens, so this format is unambiguous.
-- Returns nil when the player is not in a guild.
function addon:GetGuildKey()
    local guildName = GetGuildInfo("player")
    if not guildName or guildName == "" then return nil end
    local faction = UnitFactionGroup("player") or "Neutral"
    return faction .. "-" .. guildName
end

-- Normalize a guild key that may be in the old "Faction-Realm-GuildName"
-- format (produced by pre-fix versions) to the new "Faction-GuildName" format.
-- WoW realm names are always a single alphanumeric token (no spaces/hyphens),
-- so we can reliably strip the middle component.
function addon:NormalizeGuildKey(key)
    -- Match: faction (no hyphens) – realm (alphanumeric only) – guild name
    local faction, _, guild = key:match("^([^%-]+)%-([%a%d]+)%-(.+)$")
    if faction then
        return faction .. "-" .. guild
    end
    return key  -- Already new format: "Faction-GuildName"
end

-- Return (and lazily create) the guild-scoped sub-table for the current guild.
-- Returns nil when the player is not in a guild — callers must guard.
function addon:GetGuildDb()
    local guildKey = self:GetGuildKey()
    if not guildKey then return nil end

    local g = addon.guildDb.global.guilds
    if not g[guildKey] then
        g[guildKey] = {
            recipes         = {},  -- [profId][recipeId] = { name, icon, isSpell, crafters }
            skills          = {},  -- [charKey][profId]  = { skillRank, skillMax }
            guildData       = {},  -- [charKey] = {}  (membership index)
            cooldowns       = {},
            syncTimes       = {},
            specializations = {},
            factions        = {},
        }
    end
    -- Lazy-init fields for buckets created before this version.
    local b = g[guildKey]
    if not b.recipes         then b.recipes         = {} end
    if not b.skills          then b.skills          = {} end
    if not b.guildData       then b.guildData       = {} end
    if not b.cooldowns       then b.cooldowns       = {} end
    if not b.syncTimes       then b.syncTimes       = {} end
    if not b.specializations then b.specializations = {} end
    if not b.factions        then b.factions        = {} end
    if not b.altGroups       then b.altGroups       = {} end
    return b
end

--- Return true if charKey belongs to the local player's account.
-- Checks the account-wide accountChars table (all characters that have ever
-- logged in on this account with TOGPM installed).
function addon:IsMyCharacter(charKey)
    return addon.guildDb.global.accountChars[charKey] == true
end
