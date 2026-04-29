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
    "AceSerializer-3.0",
    "AceHook-3.0"
)
addon.lib = Ace

-- Wrap Ace.SendCommMessage with the throttling/chunking queue so DeltaSync's
-- `self.aceAddon:SendCommMessage(...)` calls avoid CRC corruption from chunk
-- interleaving under load. Must run after AceComm-3.0 has embedded.
LibStub("AceCommQueue-1.0"):Embed(Ace)

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
        minimapButton     = true,
        minimapPos        = 220,   -- LibDBIcon angle in degrees
        mailReadyOnly     = false,
        debug             = false,
        persistProfFilter = false,
        savedProfFilter   = 0,
        -- Crafter alerts
        crafterAlert              = true,
        crafterAlertSuppressAV    = false,
        crafterAlertSuppressLogin = true,
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
    ["dumprecipe"]   = "DumpRecipe",
    ["dumphashes"]   = "DumpHashes",
    ["dumpcooldowns"] = "DumpCooldowns",
    ["forcebroadcast"] = "ForceBroadcast",
    ["backfill"]     = "RunBackfill",
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

    -- Expose version on the Ace object so VersionCheck-1.0 reads it directly
    -- from hostEntry.host.Version rather than falling back to GetAddOnMetadata.
    self.Version = addon.Version

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

    -- Crafter online alert: fire when a guild member comes online. Roster
    -- transitions are sourced from GuildCache-1.0 (bundled inside the standalone
    -- DeltaSync addon, MINOR>=2) which exposes CallbackHandler-1.0 callbacks
    -- driven by both GUILD_ROSTER_UPDATE diffs and CHAT_MSG_SYSTEM parsing.
    local GuildCache = LibStub("GuildCache-1.0", true)
    if GuildCache and GuildCache.RegisterCallback then
        GuildCache:RegisterCallback("OnMemberOnline", function(_, name)
            addon:OnCrafterCameOnline(name)
        end)
    end

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

    -- v0.2.0: populate gdb.accountChars[myKey] from the account-wide flat set.
    -- This is the per-broadcaster authoritative alt group used by the new sync
    -- protocol (see docs/v0.2.0-protocol.md §7.4).  Stamp lastScan so the
    -- accountchars:<myKey> hash leaf has a content-derived updatedAt.
    if addon:GetGuildKey() then
        local gdb = addon:GetGuildDb()
        if gdb then
            local groupArr = {}
            for ck in pairs(addon.guildDb.global.accountChars) do
                if type(ck) == "string" then groupArr[#groupArr + 1] = ck end
            end
            table.sort(groupArr)  -- deterministic order so the hash is stable across peers
            gdb.accountChars[myKey] = groupArr
            if not gdb.lastScan[myKey] then gdb.lastScan[myKey] = {} end
            gdb.lastScan[myKey].accountchars = GetServerTime()
        end
    end

    -- Suppress crafter alerts during the login burst; clear the flag after 10 s.
    addon.loginInitialized = false
    C_Timer.After(10, function() addon.loginInitialized = true end)

    -- Modules hook into this via AceEvent on their own tables.
end

-- ---------------------------------------------------------------------------
-- Crafter alert
-- ---------------------------------------------------------------------------

addon.PROF_NAMES = {
    [171] = "Alchemy",       [164] = "Blacksmithing", [185] = "Cooking",
    [333] = "Enchanting",    [202] = "Engineering",   [129] = "First Aid",
    [165] = "Leatherworking",[186] = "Mining",        [197] = "Tailoring",
    [182] = "Herbalism",     [393] = "Skinning",      [755] = "Jewelcrafting",
    [773] = "Inscription",   [356] = "Fishing",       [374] = "Smelting",
}

function addon:OnCrafterCameOnline(charKey)
    if not Ace.db.profile.crafterAlert then return end
    local alerts = Ace.db.char.shoppingAlerts
    if not next(alerts) then return end

    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.recipes then return end

    local alerted  = false
    local L        = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
    local shortKey = charKey:match("^(.-)%-") or charKey

    for recipeId in pairs(alerts) do
        for profId, profRecipes in pairs(gdb.recipes) do
            local rd = profRecipes[recipeId]
            if rd and rd.crafters then
                for crafterKey in pairs(rd.crafters) do
                    local match = (crafterKey == charKey)
                    if not match and gdb.altGroups and gdb.altGroups[crafterKey] then
                        for _, altCk in ipairs(gdb.altGroups[crafterKey]) do
                            if altCk == charKey then match = true; break end
                        end
                    end
                    if match then
                        local profName    = addon.PROF_NAMES[profId] or ""
                        local label       = profName ~= "" and (profName .. ": " .. (rd.name or "")) or (rd.name or "")
                        local crafterShort = crafterKey:match("^(.-)%-") or crafterKey
                        if crafterKey == charKey then
                            addon:Print(string.format(L["AlertCrafterOnline"], shortKey, label))
                        else
                            addon:Print(string.format(L["AlertCrafterOnlineAlt"], crafterShort, shortKey, label))
                        end
                        alerted = true
                        break
                    end
                end
            end
            if alerted then break end
        end
    end

    if alerted then
        local suppress = Ace.db.profile.crafterAlertSuppressAV
                      or (Ace.db.profile.crafterAlertSuppressLogin and not addon.loginInitialized)
        if not suppress then
            PlaySound(878)
            if not addon._crafterAlertFlash then
                local flash = CreateFrame("Frame", "TOGPMCrafterAlertFlash", UIParent)
                flash:SetAllPoints(UIParent)
                flash:SetFrameStrata("FULLSCREEN_DIALOG")
                local tex = flash:CreateTexture(nil, "BACKGROUND")
                tex:SetAllPoints(flash)
                tex:SetTexture("Interface\\FullScreenTextures\\LowHealth")
                tex:SetVertexColor(1, 0.82, 0)
                flash:Hide()
                addon._crafterAlertFlash = flash
            end
            UIFrameFlash(addon._crafterAlertFlash, 0.5, 0.5, 3, false, 0, 0)
        end
    end
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

--- /togpm dumprecipe <name> — find a recipe by exact name and print its
-- stored fields + reagent table to chat. Used to diagnose missing itemLink
-- / itemId data on reagents (the bank-button + reagent-tracker rely on these).
function addon:DumpRecipe(args)
    local name = strtrim(args or "")
    if name == "" then
        Ace:Print("Usage: /togpm dumprecipe <recipe name>")
        return
    end
    local g = addon.guildDb and addon.guildDb.global and addon.guildDb.global.guilds
    if not g then Ace:Print("|cffff4444No guild DB|r"); return end

    local found = 0
    for guildKey, gdb in pairs(g) do
        for profId, profRecipes in pairs(gdb.recipes or {}) do
            for recipeId, rd in pairs(profRecipes) do
                if rd.name == name then
                    found = found + 1
                    Ace:Print(("|cffda8cff[%s]|r profId=%d recipeId=%s spellId=%s isSpell=%s"):format(
                        guildKey, profId, tostring(recipeId), tostring(rd.spellId), tostring(rd.isSpell)))
                    Ace:Print(("  itemLink=%s"):format(tostring(rd.itemLink)))
                    Ace:Print(("  recipeLink=%s"):format(tostring(rd.recipeLink)))
                    local reag = rd.reagents
                    if type(reag) ~= "table" then
                        Ace:Print(("  reagents = %s (not a table)"):format(tostring(reag)))
                    else
                        Ace:Print(("  reagents (%d):"):format(#reag))
                        for i, x in ipairs(reag) do
                            Ace:Print(("    [%d] name=%s count=%s itemId=%s itemLink=%s"):format(
                                i, tostring(x.name), tostring(x.count),
                                tostring(x.itemId), tostring(x.itemLink)))
                        end
                    end
                    local crafters = {}
                    for ck in pairs(rd.crafters or {}) do crafters[#crafters + 1] = ck end
                    Ace:Print(("  crafters: %s"):format(table.concat(crafters, ", ")))
                end
            end
        end
    end
    if found == 0 then
        Ace:Print(("|cffff4444No recipe named '%s' found in any guild bucket|r"):format(name))
    end
end

--- /togpm backfill — manually run the reagent itemId backfill pass.
function addon:RunBackfill()
    if addon.Scanner and addon.Scanner.BackfillReagentItemIds then
        addon.Scanner:BackfillReagentItemIds()
    else
        Ace:Print("|cffff4444Scanner not available yet|r")
    end
end

--- /togpm dumphashes — print the local L0 hash list for diagnostic comparison.
function addon:DumpHashes()
    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.hashes then
        Ace:Print("|cffff4444No guild DB or hash cache|r")
        return
    end
    local keys = {}
    for k in pairs(gdb.hashes) do keys[#keys + 1] = k end
    table.sort(keys)
    Ace:Print(("|cffda8cffHash leaves (%d):|r"):format(#keys))
    for _, k in ipairs(keys) do
        local e = gdb.hashes[k]
        Ace:Print(("  %s = hash:%s updatedAt:%s"):format(k,
            tostring(e.hash), tostring(e.updatedAt)))
    end
end

--- /togpm dumpcooldowns <charKey> — print stored cooldown bucket for a character.
function addon:DumpCooldowns(args)
    local charKey = strtrim(args or "")
    local gdb = addon:GetGuildDb()
    if not gdb then Ace:Print("|cffff4444No guild DB|r"); return end
    if charKey == "" then
        -- List every char with cooldowns and their bucket size.
        Ace:Print("|cffda8cffCooldown buckets:|r")
        for ck, bucket in pairs(gdb.cooldowns or {}) do
            local n = 0
            for _ in pairs(bucket) do n = n + 1 end
            Ace:Print(("  %s — %d entries"):format(ck, n))
        end
        return
    end
    local bucket = gdb.cooldowns and gdb.cooldowns[charKey]
    if not bucket then
        Ace:Print(("|cffff4444No cooldown data for %s|r"):format(charKey))
        return
    end
    local now = GetServerTime()
    Ace:Print(("|cffda8cff%s cooldowns:|r"):format(charKey))
    for spellId, expiresAt in pairs(bucket) do
        local remaining = expiresAt - now
        local name = (GetSpellInfo and GetSpellInfo(spellId)) or "?"
        Ace:Print(("  [%s] %s expiresAt=%d remaining=%ds"):format(
            tostring(spellId), name, expiresAt, remaining))
    end
end

--- /togpm forcebroadcast — bypass debounce and broadcast full hash list now.
function addon:ForceBroadcast()
    if not addon.Scanner then
        Ace:Print("|cffff4444Scanner not available yet|r")
        return
    end
    addon.Scanner._lastBroadcastAt = 0          -- bypass debounce
    addon.Scanner._lastBroadcastHashes = nil    -- force full hash list (no diff)
    addon.Scanner:BroadcastHashes()
    Ace:Print("Force broadcast sent.")
end

--- /togpm spellcache — dump the spellbook name→id cache to chat for debugging.
function addon:DumpSpellCache()
    local cache = addon.Scanner:BuildSpellNameCache()
    local count = 0
    for _ in pairs(cache) do
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
            accountChars    = {},  -- [broadcasterKey] = { charKey, ... }   (v0.2.0: per-broadcaster authoritative alt group)
            lastScan        = {},  -- [charKey] = { [profId]=ts, cooldowns=ts, accountchars=ts }   (v0.2.0: content-derived hash timestamps)
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
    -- v0.2.0 fields: empty on first migration, populated by v0.2.0 scans + receives.
    -- Existing v0.1.x altGroups data stays usable; gdb.altGroups will be rebuilt
    -- from gdb.accountChars whenever v0.2.0 broadcasts arrive.
    if not b.accountChars    then b.accountChars    = {} end
    if not b.lastScan        then b.lastScan        = {} end
    return b
end

--- Return true if charKey belongs to the local player's account.
-- Checks the account-wide accountChars table (all characters that have ever
-- logged in on this account with TOGPM installed).
function addon:IsMyCharacter(charKey)
    return addon.guildDb.global.accountChars[charKey] == true
end
