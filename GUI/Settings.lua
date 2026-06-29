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
                    Ace.db.profile.savedProfFilter = 0
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

        crafterAlertSuppressAV = {
            name  = L["SettingsCrafterAlertSuppressAV"],
            desc  = L["SettingsCrafterAlertSuppressAVDesc"],
            type  = "toggle",
            order = 17,
            get   = function() return Ace.db.profile.crafterAlertSuppressAV end,
            set   = function(_, val) Ace.db.profile.crafterAlertSuppressAV = val end,
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
            name  = "Use TradeSkillMaster pricing",
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
                if addon.MainWindow then addon.MainWindow:Refresh() end
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
                end
                addon:Print(L["MsgOwnDataPurged"])
                if addon.MainWindow then addon.MainWindow:Refresh() end
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

function addon:OpenSettings()
    local frame = AceDialog.OpenFrames and AceDialog.OpenFrames["TOGProfessionMaster"]
    if frame and frame:IsShown() then
        AceDialog:Close("TOGProfessionMaster")
    else
        AceDialog:Open("TOGProfessionMaster")
    end
end

-- ---------------------------------------------------------------------------
-- Sync Log window
-- ---------------------------------------------------------------------------

local syncLogWin

function addon:OpenSyncLog()
    if syncLogWin then
        syncLogWin:Show()
        addon:RefreshSyncLog()
        return
    end

    local win = AceGUI:Create("Frame")
    win:SetTitle(L["SyncLogTitle"])
    win:SetWidth(520)
    win:SetHeight(380)
    win:SetLayout("Fill")
    win:SetCallback("OnClose", function(w) w:Hide() end)
    syncLogWin = win

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    win:AddChild(scroll)
    win._scroll = scroll

    addon:RefreshSyncLog()
end

function addon:RefreshSyncLog()
    if not syncLogWin or not syncLogWin._scroll then return end
    local scroll = syncLogWin._scroll
    scroll:ReleaseChildren()

    local SL = addon.SyncLog
    if not SL then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["SyncLogModuleMissing"])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
        return
    end

    local entries = SL:GetEntries()
    if #entries == 0 then
        local lbl = AceGUI:Create("Label")
        lbl:SetText(L["SyncLogNoEntries"])
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
        return
    end

    local EVENT_COLOUR = {
        send    = "|cff00ccff",
        recv    = "|cff00ff00",
        request = "|cffffff00",
        version = "|cffaaaaaa",
    }

    for _, e in ipairs(entries) do
        local col  = EVENT_COLOUR[e.event] or "|cffffffff"
        local ts   = date("%Y-%m-%d %H:%M:%S", e.ts)
        local line = string.format("%s  %s%-8s|r  %s  %d B",
            ts, col, e.event, e.peer, e.bytes)
        local lbl = AceGUI:Create("Label")
        lbl:SetText(line)
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    end
end
