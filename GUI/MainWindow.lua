-- TOG Profession Master — Main Window
-- Root AceGUI frame with a TabGroup containing two tabs:
--   1. Profession browser (includes shopping list at top)
--   2. Cooldown tracker
--
-- Tab content is delegated to BrowserTab.lua and CooldownsTab.lua.
-- This file owns only the frame lifecycle, tab routing, and window
-- position persistence.

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
}

-- ---------------------------------------------------------------------------
-- ESC proxy
-- ---------------------------------------------------------------------------
-- An invisible frame registered in UISpecialFrames at load time intercepts
-- every ESC press while the main window is open.  UIParent_HandleEscape
-- iterates UISpecialFrames FORWARD and stops after hiding the first visible
-- entry — so this proxy (registered before the later-created AceGUI frame)
-- always fires first, giving us full control over close priority.
--
--   First ESC  → close ALL open popups simultaneously, then re-arm
--   Second ESC → close the main window

local _escProxy = CreateFrame("Frame", "TOGPMEscProxy", UIParent)
_escProxy:SetSize(1, 1)
_escProxy:SetAlpha(0)
_escProxy:SetPoint("CENTER")
_escProxy:Hide()
tinsert(UISpecialFrames, "TOGPMEscProxy")

_escProxy:SetScript("OnHide", function()
    if not MainWindow.frame then return end

    local closedAny = false

    -- Group / transmute popup (CooldownsTab) — raw frame, not in UISpecialFrames
    local ct = addon.CooldownsTab
    if ct and ct._groupPopup and ct._groupPopup:IsShown() then
        ct._groupPopup:Hide()
        ct._groupPopup = nil
        closedAny = true
    end

    -- Bank request dialog (Compat.lua)
    local bd = _G["TOGPMBankRequestDialog"]
    if bd and bd:IsShown() then
        bd:Hide()
        closedAny = true
    end

    if closedAny then
        -- Re-arm after one frame so the next ESC closes the main window.
        C_Timer.After(0, function()
            if MainWindow.frame then _escProxy:Show() end
        end)
    else
        MainWindow:Close()
    end
end)

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
        self.frame = nil
        self.tabs  = nil
        _escProxy:Hide()
        AceGUI:Release(_widget)
    end)

    -- Shrink the default status bar right edge to create room for the help icon.
    -- Default AceGUI statusbg goes to BOTTOMRIGHT -132; we push it to -163 so a
    -- 24px icon fits in the gap (matching the TOGBankClassic pattern).
    local statusbg = f.statustext:GetParent()
    statusbg:ClearAllPoints()
    statusbg:SetPoint("BOTTOMLEFT",  f.frame, "BOTTOMLEFT",   15, 15)
    statusbg:SetPoint("BOTTOMRIGHT", f.frame, "BOTTOMRIGHT", -163, 15)

    -- Help "i" icon
    local helpIcon = CreateFrame("Frame", nil, f.frame)
    helpIcon:SetSize(24, 24)
    helpIcon:SetPoint("BOTTOMRIGHT", f.frame, "BOTTOMRIGHT", -133, 15)
    helpIcon:EnableMouse(true)
    local helpTex = helpIcon:CreateTexture(nil, "OVERLAY")
    helpTex:SetAllPoints(helpIcon)
    helpTex:SetTexture("Interface\\Common\\help-i")

    local brand = "|c" .. (addon.BrandColor or "ffFF8000")
    local TAB_HELP = {
        browser = {
            title = "Profession Browser",
            lines = {
                "Shows all recipes known by guild members.",
                " ",
                brand .. "Recipes:|r The craftable recipe or spell name.",
                brand .. "Crafters:|r Guild members who know it. " .. brand .. "You|r is listed first.",
                " ",
                brand .. "Profession dropdown:|r Filter to a single profession.",
                brand .. "Search box:|r Filter recipes by name.",
                brand .. "View toggle:|r Guild (all members) vs Mine (your characters).",
                " ",
                brand .. "[Bank] button:|r Appears when TOGBankClassic has the reagent in stock. Click to request it.",
            },
        },
        cooldowns = {
            title = "Cooldowns Tracker",
            lines = {
                "Tracks profession cooldowns for all guild members who have the addon.",
                " ",
                brand .. "Character:|r Guild member. Right-click any row to whisper them.",
                brand .. "Cooldown:|r Profession spell name and icon.",
                brand .. "Reagent:|r Primary reagent required.",
                brand .. "Time Left:|r |cff00ff00Green|r = ready. |cffffff00Yellow|r = <2h. |cffaaaaaaGrey|r = on cooldown.",
                " ",
                brand .. "[Bank]:|r Request the reagent from TOGBankClassic.",
                brand .. "Mail icon:|r Open a mailbox first, then click to attach reagents and pre-fill the mail.",
                " ",
                brand .. "Column headers:|r Click to sort. Click again to reverse.",
                brand .. "Ready Only toggle:|r Hide cooldowns that are not yet ready.",
            },
        },

    }

    helpIcon:SetScript("OnEnter", function(self)
        local tab  = MainWindow.activeTab or "browser"
        local help = TAB_HELP[tab] or TAB_HELP.browser
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(help.title, 1, 0.82, 0, true)
        for _, line in ipairs(help.lines) do
            GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    helpIcon:SetScript("OnLeave", function()
        GameTooltip:Hide()
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

    _escProxy:Show()
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

-- Debounced refresh — defers the redraw out of the message-handler context
-- so AceGUI layout isn't called mid-callback.  Rapid back-to-back data
-- updates (multiple guild members syncing at once) collapse into one redraw.
function MainWindow:QueueRefresh()
    if self._refreshTimer then
        self._refreshTimer:Cancel()
    end
    self._refreshTimer = C_Timer.NewTimer(0.05, function()
        self._refreshTimer = nil
        self:Refresh()
    end)
end

-- ---------------------------------------------------------------------------
-- Slash command stubs (override the ones created in TOGProfessionMaster.lua)
-- ---------------------------------------------------------------------------

function addon:OpenBrowser()
    MainWindow:Toggle("browser")
end

function addon:OpenReagents()
    MainWindow:Toggle("browser")
end

-- ---------------------------------------------------------------------------
-- React to guild data updates from Scanner
-- ---------------------------------------------------------------------------

hooksecurefunc(Ace, "OnEnable", function(_self)
    addon:RegisterCallback("GUILD_DATA_UPDATED", function(_event, _charKey)
        MainWindow:QueueRefresh()
    end)
end)
