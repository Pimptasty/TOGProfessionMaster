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
                end
                addon:Print("All guild data purged.")
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
                addon:Print("Your character data purged.")
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
        local ts   = date("%H:%M:%S", e.ts)
        local line = string.format("%s  %s%-8s|r  %s  %d B",
            ts, col, e.event, e.peer, e.bytes)
        local lbl = AceGUI:Create("Label")
        lbl:SetText(line)
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    end
end
