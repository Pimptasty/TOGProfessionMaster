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
-- Option table
-- ---------------------------------------------------------------------------

local OPTIONS = {
    name    = "TOG Profession Master",
    handler = addon,
    type    = "group",
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

        -- Off by default: opening a profession opens Blizzard's own crafting
        -- window (with the TOGPM button on it to switch). Tick to open straight
        -- into the TOGPM Crafting tab instead.
        craftingTakeover = {
            name  = L["SettingsCraftingTakeover"],
            desc  = L["SettingsCraftingTakeoverDesc"],
            type  = "toggle",
            width = "full",
            order = 12.04,
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
    },
}

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------

hooksecurefunc(Ace, "OnInitialize", function(_self)
    AceConfig:RegisterOptionsTable("TOGProfessionMaster", OPTIONS)
    AceDialog:AddToBlizOptions("TOGProfessionMaster", "TOG Profession Master")
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
