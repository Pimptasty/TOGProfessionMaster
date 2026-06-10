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

-- Price-source metadata (labels + colors) shared by any UI that surfaces where
-- a number came from (TOGPM scan vs Auctionator vs TSM vs vendor fallback).
addon.PriceSourceLabels = {
    ["togpm-ah"]            = "TOGPM Live AH",
    ["auctionator"]         = "Auctionator Live",
    ["auctioneer-live"]     = "Auctioneer Live",
    ["auctioneer-cached"]   = "Auctioneer Cached",
    ["auctioneer-app"]      = "Auctioneer Cached",
    ["tsm-live"]            = "TSM Live",
    ["auctionator-history"] = "Auctionator History",
    ["tsm-history"]         = "TSM App",
    ["auctionator-vendor"]  = "Auctionator Vendor",
    ["togpm-vendor"]        = "TOGPM Vendor",
    ["vendor-static"]       = "Static Vendor",
}
addon.PriceSourceColors = {
    ["togpm-ah"]            = addon.BrandColor,
    ["auctionator"]         = "ff6da9ff",
    ["auctioneer-live"]     = "ff8fcf7f",
    ["auctioneer-cached"]   = "ff6fae61",
    ["auctioneer-app"]      = "ff6fae61",
    ["tsm-live"]            = "fff0c44f",
    ["auctionator-history"] = "ff3f7bd1",
    ["tsm-history"]         = "ffe39a3b",
    ["auctionator-vendor"]  = "ff4f8fe8",
    ["togpm-vendor"]        = "ff9a9a9a",
    ["vendor-static"]       = "ff777777",
}

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
-- v0.7.0 schema version. Bumped when the AceDB shape changes incompatibly.
-- Migration code in MigrateGuildDb (below) runs on OnInitialize when the
-- stored schemaVersion is missing or older than this.
local CURRENT_SCHEMA_VERSION = 7

