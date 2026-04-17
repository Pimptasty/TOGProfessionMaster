-- TOG Profession Master — Main Window
-- Root AceGUI frame with a TabGroup containing three tabs:
--   1. Professions browser
--   2. Cooldowns tracker
--   3. Shopping list / reagents
--
-- Tab content is delegated to BrowserTab.lua, CooldownsTab.lua,
-- and ShoppingListTab.lua respectively.  This file owns only the frame
-- lifecycle, tab routing, and window position persistence.

local _, addon = ...
local Ace    = addon.lib
local AceGUI = LibStub("AceGUI-3.0")
local L      = LibStub("AceLocale-3.0"):GetLocale("TOGProfessionMaster")

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------

local MainWindow = {}
addon.MainWindow = MainWindow

MainWindow.frame     = nil   -- root AceGUI Frame
MainWindow.tabs      = nil   -- AceGUI TabGroup
MainWindow.activeTab = "browser"

local TAB_DEFS = {
    { value = "browser",   text = L["TabProfessions"] },
    { value = "cooldowns", text = L["TabCooldowns"]   },
    { value = "bucket",   text = L["TabReagents"]    },
}

-- ---------------------------------------------------------------------------
-- Open / Close
-- ---------------------------------------------------------------------------

function MainWindow:Open(tabKey)
    if self.frame then
        -- Already open — just switch tab if requested.
        if tabKey then self:SelectTab(tabKey) end
        self.frame.frame:Raise()
        return
    end

    local f = AceGUI:Create("Frame")
    f:SetTitle(L["WindowTitle"])
    f:SetStatusText(addon.Version)
    f:SetLayout("Fill")
    f:EnableResize(true)

    -- Let AceGUI own position/size persistence.  It writes top/left/width/height
    -- directly into this sub-table on every move/resize — no manual save needed.
    local frames = Ace.db.char.frames
    frames.mainWindow = frames.mainWindow or { width = 720, height = 500 }
    f:SetStatusTable(frames.mainWindow)

    f:SetCallback("OnClose", function(_widget)
        AceGUI:Release(_widget)
        self.frame = nil
        self.tabs  = nil
    end)

    -- TabGroup
    local tg = AceGUI:Create("TabGroup")
    tg:SetTabs(TAB_DEFS)
    tg:SetLayout("Flow")
    tg:SetFullWidth(true)
    tg:SetFullHeight(true)

    tg:SetCallback("OnGroupSelected", function(_widget, _event, group)
        self.activeTab = group
        _widget:ReleaseChildren()
        self:DrawTab(group, _widget)
    end)

    f:AddChild(tg)

    self.frame = f
    self.tabs  = tg

    tg:SelectTab(tabKey or self.activeTab or "browser")
end

function MainWindow:Close()
    if self.frame then
        AceGUI:Release(self.frame)
        self.frame = nil
        self.tabs  = nil
    end
end

function MainWindow:Toggle(tabKey)
    if self.frame then
        self:Close()
    else
        self:Open(tabKey)
    end
end

function MainWindow:SelectTab(key)
    if self.tabs then
        self.tabs:SelectTab(key)
    end
end

-- ---------------------------------------------------------------------------
-- Tab routing
-- ---------------------------------------------------------------------------

function MainWindow:DrawTab(group, container)
    if group == "browser" then
        if addon.BrowserTab then
            addon.BrowserTab:Draw(container)
        end
    elseif group == "cooldowns" then
        if addon.CooldownsTab then
            addon.CooldownsTab:Draw(container)
        end
    elseif group == "bucket" then
        if addon.ShoppingListTab then
            addon.ShoppingListTab:Draw(container)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Refresh current tab (called after GUILD_DATA_UPDATED)
-- ---------------------------------------------------------------------------

function MainWindow:Refresh()
    if not self.frame or not self.tabs then return end
    self.tabs:ReleaseChildren()
    self:DrawTab(self.activeTab, self.tabs)
end

-- ---------------------------------------------------------------------------
-- Slash command stubs (override the ones created in TOGProfessionMaster.lua)
-- ---------------------------------------------------------------------------

function addon:OpenBrowser()
    MainWindow:Toggle("browser")
end

function addon:OpenReagents()
    MainWindow:Toggle("bucket")
end

-- ---------------------------------------------------------------------------
-- React to guild data updates from Scanner
-- ---------------------------------------------------------------------------

hooksecurefunc(Ace, "OnEnable", function(_self)
    addon:RegisterCallback("GUILD_DATA_UPDATED", function(_event, _charKey)
        MainWindow:Refresh()
    end)
end)
