-- TOG Profession Master — Settings
-- AceConfig-3.0 option table.  Registered with AceConfigRegistry so it
-- appears under ESC → Options → Addons → TOG Profession Master.
-- Also opened directly by /togpm settings and Shift+Left-click on minimap.

local _, addon = ...
local Ace         = addon.lib
local AceConfig   = LibStub("AceConfig-3.0",       true)
local AceDialog   = LibStub("AceConfigDialog-3.0", true)
local AceRegistry = LibStub("AceConfigRegistry-3.0", true)
local AceGUI      = LibStub("AceGUI-3.0")
local L           = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

if not AceConfig or not AceDialog then
    addon:DebugPrint("Settings: AceConfig-3.0 or AceConfigDialog-3.0 not found — settings panel disabled")
    return
end

-- ---------------------------------------------------------------------------
-- Cross-guild diagnostics
-- A live, read-only snapshot rendered as a "description" on the Cross-Guild
-- tab so testers can see cross-guild state at a glance instead of running /run
-- probes: dependency status, known rosters (home + sisters) with counts, the
-- configured allied guilds, crafter counts per guild, and persisted sister
-- rosters. The description's `name` is a function, so AceConfig re-evaluates it
-- every render — the Refresh button just forces a re-render via NotifyChange.
-- ---------------------------------------------------------------------------

local function og(s) return "|c" .. (addon.BrandColor or "ffFF8000") .. s .. "|r" end

-- ---------------------------------------------------------------------------
-- Crafter-alert sound / visual options — the two dropdowns in the Alerts section.
-- ---------------------------------------------------------------------------
-- Sounds: raw numeric SoundKit IDs, the same style the alert already used
-- (PlaySound(878)). All are core kits present on every supported Classic flavor
-- (verified IDs). Selecting one in the dropdown previews it. Option labels are
-- kept in English deliberately — they're short game terms most addons don't
-- translate; the dropdown's own name/desc ARE localized.
local ALERT_SOUNDS = {
    [878]  = "Chime (default)",
    [8960] = "Ready Check",
    [8959] = "Raid Warning",
    [5274] = "Auction Bell",
    [3081] = "Whisper",
    [3175] = "Map Ping",
}
local ALERT_SOUND_SORTING = { 878, 8960, 8959, 5274, 3081, 3175 }