-- v0.7.0 SCHEMA — flat universal tables, no per-guild buckets.
-- Each crafter entry carries a guild tag (hash of guildKey) inline so a single
-- DB serves any number of guilds the player has been in; display-time filters
-- on tag match + libguildroster presence to pick out the right people. Recipe
-- metadata (name, icon, reagents, etc.) is NOT stored — those live in the
-- shipped authoritative addon.recipeDB and are looked up by recipeId at
-- render time, so the DB stays tight and there's no obsolete-name churn.
local GUILD_DB_DEFAULTS = {
    global = {
        -- DO NOT put schemaVersion here. AceDB applies defaults BEFORE
        -- OnInitialize fires, so a default value would make MigrateGuildDb's
        -- early-return check trip BEFORE it ever ran the data walk — wiping
        -- out cooldowns on the first v0.7.0 launch. schemaVersion is set
        -- exclusively at the end of MigrateGuildDb, after migration succeeds.

        -- Recipes: ONE row per recipe, crafters carry guild tag inline.
        --   recipes[profId][recipeId] = {
        --     crafters = { [charKey] = guildTag }   -- "abc123" hex hash or "personal"
        --   }
        -- Receivers hide rows whose recipeId isn't in their local addon.recipeDB
        -- (shipped data may differ between addon versions).
        recipes = {},

        -- Per-character data — no guild scope needed (charKey is globally unique).
        cooldowns       = {},  -- [charKey] = { [spellId] = expiresAt }
        skills          = {},  -- [charKey][profId] = { skillRank, skillMax }
        specializations = {},  -- [charKey][profId] = spellSpecId (v0.6.3)
        factions        = {},  -- [charKey] = "Alliance"|"Horde"
        syncTimes       = {},  -- [charKey] = timestamp

        -- Account-level (own characters, populated locally).
        accountChars    = {},  -- [charKey] = true   (local-only flag, used by IsMyCharacter)
        altClaims       = {},  -- [broadcasterKey] = { array of charKeys }
                               --   per-broadcaster authoritative alt-group claim,
                               --   sync'd via the accountchars: DeltaSync leaf.
                               --   Lives in its own field (separate from
                               --   accountChars above) to avoid the boolean/array
                               --   type conflict when the same charKey is both an
                               --   own char AND a broadcaster.
        altGroups       = {},  -- [charKey] = { array of charKeys on same account }
                               --   derived view, rebuilt from altClaims on receive

        -- Guild registry: maps tag → metadata. Tag is FNV-1a-32 hash of the
        -- guildKey ("Faction-GuildName") as 6 hex chars. Reserved tag "personal"
        -- is for the player's own guildless alts.
        guildRegistry = {
            personal = { name = "Personal Alts", reserved = true },
        },

        -- v0.7.0: charKeys flagged for purge on next OnRosterReady + 60s sweep.
        -- Populated by the display gate when a tag-matching charKey isn't in
        -- libguildroster. Data stays in the main DB until the sweep runs.
        pendingPurge = {},

        -- DeltaSync hash leaves + per-character last-scan timestamps.
        hashes   = {},
        lastScan = {},

        -- Trainer-observed required-skill values (v0.5.6), per-spell, no guild scope.
        trainerObservations = {},

        -- Sync log ring buffer (Modules/SyncLog.lua caps at 200 entries).
        syncLog = {},

        -- v0.10.1 cross-guild: persisted sister-guild rosters, re-fed into
        -- LibGuildRoster on login. [guildKey] = { members, meta, fedAt }.
        sisterRosters = {},
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

        -- Cost-to-craft price source. OFF by default: TOGPM uses its OWN
        -- auto-scanned AH prices (Modules/AHScanner full scan on AH open) plus
        -- the shipped vendor table. Tick this to ALSO read Auctionator's price
        -- DB (preferred over our scan when present). Read in Modules/Price.lua.
        useTOGPMAH = true,
        useAuctionator = false,
        useAuctionatorHistorical = true,

        -- Optional Auctioneer pricing bridge. When enabled and Auctioneer is
        -- installed, TOGPM can use Auctioneer's market-value estimate.
        -- `useAuctioneerCached` adds a second-stage fallback to Auctioneer
        -- stat engines when no market value exists.
        useAuctioneer = false,
        useAuctioneerCached = true,

        -- TSM integrations are explicit opt-in, mirroring Auctionator's default.
        -- `useTSM` enables direct reads from TradeSkillMaster's in-game API.
        -- `useTSMAppHelper` enables historical-style TSM sources that depend on
        -- desktop-app-fed data. Both are off by default.
        useTSM = false,
        useTSMAppHelper = false,

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

        -- Cross-guild: user-configured allied ("sister") guild names that TOGPM
        -- shares profession data with. Flat list of display names; faction is
        -- derived from the current player when forming "Faction-GuildName" keys.
        sisterGuilds = {},
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

        -- Crafting tab: last-selected profession name (for the dropdown), and
        -- the craft queue. The queue is an ORDERED array — order is the
        -- user's stack rank (drag-to-reorder), and Craft Next processes it
        -- top-down. Each entry: { profId = N, recipeId = N, qty = N }.
        craftSelProf    = nil,
        craftQueue      = {},

        -- Profit tab: last-selected subtab ("live" or "history").
        profitSubTab    = "live",

        -- Main window: last-selected main tab (saved across reloads).
        lastMainTab     = "browser",
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
    ["craft"]        = "ToggleCraftingTakeover",
    ["spellcache"]   = "DumpSpellCache",
    ["itemgaps"]     = "ReportItemDBGaps",
    ["dumprecipe"]   = "DumpRecipe",
    ["dumphashes"]   = "DumpHashes",
    ["dumpcooldowns"] = "DumpCooldowns",
    ["transmutedebug"] = "DumpTransmuteDiag",
    ["dumpprice"]   = "DumpPrice",
    ["forcebroadcast"] = "ForceBroadcast",
    ["backfill"]     = "RunBackfill",
    ["myalts"]       = "DumpMyAlts",
    ["pullroster"]   = "PullSisterRoster",
    ["xgdiag"]       = "PrintCrossGuildDiagnostics",
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
    -- The AceDB instance lives on the AceAddon object (addon.lib), NOT on
    -- addon itself. Reading self.db.profile here would always be nil and
    -- silently fall through to "auto" — which is exactly what made this
    -- function appear to do nothing in v0.7.0 pre-ship.
    local db = addon.lib and addon.lib.db
    local override = db and db.profile and db.profile.uiLanguageOverride or "auto"

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

    -- Rebuild any caller-level tables that captured L["..."] values at
    -- module load time (before this override ran).
    if addon.RebuildLocalizedTables then addon:RebuildLocalizedTables() end
end

function Ace:OnInitialize()
    -- Set up SavedVariables via AceDB (two separate SVs).
    -- TOGPM_Settings: profile (UI prefs) and char (shopping list, reagent watch, frames)
    self.db       = LibStub("AceDB-3.0"):New("TOGPM_Settings", SETTINGS_DEFAULTS, true)
    -- TOGPM_GuildDB: global guild-wide data (recipes, skills, cooldowns, sync log)
    addon.guildDb = LibStub("AceDB-3.0"):New("TOGPM_GuildDB", GUILD_DB_DEFAULTS, true)

    -- v0.7.0 schema migration. One-shot: wipes the old per-guild bucket tree
    -- and rebuilds the flat top-level tables. Cooldown timers are preserved
    -- (merged out of every old bucket). Everything else regenerates on next
    -- trade-skill scan + guild sync. No-op when SV is already at v7.
    addon:MigrateGuildDb()

    -- v0.7.1: recovery pass for the Vanilla / HC scan-key bug. Tailors,
    -- Cooks, etc. on Vanilla scanned with `Hitem:ITEMID` links and stored
    -- recipes under crafted-item-ID keys; the rest of the addon looks them
    -- up by spell ID. Idempotent — moves item-keyed entries onto their
    -- spell-ID slots when a match exists in addon.recipeDB.
    addon:RemapItemKeysToSpellIds()

    -- v0.7.2: evict spell IDs from gdb.cooldowns that aren't in the explicit
    -- whitelist. Stale data (mage talents, portals, etc.) had slipped in via
    -- buggy v0.6.x code paths or peer broadcasts before the receive path was
    -- whitelisted; this pass cleans the SV and stops the entries from
    -- re-broadcasting forward. Idempotent — no-op once clean.
    addon:RemoveBogusCooldowns()

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
    -- transitions are sourced from LibGuildRoster-1.0 (the standalone GuildRoster
    -- addon, pulled in via DeltaSync's dependency chain) which exposes
    -- CallbackHandler-1.0 callbacks driven by both GUILD_ROSTER_UPDATE diffs and
    -- CHAT_MSG_SYSTEM parsing.
    local GuildRoster = LibStub("LibGuildRoster-1.0", true)
    if GuildRoster and GuildRoster.RegisterCallback then
        GuildRoster:RegisterCallback("OnMemberOnline", function(_, name)
            addon:OnCrafterCameOnline(name)
        end)

        -- v0.7.0 timed-purge sweep. OnRosterReady fires after the initial
        -- guild roster scan completes; we add a 60-second buffer to cover
        -- straggler GUILD_ROSTER_UPDATE events on large guilds (>500
        -- members) where the roster trickles in over multiple ticks. After
        -- the buffer, walk addon.guildDb.global.pendingPurge and delete
        -- every reference for each flagged charKey (departed members
        -- queued by display-time visibility checks).
        GuildRoster:RegisterCallback("OnRosterReady", function()
            self:ScheduleTimer(function() addon:RunPendingPurge() end, 60)
        end)
    end

    -- Cross-guild config propagation (gossip): receive guildmates' allied-guild
    -- lists, announce ours shortly after login, and re-broadcast every ~12 min
    -- so members who log in later converge. See addon:BroadcastSisterConfig.
    self:RegisterComm(addon.SisterCfgPrefix, "OnSisterConfigComm")
    self:ScheduleTimer(function() addon:BroadcastSisterConfig() end, 20)
    self:ScheduleRepeatingTimer(function() addon:BroadcastSisterConfig() end, 720)

    -- Cross-guild ROSTER propagation (Part B): receive relayed sister rosters,
    -- and broadcast any we hold so members who never pulled still get the
    -- canonical roster the visibility gate needs. Suppression keeps it to ~one
    -- broadcaster per interval. See addon:BroadcastSisterRosters.
    self:RegisterComm(addon.SisterRosterPrefix, "OnSisterRosterComm")
    self:ScheduleTimer(function() addon:BroadcastSisterRosters() end, 35)
    self:ScheduleRepeatingTimer(function() addon:BroadcastSisterRosters() end, 300)

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

    -- v0.7.0: legacy "Faction-Realm-GuildName" → "Faction-GuildName" bucket
    -- migration removed. gdb.guilds tree was wiped by MigrateGuildDb at
    -- OnInitialize and there's no per-guild bucket to normalize anymore.

    -- v0.7.0: populate gdb.altClaims[myKey] from the local account-wide flag set.
    -- altClaims is the per-broadcaster authoritative alt-group used by the
    -- sync protocol; accountChars stays a separate local boolean-flag table
    -- so the two semantics don't collide (the v0.7.0 first build collapsed
    -- them and crashed in BuildLeafPayload — see the migration in
    -- MigrateGuildDb that splits them back apart).
    if addon:GetGuildKey() then
        local gdb = addon:GetGuildDb()
        if gdb then
            local groupArr = {}
            for ck in pairs(addon.guildDb.global.accountChars) do
                if type(ck) == "string" then groupArr[#groupArr + 1] = ck end
            end
            table.sort(groupArr)  -- deterministic order so the hash is stable across peers
            if not gdb.altClaims then gdb.altClaims = {} end
            gdb.altClaims[myKey] = groupArr
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
--
-- v0.7.0: PROF_NAMES is built from PROF_LOCALE_KEYS so it can be REBUILT
-- after the UI Language Override is applied. Without the rebuild,
-- module-load-time L["..."] reads freeze English strings before
-- ApplyLocaleOverride can mutate the AceLocale table — the dropdowns
-- then stay English even after the override.
local PROF_LOCALE_KEYS = {
    [171] = "ProfAlchemy",        [164] = "ProfBlacksmithing",  [185] = "ProfCooking",
    [333] = "ProfEnchanting",     [202] = "ProfEngineering",    [129] = "ProfFirstAid",
    [165] = "ProfLeatherworking", [186] = "ProfMining",         [197] = "ProfTailoring",
    [182] = "ProfHerbalism",      [393] = "ProfSkinning",       [755] = "ProfJewelcrafting",
    [773] = "ProfInscription",    [356] = "ProfFishing",        [374] = "ProfSmelting",
}

addon.PROF_NAMES = {}
function addon:RebuildLocalizedTables()
    for profId, lkey in pairs(PROF_LOCALE_KEYS) do
        addon.PROF_NAMES[profId] = L[lkey]
    end
end
addon:RebuildLocalizedTables()  -- initial population from current L state

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

-- /togpm pullroster <Name[-Realm]> — manually pull an allied guild's roster
-- from a known online member. Test trigger for cross-guild sync; the automatic
-- /who discovery comes in a later step. Routes through DeltaSync RosterSync over
-- a whisper; on success the sister roster lands in LibGuildRoster and is
-- persisted (watch for "sister roster updated" in debug output).
function addon:PullSisterRoster(args)
    local peer = strtrim(args or "")
    if peer == "" then
        Ace:Print("Usage: /togpm pullroster <Name> (an online member of an allied guild)")
        return
    end
    local DS = addon.Scanner and addon.Scanner.DS
    if not DS or not DS.RequestRosterSync then
        Ace:Print("|cffff4444Cross-guild sync unavailable|r (DeltaSync RosterSync not loaded).")
        return
    end
    Ace:Print("Requesting roster + profession data from " .. peer .. " ...")
    DS:RequestRosterSync(peer)
    if addon.Scanner and addon.Scanner.RequestSisterData then
        addon.Scanner:RequestSisterData(peer)
    end
end

--- /togpm dumprecipe <name> — find a recipe by exact name and print its
-- stored fields + reagent table to chat. Used to diagnose missing itemLink
-- / itemId data on reagents (the bank-button + reagent-tracker rely on these).
function addon:DumpRecipe(args)
    local name = strtrim(args or "")
    if name == "" then
        Ace:Print("Usage: /togpm dumprecipe <recipe name>")
        return
    end
    local gdb = addon:GetGuildDb()
    if not gdb then Ace:Print("|cffff4444No guild DB|r"); return end

    -- v0.7.0: walk the shipped addon.recipeDB by name (authoritative
    -- metadata) and cross-reference each hit against gdb.recipes for the
    -- crafter set.
    local found = 0
    if addon.recipeDB then
        for profId, profMeta in pairs(addon.recipeDB) do
            for recipeId, meta in pairs(profMeta) do
                if meta.name == name then
                    found = found + 1
                    Ace:Print(("|cffda8cff[prof %d]|r recipeId=%s teaches=%s craftedItemId=%s"):format(
                        profId, tostring(recipeId), tostring(meta.teaches), tostring(meta.craftedItemId)))
                    Ace:Print(("  requiredSkill=%s"):format(tostring(meta.requiredSkill)))
                    if meta.reagents then
                        local n = 0; for _ in pairs(meta.reagents) do n = n + 1 end
                        Ace:Print(("  reagents (%d):"):format(n))
                        for itemId, count in pairs(meta.reagents) do
                            Ace:Print(("    [item %s] count=%s"):format(tostring(itemId), tostring(count)))
                        end
                    end
                    local rd = gdb.recipes and gdb.recipes[profId] and gdb.recipes[profId][recipeId]
                    local crafters = {}
                    if rd and rd.crafters then
                        for ck, tag in pairs(rd.crafters) do
                            crafters[#crafters + 1] = ck .. "(" .. tostring(tag) .. ")"
                        end
                    end
                    Ace:Print(("  crafters: %s"):format(table.concat(crafters, ", ")))
                end
            end
        end
    end
    if found == 0 then
        Ace:Print(("|cffff4444No recipe named '%s' found in addon.recipeDB|r"):format(name))
    end
end

--- /togpm backfill — v0.7.0: no-op. Metadata isn't stored in SV anymore,
--- so there's nothing to backfill. Kept as a slash command for muscle memory.
function addon:RunBackfill()
    Ace:Print("|cffaaaaaav0.7.0: metadata lives in addon.recipeDB; nothing to backfill.|r")
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

--- /togpm dumpprice <itemId|itemLink> — print the current price-resolution
-- output plus Auctioneer live/cached diagnostics for one item.
function addon:DumpPrice(args)
    local raw = strtrim(args or "")
    local itemId = tonumber(raw)
    if not itemId and raw ~= "" then
        itemId = tonumber(raw:match("item:(%d+)"))
    end
    if not itemId then
        Ace:Print("Usage: /togpm dumpprice <itemId|itemLink>")
        return
    end

    if not addon.Price then
        Ace:Print("|cffff4444Price module not loaded|r")
        return
    end

    local itemName = (GetItemInfo and GetItemInfo(itemId)) or ("item:" .. tostring(itemId))
    Ace:Print(("|cffda8cffPrice diagnostic|r for %s (%d)"):format(tostring(itemName), itemId))

    local p, src, age = addon.Price.Get(itemId)
    Ace:Print(("  Get: %s  src=%s  age=%s"):format(
        p and addon.Price.Money(p) or "nil",
        tostring(src),
        tostring(age)))

    local liveP, liveSrc = addon.Price.GetSaleLive(itemId)
    Ace:Print(("  GetSaleLive: %s  src=%s"):format(
        liveP and addon.Price.Money(liveP) or "nil",
        tostring(liveSrc)))

    local histP, histSrc = addon.Price.GetSaleHistorical(itemId)
    Ace:Print(("  GetSaleHistorical: %s  src=%s"):format(
        histP and addon.Price.Money(histP) or "nil",
        tostring(histSrc)))

    local diag = addon.Price.GetAuctioneerDiagnostics and addon.Price.GetAuctioneerDiagnostics(itemId)
    if diag then
        Ace:Print(("  Auctioneer toggles: useAuctioneer=%s useAuctioneerCached=%s"):format(
            tostring(diag.useAuctioneer), tostring(diag.useAuctioneerCached)))
        Ace:Print(("  Auctioneer API: ready=%s hasAlgorithmAPI=%s hasModuleRegistry=%s serverKey=%s"):format(
            tostring(diag.ready), tostring(diag.hasAlgorithmAPI), tostring(diag.hasModuleRegistry), tostring(diag.serverKey)))
        Ace:Print(("  Auctioneer values: live=%s cached=%s"):format(
            diag.live and addon.Price.Money(diag.live) or "nil",
            diag.cached and addon.Price.Money(diag.cached) or "nil"))
    end
end

--- /togpm itemgaps [profId] — list crafted items whose stats LibItemDB is
--- missing, so the gaps can be filled into LibItemDB. Reports two kinds: items
--- not in ItemDB at all, and items present but returning no stats (some of those
--- genuinely grant none — toys, bags, ammo, reagents — so eyeball before
--- filling). Output is capped to keep chat usable; pass a profession id to scope.
function addon:ReportItemDBGaps(args)
    local DB = self:GetItemDB()
    if not (DB and DB:IsReady()) then
        Ace:Print("LibItemDB not ready (is the ItemDB addon enabled?).")
        return
    end
    local rdb = self.recipeDB
    if not rdb then Ace:Print("No recipe data loaded.") return end

    local onlyProf = tonumber(strtrim(args or ""))
    local total, unknown, nostat, shown = 0, 0, 0, 0
    local CAP = 60
    Ace:Print("|cffFF8000LibItemDB gaps|r — crafted items with no stat data:")
    for pid, recipes in pairs(rdb) do
        if recipes and (not onlyProf or pid == onlyProf) then
            for _, m in pairs(recipes) do
                local cid = m.craftedItemId
                if cid then
                    total = total + 1
                    local known = DB:HasItem(cid)
                    local stats = known and DB:GetStats(cid)
                    if not known then
                        unknown = unknown + 1
                        if shown < CAP then
                            shown = shown + 1
                            Ace:Print(("  prof %d  item %d  \226\128\148 not in ItemDB"):format(pid, cid))
                        end
                    elseif not (stats and next(stats)) then
                        nostat = nostat + 1
                        if shown < CAP then
                            shown = shown + 1
                            Ace:Print(("  prof %d  item %d  %s \226\128\148 no stats"):format(pid, cid, DB:GetName(cid) or "?"))
                        end
                    end
                end
            end
        end
    end
    Ace:Print(("Scanned %d crafted items: %d not in ItemDB, %d with no stats%s."):format(
        total, unknown, nostat, (shown >= CAP) and (" (showing first " .. CAP .. ")") or ""))
    if shown >= CAP then
        Ace:Print("Tip: scope with /togpm itemgaps <profId> to list the rest.")
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

--- /togpm craft [on|off] — toggle the Crafting-tab takeover of the native
--- profession window. Also serves as an escape hatch during development: if
--- the reskin ever misbehaves, `/togpm craft off` restores Blizzard's default
--- window immediately. The proper Settings UI toggle comes in a later step.
function addon:ToggleCraftingTakeover(args)
    local Engine = addon.CraftingEngine
    if not Engine then
        Ace:Print("Crafting engine not loaded.")
        return
    end
    local arg = strtrim(args or ""):lower()
    local on
    if arg == "on" then
        on = true
    elseif arg == "off" then
        on = false
    else
        on = not Engine:IsTakeoverEnabled()
    end
    Engine:SetTakeoverEnabled(on)
    Ace:Print("Crafting window takeover: " .. (on and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
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
    self:Print("  /togpm dumpprice <itemId|itemLink> \226\128\148 Dump full price diagnostics for an item")
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

-- v0.7.0: NoGuildBucketKey no longer used (flat schema). Reserved tag
-- "personal" handles guildless own alts via the guildRegistry.
addon.NoGuildBucketKey = "__noguild"  -- kept as a constant for legacy migration code

-- Return the global flat data table. Field names (recipes / skills / cooldowns
-- / specializations / accountChars / altGroups / factions / syncTimes / hashes
-- / lastScan / pendingPurge / trainerObservations / guildRegistry) mirror the
-- old per-guild bucket fields, so most call sites continue to work without
-- code change. The DATA SHAPE inside recipes changed though — crafters values
-- are now guild tags (strings) instead of bools — see top-of-file schema notes.
function addon:GetGuildDb()
    return addon.guildDb.global
end

-- ---------------------------------------------------------------------------
-- v0.7.0 guild-tag helpers
-- ---------------------------------------------------------------------------

-- Reserved tag for guildless own alts. Used in place of a hash so it's visually
-- distinguishable in the SV file and can't collide with any FNV-1a output.
addon.PersonalTag = "personal"

-- FNV-1a 32-bit hash of a string → 6 hex chars. Deterministic across all clients
-- so the same guildKey always produces the same tag. 24-bit output (~16M
-- possible values) is collision-safe at the scale of a single user's SV (a
-- handful of guilds over a playing lifetime).
local FNV_OFFSET = 2166136261
local FNV_PRIME  = 16777619
local bit_band, bit_bxor = bit.band, bit.bxor

local function fnv1aHash6(str)
    local h = FNV_OFFSET
    for i = 1, #str do
        h = bit_bxor(h, str:byte(i))
        h = bit_band(h * FNV_PRIME, 0xFFFFFFFF)
    end
    -- Take low 24 bits → 6 hex chars (1 in 16M collision per pair; safe at our scale).
    return string.format("%06x", bit_band(h, 0xFFFFFF))
end

-- Compute the tag for a given guildKey, or PersonalTag when nil/empty.
-- Registers the guild in guildRegistry on first call so the UI can later
-- resolve the tag back to a human-readable name.
function addon:GetGuildTagFor(guildKey, faction, guildName)
    if not guildKey or guildKey == "" then return addon.PersonalTag end
    local tag = fnv1aHash6(guildKey)
    local gdb = self:GetGuildDb()
    if not gdb.guildRegistry then gdb.guildRegistry = {} end
    if not gdb.guildRegistry[tag] then
        gdb.guildRegistry[tag] = {
            name    = guildName,
            faction = faction,
            key     = guildKey,
        }
    end
    return tag
end

-- Convenience: the tag for the LOCAL player's current guild (or PersonalTag
-- when guildless). Called by Scanner when tagging a freshly-scanned crafter
-- entry, and by display sites to know which tag is "ours" for filtering.
function addon:GetCurrentGuildTag()
    local guildKey = self:GetGuildKey()
    if not guildKey then return addon.PersonalTag end
    local guildName = GetGuildInfo("player")
    local faction   = UnitFactionGroup("player") or "Neutral"
    return self:GetGuildTagFor(guildKey, faction, guildName)
end

-- Derive the guild tag for an arbitrary "Faction-GuildName" key (e.g. a sister
-- guild's, learned from inbound cross-guild data), registering it in
-- guildRegistry so the UI can resolve tag → name. Returns PersonalTag for a
-- nil/empty key. Like GetCurrentGuildTag, but for a key other than our own.
function addon:GuildTagFromKey(guildKey)
    if not guildKey or guildKey == "" then return addon.PersonalTag end
    local faction, name = guildKey:match("^([^%-]+)%-(.+)$")
    return self:GetGuildTagFor(guildKey, faction, name)
end

-- ---------------------------------------------------------------------------
-- Cross-guild ("sister guild") configuration
-- ---------------------------------------------------------------------------

-- The user-configured list of allied guild display names TOGPM shares
-- profession data with. Stored in the shared settings profile; nil-safe.
function addon:GetSisterGuilds()
    return (Ace.db and Ace.db.profile and Ace.db.profile.sisterGuilds) or {}
end

-- Parse newline-separated text from the settings input into a trimmed,
-- case-insensitively de-duplicated list of guild names and store it.
function addon:SetSisterGuilds(text)
    local out, seen = {}, {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local name = line:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" and not seen[name:lower()] then
            seen[name:lower()] = true
            out[#out + 1] = name
        end
    end
    if Ace.db and Ace.db.profile then
        -- Capture which sister guilds we're DROPPING so we can tear down their
        -- federated roster + data — everything gates on the list, so a removed
        -- guild must stop being served, accepted, displayed, and re-fed.
        local oldKeys = self:GetSisterGuildKeySet()
        Ace.db.profile.sisterGuilds   = out
        -- Stamp a fresh server-time so this edit wins the last-writer race, then
        -- gossip it to the home guild immediately (config-propagation MVP).
        Ace.db.profile.sisterGuildsTs = (GetServerTime and GetServerTime()) or (time and time()) or 0
        local newKeys = self:GetSisterGuildKeySet()
        for key in pairs(oldKeys) do
            if not newKeys[key] then self:DropSisterGuildData(key) end
        end
        self:BroadcastSisterConfig()
    end
end

-- Tear down a sister guild we no longer federate with: remove its roster from
-- LibGuildRoster, drop our persisted copy (so login re-feed doesn't resurrect
-- it), and let the visibility gate purge its now-unrostered crafters on the next
-- refresh. Called when a guild is removed from the allied-guild list.
function addon:DropSisterGuildData(guildKey)
    if not guildKey then return end
    local Scanner = self.Scanner
    local GR = Scanner and Scanner.GuildRoster
    if GR and GR.RemoveSisterRoster then GR:RemoveSisterRoster(guildKey) end
    local gdb = self:GetGuildDb()
    if gdb and type(gdb.sisterRosters) == "table" then
        gdb.sisterRosters[guildKey] = nil
    end
    self:DebugPrint("Cross-guild: dropped de-configured sister guild", guildKey)
end

-- ---------------------------------------------------------------------------
-- Cross-guild config propagation (gossip)
-- The allied-guild list must reach every home-guild member — eventually only
-- officers can EDIT it, so members can only RECEIVE it. Model: broadcast on
-- change, on a ~12-minute repeating timer, and on demand (the "Sync now"
-- button); last-writer-wins by the server-time stamp captured when
-- SetSisterGuilds ran. Re-broadcasts carry the ORIGINAL stamp, so a member
-- relaying can't clobber a newer officer edit. A member holding no config
-- (ts 0) never broadcasts, so an empty list can't win the race against a real
-- one — and a member who logs in later converges within one timer interval.
-- ---------------------------------------------------------------------------

addon.SisterCfgPrefix = "TOGPMxgc"   -- AceComm prefix (must be <= 16 chars)

function addon:GetSisterGuildsTs()
    return (Ace.db and Ace.db.profile and tonumber(Ace.db.profile.sisterGuildsTs)) or 0
end

-- Serialize + send our current allied-guild list on GUILD. No-op when we hold
-- nothing (ts 0), so empties never participate in the last-writer race.
function addon:BroadcastSisterConfig()
    if not (Ace.db and Ace.db.profile) then return end
    local ts = self:GetSisterGuildsTs()
    if ts <= 0 then return end
    local guilds = self:GetSisterGuilds()
    local ok, msg = pcall(function() return Ace:Serialize({ g = guilds, t = ts }) end)
    if ok and type(msg) == "string" then
        Ace:SendCommMessage(addon.SisterCfgPrefix, msg, "GUILD")
        self:DebugPrint("Cross-guild: broadcast sister config (ts", ts, ",", #guilds, "guild(s))")
    end
end

-- A guildmate sent their allied-guild list. Last-writer-wins by stamp; adopt a
-- strictly-newer config WITHOUT re-stamping (keep the origin ts so gossip
-- converges) and without re-broadcasting (the on-change broadcast already
-- reached every online member; the periodic timer covers latecomers).
function addon:OnSisterConfigReceived(prefix, message, _distribution, sender)
    if prefix ~= addon.SisterCfgPrefix then return end
    -- Drop our own echo.
    local GR = self.Scanner and self.Scanner.GuildRoster
    local me = self:GetCharacterKey()
    local normSender = (GR and GR.NormalizeName and GR:NormalizeName(sender)) or sender
    if sender == me or normSender == me then return end

    local success, payload = Ace:Deserialize(message)
    if not success or type(payload) ~= "table" then return end
    local incomingTs = tonumber(payload.t) or 0
    if incomingTs <= self:GetSisterGuildsTs() then return end   -- not newer → ignore
    if type(payload.g) ~= "table" then return end

    local clean = {}
    for _, name in ipairs(payload.g) do
        if type(name) == "string" and name ~= "" then clean[#clean + 1] = name end
    end
    -- Tear down any guild this adopted config drops (same as a manual edit), so
    -- a federated removal also stops the gates/display for that guild.
    local oldKeys = self:GetSisterGuildKeySet()
    Ace.db.profile.sisterGuilds   = clean
    Ace.db.profile.sisterGuildsTs = incomingTs
    local newKeys = self:GetSisterGuildKeySet()
    for key in pairs(oldKeys) do
        if not newKeys[key] then self:DropSisterGuildData(key) end
    end
    self:DebugPrint("Cross-guild: adopted sister config from", sender, "(ts", incomingTs, ",", #clean, "guild(s))")

    local AceRegistry = LibStub("AceConfigRegistry-3.0", true)
    if AceRegistry then AceRegistry:NotifyChange("TOGProfessionMaster") end
    if self.callbacks then self.callbacks:Fire("GUILD_DATA_UPDATED", "sisterconfig") end
end

-- AceComm dispatches to a named method on the addon object (Ace); bounce to the
-- addon-namespace handler above.
function Ace:OnSisterConfigComm(prefix, message, distribution, sender)
    addon:OnSisterConfigReceived(prefix, message, distribution, sender)
end

-- ---------------------------------------------------------------------------
-- Cross-guild ROSTER propagation (Part B)
-- The visibility gate keeps a sister crafter only if their charKey is in a
-- sister roster we hold. A member who configured the allied guild (via the
-- config gossip above) but never PULLED its roster would therefore purge every
-- relayed sister crafter — so the roster must reach the whole guild too, not
-- just the puller. A member who holds a sister roster broadcasts it on the GUILD
-- channel; others apply it. A "recently-seen by hash" suppression means only ~one
-- holder broadcasts per interval no matter how many hold it, and whoever holds
-- it can take over if the usual broadcaster logs off. Gated by IsSisterGuildKey
-- on receive, so an unlisted guild's roster is never accepted.
-- ---------------------------------------------------------------------------

addon.SisterRosterPrefix = "TOGPMxgr"   -- AceComm prefix (<= 16 chars)
addon._seenSisterRoster  = addon._seenSisterRoster or {}   -- guildKey -> { hash, t }
local SISTERROSTER_SUPPRESS = 270       -- seconds; skip if seen this hash recently

-- Broadcast each held sister roster to our home guild, unless we saw the same
-- roster (by hash) circulate recently.
function addon:BroadcastSisterRosters()
    local GR = self.Scanner and self.Scanner.GuildRoster
    if not GR or not GR.GetKnownRosters or not GR.GetRoster then return end
    if #self:GetSisterGuilds() == 0 then return end
    local homeKey = self:GetGuildKey()
    local now = (GetServerTime and GetServerTime()) or (time and time()) or 0
    for _, key in ipairs(GR:GetKnownRosters()) do
        if key ~= homeKey and self:IsSisterGuildKey(key) then
            local hash = (GR.GetRosterHash and GR:GetRosterHash(key)) or 0
            local seen = self._seenSisterRoster[key]
            if not (seen and seen.hash == hash and (now - seen.t) < SISTERROSTER_SUPPRESS) then
                local roster, members = GR:GetRoster(key) or {}, {}
                for ck, m in pairs(roster) do
                    members[#members + 1] = { n = ck, c = m and m.class, l = m and m.level }
                end
                if #members > 0 then
                    local ok, msg = pcall(function() return Ace:Serialize({ k = key, h = hash, m = members }) end)
                    if ok and type(msg) == "string" then
                        Ace:SendCommMessage(self.SisterRosterPrefix, msg, "GUILD")
                        -- Record our own send so we suppress next interval too
                        -- (broadcasting duty rotates rather than pinning one member).
                        self._seenSisterRoster[key] = { hash = hash, t = now }
                        self:DebugPrint("Cross-guild: broadcast sister roster", key, "(", #members, "members, hash", hash, ")")
                    end
                end
            end
        end
    end
end

-- A home guildmate relayed a sister roster. Apply it (if we don't already hold
-- the same one), gated by IsSisterGuildKey, and note it as circulating.
function addon:OnSisterRosterReceived(prefix, message, _distribution, sender)
    if prefix ~= self.SisterRosterPrefix then return end
    local GR = self.Scanner and self.Scanner.GuildRoster
    if not GR or not GR.SetSisterRoster then return end
    local success, payload = Ace:Deserialize(message)
    if not success or type(payload) ~= "table" then return end
    local key = payload.k
    if not self:IsSisterGuildKey(key) then return end          -- federation gate
    local hash = tonumber(payload.h) or 0
    self._seenSisterRoster[key] = { hash = hash, t = (GetServerTime and GetServerTime()) or 0 }
    -- Skip if we already hold this exact roster (avoid redundant re-feeds).
    local mine = GR.GetRosterHash and GR:GetRosterHash(key) or nil
    if mine and mine == hash then return end
    if type(payload.m) ~= "table" then return end
    local members = {}
    for _, e in ipairs(payload.m) do
        if type(e) == "table" and type(e.n) == "string" then
            members[#members + 1] = { name = e.n, class = e.c, level = e.l }
        end
    end
    if #members == 0 then return end
    GR:SetSisterRoster(key, members, { via = sender })
    -- Persist (so it survives /reload) + refresh UI, WITHOUT re-broadcasting —
    -- the suppression above keeps the relay from echoing around the guild.
    if self.Scanner.PersistSisterRoster then self.Scanner:PersistSisterRoster(key) end
    if self.callbacks then self.callbacks:Fire("GUILD_DATA_UPDATED", "sisterroster:relay") end
    self:DebugPrint("Cross-guild: applied relayed sister roster", key, "from", sender, "(", #members, "members)")
end

function Ace:OnSisterRosterComm(prefix, message, distribution, sender)
    addon:OnSisterRosterReceived(prefix, message, distribution, sender)
end

-- The configured sister guilds as "Faction-GuildName" keys for the current
-- player's faction, excluding the player's own home guild (you never
-- sister-sync your own guild). Cross-faction confederations can't sync —
-- /who and whispers don't cross factions — so the current faction is assumed.
-- Returns an empty table when unconfigured or guildless.
function addon:GetSisterGuildKeys()
    local names = self:GetSisterGuilds()
    if #names == 0 then return {} end
    local faction = UnitFactionGroup("player") or "Neutral"
    local homeKey = self:GetGuildKey()
    local keys = {}
    for _, name in ipairs(names) do
        local key = faction .. "-" .. name
        if key ~= homeKey then
            keys[#keys + 1] = key
        end
    end
    return keys
end

-- A { guildKey -> true } set of our configured sister guilds. Used as the
-- "consent proof" we attach to outbound cross-guild requests and to gate
-- inbound traffic. O(1) membership test vs. the array form above.
function addon:GetSisterGuildKeySet()
    local set = {}
    for _, key in ipairs(self:GetSisterGuildKeys()) do set[key] = true end
    return set
end

-- True if guildKey is one of our configured sister guilds. The single source of
-- truth for "may I exchange cross-guild data with this guild?" — every serve /
-- accept / roster gate calls this, so an unlisted guild (a stranger, an
-- accidental config, a malicious puller) is refused everywhere.
function addon:IsSisterGuildKey(guildKey)
    if not guildKey or guildKey == "" then return false end
    return self:GetSisterGuildKeySet()[guildKey] == true
end

-- The set of guild TAGS whose crafter data we are permitted to STORE and RELAY:
-- our own alts (PersonalTag), our home guild, and every configured sister guild.
-- The merge gate drops any crafter whose tag is not in here, which (a) discards
-- data for guilds we don't federate with — even when it arrives relayed inside a
-- home-guild broadcast — and (b) gives the "no sister list => purely local guild
-- operation" behavior for free (the set collapses to home + personal). Rebuilt
-- on demand so it always reflects the current (possibly just-federated) config.
function addon:GetAllowedGuildTagSet()
    local set = { [addon.PersonalTag] = true }
    if self:GetGuildKey() then set[self:GetCurrentGuildTag()] = true end
    for _, key in ipairs(self:GetSisterGuildKeys()) do
        set[self:GuildTagFromKey(key)] = true
    end
    return set
end

-- ---------------------------------------------------------------------------
-- v0.7.0 display-time visibility gate
-- ---------------------------------------------------------------------------

-- Return true if a crafter entry should be displayed RIGHT NOW.
--   charKey:  "Name-Realm"
--   crafterTag: the guild tag stored on the crafter entry
-- Rules (any TRUE keeps the crafter visible):
--   1. The crafter is one of the local player's own characters (own alt).
--   2. The crafter's tag matches the current guild AND they're in libguildroster.
-- A charKey that matches no rule gets queued in pendingPurge for the timed
-- sweep — the data stays in the DB until the sweep runs so a transient roster
-- glitch doesn't permanently strip them.
function addon:IsVisibleCrafter(charKey, crafterTag)
    if not charKey then return false end
    -- Own alts (accountChars-tracked) always visible, regardless of guild.
    if self:IsMyCharacter(charKey) then return true end

    local myTag = self:GetCurrentGuildTag()

    -- Tag mismatch = either stale data from a previous guild, OR a tracked
    -- SISTER guild (cross-guild sharing). Keep the crafter if LibGuildRoster
    -- confirms the charKey belongs to any roster we hold (their sister roster);
    -- while the roster lib isn't ready, don't purge a sister-tagged crafter
    -- (cold-start guard — the sister roster may not be re-fed yet). Otherwise
    -- it's genuinely stale → flag for the timed purge sweep.
    if crafterTag ~= myTag then
        if crafterTag ~= addon.PersonalTag then
            local GR = self.Scanner and self.Scanner.GuildRoster
            if GR and GR.IsInAnyRoster then
                if GR:IsInAnyRoster(charKey) then return true end
                if GR.IsReady and not GR:IsReady() then return true end
            end
        end
        self:FlagForPurge(charKey)
        return false
    end

    -- We're guildless (PersonalTag) and they're not own alt — orphan.
    if crafterTag == addon.PersonalTag then
        self:FlagForPurge(charKey)
        return false
    end

    local GC = self.Scanner and self.Scanner.GuildRoster

    -- Membership can only be judged once the roster lib is loaded AND has
    -- completed its first stabilized build. LibGuildRoster:IsInGuild is a strict
    -- membership check, whereas the retired GuildCache returned true on an
    -- unbuilt roster. If the lib is absent or not yet ready, treat a
    -- tag-matching crafter as visible and DO NOT flag it — otherwise an
    -- early-login refresh (GetNumGuildMembers() still 0) or a lib-load failure
    -- would queue legitimate members for the deferred purge sweep and silently
    -- delete their data. Erring visible here is the safe, behavior-preserving
    -- choice; a real ex-member is re-evaluated and purged on the next refresh
    -- once the roster is ready.
    if not GC or (GC.IsReady and not GC:IsReady()) then return true end

    -- Tag matches current guild. Confirm membership via LibGuildRoster.
    if GC:IsInGuild(charKey) then return true end

    -- Not in roster directly — keep alive if they're an alt of someone IN
    -- the roster (bank alts of in-guild mains stay visible).
    if self:IsAltOfInRosterCharacter(charKey) then return true end

    self:FlagForPurge(charKey)
    return false
end

-- Return true if charKey is in any altGroup whose owner OR any sibling is
-- currently in the guild roster. Protects bank alts of in-guild mains.
function addon:IsAltOfInRosterCharacter(charKey)
    local gdb = self:GetGuildDb()
    local altGroups = gdb and gdb.altGroups
    if not altGroups then return false end
    local GC = self.Scanner and self.Scanner.GuildRoster
    if not GC then return false end

    for ownerKey, alts in pairs(altGroups) do
        local belongsHere = (ownerKey == charKey)
        if not belongsHere and type(alts) == "table" then
            for _, altCk in ipairs(alts) do
                if altCk == charKey then belongsHere = true; break end
            end
        end
        if belongsHere then
            if GC:IsInGuild(ownerKey) then return true end
            if type(alts) == "table" then
                for _, altCk in ipairs(alts) do
                    if altCk ~= charKey and GC:IsInGuild(altCk) then return true end
                end
            end
        end
    end
    return false
end

-- Return true if charKey appears as an alt in someone's accountChars / altGroups
-- list. Used by the visibility gate to keep alts of in-guild members alive
-- even when the alt itself isn't in the roster.
function addon:IsAltOfKnownCharacter(charKey)
    local gdb = self:GetGuildDb()
    local altGroups = gdb and gdb.altGroups
    if not altGroups then return false end
    for ownerKey, alts in pairs(altGroups) do
        if ownerKey == charKey then return true end   -- own owner key
        if type(alts) == "table" then
            for _, altCk in ipairs(alts) do
                if altCk == charKey then return true end
            end
        end
    end
    return false
end

-- Add a charKey to the pending-purge list. The timed sweep at OnRosterReady +
-- 60s walks this list and deletes each charKey's references from every table.
function addon:FlagForPurge(charKey)
    if not charKey then return end
    local gdb = self:GetGuildDb()
    if not gdb.pendingPurge then gdb.pendingPurge = {} end
    gdb.pendingPurge[charKey] = true
end

-- Walk pendingPurge and delete every reference for each flagged charKey.
-- Called by Scanner after libguildroster is confirmed populated (OnRosterReady
-- callback + 60s safety buffer for stragglers on large rosters).
function addon:RunPendingPurge()
    local gdb = self:GetGuildDb()
    if not gdb.pendingPurge or not next(gdb.pendingPurge) then return 0 end

    -- Never delete based on an unconfirmed roster. The sweep is scheduled off
    -- LibGuildRoster's OnRosterReady so this normally passes; but if the lib is
    -- missing or hasn't finished its first build, bail and keep the flags for a
    -- later, confirmable sweep. Deleting now would destroy data for members the
    -- roster simply can't vouch for yet (e.g. flags accumulated while the roster
    -- lib was unavailable).
    local GC = self.Scanner and self.Scanner.GuildRoster
    if not GC or (GC.IsReady and not GC:IsReady()) then
        addon:DebugPrint("Purge skipped — roster not ready/confirmable")
        return 0
    end

    local count = 0
    for charKey in pairs(gdb.pendingPurge) do
        -- Re-validate at sweep time. A charKey can land in pendingPurge from an
        -- early-login refresh, or a period when the roster lib was unavailable,
        -- yet still be a real member. Only delete those the now-ready roster
        -- confirms are gone (left the guild, or wrong-guild stale data); a
        -- confirmed member or own alt just has its stale flag dropped.
        if self:IsMyCharacter(charKey)
            or (GC.IsInAnyRoster and GC:IsInAnyRoster(charKey))
            or GC:IsInGuild(charKey)
            or self:IsAltOfInRosterCharacter(charKey) then
            -- Still present (home or a tracked sister guild) — keep the data;
            -- the flag is cleared by the wipe below.
        else
            -- Walk every recipe's crafters list and strip this charKey.
            for _, profRecipes in pairs(gdb.recipes or {}) do
                for _, rd in pairs(profRecipes) do
                    if rd.crafters then rd.crafters[charKey] = nil end
                end
            end
            if gdb.cooldowns       then gdb.cooldowns[charKey]       = nil end
            if gdb.skills          then gdb.skills[charKey]          = nil end
            if gdb.specializations then gdb.specializations[charKey] = nil end
            if gdb.factions        then gdb.factions[charKey]        = nil end
            if gdb.syncTimes       then gdb.syncTimes[charKey]       = nil end
            if gdb.altGroups then
                gdb.altGroups[charKey] = nil
                -- Also strip charKey from other owners' alt arrays.
                for _, alts in pairs(gdb.altGroups) do
                    if type(alts) == "table" then
                        for i = #alts, 1, -1 do
                            if alts[i] == charKey then table.remove(alts, i) end
                        end
                    end
                end
            end
            count = count + 1
        end
    end

    -- Drop guildRegistry entries whose last crafter just got purged.
    if gdb.guildRegistry and gdb.recipes then
        local stillReferenced = {}
        for _, profRecipes in pairs(gdb.recipes) do
            for _, rd in pairs(profRecipes) do
                for _, tag in pairs(rd.crafters or {}) do
                    stillReferenced[tag] = true
                end
            end
        end
        for tag, entry in pairs(gdb.guildRegistry) do
            if not entry.reserved and not stillReferenced[tag] then
                gdb.guildRegistry[tag] = nil
            end
        end
    end

    gdb.pendingPurge = {}
    addon:DebugPrint("Purge swept", count, "charKey(s) from the DB")
    return count
end

-- ---------------------------------------------------------------------------
-- v0.7.0 recipe-metadata accessors (read from shipped addon.recipeDB)
--
-- The SV no longer carries name/icon/reagents/links per recipe — those live
-- in the shipped Data/Recipes/<Prof>.lua tables. Every GUI consumer uses
-- these helpers to look up display metadata at render time.
-- ---------------------------------------------------------------------------

function addon:GetRecipeMeta(profId, recipeId)
    local prof = self.recipeDB and self.recipeDB[profId]
    return prof and prof[recipeId]
end

function addon:GetRecipeName(profId, recipeId)
    local m = self:GetRecipeMeta(profId, recipeId)
    if m and m.name then return m.name end
    -- Fallback: WoW client APIs (may return localized name).
    if type(recipeId) == "number" then
        local n = (GetSpellInfo and GetSpellInfo(recipeId)) or (GetItemInfo and GetItemInfo(recipeId))
        if n then return n end
    end
    return tostring(recipeId)
end

function addon:GetRecipeIcon(profId, recipeId)
    local m = self:GetRecipeMeta(profId, recipeId)
    if m and m.craftedItemId and GetItemIcon then
        local t = GetItemIcon(m.craftedItemId)
        if t then return t end
    end
    if type(recipeId) == "number" then
        if GetSpellTexture then
            local t = GetSpellTexture(recipeId)
            if t then return t end
        end
        if GetItemIcon then
            local t = GetItemIcon(recipeId)
            if t then return t end
        end
    end
    return 134400  -- generic question-mark fallback
end

-- Return reagents as the array-of-tables form GUI consumers expect:
--   { { itemId, count, name, itemLink }, ... }
-- The shipped addon.recipeDB stores { [itemId] = count }, so we convert on
-- read. GetItemInfo populates name+link; nil values are fine (consumers
-- handle uncached items by retrying via Item:CreateFromItemID).
function addon:GetRecipeReagents(profId, recipeId)
    local m = self:GetRecipeMeta(profId, recipeId)
    if not m or not m.reagents then return nil end
    local arr = {}
    for itemId, count in pairs(m.reagents) do
        local name, link = GetItemInfo(itemId)
        arr[#arr + 1] = {
            itemId   = itemId,
            count    = count,
            name     = name or ("Item #" .. itemId),
            itemLink = link,
        }
    end
    return arr
end

-- The crafted item ID (what the recipe produces). Used for icon resolution,
-- tooltip SetItemByID, shopping list output naming. nil for spells with no
-- physical product (currently none in the shipped DB).
function addon:GetRecipeCraftedItemId(profId, recipeId)
    local m = self:GetRecipeMeta(profId, recipeId)
    return m and m.craftedItemId
end

-- LibItemDB (optional standalone addon, read via LibStub — NOT embedded): the
-- use-effect buff a consumable grants (food / elixir / flask / potion). Resolved
-- lazily so it works whether ItemDB loaded before or after us.
function addon:GetItemDB()
    if self._itemDB == nil then
        self._itemDB = (LibStub and LibStub("LibItemDB-1.0", true)) or false
    end
    return self._itemDB or nil
end

-- A crafted item's stats as a display/search string ("+5 Strength, +12 Stamina"),
-- from LibItemDB. Uses GetStats, which MERGES equipment stats + use-effects — so
-- this covers BOTH crafted gear (BS/Tailoring/LW: the equip stats) AND consumables
-- (food/elixir/flask/potion: the use-effect buff) in one path. nil when ItemDB is
-- absent / not ready / the item has no stats. Cached per item id (session-stable).
-- KEYs are GetItemStats keys (_G[KEY] → localized name, also covers
-- RESISTANCE<n>_NAME for armor/resistances); a few use-effect-only keys have no
-- _G entry. An item that comes back nil/empty is a coverage GAP in LibItemDB
-- (see addon:ReportItemDBGaps) unless it genuinely grants no stats.
local EFFECT_CUSTOM_LABEL = {
    CRIT_PCT = "Crit", SPELL_CRIT_PCT = "Spell Crit", HEALTH = "Health", MANA = "Mana",
}
function addon:GetCraftedItemStatText(itemId)
    if not itemId then return nil end
    self._itemStatText = self._itemStatText or {}
    local cached = self._itemStatText[itemId]
    if cached ~= nil then return cached or nil end

    local DB = self:GetItemDB()
    local stats = (DB and DB:IsReady() and DB:GetStats(itemId)) or nil
    if not stats then
        self._itemStatText[itemId] = false
        return nil
    end
    local parts = {}
    for k, v in pairs(stats) do
        local label = _G[k] or EFFECT_CUSTOM_LABEL[k] or k
        -- Whole numbers print as integers (+8 Agility); fractional values (e.g.
        -- weapon DPS, 28.529411…) round to one decimal like the native tooltip
        -- (+28.5 Damage Per Second) instead of trailing 8–10 digits.
        local num
        if type(v) == "number" and v ~= math.floor(v) then
            num = ("%.1f"):format(v)
        else
            num = tostring(v)
        end
        parts[#parts + 1] = ("+%s %s"):format(num, label)
    end
    table.sort(parts)
    local s = (#parts > 0) and table.concat(parts, ", ") or false
    self._itemStatText[itemId] = s
    return s or nil
end

-- The effect/buff text shown + searched for a recipe: the shipped enchant effect
-- (ProfessionDB) when present, else the crafted consumable's use-effect buff
-- (LibItemDB). Lets food/elixir/flask recipes be found by "12 stam" etc. and
-- carry a buff line in their tooltip — the same `effect` field enchants use.
-- Full searchable text of a crafted item's tooltip — name + stats + use/proc
-- text + flavor + requirements — lowercased, for the "search anything" recipe
-- search, so a query like "hour", "chance on hit", or "requires level 40"
-- matches. LibItemDB stores stat *values*, not the prose, so this comes from the
-- live client item tooltip, scraped once per item and cached. Items the client
-- hasn't loaded yet aren't cached (GetItemInfo is pinged to warm them), so they
-- become searchable once their data arrives. nil when there's nothing yet.
local _ttScraper
function addon:GetItemTooltipSearchText(itemId)
    if not itemId then return nil end
    self._itemTTText = self._itemTTText or {}
    local cached = self._itemTTText[itemId]
    if cached ~= nil then return cached or nil end
    -- Don't scrape until the client has the item (an unloaded item tooltips
    -- empty); calling GetItemInfo also warms it so it's ready next time.
    if GetItemInfo and not GetItemInfo(itemId) then return nil end
    if not _ttScraper then
        _ttScraper = CreateFrame("GameTooltip", "TOGPMSearchScraper", UIParent, "GameTooltipTemplate")
    end
    if not _ttScraper.SetItemByID then return nil end
    _ttScraper:SetOwner(UIParent, "ANCHOR_NONE")
    _ttScraper:ClearLines()
    _ttScraper:SetItemByID(itemId)
    local parts = {}
    for i = 1, _ttScraper:NumLines() do
        local fs  = _G["TOGPMSearchScraperTextLeft" .. i]
        local txt = fs and fs:GetText()
        if txt and txt ~= "" then parts[#parts + 1] = txt:lower() end
    end
    local s = (#parts > 0) and table.concat(parts, " ") or false
    self._itemTTText[itemId] = s
    return s or nil
end

function addon:GetRecipeEffect(profId, recipeId)
    local m = self:GetRecipeMeta(profId, recipeId)
    if not m then return nil end
    -- Crafted gear and consumables take their stats/buff from LibItemDB; the
    -- ProfessionDB enchant effect is only the fallback for things LibItemDB has no
    -- stats for (true enchants applied to gear).
    local e = self:GetCraftedItemStatText(m.craftedItemId)
    if e then return e end
    return (m.effect and m.effect ~= "" and m.effect) or nil
end

-- v0.7.1: reverse lookup table — craftedItemId → recipeId (spell ID) per
-- profession. Used on Vanilla / Classic Hardcore where the trade-skill
-- recipe link is `Hitem:ITEMID` (not `Henchant:SPELLID` like TBC+),
-- so the scanner returns the crafted item ID instead of the spell ID
-- the rest of the addon expects. Built lazily per profession on first
-- access; reset to nil to force rebuild after a Data/Recipes update.
function addon:GetSpellIdForCraftedItem(profId, craftedItemId)
    if not profId or not craftedItemId then return nil end
    self._craftedItemMap = self._craftedItemMap or {}
    local profMap = self._craftedItemMap[profId]
    if not profMap then
        profMap = {}
        local profMeta = self.recipeDB and self.recipeDB[profId]
        if profMeta then
            for spellId, meta in pairs(profMeta) do
                if meta.craftedItemId then
                    profMap[meta.craftedItemId] = spellId
                end
            end
        end
        self._craftedItemMap[profId] = profMap
    end
    return profMap[craftedItemId]
end

-- v0.7.2: walk gdb.cooldowns and strip any spell IDs that aren't in the
-- explicit whitelist (data.cooldowns + data.transmutes + groupBySpell +
-- saltShakerItem). Used to evict stale junk like Impact 12360 (a Fire
-- Mage talent) or Portal: Undercity from cooldown buckets — those
-- entries slipped in via v0.6.x code paths or buggy peer broadcasts
-- before the receive path was whitelisted. Idempotent — no-op once
-- clean. Called at OnInitialize.
function addon:RemoveBogusCooldowns()
    local gdb = self:GetGuildDb()
    if not gdb or not gdb.cooldowns then return 0 end
    local data = self.GetCooldownData and self:GetCooldownData()
    if not data then return 0 end
    local valid = function(sid)
        return data.cooldowns[sid]
            or data.transmutes[sid]
            or (data.groupBySpell and data.groupBySpell[sid])
            or sid == data.saltShakerItem
    end
    local stripped = 0
    for _, cds in pairs(gdb.cooldowns) do
        if type(cds) == "table" then
            local toRemove = {}
            for sid in pairs(cds) do
                if not valid(sid) then toRemove[#toRemove + 1] = sid end
            end
            for _, sid in ipairs(toRemove) do
                cds[sid] = nil
                stripped = stripped + 1
            end
        end
    end
    if stripped > 0 then
        addon:DebugPrint("RemoveBogusCooldowns: stripped", stripped, "non-whitelisted cooldown entries")
    end
    return stripped
end

-- v0.7.1: walk gdb.recipes and remap any item-ID-keyed entries to their
-- spell-ID equivalents. Idempotent — only touches entries whose current
-- key matches a craftedItemId in addon.recipeDB and is NOT a recognized
-- spell ID in the same profession bucket. Safe to call on every
-- OnInitialize; a no-op on already-correct data. Recovery path for the
-- Vanilla / HC scan-key bug: existing tailors / cooks / etc. had 60+
-- recipes scanned under itemID keys that nothing could cross-reference.
function addon:RemapItemKeysToSpellIds()
    local gdb = self:GetGuildDb()
    if not gdb or not gdb.recipes then return 0 end
    local moved = 0
    for profId, profRecipes in pairs(gdb.recipes) do
        local profMeta = self.recipeDB and self.recipeDB[profId]
        if profMeta then
            -- Snapshot keys first; mutating profRecipes mid-iteration is
            -- undefined behavior in Lua 5.1.
            local keys = {}
            for k in pairs(profRecipes) do keys[#keys + 1] = k end
            for _, key in ipairs(keys) do
                if not profMeta[key] then
                    local spellId = self:GetSpellIdForCraftedItem(profId, key)
                    if spellId and profMeta[spellId] then
                        local rd = profRecipes[key]
                        local target = profRecipes[spellId]
                        if not target then
                            profRecipes[spellId] = rd
                        else
                            -- Union the crafter sets when both keys carry data.
                            if not target.crafters then target.crafters = {} end
                            for ck, tag in pairs(rd.crafters or {}) do
                                target.crafters[ck] = tag
                            end
                        end
                        profRecipes[key] = nil
                        moved = moved + 1
                    end
                end
            end
        end
    end
    if moved > 0 then
        addon:DebugPrint("RemapItemKeysToSpellIds: moved", moved, "item-keyed entries to spell-keyed slots")
    end
    return moved
end

-- ---------------------------------------------------------------------------
-- v0.7.0 schema migration (one-shot at first OnInitialize on a v0.6.x SV)
-- ---------------------------------------------------------------------------

function addon:MigrateGuildDb()
    local gdb = addon.guildDb and addon.guildDb.global
    if not gdb then return end

    -- Migrate if either (a) schemaVersion is missing/old, OR (b) the legacy
    -- gdb.guilds tree is still present. The (b) branch is a recovery path
    -- for the first v0.7.0 release, which incorrectly set schemaVersion via
    -- defaults BEFORE the migration walk ran — leaving cooldowns stranded
    -- inside the orphaned gdb.guilds[X].cooldowns tables. On the next load
    -- with the corrected code, gdb.guilds is still there (the broken
    -- migration never wiped it because it returned early), so we detect it
    -- and run the walk now, recovering the cooldown timers.
    local needsMigration = (not gdb.schemaVersion)
                       or (gdb.schemaVersion < CURRENT_SCHEMA_VERSION)
                       or (gdb.guilds ~= nil)
    if not needsMigration then return end

    addon:DebugPrint("Migrating GuildDB to schema v" .. CURRENT_SCHEMA_VERSION)

    -- Preserve cooldowns from the old per-guild buckets — they're time-
    -- sensitive (re-scanning loses the active expiry timer). Also preserve
    -- any cooldowns already at the top level (from an in-progress migration
    -- or hand-edit) by merging both sources, with bucket data taking priority
    -- when both have the same charKey (buckets are the older / more complete
    -- record from before the broken migration).
    local mergedCooldowns = {}
    if type(gdb.cooldowns) == "table" then
        for charKey, expiries in pairs(gdb.cooldowns) do
            if type(expiries) == "table" then mergedCooldowns[charKey] = expiries end
        end
    end
    if gdb.guilds then
        for _, bucket in pairs(gdb.guilds) do
            for charKey, expiries in pairs(bucket.cooldowns or {}) do
                if type(expiries) == "table" then mergedCooldowns[charKey] = expiries end
            end
        end
    end

    -- Recover per-broadcaster alt-group arrays from the old per-guild buckets
    -- (where they used to live under bucket.accountChars[broadcasterKey]).
    -- v0.7.0's first build mistakenly stomped them into the top-level
    -- accountChars boolean-flag table, causing a runtime crash when
    -- BuildLeafPayload tried to read accountchars: leaves. Move any
    -- table-valued entries currently in gdb.accountChars into altClaims and
    -- reset accountChars to its proper boolean-flag-only semantics.
    local altClaims = {}
    if gdb.guilds then
        for _, bucket in pairs(gdb.guilds) do
            for broadcasterKey, arr in pairs(bucket.accountChars or {}) do
                if type(arr) == "table" then altClaims[broadcasterKey] = arr end
            end
        end
    end
    if type(gdb.accountChars) == "table" then
        for ck, v in pairs(gdb.accountChars) do
            if type(v) == "table" then
                altClaims[ck] = v
                gdb.accountChars[ck] = true   -- restore boolean flag semantics
            end
        end
    end

    gdb.guilds              = nil      -- drop the entire old per-guild tree
    gdb.recipes             = {}
    gdb.skills              = {}
    gdb.specializations     = {}
    gdb.factions            = {}
    gdb.syncTimes           = {}
    gdb.altGroups           = {}
    gdb.guildRegistry       = { [addon.PersonalTag] = { name = "Personal Alts", reserved = true } }
    gdb.pendingPurge        = {}
    gdb.hashes              = {}
    gdb.lastScan            = {}
    gdb.trainerObservations = gdb.trainerObservations or {}
    gdb.cooldowns           = mergedCooldowns
    gdb.accountChars        = gdb.accountChars or {}
    gdb.altClaims           = altClaims
    gdb.syncLog             = gdb.syncLog or {}
    gdb.schemaVersion       = CURRENT_SCHEMA_VERSION

    addon:DebugPrint("Migration complete. Recovered cooldown entries:",
        (function() local n = 0; for _ in pairs(mergedCooldowns) do n = n + 1 end; return n end)(),
        "altClaim entries:",
        (function() local n = 0; for _ in pairs(altClaims) do n = n + 1 end; return n end)())
end

--- Return true if charKey belongs to the local player's account.
-- Checks the account-wide accountChars table (all characters that have ever
-- logged in on this account with TOGPM installed).
function addon:IsMyCharacter(charKey)
    return addon.guildDb.global.accountChars[charKey] == true
end

--- v0.7.0 compatibility shim. The flat schema has no per-guild buckets
--- anymore — there's a single global data tree. Callers that still iterate
--- "every bucket" now get a single virtual "bucket" (the global table)
--- that exposes the same field names (recipes, skills, cooldowns, etc.).
-- @param callback  function(bucket)  — invoked once, with the flat global
function addon:ForEachGuildBucket(callback)
    if not self.guildDb or not self.guildDb.global then return end
    callback(self.guildDb.global)
end

--- v0.7.0 compatibility shim. With the flat schema there's only one
--- "bucket" (the global table), so this returns it if the field+charKey
--- exists, nil otherwise.
function addon:FindBucketForChar(charKey, field)
    if not charKey or not field then return nil end
    local g = self.guildDb and self.guildDb.global
    if g and g[field] and g[field][charKey] then return g end
    return nil
end
