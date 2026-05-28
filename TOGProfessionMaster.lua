-- TOG Profession Master
-- Author: Pimptasty
-- Guild profession browser, cooldown tracker, and reagent planner for Classic WoW.

local addonName, addon = ...
local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

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

-- Static recipe-universe tables populated by Data/Recipes/*.lua and
-- Data/Sources/*.lua at load time. Used by GUI/MissingRecipesTab.lua to
-- compute the set of recipes a character is missing for each profession.
-- Keyed by [professionSpellId][recipeSpellId].
addon.recipeDB = addon.recipeDB or {}
addon.sourceDB = addon.sourceDB or {}

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
        --   trainerObservations = { [spellId] = {
        --       reqSkill, moneyCost, profId, observedBy, observedAt
        --   } }  -- v0.5.6: TRAINER_SHOW-captured ReqSkillRank values for
        --        recipes (the literal "Requires Tailoring (100)" trainer
        --        tooltip line). Lazy-created on first capture in
        --        Scanner.lua's OnTrainerShow. Eventual extraction script
        --        feeds this back into the shipped recipe DB to close the
        --        ~20% requiredSkill gap that emulator SQL doesn't cover.
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
        -- Cooldown-ready alerts: when ON, ping + chat-print as soon as a
        -- "!"-armed cooldown expires on any of your characters. The
        -- "suppress in instances" sibling defaults ON so raids / dungeons /
        -- BGs stay quiet. The reminder interval (in minutes) re-fires the
        -- alert every N minutes while the cooldown is still ready and the
        -- user hasn't crafted yet — 0 means "fire only once per ready
        -- cycle." Range guard 0..1440 (24h) enforced in Settings.lua.
        cooldownAlertSuppressProtected = true,
        cooldownAlertReminderMinutes   = 0,

        -- Auction House scan delay (seconds between QueryAuctionItems calls).
        -- 0 = use the version-appropriate default (1.5s on Classic Era /
        -- Anniversary where the server throttle is loose, 3.0s on TBC /
        -- Wrath / Cata / MoP where it's stricter). User-tunable via Settings
        -- so guilds on unusual server configurations can dial it up or down.
        -- Resolved at scan time in Modules/AHScanner.lua so the version flag
        -- (set by Compat.lua, which loads AFTER this defaults table) is
        -- guaranteed populated before we read it.
        ahScanDelay = 0,

        -- Global item tooltip lines. Both OFF by default — opt-in via
        -- Settings to keep the addon's tooltip footprint minimal until the
        -- user explicitly wants either signal. Independent toggles so users
        -- can keep just the crafters list, just the IDs (for troubleshooting),
        -- both, or neither. Read in Tooltip.lua's AppendCrafters.
        tooltipShowCrafters = false,
        tooltipShowIds      = false,

        -- TBC Anniversary content phase. The recipe DB ships with `phase`
        -- field on TBC raid / Shattered-Sun / BT / Hyjal / Sunwell recipes
        -- (sourced from ATT at build time). When the client is TBC, the
        -- Missing Recipes tab hides any recipe whose `phase` exceeds this
        -- setting — keeps phase-locked content like Sunwell jewelcrafting
        -- patterns from showing up before Blizzard opens the phase. Defaults
        -- to 2 (Anniversary live state as of v0.5.4 release: SSC + TK).
        -- User bumps it manually when phase 3 / 3.5 / 4 go live; we'll ship
        -- the new default in a follow-up patch each time.
        tbcAnniversaryPhase = 2,

        -- UI Language Override. "auto" = follow the WoW client's GetLocale().
        -- Other values map to a locale code in addon.Locales (populated by
        -- the files in Locale/*.lua). At OnInitialize, ApplyLocaleOverride
        -- mutates the AceLocale L table in place so every existing
        -- `local L = LibStub("AceLocale-3.0"):GetLocale(...)` reference
        -- picks up the override without code changes elsewhere.
        --
        -- Includes non-WoW-supported locales (thTH, filPH) that AceLocale
        -- would never auto-select — the override mechanism is the only way
        -- those locales reach players on enUS / zhTW / etc. clients.
        uiLanguageOverride = "auto",
    },
    char = {
        -- Shopping list: [spellId] = { quantity = N }
        shoppingList    = {},

        -- Reagent watch list: [itemId] = true
        reagentWatch    = {},

        -- Shopping list alert flags: [spellId] = true
        shoppingAlerts  = {},

        -- Cooldown-ready alert flags. Keyed by alertKey (built by the
        -- CooldownAlerts module). Each entry is a metadata table:
        --   { charKey, label, groupKind, spellId }
        -- groupKind is "transmute", "group:<groupKey>", or nil for a
        -- single-spell row. spellId is only meaningful when groupKind is nil
        -- — for groups the module re-derives the effective expiry by walking
        -- data.transmutes / data.groupBySpell, so adding new transmute spells
        -- post-toggle still works.
        cooldownAlerts  = {},

        -- Cached personal bank counts: [itemId] = count.  Refreshed on
        -- BANKFRAME_CLOSED (mirrors TOGBankClassic's pattern of scanning
        -- on close to capture all changes).  Combined with bag counts in
        -- "have" calculations across the addon.
        bankCounts      = {},

        -- Cached mail-attachment counts: [itemId] = count.  Refreshed on
        -- MAIL_CLOSED.  COD mail is excluded (can't take attachments
        -- without paying, so it's not really in our possession).
        mailCounts      = {},

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
    ["transmutedebug"] = "DumpTransmuteDiag",
    ["forcebroadcast"] = "ForceBroadcast",
    ["backfill"]     = "RunBackfill",
    ["myalts"]       = "DumpMyAlts",
    ["help"]         = "PrintHelp",
}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- Swap the AceLocale-managed L table for the user's chosen override locale.
--- Default ("auto") leaves the table untouched — AceLocale already populated
--- it with the GetLocale()-matched strings at file load. For any other value,
--- we wipe the table and re-fill it from addon.Locales[override] layered on
--- top of the enUS baseline (so keys missing in the override still resolve).
---
--- Mutates the table in place rather than reassigning, so every
---   local L = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")
--- reference captured at file load time sees the new strings without code
--- changes elsewhere. Called once at OnInitialize after AceDB is ready.
function addon:ApplyLocaleOverride()
    local override = self.db and self.db.profile and self.db.profile.uiLanguageOverride or "auto"

    -- Fast path: first call after load with override=="auto" — AceLocale has
    -- already populated localeTbl with the GetLocale()-matched strings, so
    -- there's nothing to do. _localeOverrideApplied tracks whether a previous
    -- non-auto override left localeTbl in a non-auto state we need to restore.
    if override == "auto" and not self._localeOverrideApplied then return end

    local AceLocale = LibStub("AceLocale-3.0", true)
    if not AceLocale then return end
    local localeTbl = AceLocale:GetLocale("TOGProfessionMaster", true)
    if not localeTbl then return end

    local Locales = self.Locales or {}
    local enUS    = Locales.enUS or {}
    local target
    if override == "auto" then
        target = Locales[GetLocale()] or enUS
    else
        target = Locales[override]
        if not target then
            addon:DebugPrint("ApplyLocaleOverride: unknown locale", override, "— ignoring")
            return
        end
    end
    self._localeOverrideApplied = (override ~= "auto")

    for k in pairs(localeTbl) do localeTbl[k] = nil end
    for k, v in pairs(enUS) do localeTbl[k] = v end          -- baseline fallback
    for k, v in pairs(target) do localeTbl[k] = v end        -- chosen on top
end

function Ace:OnInitialize()
    -- Set up SavedVariables via AceDB (two separate SVs).
    -- TOGPM_Settings: profile (UI prefs) and char (shopping list, reagent watch, frames)
    self.db       = LibStub("AceDB-3.0"):New("TOGPM_Settings", SETTINGS_DEFAULTS, true)
    -- TOGPM_GuildDB: global guild-wide data (recipes, skills, cooldowns, sync log)
    addon.guildDb = LibStub("AceDB-3.0"):New("TOGPM_GuildDB", GUILD_DB_DEFAULTS, true)

    -- Apply UI Language Override (if any) before any GUI module reads L.
    -- This mutates the AceLocale table in place; all subsequent reads pick
    -- up the chosen locale automatically. No-op when override is "auto".
    addon:ApplyLocaleOverride()

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

function Ace:OnPlayerEnteringWorld(_event, isInitialLogin, isReloadingUi)
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

-- Master profession ID → display name table. Shared across every tab so
-- a single edit here propagates to Browser / Cooldowns / Missing Recipes
-- dropdowns and the Tooltip / crafter-alert lookups. Per-version filtering
-- happens via addon.PROF_AVAILABILITY below; per-tab category filtering
-- happens via addon.CRAFTING_PROFS.
addon.PROF_NAMES = {
    [171] = L["ProfAlchemy"],        [164] = L["ProfBlacksmithing"],  [185] = L["ProfCooking"],
    [333] = L["ProfEnchanting"],     [202] = L["ProfEngineering"],    [129] = L["ProfFirstAid"],
    [165] = L["ProfLeatherworking"], [186] = L["ProfMining"],         [197] = L["ProfTailoring"],
    [182] = L["ProfHerbalism"],      [393] = L["ProfSkinning"],       [755] = L["ProfJewelcrafting"],
    [773] = L["ProfInscription"],    [356] = L["ProfFishing"],        [374] = L["ProfSmelting"],
}

-- Per-profession version availability. Each entry is a function that
-- returns true when the profession exists on the current client. Default
-- (no entry) = available on every supported client (Vanilla onwards).
--
-- Functions, not flags — the addon.is* version flags aren't set until
-- Compat.lua runs (loaded after this file), so anything evaluated at
-- assignment time would see nil. Calls happen at dropdown-build time
-- where the flags are guaranteed populated.
addon.PROF_AVAILABILITY = {
    [755] = function() return addon.isTBC   or addon.isWrath or addon.isCata or addon.isMoP end,  -- Jewelcrafting (TBC+)
    [773] = function() return addon.isWrath or addon.isCata  or addon.isMoP end,                  -- Inscription (Wrath+)
}

--- True if this profession exists on the current WoW client version.
-- Used by every tab's profession dropdown to hide professions that
-- aren't in the current expansion (e.g. Jewelcrafting on Vanilla).
function addon.IsProfessionAvailable(profId)
    local check = addon.PROF_AVAILABILITY[profId]
    if not check then return true end  -- default: always available
    return check() == true
end

-- Crafting professions — produce learnable recipes that belong in the
-- Browser / Missing Recipes lists. Excludes pure gathering professions
-- (Herbalism / Skinning / Fishing) which have no craft output. Mining
-- IS included because Smelting produces craftable bars. Cooldowns tab
-- ignores this; its dropdown is filtered by COOLDOWN_BY_PROFESSION
-- presence instead.
addon.CRAFTING_PROFS = {
    [171] = true,  -- Alchemy
    [164] = true,  -- Blacksmithing
    [185] = true,  -- Cooking
    [333] = true,  -- Enchanting
    [202] = true,  -- Engineering
    [129] = true,  -- First Aid
    [165] = true,  -- Leatherworking
    [186] = true,  -- Mining (smelting)
    [197] = true,  -- Tailoring
    [755] = true,  -- Jewelcrafting (TBC+)
    [773] = true,  -- Inscription (Wrath+)
}

function addon:OnCrafterCameOnline(charKey)
    if not Ace.db.profile.crafterAlert then return end
    local alerts = Ace.db.char.shoppingAlerts
    if not next(alerts) then return end

    local gdb = addon:GetGuildDb()
    if not gdb or not gdb.recipes then return end

    local alerted  = false
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
        if addon.Scanner.BackfillBogusRecipeNames then
            addon.Scanner:BackfillBogusRecipeNames()
        end
    else
        Ace:Print("|cffff4444Scanner not available yet|r")
    end
end

--- /togpm myalts — diagnostic: print what the addon thinks are this
--- account's own characters (the global accountChars set used by every
--- "My Characters" filter) AND which other guildmate keys leak into the
--- Missing Recipes character dropdown (a guildmate appearing here means
--- IsMyCharacter is returning true for them, which is the bug we're
--- chasing).
function addon:DumpMyAlts()
    Ace:Print("|cffda8cff[TOGPM] My Characters diagnostic|r")
    local ac = addon.guildDb and addon.guildDb.global and addon.guildDb.global.accountChars
    if not ac then
        Ace:Print("  global.accountChars: |cffff4444nil|r (db not loaded)")
        return
    end
    -- 1. Raw global.accountChars dump
    local keys = {}
    for k, v in pairs(ac) do keys[#keys + 1] = tostring(k) .. " = " .. tostring(v) end
    table.sort(keys)
    Ace:Print(("  global.accountChars (%d entries):"):format(#keys))
    for _, line in ipairs(keys) do Ace:Print("    " .. line) end

    -- 2. Reverse-check: for every charKey we have skill data for across all
    --    guild buckets, print whether IsMyCharacter returns true. If a
    --    guildmate's name shows IsMyChar=true, accountChars is polluted.
    Ace:Print("  IsMyCharacter() result for every known charKey:")
    local seen = {}
    addon:ForEachGuildBucket(function(bucket)
        for ck in pairs(bucket.skills or {})      do seen[ck] = true end
        for ck in pairs(bucket.cooldowns or {})   do seen[ck] = true end
        for ck in pairs(bucket.guildData or {})   do seen[ck] = true end
    end)
    local sorted = {}
    for ck in pairs(seen) do sorted[#sorted + 1] = ck end
    table.sort(sorted)
    local n_mine, n_others = 0, 0
    for _, ck in ipairs(sorted) do
        local is_mine = addon:IsMyCharacter(ck)
        if is_mine then n_mine = n_mine + 1
        else            n_others = n_others + 1 end
        local marker = is_mine and "|cff00ff00MINE|r" or "|cff888888other|r"
        Ace:Print(string.format("    %s  %s", marker, ck))
    end
    Ace:Print(string.format("  Totals: |cff00ff00%d mine|r, |cff888888%d other|r",
        n_mine, n_others))
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

--- /togpm transmutedebug — one-shot diagnostic for the transmute-cooldown
--- chain.  Walks every transmute spell ID in the version-appropriate
--- catalogue, prints which one (if any) the WoW API says is on cooldown,
--- which transmutes are in our recipe DB for the local character, and
--- which are stored in gdb.cooldowns[charKey].  No spell IDs to look up;
--- just run the command and paste the output.
function addon:DumpTransmuteDiag()
    -- Run the runtime augmentation first so the diagnostic reflects the
    -- post-refresh state (spellbook-fallback resolution via GetSpellLink may
    -- have filled in spellIds that the earlier ScanCooldowns missed).
    if addon.RefreshTransmuteCatalogueFromRecipes then
        local added = addon:RefreshTransmuteCatalogueFromRecipes()
        if added > 0 then
            Ace:Print(("|cff88ff88Augmented catalogue with %d new transmute IDs from recipe DB|r"):format(added))
        end
    end

    local data = addon:GetCooldownData()
    if not data or not data.transmutes then
        Ace:Print("|cffff4444No cooldown data — addon.isVanilla/etc. not set?|r")
        return
    end
    local charKey = addon:GetCharacterKey()
    local gdb     = addon:GetGuildDb()

    Ace:Print("|cffda8cffTransmute diagnostic for|r " .. tostring(charKey))

    -- (1) API: which transmute spells does GetSpellCooldown say are on CD?
    local apiActive = {}
    local total = 0
    for spellId, name in pairs(data.transmutes) do
        total = total + 1
        local start, duration = GetSpellCooldown(spellId)
        if start and start > 0 and duration and duration > 1.5 then
            local remaining = (start + duration) - GetTime()
            apiActive[spellId] = { name = name, start = start, duration = duration, remaining = remaining }
        end
    end
    Ace:Print(("  [API] %d transmute IDs in catalogue; on-cooldown: %d"):format(
        total, (function() local n = 0; for _ in pairs(apiActive) do n = n + 1 end; return n end)()))
    for spellId, info in pairs(apiActive) do
        Ace:Print(("    %d (%s) start=%.1f duration=%.0f remaining=%.0fs"):format(
            spellId, info.name, info.start, info.duration, info.remaining))
    end

    -- (2) Recipe DB: which transmutes does the local char know per gdb.recipes[171]?
    local recipeKnown = {}
    if gdb and gdb.recipes and gdb.recipes[171] then
        for _, rd in pairs(gdb.recipes[171]) do
            if rd.crafters and rd.crafters[charKey]
               and rd.spellId and data.transmutes[rd.spellId] then
                recipeKnown[rd.spellId] = rd.name
            end
        end
    end
    Ace:Print(("  [Recipes] gdb.recipes[171] crafters[%s] entries matching transmutes: %d"):format(
        charKey, (function() local n = 0; for _ in pairs(recipeKnown) do n = n + 1 end; return n end)()))
    for spellId, name in pairs(recipeKnown) do
        Ace:Print(("    %d (%s)"):format(spellId, name))
    end

    -- (3) IsSpellKnown: does the WoW API agree the player knows these?
    local isSpellKnownTrue = 0
    for spellId in pairs(data.transmutes) do
        if IsSpellKnown(spellId, false) then
            isSpellKnownTrue = isSpellKnownTrue + 1
        end
    end
    Ace:Print(("  [IsSpellKnown] returns true for %d / %d transmute IDs"):format(
        isSpellKnownTrue, total))

    -- (4) Stored: what's in gdb.cooldowns[charKey] for transmute IDs?
    local stored = {}
    if gdb and gdb.cooldowns and gdb.cooldowns[charKey] then
        for spellId, expiresAt in pairs(gdb.cooldowns[charKey]) do
            if data.transmutes[spellId] then
                stored[spellId] = expiresAt
            end
        end
    end
    local now = GetServerTime()
    Ace:Print(("  [gdb.cooldowns[%s]] transmute entries stored: %d"):format(
        charKey, (function() local n = 0; for _ in pairs(stored) do n = n + 1 end; return n end)()))
    for spellId, expiresAt in pairs(stored) do
        local remaining = expiresAt - now
        local label = remaining > 0 and (("%ds remaining"):format(remaining)) or "Ready"
        Ace:Print(("    %d (%s) expiresAt=%d %s"):format(
            spellId, data.transmutes[spellId] or "?", expiresAt, label))
    end

    -- (5) Total alchemy recipes in the DB for this char, with whatever
    -- spellIds they actually have.  If this is 0, the alchemy scan never ran
    -- (need to open the alchemy trade skill window).  If non-zero but with
    -- mostly nil spellIds, BuildSpellNameCache isn't finding the spells.  If
    -- non-zero with populated spellIds that don't match data.transmutes, the
    -- IDs in VANILLA_TRANSMUTES are wrong for this client (Anniversary may
    -- use different IDs).
    local profCount, withSpellId, transmuteByName = 0, 0, {}
    if gdb and gdb.recipes and gdb.recipes[171] then
        for _, rd in pairs(gdb.recipes[171]) do
            if rd.crafters and rd.crafters[charKey] then
                profCount = profCount + 1
                if rd.spellId then withSpellId = withSpellId + 1 end
                if type(rd.name) == "string" and rd.name:find("[Tt]ransmute") then
                    transmuteByName[rd.name] = rd.spellId or "(nil spellId)"
                end
            end
        end
    end
    Ace:Print(("  [gdb.recipes[171] total for %s] %d recipes, %d with spellId"):format(
        charKey, profCount, withSpellId))
    Ace:Print("  [recipes whose name contains 'Transmute']:")
    for name, spellId in pairs(transmuteByName) do
        Ace:Print(("    %s -> spellId=%s%s"):format(
            name, tostring(spellId),
            (type(spellId) == "number" and data.transmutes[spellId]) and " (in catalogue)" or ""))
    end

    -- (6) Spellbook walk: find every spell whose name starts with "Transmute"
    -- and print the spell ID the client uses.  This bypasses the recipe DB
    -- entirely.  If the IDs printed here aren't in VANILLA_TRANSMUTES, our
    -- catalogue is stale for this client.
    Ace:Print("  [Spellbook 'Transmute*' entries]:")
    local sbHits = 0
    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for j = 1, (numSpells or 0) do
            local idx = offset + j
            local _, sId = GetSpellBookItemInfo(idx, "spell")
            if sId then
                local sName = GetSpellInfo(sId)
                if sName and sName:find("[Tt]ransmute") then
                    sbHits = sbHits + 1
                    Ace:Print(("    %s -> spellId=%d%s"):format(
                        sName, sId,
                        data.transmutes[sId] and " (in catalogue)" or " (NOT in catalogue)"))
                end
            end
        end
    end
    if sbHits == 0 then
        Ace:Print("    (no 'Transmute*' spells in the spellbook)")
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
    Ace:Print(L["SlashForceBroadcastSent"])
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
    Ace:Print(string.format(L["SlashDebugToggleFormat"], addon.debug and L["SlashDebugEnabled"] or L["SlashDebugDisabled"]))
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
    self:Print(L["SlashHelpHeader"])
    self:Print("  /togpm              \226\128\148 " .. L["SlashHelpOpen"])
    self:Print("  /togpm reagents     \226\128\148 " .. L["SlashHelpReagents"])
    self:Print("  /togpm minimap      \226\128\148 " .. L["SlashHelpMinimap"])
    self:Print("  /togpm purge        \226\128\148 " .. L["SlashHelpPurge"])
    self:Print("  /togpm sync         \226\128\148 " .. L["SlashHelpSync"])
    self:Print("  /togpm status       \226\128\148 " .. L["SlashHelpStatus"])
    self:Print("  /togpm versioncheck \226\128\148 " .. L["SlashHelpVersionCheck"])
    self:Print("  /togpm debug        \226\128\148 " .. L["SlashHelpDebug"])
    self:Print("  /togpm help         \226\128\148 " .. L["SlashHelpHelp"])
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

-- Synthetic guild-bucket key used when the player has no guild. Lets the
-- scanner store own-character scans somewhere coherent so the "My Characters"
-- view filter on the Cooldowns / Missing Recipes tabs can surface guildless
-- alts. Local-only by construction: every broadcast helper in Scanner.lua
-- gates on addon:GetGuildKey() returning a real (non-nil) value, so the
-- synthetic bucket's contents never reach the wire. Connected-realm names
-- can't contain underscores so this key cannot collide with a real guild.
addon.NoGuildBucketKey = "__noguild"

-- Return (and lazily create) the guild-scoped sub-table for the current guild.
-- Falls back to the synthetic NoGuildBucketKey bucket when the player is not
-- in a guild so own-character scans always have somewhere to write.
function addon:GetGuildDb()
    local guildKey = self:GetGuildKey() or addon.NoGuildBucketKey

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

--- Iterate every guild bucket in addon.guildDb.global.guilds.
-- Used by tabs to walk all stored data when the "My Characters" view needs
-- to surface data for own alts that live in other guild buckets (or in the
-- synthetic NoGuildBucketKey bucket for guildless alts). Local read only —
-- no sync-protocol implications since broadcasts gate on addon:GetGuildKey()
-- returning a real non-nil value.
-- @param callback  function(bucket)  — invoked once per bucket
function addon:ForEachGuildBucket(callback)
    for _, bucket in pairs(self.guildDb.global.guilds or {}) do
        callback(bucket)
    end
end

--- Find the first guild bucket whose `field` sub-table has an entry for
-- charKey. Use for cross-bucket lookups when a character's tracked data
-- (skills, cooldowns, specializations, etc.) may live in any bucket because
-- the character is in a different guild from the logged-in player or in no
-- guild at all.
-- @param charKey  string — "Name-Realm"
-- @param field    string — bucket sub-table to inspect ("skills", "cooldowns", "specializations", ...)
-- @return         bucket table or nil if no bucket has data for this character
function addon:FindBucketForChar(charKey, field)
    if not charKey or not field then return nil end
    for _, bucket in pairs(self.guildDb.global.guilds or {}) do
        if bucket[field] and bucket[field][charKey] then
            return bucket
        end
    end
    return nil
end