-- Visuals: a style key the alert renderer (addon:FireCrafterAlertVisual) maps to
-- a canned WoW effect — a full-screen flash in one of three tints, or a taskbar/
-- window flash (FlashClientIcon, which flashes the game in the OS taskbar — handy
-- when you're alt-tabbed).
local ALERT_VISUALS = {
    flashGold   = "Screen flash \226\128\148 gold",
    flashRed    = "Screen flash \226\128\148 red",
    flashBlue   = "Screen flash \226\128\148 blue",
    raidWarning = "Raid-warning banner",
    errorText   = "Error text (top center)",
    taskbar     = "Taskbar flash (alt-tabbed)",
}
local ALERT_VISUAL_SORTING = { "flashGold", "flashRed", "flashBlue", "raidWarning", "errorText", "taskbar" }

local function countPairs(t)
    local n = 0
    if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function BuildCrossGuildDiagnostics()
    local lines = {}
    local GR  = addon.Scanner and addon.Scanner.GuildRoster
    local DS  = addon.Scanner and addon.Scanner.DS
    local gdb = addon:GetGuildDb()

    -- Dependencies -----------------------------------------------------------
    lines[#lines + 1] = og("Dependencies")
    if DS then
        lines[#lines + 1] = "  DeltaSync: loaded  (RosterSync: " ..
            (DS.RequestRosterSync and "|cff00ff00yes|r" or "|cffff4040no|r") .. ")"
    else
        lines[#lines + 1] = "  DeltaSync: |cffff4040not loaded|r"
    end
    if GR then
        lines[#lines + 1] = "  LibGuildRoster: loaded  (multi-roster: " ..
            (GR.SetSisterRoster and "|cff00ff00yes|r" or "|cffff4040no|r") .. ")"
    else
        lines[#lines + 1] = "  LibGuildRoster: |cffff4040not loaded|r"
    end

    -- Known rosters ----------------------------------------------------------
    lines[#lines + 1] = " "
    lines[#lines + 1] = og("Known rosters")
    if GR and GR.GetKnownRosters then
        local homeKey = GR.GetHomeGuildKey and GR:GetHomeGuildKey() or nil
        local known   = GR:GetKnownRosters() or {}
        if #known == 0 then
            lines[#lines + 1] = "  |cffaaaaaa(none yet)|r"
        else
            for _, k in ipairs(known) do
                local n   = countPairs(GR.GetRoster and GR:GetRoster(k))
                local tag = (k == homeKey) and " |cff00ccff(home)|r" or " |cffffd100(sister)|r"
                lines[#lines + 1] = string.format("  %s%s  \226\128\148  %d members", k, tag, n)
            end
        end
    else
        lines[#lines + 1] = "  |cffaaaaaa(roster library unavailable)|r"
    end

    -- Configured allied guilds ----------------------------------------------
    lines[#lines + 1] = " "
    lines[#lines + 1] = og("Configured allied guilds")
    local sisters = addon:GetSisterGuilds() or {}
    if #sisters == 0 then
        lines[#lines + 1] = "  |cffaaaaaa(none configured \226\128\148 add one above)|r"
    else
        for _, name in ipairs(sisters) do
            lines[#lines + 1] = "  " .. name
        end
    end

    -- Crafter data by guild --------------------------------------------------
    lines[#lines + 1] = " "
    lines[#lines + 1] = og("Crafter data by guild")
    if gdb then
        local byTag = {}   -- tag -> set of distinct charKeys
        for _, profRecipes in pairs(gdb.recipes or {}) do
            for _, rd in pairs(profRecipes) do
                if rd.crafters then
                    for ck, tag in pairs(rd.crafters) do
                        byTag[tag] = byTag[tag] or {}
                        byTag[tag][ck] = true
                    end
                end
            end
        end
        local reg   = gdb.guildRegistry or {}
        local myTag = addon:GetCurrentGuildTag()
        local any   = false
        for tag, cks in pairs(byTag) do
            any = true
            local info  = reg[tag]
            local nm    = (info and info.name) or ("tag " .. tostring(tag))
            local total = countPairs(cks)
            if tag == myTag or tag == addon.PersonalTag or not (GR and GR.IsInAnyRoster) then
                lines[#lines + 1] = string.format("  %s  \226\128\148  %d crafters", nm, total)
            else
                -- Sister/foreign tag: the gate keeps only crafters whose key is
                -- found in a known roster; the rest get purged. Break it down so
                -- we can see whether the misses are alts (recognizable mains'
                -- alts) or a key-normalization issue (e.g. all on one realm).
                local inRoster, orphans = 0, {}
                for ck in pairs(cks) do
                    if GR:IsInAnyRoster(ck) then
                        inRoster = inRoster + 1
                    elseif #orphans < 6 then
                        orphans[#orphans + 1] = ck
                    end
                end
                lines[#lines + 1] = string.format("  %s  \226\128\148  %d crafters (%d in roster, |cffff6060%d orphaned|r)",
                    nm, total, inRoster, total - inRoster)
                if #orphans > 0 then
                    lines[#lines + 1] = "    e.g. " .. table.concat(orphans, ", ")
                end
            end
        end
        if not any then lines[#lines + 1] = "  |cffaaaaaa(no crafter data)|r" end
    end

    -- Persisted sister rosters ----------------------------------------------
    if gdb and type(gdb.sisterRosters) == "table" and next(gdb.sisterRosters) then
        lines[#lines + 1] = " "
        lines[#lines + 1] = og("Persisted allied rosters (survive /reload)")
        for key, entry in pairs(gdb.sisterRosters) do
            local mc  = (type(entry) == "table" and type(entry.members) == "table") and #entry.members or 0
            local fed = (type(entry) == "table" and entry.fedAt) and date("%H:%M:%S", entry.fedAt) or "?"
            lines[#lines + 1] = string.format("  %s  \226\128\148  %d members (fed %s)", key, mc, fed)
        end
    end

    return table.concat(lines, "\n")
end

-- /togpm xgdiag — dump the same cross-guild diagnostics to chat (raw print, no
-- addon prefix) so it's easy to copy-paste for troubleshooting.
function addon:PrintCrossGuildDiagnostics()
    print("|c" .. (addon.BrandColor or "ffFF8000") .. "TOGPM cross-guild diagnostics|r")
    for line in (BuildCrossGuildDiagnostics() .. "\n"):gmatch("(.-)\n") do
        print(line)
    end
end

-- ---------------------------------------------------------------------------
-- Option table
-- ---------------------------------------------------------------------------

local OPTIONS = {
    name    = "TOG Profession Master",
    handler = addon,
    type    = "group",
    childGroups = "tab",
    args = {

        general = {
            name  = L["SettingsTabGeneral"],
            type  = "group",
            order = 1,
            args = {

        -- ---- Display -------------------------------------------------------
        displayHeader = {
            name  = L["SettingsDisplayHeader"],
            type  = "header",
            order = 1,
        },

        minimapButton = {
            name  = L["SettingsMinimapBtn"],
            desc  = L["SettingsMinimapBtnDesc"],
            type  = "toggle",
            order = 2,
            get   = function() return Ace.db.profile.minimapButton end,
            set   = function(_, val)
                Ace.db.profile.minimapButton = val
                local icon = LibStub("LibDBIcon-1.0", true)
                if icon then
                    if val then icon:Show("TOGProfessionMaster")
                    else        icon:Hide("TOGProfessionMaster") end
                end
            end,
        },

        persistProfFilter = {
            name  = L["SettingsPersistProfFilter"],
            desc  = L["SettingsPersistProfFilterDesc"],
            type  = "toggle",
            order = 3,
            get   = function() return Ace.db.profile.persistProfFilter end,
            set   = function(_, val)
                Ace.db.profile.persistProfFilter = val
                if not val then
                    -- Clear the saved filter (shared helper — same key BrowserTab persists).
                    local _, setProfFilter = addon.GUI.PersistentChoice("profile", "savedProfFilter")
                    setProfFilter(0)
                end
            end,
        },

        -- UI Language Override. "auto" follows the WoW client's GetLocale();
        -- any other value forces TOGPM's own UI strings into that locale even
        -- on a different client (in-game item / spell / NPC names still come
        -- from Blizzard's APIs and render in the client's actual language —
        -- this only overrides strings the addon itself ships). The
        -- ApplyLocaleOverride function in TOGProfessionMaster.lua mutates the
        -- AceLocale L table in place at OnInitialize and on each set here,
        -- so already-open windows pick up the change on next refresh; a
        -- /reload is recommended to be safe (some captured strings may have
        -- been formatted into widgets already).
        --
        -- Dropdown labels are intentionally NOT localized — they always
        -- show in each language's native script so users can recognize
        -- their language regardless of the current UI language.
        uiLanguageOverride = {
            name   = L["SettingsUILangOverride"],
            desc   = L["SettingsUILangOverrideDesc"],
            type   = "select",
            order  = 4,
            values = {
                auto  = L["SettingsUILangAuto"],
                enUS  = "English (US)",
                enGB  = "English (UK)",
                deDE  = "Deutsch",
                esES  = "Español (España)",
                esMX  = "Español (México)",
                frFR  = "Français",
                itIT  = "Italiano",
                nlNL  = "Nederlands",
                ptBR  = "Português (Brasil)",
                ruRU  = "Русский",
                koKR  = "한국어",
                zhCN  = "简体中文",
                zhTW  = "繁體中文",
                thTH  = "Thai",  -- WoW's default fonts don't ship Thai glyphs; native script "ไทย" would render as boxes
                filPH = "Filipino",
            },
            sorting = { "auto", "enUS", "enGB", "deDE", "esES", "esMX", "frFR",
                        "itIT", "nlNL", "ptBR", "ruRU", "koKR", "zhCN", "zhTW", "thTH", "filPH" },
            get = function() return Ace.db.profile.uiLanguageOverride or "auto" end,
            set = function(_, val)
                Ace.db.profile.uiLanguageOverride = val
                addon:ApplyLocaleOverride()
                addon:Print(L["SettingsUILangReloadHint"])
            end,
        },

        -- Whole-window UI scale. Lets the window (Crafting tab included) take
        -- less screen space than the resize floor allows, by scaling every
        -- element proportionally rather than shrinking the layout.
        windowScale = {
            name      = L["SettingsWindowScale"],
            desc      = L["SettingsWindowScaleDesc"],
            type      = "range",
            order     = 4.5,
            min       = 0.5,
            max       = 1.5,
            step      = 0.05,
            isPercent = true,
            get       = function() return tonumber(Ace.db.profile.windowScale) or 1 end,
            set       = function(_, val)
                Ace.db.profile.windowScale = val
                if addon.MainWindow and addon.MainWindow.ApplyScale then
                    addon.MainWindow:ApplyScale()
                end
            end,
        },

        -- ---- Sync ----------------------------------------------------------
        syncHeader = {
            name  = L["SettingsSyncHeader"],
            type  = "header",
            order = 5,
        },

        -- Guild-only sync mode. For private/emulated servers (e.g. Whitemane)
        -- that don't deliver addon messages over WHISPER, which breaks normal
        -- peer sync. Reroutes DeltaSync's directed channels onto the guild
        -- channel. Realm-scoped (Ace.db.realm) — set once per server, applies
        -- to all your alts there. Feature-detected: the toggle is hidden unless
        -- the loaded DeltaSync exposes guild-mode (MINOR >= 13). `get` reads the
        -- live library state when available so the box always matches reality;
        -- `set` flips DeltaSync (which persists via the onChanged wired in
        -- Scanner) and also writes the realm DB directly as a belt-and-suspenders
        -- guard for the rare case the flip is rejected before init.
        guildMode = {
            name  = L["SettingsGuildMode"],
            desc  = L["SettingsGuildModeDesc"],
            type  = "toggle",
            width = "full",
            order = 5.1,
            hidden = function()
                local DS = addon.Scanner and addon.Scanner.DS
                return not (DS and DS.InitGuildMode)
            end,
            get = function()
                local DS = addon.Scanner and addon.Scanner.DS
                if DS and DS.IsGuildMode then return DS:IsGuildMode() end
                return Ace.db and Ace.db.realm and Ace.db.realm.guildMode or false
            end,
            set = function(_, val)
                val = val and true or false
                local DS = addon.Scanner and addon.Scanner.DS
                if DS and DS.SetGuildMode then DS:SetGuildMode(val) end
                if Ace.db and Ace.db.realm then Ace.db.realm.guildMode = val end
            end,
        },

        -- ---- Cooldowns -----------------------------------------------------
        cooldownsHeader = {
            name  = L["SettingsCooldownsHeader"],
            type  = "header",
            order = 10,
        },

        mailReadyOnly = {
            name  = L["SettingsMailReadyOnly"],
            desc  = L["SettingsMailReadyOnlyDesc"],
            type  = "toggle",
            order = 11,
            get   = function() return Ace.db.profile.mailReadyOnly end,
            set   = function(_, val) Ace.db.profile.mailReadyOnly = val end,
        },

        -- ---- Crafting ------------------------------------------------------
        craftingHeader = {
            name  = L["SettingsCraftingHeader"],
            type  = "header",
            order = 12,
        },

        -- ON by default: TOGPM stays out of the crafting window when you open a
        -- profession — Blizzard's UI (or TSM/Skillet) owns it, and no second
        -- window appears beside it. The Crafting tab is still usable from the
        -- main window. Untick to let TOGPM manage the window (legacy takeover
        -- behavior below applies). Needs /reload.
        craftingHandsOff = {
            name  = L["SettingsCraftingHandsOff"],
            desc  = L["SettingsCraftingHandsOffDesc"],
            type  = "toggle",
            width = "full",
            order = 12.01,
            get   = function() return Ace.db.profile.craftingHandsOff ~= false end,  -- default ON
            set   = function(_, val)
                Ace.db.profile.craftingHandsOff = val and true or false
                addon:Print(L["SettingsCraftingReloadHint"])
            end,
        },

        -- Off by default. Remove the Crafting tab from the main window entirely.
        hideCraftingTab = {
            name  = L["SettingsHideCraftingTab"],
            desc  = L["SettingsHideCraftingTabDesc"],
            type  = "toggle",
            width = "full",
            order = 12.02,
            get   = function() return Ace.db.profile.hideCraftingTab == true end,
            set   = function(_, val)
                Ace.db.profile.hideCraftingTab = val and true or false
                addon:Print(L["SettingsCraftingReloadHint"])
            end,
        },

        -- Off by default: opening a profession opens Blizzard's own crafting
        -- window (with the TOGPM button on it to switch). Tick to open straight
        -- into the TOGPM Crafting tab instead. Only applies when "Don't take
        -- over the crafting window" is OFF.
        craftingTakeover = {
            name  = L["SettingsCraftingTakeover"],
            desc  = L["SettingsCraftingTakeoverDesc"],
            type  = "toggle",
            width = "full",
            order = 12.04,
            disabled = function() return Ace.db.profile.craftingHandsOff ~= false end,
            get   = function() return Ace.db.profile.craftingTakeover == true end,
            set   = function(_, val) Ace.db.profile.craftingTakeover = val and true or false end,
        },

        -- Off by default. Reopen whichever crafting UI you used last (Blizzard
        -- or TOGPM); when a choice is saved it overrides the toggle above.
        craftingRememberLast = {
            name  = L["SettingsCraftingRememberLast"],
            desc  = L["SettingsCraftingRememberLastDesc"],
            type  = "toggle",
            width = "full",
            order = 12.06,
            disabled = function() return Ace.db.profile.craftingHandsOff ~= false end,
            get   = function() return Ace.db.profile.craftingRememberLast == true end,
            set   = function(_, val) Ace.db.profile.craftingRememberLast = val and true or false end,
        },

        -- The craft queue is deliberately KEPT when you switch the Crafting-tab
        -- profession dropdown (so you can bounce between professions toward one
        -- goal). This opt-in flips that to "clear on switch" for players who
        -- want a clean queue per profession. Off by default.
        clearQueueOnProfSwitch = {
            name  = L["SettingsClearQueueOnProfSwitch"],
            desc  = L["SettingsClearQueueOnProfSwitchDesc"],
            type  = "toggle",
            width = "full",
            order = 12.1,
            get   = function() return Ace.db.profile.clearQueueOnProfSwitch == true end,
            set   = function(_, val) Ace.db.profile.clearQueueOnProfSwitch = val and true or false end,
        },

        -- ---- Crafter Alerts ------------------------------------------------
        alertsHeader = {
            name  = L["SettingsAlertsHeader"],
            type  = "header",
            order = 15,
        },

        crafterAlert = {
            name  = L["SettingsCrafterAlert"],
            desc  = L["SettingsCrafterAlertDesc"],
            type  = "toggle",
            order = 16,
            get   = function() return Ace.db.profile.crafterAlert end,
            set   = function(_, val) Ace.db.profile.crafterAlert = val end,
        },

        crafterAlertSuppressAudio = {
            name  = L["SettingsCrafterAlertSuppressAudio"],
            desc  = L["SettingsCrafterAlertSuppressAudioDesc"],
            type  = "toggle",
            order = 17,
            get   = function() return Ace.db.profile.crafterAlertSuppressAudio end,
            set   = function(_, val) Ace.db.profile.crafterAlertSuppressAudio = val end,
        },

        crafterAlertSuppressVisual = {
            name  = L["SettingsCrafterAlertSuppressVisual"],
            desc  = L["SettingsCrafterAlertSuppressVisualDesc"],
            type  = "toggle",
            order = 17.5,
            get   = function() return Ace.db.profile.crafterAlertSuppressVisual end,
            set   = function(_, val) Ace.db.profile.crafterAlertSuppressVisual = val end,
        },

        crafterAlertSound = {
            name     = L["SettingsCrafterAlertSound"],
            desc     = L["SettingsCrafterAlertSoundDesc"],
            type     = "select",
            order    = 17.25,
            values   = ALERT_SOUNDS,
            sorting  = ALERT_SOUND_SORTING,
            -- Greyed out while alert audio is muted above — the pick has no effect then.
            disabled = function() return Ace.db.profile.crafterAlertSuppressAudio end,
            get      = function() return Ace.db.profile.crafterAlertSound or 878 end,
            set      = function(_, val)
                Ace.db.profile.crafterAlertSound = val
                PlaySound(val)   -- preview the chosen sound
            end,
        },

        crafterAlertVisual = {
            name     = L["SettingsCrafterAlertVisual"],
            desc     = L["SettingsCrafterAlertVisualDesc"],
            type     = "select",
            order    = 17.75,
            values   = ALERT_VISUALS,
            sorting  = ALERT_VISUAL_SORTING,
            disabled = function() return Ace.db.profile.crafterAlertSuppressVisual end,
            get      = function() return Ace.db.profile.crafterAlertVisual or "flashGold" end,
            set      = function(_, val)
                Ace.db.profile.crafterAlertVisual = val
                if addon.FireCrafterAlertVisual then
                    addon:FireCrafterAlertVisual(val, L["AlertCrafterOnlineBanner"])  -- preview
                end
            end,
        },

        crafterAlertSuppressLogin = {
            name  = L["SettingsCrafterAlertSuppressLogin"],
            desc  = L["SettingsCrafterAlertSuppressLoginDesc"],
            type  = "toggle",
            order = 18,
            get   = function() return Ace.db.profile.crafterAlertSuppressLogin end,
            set   = function(_, val) Ace.db.profile.crafterAlertSuppressLogin = val end,
        },

        cooldownAlertSuppressProtected = {
            name  = L["SettingsCooldownAlertSuppressProtected"],
            desc  = L["SettingsCooldownAlertSuppressProtectedDesc"],
            type  = "toggle",
            order = 19,
            get   = function() return Ace.db.profile.cooldownAlertSuppressProtected end,
            set   = function(_, val) Ace.db.profile.cooldownAlertSuppressProtected = val end,
        },

        cooldownAlertReminderMinutes = {
            name  = L["SettingsCooldownReminderInterval"],
            desc  = L["SettingsCooldownReminderIntervalDesc"],
            type  = "input",
            order = 19.5,
            -- Stored value is an integer; display layer shows it as a string
            -- and renders 0 as empty so "off" looks like an empty field
            -- (avoids the visual "0" that users tend to interpret as a
            -- placeholder rather than a real setting).
            get   = function()
                local m = tonumber(Ace.db.profile.cooldownAlertReminderMinutes) or 0
                if m <= 0 then return "" end
                return tostring(m)
            end,
            -- Validate-first / set-second: validate runs on Enter and gates
            -- the set call, so any bad input never reaches the saved
            -- variable. Both functions share the same "empty | off | 0..1440"
            -- parse so the rules can't drift.
            validate = function(_, val)
                local trimmed = strtrim(val or "")
                if trimmed == "" or trimmed:lower() == "off" then return true end
                local n = tonumber(trimmed)
                if not n or n ~= math.floor(n) then
                    return L["SettingsCooldownReminderInvalid"]
                end
                if n < 0 or n > 1440 then
                    return L["SettingsCooldownReminderInvalid"]
                end
                return true
            end,
            set   = function(_, val)
                local trimmed = strtrim(val or "")
                if trimmed == "" or trimmed:lower() == "off" then
                    Ace.db.profile.cooldownAlertReminderMinutes = 0
                    return
                end
                local n = tonumber(trimmed)
                if n then
                    n = math.floor(n)
                    if n < 0     then n = 0     end
                    if n > 1440  then n = 1440  end
                    Ace.db.profile.cooldownAlertReminderMinutes = n
                end
            end,
        },

        -- ---- Auction House -------------------------------------------------
        ahHeader = {
            name  = L["SettingsAHHeader"],
            type  = "header",
            order = 19.7,
        },

        ahDataSourceNote = {
            name  = "|cffFFD100Note:|r Changes to the data source checkboxes below require a |cffFF4040/reload|r to take effect.",
            type  = "header",
            order = 19.705,
        },

        -- Off by default: the full getAll scan is a shared, ~once-per-15-min,
        -- client-wide budget, so auto-firing it would starve a dedicated AH
        -- addon's own scan. Opt-in only; tooltip spells out the trade-off.
        autoScanAH = {
            name  = L["SettingsAutoScanAH"],
            desc  = L["SettingsAutoScanAHDesc"],
            type  = "toggle",
            width = "full",
            order = 19.72,
            get   = function() return Ace.db.profile.autoScanAH == true end,
            set   = function(_, val) Ace.db.profile.autoScanAH = val and true or false end,
        },

        useTOGPMAH = {
            name  = L["SettingsUseTOGPMAH"],
            desc  = L["SettingsUseTOGPMAHDesc"],
            type  = "toggle",
            width = "full",
            order = 19.735,
            get   = function()
                if Ace.db.profile.useTOGPMAH == nil then return true end
                return Ace.db.profile.useTOGPMAH == true
            end,
            set   = function(_, val) Ace.db.profile.useTOGPMAH = val and true or false end,
        },

        useAuctionator = {
            name  = L["SettingsUseAuctionator"],
            desc  = L["SettingsUseAuctionatorDesc"],
            type  = "toggle",
            width = "full",
            order = 19.75,
            get   = function() return Ace.db.profile.useAuctionator == true end,
            set   = function(_, val)
                Ace.db.profile.useAuctionator = val and true or false
                if not val then
                    Ace.db.profile.useAuctionatorHistorical = false
                end
            end,
        },

        useAuctionatorHistorical = {
            name  = L["SettingsUseAuctionatorHistorical"],
            desc  = L["SettingsUseAuctionatorHistoricalDesc"],
            type  = "toggle",
            width = "full",
            order = 19.752,
            disabled = function() return Ace.db.profile.useAuctionator ~= true end,
            get   = function() return Ace.db.profile.useAuctionatorHistorical ~= false end,
            set   = function(_, val) Ace.db.profile.useAuctionatorHistorical = val and true or false end,
        },

        useAuctioneer = {
            name  = L["SettingsUseAuctioneer"],
            desc  = L["SettingsUseAuctioneerDesc"],
            type  = "toggle",
            width = "full",
            order = 19.755,
            get   = function() return Ace.db.profile.useAuctioneer == true end,
            set   = function(_, val)
                Ace.db.profile.useAuctioneer = val and true or false
                if not val then
                    Ace.db.profile.useAuctioneerCached = false
                end
            end,
        },

        useAuctioneerCached = {
            name  = L["SettingsUseAuctioneerCached"],
            desc  = L["SettingsUseAuctioneerCachedDesc"],
            type  = "toggle",
            width = "full",
            order = 19.757,
            disabled = function() return Ace.db.profile.useAuctioneer ~= true end,
            get   = function() return Ace.db.profile.useAuctioneerCached ~= false end,
            set   = function(_, val) Ace.db.profile.useAuctioneerCached = val and true or false end,
        },

        useTSM = {
            name  = "Use TSM pricing",
            desc  = "When TradeSkillMaster is installed, allow TOGPM to use TSM live price sources for profit views. Off by default.",
            type  = "toggle",
            width = "full",
            order = 19.76,
            get   = function() return Ace.db.profile.useTSM == true end,
            set   = function(_, val) Ace.db.profile.useTSM = val and true or false end,
        },

        useTSMAppHelper = {
            name  = "Use TSM App Helper pricing",
            desc  = "Requires TradeSkillMaster_AppHelper. Enables TSM historical-style price sources for profit views. Off by default.",
            type  = "toggle",
            width = "full",
            order = 19.77,
            get   = function() return Ace.db.profile.useTSMAppHelper == true end,
            set   = function(_, val) Ace.db.profile.useTSMAppHelper = val and true or false end,
        },

        ahScanDelay = {
            name  = L["SettingsAHScanDelay"],
            desc  = L["SettingsAHScanDelayDesc"],
            type  = "input",
            order = 19.8,
            -- Stored as a number (seconds). Display layer shows it as a
            -- string with one decimal; empty / 0 means "use the version
            -- default" (1.5s on Classic Era / Anniversary, 3.0s elsewhere).
            -- Resolved at scan time in Modules/AHScanner.lua so changes to
            -- this setting take effect immediately on the next query.
            get = function()
                local n = tonumber(Ace.db.profile.ahScanDelay) or 0
                if n <= 0 then return "" end
                return tostring(n)
            end,
            validate = function(_, val)
                local trimmed = strtrim(val or "")
                if trimmed == "" or trimmed:lower() == "off" then return true end
                local n = tonumber(trimmed)
                if not n then
                    return L["SettingsAHScanDelayInvalid"]
                end
                if n < 0.5 or n > 10 then
                    return L["SettingsAHScanDelayInvalid"]
                end
                return true
            end,
            set = function(_, val)
                local trimmed = strtrim(val or "")
                if trimmed == "" or trimmed:lower() == "off" then
                    Ace.db.profile.ahScanDelay = 0
                    return
                end
                local n = tonumber(trimmed)
                if n then
                    if n < 0.5 then n = 0.5 end
                    if n > 10  then n = 10  end
                    Ace.db.profile.ahScanDelay = n
                end
            end,
        },

        -- ---- Global item tooltip lines ------------------------------------
        -- The addon hooks the global item tooltip (bags, AH, chat links,
        -- vendor, etc.) and appends up to two TOGPM lines: a crafters list
        -- (who in your guild can make this) and an IDs line (itemId /
        -- spellId — useful for troubleshooting icon or link issues).
        -- Both default ON; each is independently togglable so users can
        -- pick crafters-only, IDs-only, both, or none.
        tooltipHeader = {
            name  = L["SettingsTooltipHeader"],
            type  = "header",
            order = 19.50,
        },
        tooltipShowCrafters = {
            name  = L["SettingsTooltipShowCrafters"],
            desc  = L["SettingsTooltipShowCraftersDesc"],
            type  = "toggle",
            order = 19.51,
            width = "full",
            get   = function() return Ace.db.profile.tooltipShowCrafters ~= false end,
            set   = function(_, val) Ace.db.profile.tooltipShowCrafters = val and true or false end,
        },
        tooltipShowIds = {
            name  = L["SettingsTooltipShowIds"],
            desc  = L["SettingsTooltipShowIdsDesc"],
            type  = "toggle",
            order = 19.52,
            width = "full",
            get   = function() return Ace.db.profile.tooltipShowIds ~= false end,
            set   = function(_, val) Ace.db.profile.tooltipShowIds = val and true or false end,
        },

        -- ---- Phase filtering (TBC Anniversary only) ------------------------
        -- Only meaningful on TBC clients; hidden on Vanilla / Wrath / Cata /
        -- MoP where there's nothing to filter. The recipe DB ships with a
        -- `phase` field on Phase 2+ TBC recipes (sourced at build time from
        -- ATT — see tools/att_extract_phase.py). GUI/MissingRecipesTab.lua
        -- skips any recipe with phase > tbcAnniversaryPhase on TBC clients.
        phaseHeader = {
            name   = L["SettingsTBCPhaseHeader"],
            type   = "header",
            order  = 19.85,
            hidden = function() return not addon.isTBC end,
        },

        tbcAnniversaryPhase = {
            name   = L["SettingsTBCPhase"],
            desc   = L["SettingsTBCPhaseDesc"],
            type   = "select",
            order  = 19.86,
            hidden = function() return not addon.isTBC end,
            values = {
                [1] = L["SettingsTBCPhase1"],
                [2] = L["SettingsTBCPhase2"],
                [3] = L["SettingsTBCPhase3"],
                [4] = L["SettingsTBCPhase4"],
            },
            -- Explicit order so the dropdown lists Phase 1 → 4 instead of
            -- AceConfig's default alphabetical-by-label sort (which would
            -- put "Phase 2 (SSC / Tempest Keep)" before "Phase 1 (...)"
            -- depending on the localised label text).
            sorting = { 1, 2, 3, 4 },
            get = function() return Ace.db.profile.tbcAnniversaryPhase or 2 end,
            set = function(_, val)
                Ace.db.profile.tbcAnniversaryPhase = val
                -- Re-render Missing Recipes if it's the active tab so the
                -- filter change takes effect immediately rather than on
                -- next refresh.
                if addon.MainWindow and addon.MainWindow.activeTab == "missing"
                   and addon.MissingRecipesTab and addon.MissingRecipesTab.RefreshList then
                    addon.MissingRecipesTab:RefreshList()
                end
            end,
        },

        -- ---- Debug ---------------------------------------------------------
        debugHeader = {
            name  = L["SettingsDevHeader"],
            type  = "header",
            order = 20,
        },

        debug = {
            name  = L["SettingsDebug"],
            desc  = L["SettingsDebugDesc"],
            type  = "toggle",
            order = 21,
            get   = function() return Ace.db.profile.debug end,
            set   = function(_, val)
                Ace.db.profile.debug = val
                addon.debug = val
            end,
        },

        -- ---- Data management -----------------------------------------------
        dataHeader = {
            name  = L["SettingsDataHeader"],
            type  = "header",
            order = 30,
        },

        syncNow = {
            name  = L["SettingsSyncNow"],
            desc  = L["SettingsSyncNowDesc"],
            type  = "execute",
            order = 31,
            func  = function() addon:ForceSync() end,
        },

        purgeGuildData = {
            name  = L["SettingsPurgeGuild"],
            desc  = L["SettingsPurgeGuildDesc"],
            type  = "execute",
            order = 32,
            confirm     = true,
            confirmText = L["SettingsPurgeGuildConfirm"],
            func  = function()
                local gdb = addon:GetGuildDb()
                if gdb then
                    gdb.recipes         = {}
                    gdb.skills          = {}
                    gdb.guildData       = {}
                    gdb.cooldowns       = {}
                    gdb.syncTimes       = {}
                    gdb.specializations = {}
                    gdb.factions        = {}
                    Ace.db.char.shoppingList   = {}
                    Ace.db.char.shoppingAlerts = {}
                    Ace.db.char.cooldownAlerts = {}
                end
                addon:Print(L["MsgGuildDataPurged"])
                -- Drop the Browser's pre-built recipe cache or the redraw below
                -- re-renders the just-purged data (the cache isn't keyed on the
                -- DB, so clearing gdb alone doesn't invalidate it). Cooldowns /
                -- Missing Recipes have no cache and reflect the empty DB directly.
                if addon.BrowserTab and addon.BrowserTab.InvalidateCache then
                    addon.BrowserTab:InvalidateCache()
                end
                addon:DebugPrint("Purge(guild): cleared gdb + invalidated browser cache; activeTab=",
                    addon.MainWindow and addon.MainWindow.activeTab or "?")
                -- QueueRefresh, NOT Refresh: this func runs inside the AceConfig
                -- execute-button handler. A synchronous Refresh() lays out the
                -- main window's AceGUI tab mid-callback, which silently fails to
                -- apply — the purged rows stay on screen until a clean redraw
                -- (e.g. a tab switch). QueueRefresh defers the redraw one tick out
                -- of this handler — exactly what it exists for.
                if addon.MainWindow then addon.MainWindow:QueueRefresh() end
            end,
        },

        purgeMyData = {
            name  = L["SettingsPurgeMine"],
            desc  = L["SettingsPurgeMineDesc"],
            type  = "execute",
            order = 33,
            confirm     = true,
            confirmText = L["SettingsPurgeMineConfirm"],
            func  = function()
                local charKey = addon:GetCharacterKey()
                local gdb     = addon:GetGuildDb()
                if gdb then
                    -- Remove charKey from all recipe crafters lists.
                    if gdb.recipes then
                        for _, profRecipes in pairs(gdb.recipes) do
                            for _, rd in pairs(profRecipes) do
                                if rd.crafters then rd.crafters[charKey] = nil end
                            end
                        end
                    end
                    if gdb.skills  then gdb.skills[charKey]          = nil end
                    gdb.guildData[charKey]       = nil
                    gdb.cooldowns[charKey]        = nil
                    gdb.syncTimes[charKey]        = nil
                    gdb.specializations[charKey]  = nil
                    gdb.factions[charKey]         = nil
                    -- Drop the leaf hashes too, or they become orphans that keep
                    -- being advertised and (for cooldowns) inflate our request
                    -- stamps so owners stay silent. See RunPendingPurge.
                    local DS = addon.Scanner and addon.Scanner.DS
                    if DS and addon.HashManager and gdb.hashes then
                        addon.HashManager:DropOrphanLeaf(DS, gdb, "cooldown:"     .. charKey)
                        addon.HashManager:DropOrphanLeaf(DS, gdb, "skills:"       .. charKey)
                        addon.HashManager:DropOrphanLeaf(DS, gdb, "professions:"  .. charKey)
                        addon.HashManager:DropOrphanLeaf(DS, gdb, "accountchars:" .. charKey)
                    elseif gdb.hashes then
                        gdb.hashes["cooldown:"     .. charKey] = nil
                        gdb.hashes["skills:"       .. charKey] = nil
                        gdb.hashes["professions:"  .. charKey] = nil
                        gdb.hashes["accountchars:" .. charKey] = nil
                    end
                end
                addon:Print(L["MsgOwnDataPurged"])
                -- See purgeGuildData: clear the Browser's recipe cache, and use
                -- QueueRefresh (not Refresh) to defer the redraw out of this
                -- button-click handler so AceGUI lays the tab out correctly.
                if addon.BrowserTab and addon.BrowserTab.InvalidateCache then
                    addon.BrowserTab:InvalidateCache()
                end
                if addon.MainWindow then addon.MainWindow:QueueRefresh() end
            end,
        },

        -- ---- Sync Log ------------------------------------------------------
        syncLogHeader = {
            name  = L["SettingsSyncLogHeader"],
            type  = "header",
            order = 40,
        },

        syncLogBtn = {
            name  = L["SettingsViewLog"],
            desc  = L["SettingsViewLogDesc"],
            type  = "execute",
            order = 41,
            func  = function() addon:OpenSyncLog() end,
        },

        clearLogBtn = {
            name  = L["SettingsClearLog"],
            type  = "execute",
            order = 42,
            confirm     = true,
            confirmText = L["SettingsClearLogConfirm"],
            func  = function()
                if addon.SyncLog then addon.SyncLog:Clear() end
            end,
        },

            },  -- general.args
        },      -- general tab

        crossguild = {
            name  = L["SettingsTabCrossGuild"],
            type  = "group",
            order = 2,
            args = {

        crossGuildDesc = {
            name     = L["SettingsCrossGuildDesc"],
            type     = "description",
            fontSize = "medium",
            order    = 44,
        },

        -- A read-only notice shown to non-officers (the input below is disabled
        -- for them). Officers don't see it (hidden).
        sisterGuildsReadOnly = {
            name     = L["SettingsSisterGuildsReadOnly"],
            type     = "description",
            order    = 44.5,
            hidden   = function() return addon:CanEditSisterGuilds() end,
        },

        sisterGuilds = {
            name      = L["SettingsSisterGuilds"],
            desc      = L["SettingsSisterGuildsDesc"],
            type      = "input",
            multiline = 5,
            width     = "full",
            order     = 45,
            -- Guild-wide list: officer/GM only may edit (it federates to every
            -- member). Members see it greyed/read-only.
            disabled  = function() return not addon:CanEditSisterGuilds() end,
            get = function() return table.concat(addon:GetSisterGuilds(), "\n") end,
            set = function(_, val)
                addon:SetSisterGuilds(val)
                if AceRegistry then AceRegistry:NotifyChange("TOGProfessionMaster") end
            end,
        },

        syncConfigBtn = {
            name  = L["SettingsCrossGuildSyncNow"],
            desc  = L["SettingsCrossGuildSyncNowDesc"],
            type  = "execute",
            order = 46,
            func  = function() addon:BroadcastSisterConfig() end,
        },

        -- ---- Diagnostics ---------------------------------------------------
        diagHeader = {
            name  = L["SettingsCrossGuildDiagHeader"],
            type  = "header",
            order = 50,
        },

        diagText = {
            name     = function() return BuildCrossGuildDiagnostics() end,
            type     = "description",
            fontSize = "medium",
            order    = 51,
        },

        diagRefresh = {
            name  = L["SettingsCrossGuildDiagRefresh"],
            desc  = L["SettingsCrossGuildDiagRefreshDesc"],
            type  = "execute",
            order = 52,
            func  = function()
                if AceRegistry then AceRegistry:NotifyChange("TOGProfessionMaster") end
            end,
        },

        -- ---- Manual pull (testing) -----------------------------------------
        pullHeader = {
            name  = L["SettingsCrossGuildPullHeader"],
            type  = "header",
            order = 60,
        },

        pullInput = {
            name  = L["SettingsCrossGuildPull"],
            desc  = L["SettingsCrossGuildPullDesc"],
            type  = "input",
            width = "full",
            order = 61,
            get   = function() return "" end,
            set   = function(_, val)
                local peer = strtrim(val or "")
                if peer ~= "" then addon:PullSisterRoster(peer) end
                if AceRegistry then AceRegistry:NotifyChange("TOGProfessionMaster") end
            end,
        },

            },  -- crossguild.args
        },      -- crossguild tab
    },
}

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

hooksecurefunc(Ace, "OnInitialize", function(_self)
    AceConfig:RegisterOptionsTable("TOGProfessionMaster", OPTIONS)
    AceDialog:AddToBlizOptions("TOGProfessionMaster", "TOG Profession Master")

    -- Persist the standalone settings window's position/size and selected tab
    -- across /reload. AceConfigDialog keeps per-app status (Status[appName] =
    -- { status = window geometry, groups = selected tab }) in a runtime-only
    -- table, so it resets on reload. Back it with a SavedVariables table —
    -- Ace.db.char.frames.settings — mirroring the main window's persistence.
    Ace.db.char.frames = Ace.db.char.frames or {}
    local frames = Ace.db.char.frames
    if type(frames.settings) ~= "table" then frames.settings = {} end
    frames.settings.status   = frames.settings.status   or {}
    frames.settings.children = frames.settings.children or {}
    frames.settings.groups   = frames.settings.groups   or {}
    AceDialog.Status = AceDialog.Status or {}
    AceDialog.Status["TOGProfessionMaster"] = frames.settings
end)

-- ---------------------------------------------------------------------------
-- Direct open (Shift+left-click on minimap, or /togpm settings)
-- ---------------------------------------------------------------------------

-- Re-run the AceGUI layout over the whole widget tree, deepest first.
--
-- Why: AceGUI's ScrollFrame decides whether to SHOW its scrollbar by comparing
-- the scroll frame's height against a content height it CACHED during layout
-- (`LayoutFinished` → `content:SetHeight(height)` → `FixScroll`), not against
-- what the widgets actually measure now. Ace3 skinners — ElvUI in the report —
-- restyle AceGUI widgets AFTER AceConfigDialog has laid the options out, which
-- changes their real heights. The cached height stays at the pre-skin value, so
-- the ScrollFrame believes everything fits: no scrollbar appears, the options
-- past the bottom edge are clipped, and the mouse wheel doesn't help either
-- (`MoveScroll` is a no-op while `scrollBarShown` is false) — the bottom of the
-- Settings window becomes unreachable. Laying out again once the frame has
-- settled re-measures the skinned widgets and lets FixScroll put the bar up.
--
-- Deepest-first so inner content heights are final before each parent measures
-- them. Harmless when nothing skinned anything: the numbers come out the same.
local function RelayoutTree(widget)
    if type(widget) ~= "table" then return end
    if type(widget.children) == "table" then
        for _, child in ipairs(widget.children) do RelayoutTree(child) end
    end
    if type(widget.DoLayout) == "function" then pcall(widget.DoLayout, widget) end
end

function addon:OpenSettings()
    local frame = AceDialog.OpenFrames and AceDialog.OpenFrames["TOGProfessionMaster"]
    if frame and frame:IsShown() then
        AceDialog:Close("TOGProfessionMaster")
    else
        AceDialog:Open("TOGProfessionMaster")
        -- Twice: next frame for skins that restyle synchronously on show, and a
        -- beat later for the ones that defer their own work to a timer.
        if C_Timer and C_Timer.After then
            for _, delay in ipairs({ 0, 0.2 }) do
                C_Timer.After(delay, function()
                    local f = AceDialog.OpenFrames and AceDialog.OpenFrames["TOGProfessionMaster"]
                    if f and f.frame and f.frame:IsShown() then RelayoutTree(f) end
                end)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Sync Log window
-- ---------------------------------------------------------------------------

local syncLogWin
local syncLogRefreshTimer
local syncLogLiveHooked
-- Pause state: when true the live view is frozen so a text selection survives
-- long enough to copy. Entries keep landing in the ring buffer (SyncLog:Record is
-- untouched); syncLogPausedCount tracks how many arrived while frozen for the
-- title note, and unpausing calls RefreshSyncLog to catch the view up.
local syncLogPaused = false
local syncLogPausedCount = 0

-- Title bar: base title, plus a "(paused — N buffered)" note while frozen.
function addon:UpdateSyncLogTitle()
    if not syncLogWin then return end
    local title = L["SyncLogTitle"]
    if syncLogPaused then
        title = title .. string.format(L["SyncLogPausedNote"], syncLogPausedCount)
    end
    syncLogWin:SetTitle(title)
end

-- Toggle the freeze. Unpausing resets the buffered counter and immediately
-- catches the view up to the current ring buffer.
function addon:SetSyncLogPaused(paused)
    syncLogPaused = paused and true or false
    if not syncLogPaused then
        syncLogPausedCount = 0
        addon:RefreshSyncLog()
    end
    if syncLogWin and syncLogWin._pauseBtn then
        syncLogWin._pauseBtn:SetText(
            syncLogPaused and L["SyncLogResume"] or L["SyncLogPause"])
    end
    addon:UpdateSyncLogTitle()
end

function addon:OpenSyncLog()
    if syncLogWin then
        syncLogWin:Show()
        addon:RefreshSyncLog()
        return
    end

    -- Persist position + size across /reload, like the main window / settings.
    Ace.db.char.frames = Ace.db.char.frames or {}
    local st = Ace.db.char.frames.syncLog or {}
    Ace.db.char.frames.syncLog = st
    if not st.width  then st.width  = 560 end
    if not st.height then st.height = 420 end

    local win = AceGUI:Create("Frame")
    win:SetTitle(L["SyncLogTitle"])
    win:SetLayout("Fill")
    win:SetStatusTable(st)                 -- AceGUI reads/writes pos+size here
    win:SetCallback("OnClose", function(w) w:Hide() end)
    syncLogWin = win

    -- Read-only, COPYABLE multiline box. Plain text (no |c colour codes) so it
    -- pastes cleanly. Created ONCE and reused — RefreshSyncLog just calls SetText,
    -- so it's never released/recreated (cheap, keeps scroll position).
    local eb = AceGUI:Create("MultiLineEditBox")
    if eb then
        eb:SetLabel(" ")   -- reserve the header-row height above the edit area
        eb:DisableButton(true)
        eb:SetFullWidth(true)
        eb:SetFullHeight(true)
        win:AddChild(eb)
        win._editbox = eb

        -- Column headers, positioned to line up with the DATA columns. A single
        -- space-padded header string can't align in WoW's proportional font — the
        -- short header words ("Time"/"Event"…) are far narrower than the digit-heavy
        -- rows, so everything downstream drifts left (what the user saw). Instead we
        -- MEASURE where each column starts — in the box's own font, on a
        -- representative "send …" row — and anchor a separate header label at that x
        -- just above the text. Left-anchored so it holds on resize. Exact for "send"
        -- rows, within a couple px for "recv". Raw-frame use is safe: this box is
        -- created once for the persistent window and never recycled.
        if eb.editBox and eb.frame then
            local fp, fsz, ff = eb.editBox:GetFont()
            local li = 0
            if eb.editBox.GetTextInsets then li = (eb.editBox:GetTextInsets()) or 0 end
            local meas = eb.frame:CreateFontString(nil, "OVERLAY")
            meas:SetFont(fp, fsz, ff); meas:Hide()
            local function wof(s) meas:SetText(s); return meas:GetStringWidth() end
            local TS = "2026-07-01 10:27:50"   -- 19-char stand-in for the timestamp
            -- Column start offsets = width of the row prefix up to each column, in
            -- the box font; must mirror RefreshSyncLog's "%s  %-7s  %9s  %-18s  %s".
            -- Peer/Detail get a +10px nudge: the measured offsets assume a tiny "0 B"
            -- size, but real sizes are wider (more digits), which pushes those two
            -- data columns right — so the headers need to shift right to match.
            local cols = {
                { "Time",   0 },
                { "Event",  wof(("%s  "):format(TS)) },
                { "Size",   wof(("%s  %-7s  "):format(TS, "send")) },
                { "Peer",   wof(("%s  %-7s  %9s  "):format(TS, "send", "0 B")) + 10 },
                { "Detail", wof(("%s  %-7s  %9s  %-18s  "):format(TS, "send", "0 B", "guild")) + 10 },
            }
            win._hdrFS = win._hdrFS or {}
            for i, c in ipairs(cols) do
                local h = win._hdrFS[i] or eb.frame:CreateFontString(nil, "OVERLAY")
                h:SetFont(fp, fsz, ff)
                h:SetText(c[1])
                h:ClearAllPoints()
                h:SetPoint("BOTTOMLEFT", eb.editBox, "TOPLEFT", li + c[2], 3)
                win._hdrFS[i] = h
            end
        end

        -- Read-only without losing copyability: select + Ctrl+C don't fire
        -- OnTextChanged(userInput); typing / paste / delete do — revert those.
        local edit = eb.editBox
        if edit then
            edit:HookScript("OnTextChanged", function(box, userInput)
                if userInput then
                    box:SetText(syncLogWin and syncLogWin._syncLogText or "")
                    box:ClearFocus()
                end
            end)
        end
    end

    -- Pause button: freezes the live view so a text selection survives long
    -- enough to copy. Entries keep accumulating in the ring buffer while paused;
    -- unpausing catches the view up (see SetSyncLogPaused). Raw button on the
    -- persistent, never-recycled window frame — same rationale as the column-
    -- header fontstrings above: AceGUI's Fill layout hosts only the editbox, and
    -- this frame is created once and never returned to the widget pool.
    if not win._pauseBtn and win.frame then
        local btn = CreateFrame("Button", nil, win.frame, "UIPanelButtonTemplate")
        btn:SetSize(72, 20)
        btn:SetText(L["SyncLogPause"])
        btn:SetScript("OnClick", function()
            addon:SetSyncLogPaused(not syncLogPaused)
        end)
        -- Sit in the reserved label-row gap at the top-right, above the text and
        -- clear of the left-aligned column headers. Bump the frame level so the
        -- click lands on the button, not the editbox behind it.
        local anchor = (win._editbox and win._editbox.frame) or win.frame
        btn:ClearAllPoints()
        btn:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -2, 4)
        btn:SetFrameLevel(win.frame:GetFrameLevel() + 10)
        win._pauseBtn = btn
    end

    -- Live refresh while open. SyncLog:Record / :Clear fire SYNC_LOG_UPDATED;
    -- debounce it (sync bursts fire many times a second) and skip when closed.
    -- Registered once for the addon's lifetime.
    if not syncLogLiveHooked then
        syncLogLiveHooked = true
        addon:RegisterCallback("SYNC_LOG_UPDATED", function()
            if not (syncLogWin and syncLogWin.frame and syncLogWin.frame:IsShown()) then return end
            if syncLogPaused then
                -- Frozen: leave the view (and the user's selection) alone. The
                -- entry is already in the ring buffer; just tally it for the note.
                syncLogPausedCount = syncLogPausedCount + 1
                addon:UpdateSyncLogTitle()
                return
            end
            if syncLogRefreshTimer then return end
            syncLogRefreshTimer = C_Timer.NewTimer(0.3, function()
                syncLogRefreshTimer = nil
                addon:RefreshSyncLog()
            end)
        end)
    end

    addon:SetSyncLogPaused(syncLogPaused)   -- sync button label + title to state
    addon:RefreshSyncLog()
end

function addon:RefreshSyncLog()
    if not (syncLogWin and syncLogWin._editbox) then return end

    local SL = addon.SyncLog
    local text
    if not SL then
        text = L["SyncLogModuleMissing"]
    else
        local entries = SL:GetEntries()   -- newest first
        if #entries == 0 then
            text = L["SyncLogNoEntries"]
        else
            local lines = {}
            for _, e in ipairs(entries) do
                -- tonumber guard: pre-enrichment persisted entries stored the itemKey
                -- string in the bytes slot, so coerce before formatting to avoid a
                -- string-vs-number error on old logs.
                local nbytes  = tonumber(e.bytes) or 0
                local sizeStr = nbytes > 0 and (nbytes .. " B") or "-"
                -- Detail prefers the explicit field; falls back to a legacy string
                -- bytes slot (old entries stored the itemKey there) so they still read.
                local detail  = e.detail or (type(e.bytes) == "string" and e.bytes) or ""
                -- Columns: time | event | SIZE | peer | detail — fixed widths so the
                -- copyable text stays aligned; size right-justified for every row.
                lines[#lines + 1] = string.format("%s  %-7s  %9s  %-18s  %s",
                    date("%Y-%m-%d %H:%M:%S", e.ts), e.event, sizeStr, e.peer, detail)
            end
            text = table.concat(lines, "\n")
        end
    end

    -- Skip the SetText when unchanged so we never disturb an active selection
    -- (e.g. the user mid-copy while a live update fires). Store the canonical
    -- text so the read-only hook reverts edits to it.
    if syncLogWin._syncLogText ~= text then
        syncLogWin._syncLogText = text
        syncLogWin._editbox:SetText(text)
    end
end
