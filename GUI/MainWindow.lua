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

-- ---------------------------------------------------------------------------
-- AceGUI shared utility — leak-safe raw frame scripts on AceGUI widgets.
-- ---------------------------------------------------------------------------
-- AceGUI clears widget.events (the SetCallback registry) on Release but
-- does NOT reset raw scripts set via `widget.frame:SetScript(...)`. Since
-- AceGUI pools widgets account-wide and recycles them across every addon
-- that uses AceGUI, leftover scripts keep firing in the new owner's UI —
-- e.g. our cooldown tooltip showing up when the user hovers a Dropdown
-- in a different addon.
--
-- Critical: many AceGUI widget Constructors install internal dispatch
-- scripts on widget.frame themselves (Button's `frame:SetScript("OnEnter",
-- Control_OnEnter)` is the canonical example — that's what fires the
-- widget:SetCallback("OnEnter", ...) handlers). Naively nilling those on
-- release would break the widget for whoever recycles it next. So this
-- helper SAVES the prior script and RESTORES it on release rather than
-- nilling.
--
-- Prefer widget:SetCallback("OnEnter", fn) when the widget supports it
-- (Button, Dropdown, EditBox, etc. all do — Control_OnEnter fires the
-- registry). Use this helper only for widgets without native dispatch
-- (e.g. SimpleGroup) or for events the widget doesn't expose (OnMouseDown).
--
-- Usage:
--   addon.AceGUIFrameScripts(widget, {
--       OnMouseDown = function(f, button) ... end,
--   })
function addon.AceGUIFrameScripts(widget, scripts)
    if not (widget and widget.frame and scripts) then return end
    local saved = {}
    for evt, fn in pairs(scripts) do
        saved[evt] = widget.frame:GetScript(evt)
        widget.frame:SetScript(evt, fn)
    end
    widget:SetCallback("OnRelease", function(self)
        if not self.frame then return end
        for evt, prior in pairs(saved) do
            self.frame:SetScript(evt, prior)
        end
    end)
end

MainWindow.frame     = nil   -- root AceGUI Frame
MainWindow.tabs      = nil   -- AceGUI TabGroup
MainWindow.activeTab = "browser"

local TAB_DEFS = {
    { value = "browser",   text = L["TabProfessions"]    },
    { value = "cooldowns", text = L["TabCooldowns"]      },
    { value = "missing",   text = L["TabMissingRecipes"] },
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
    -- Resize is enabled/disabled per-tab in ApplyTabSize below. Start
    -- enabled (matches AceGUI default; ApplyTabSize will tighten it
    -- after the initial tab is selected).
    f:EnableResize(true)

    -- AceGUI position/size persistence. It writes top/left/width/height
    -- into this sub-table on every move/resize. The per-tab size policy
    -- below means width/height get overwritten whenever the user is on
    -- a locked tab, so we keep the user's last Browser size separately
    -- in browserWidth/browserHeight — restored when switching back to
    -- Browser. Position (top/left) is shared across all tabs.
    --
    -- Declared BEFORE the OnSizeChanged hook below because that hook
    -- captures `frames` as an upvalue (used to persist Browser's resized
    -- dimensions); the hook's closure is created at registration time
    -- and the upvalue must already exist by then.
    local frames = Ace.db.char.frames
    frames.mainWindow = frames.mainWindow or { width = 720, height = 500 }
    frames.mainWindow.browserWidth  = frames.mainWindow.browserWidth  or 720
    frames.mainWindow.browserHeight = frames.mainWindow.browserHeight or 500
    -- SetStatusTable triggers SetSize internally → fires our OnSizeChanged
    -- hook with whatever size was last persisted (which might be a locked
    -- tab's size if the user last left on Cooldowns/Missing). Suppress
    -- the browserWidth/Height save during this call so the saved Browser
    -- size isn't overwritten with a locked tab's dimensions.
    self._suppressBrowserSize = true
    f:SetStatusTable(frames.mainWindow)
    self._suppressBrowserSize = false

    -- Fire a cross-tab WINDOW_RESIZED callback (debounced ~150ms) on every
    -- user-driven resize so tabs that compute responsive layouts can re-
    -- render. HookScript chains rather than overriding, so AceGUI's own
    -- size handling continues to run. Also persist Browser's resized
    -- dimensions here — only when Browser is the active tab AND the
    -- resize wasn't programmatic (ApplyTabSize sets _suppressBrowserSize
    -- so the locked-tab SetSize / initial-Open SetStatusTable size
    -- doesn't overwrite Browser's user-chosen size).
    local _resizeTimer
    f.frame:HookScript("OnSizeChanged", function(_self, w, h)
        if self.activeTab == "browser" and w and h
           and not self._suppressBrowserSize then
            frames.mainWindow.browserWidth  = math.floor(w + 0.5)
            frames.mainWindow.browserHeight = math.floor(h + 0.5)
        end
        if _resizeTimer then _resizeTimer:Cancel() end
        _resizeTimer = C_Timer.NewTimer(0.15, function()
            _resizeTimer = nil
            if addon.callbacks then
                addon.callbacks:Fire("WINDOW_RESIZED", w, h)
            end
        end)
    end)

    f:SetCallback("OnClose", function(_widget)
        -- Browser's last user-chosen size is already persisted by the
        -- OnSizeChanged hook above, so no special-case capture needed
        -- on close.
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

    local brand   = "|c" .. (addon.BrandColor  or "ffFF8000")
    local cYou    = "|c" .. (addon.ColorYou    or addon.BrandColor or "ffFF8000")
    local cOnline = "|c" .. (addon.ColorOnline  or "ffffffff")
    local cOffline= "|c" .. (addon.ColorOffline or "ff888888")
    -- Shared legend (first line of every tab's help) — explains the name
    -- color coding used across the addon. Built from the addon-wide color
    -- constants so a palette change in TOGProfessionMaster.lua propagates
    -- everywhere automatically. \194\183 = middle dot "\u{00B7}".
    local nameColorLegend = brand .. "Name colors:|r " ..
        cYou     .. "You|r (your characters) \194\183 " ..
        cOnline  .. "Online|r \194\183 " ..
        cOffline .. "Offline|r"

    local TAB_HELP = {
        browser = {
            title = "Profession Browser",
            lines = {
                nameColorLegend,
                " ",
                "Recipes known by guild members. Click any recipe to open its details on the right.",
                " ",
                brand .. "Filters:|r Profession dropdown, name search, and " .. brand .. "Guild|r vs " .. brand .. "Mine|r view toggle.",
                " ",
                brand .. "Shopping list (top):|r Click a row to expand its reagents. " .. brand .. "−|r / qty / " .. brand .. "+|r adjust, " .. brand .. "×|r removes, " .. brand .. "!|r (gold = armed) pings you when a crafter for that recipe logs in. Reagent rows show the scaled count with [Bank] when TOGBankClassic has stock.",
                " ",
                brand .. "Recipe area:|r Recipes column shows icon + name. Crafters column is a truncated list (" .. brand .. "You|r first). [Bank] appears when the crafted item itself is in TOGBankClassic stock.",
                " ",
                brand .. "Detail area (right):|r Name hover = item tooltip, shift-click = link in chat. Shopping-list controls mirror the top. Reagents support the same hover/shift-click + per-reagent [Bank]. Full crafters list at the bottom — right-click a name to whisper.",
                " ",
                brand .. "Everywhere else:|r A [TOGPM] line is appended to every item tooltip in the game (bags, AH, chat links, comparison tooltips) listing guild crafters.",
            },
        },
        cooldowns = {
            title = "Cooldowns Tracker",
            lines = {
                nameColorLegend,
                " ",
                "Profession cooldowns for every guild member running the addon.",
                " ",
                brand .. "Columns:|r " .. brand .. "Character|r (right-click to whisper), " .. brand .. "Cooldown|r (hover for spell tooltip, click group rows like transmutes to expand), " .. brand .. "Reagent|r (hover for item tooltip), " .. brand .. "Time Left|r (|cff00ff00green|r = ready, |cffffff00yellow|r = <2h, |cffaaaaaagrey|r = on cooldown).",
                " ",
                brand .. "Row actions:|r [Bank] requests the reagent from TOGBankClassic. Mail icon (visible when a mailbox is open) attaches the reagents and pre-fills the recipient.",
                " ",
                brand .. "Controls:|r Click any column header to sort (click again to reverse). " .. brand .. "Ready Only|r toggle hides cooldowns that aren't ready yet.",
            },
        },
        missing = {
            title = "Missing Recipes",
            lines = {
                "Recipes the selected character has not yet learned for a profession \226\128\148 useful for AH hunting.",
                " ",
                brand .. "Filters:|r " .. brand .. "Character|r (your current toon and any tracked alts), " .. brand .. "Profession|r (only professions that character has learned), name search.",
                " ",
                brand .. "Trainer toggle:|r By default trainer-only recipes are hidden (can't be bought). Tick " .. brand .. "Include trainer-only|r to also see those.",
                " ",
                brand .. "Row actions:|r Hover the recipe name for an item tooltip, shift-click to link in chat. Click " .. brand .. "+|r to add the scroll to your Reagent Watch \226\128\148 you'll be alerted the moment it lands in your bags.",
                " ",
                brand .. "Sources:|r Each row tags how the recipe is obtained: " .. brand .. "Vendor|r, " .. brand .. "Drop|r, " .. brand .. "Quest|r, " .. brand .. "Crafted|r, " .. brand .. "Container|r, " .. brand .. "Fishing|r, or " .. brand .. "Trainer|r when shown.",
            },
        },

    }

    helpIcon:SetScript("OnEnter", function(self)
        local tab  = MainWindow.activeTab or "browser"
        local help = TAB_HELP[tab] or TAB_HELP.browser
        -- ANCHOR_TOP (centered above) is intentional here; the helper's
        -- TOPLEFT/BOTTOMLEFT picks look worse for this fixed-position icon.
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetMinimumWidth(480)
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
        -- Browser's last size is kept current by the OnSizeChanged hook
        -- above (it persists w/h whenever activeTab == "browser"), so by
        -- the time we leave Browser the saved value is already correct.
        self.activeTab = group
        self:ApplyTabSize(group)
        _widget:ReleaseChildren()
        self:DrawTab(group, _widget)
    end)

    f:AddChild(tg)

    self.frame = f
    self.tabs  = tg

    _escProxy:Show()
    -- Apply size BEFORE selecting the tab so the first Draw sees the
    -- correct frame dimensions (some tabs read frame width during Draw).
    local initialTab = tabKey or self.activeTab or "browser"
    self:ApplyTabSize(initialTab)
    tg:SelectTab(initialTab)
end

-- ---------------------------------------------------------------------------
-- Per-tab window sizing
-- ---------------------------------------------------------------------------
-- Each tab declares a WINDOW_SIZE table on its module:
--   { width=W, height=H, locked=true }       — resize disabled, snap to W×H
--   { minWidth=W, minHeight=H }              — resizable, with a floor
--
-- Locked tabs (Cooldowns, Missing) use IDENTICAL dimensions so switching
-- between them produces no visible jump. Only switching to/from Browser
-- (the resizable tab) changes the window size, and Browser's last size
-- is restored from frames.mainWindow.browserWidth/browserHeight.
local _TAB_SIZE_LOOKUP = {
    browser   = function() return addon.BrowserTab        and addon.BrowserTab.WINDOW_SIZE        end,
    cooldowns = function() return addon.CooldownsTab      and addon.CooldownsTab.WINDOW_SIZE      end,
    missing   = function() return addon.MissingRecipesTab and addon.MissingRecipesTab.WINDOW_SIZE end,
}

function MainWindow:ApplyTabSize(tabKey)
    if not (self.frame and self.frame.frame) then return end
    local lookup = _TAB_SIZE_LOOKUP[tabKey]
    local spec = lookup and lookup()
    if not spec then return end
    local f = self.frame
    local frames = Ace.db.char.frames

    -- Suppress the OnSizeChanged hook's browserWidth/Height save during
    -- programmatic SetWidth/SetHeight below — when switching to a locked
    -- tab the snap to spec.width/height fires OnSizeChanged with the
    -- LOCKED size, which would otherwise overwrite Browser's saved size.
    -- For the resizable branch we restore the saved size explicitly so
    -- there's nothing useful for the hook to capture either; suppression
    -- avoids a redundant save-of-the-same-value.
    self._suppressBrowserSize = true

    if spec.locked then
        -- SetResizeBounds with min == max collapses the resize handle
        -- range to zero — the user can still drag the corner but the
        -- frame won't actually change size. Combined with EnableResize
        -- (false) the grip itself is also hidden. Modern API takes
        -- (minW, minH, maxW, maxH); legacy SetMinResize/SetMaxResize
        -- needs both halves separately.
        f:EnableResize(false)
        if f.frame.SetResizeBounds then
            f.frame:SetResizeBounds(spec.width, spec.height, spec.width, spec.height)
        else
            if f.frame.SetMinResize then f.frame:SetMinResize(spec.width, spec.height) end
            if f.frame.SetMaxResize then f.frame:SetMaxResize(spec.width, spec.height) end
        end
        f.frame:SetWidth(spec.width)
        f.frame:SetHeight(spec.height)
    else
        -- Resizable. Restore Browser's last size (saved separately from
        -- AceGUI's status table — see Open() for why) and clamp the
        -- minimum via SetResizeBounds. No max bound.
        f:EnableResize(true)
        local minW = spec.minWidth  or 600
        local minH = spec.minHeight or 350
        if f.frame.SetResizeBounds then
            f.frame:SetResizeBounds(minW, minH)
        elseif f.frame.SetMinResize then
            f.frame:SetMinResize(minW, minH)
        end
        local w = math.max(minW, frames.mainWindow.browserWidth  or minW)
        local h = math.max(minH, frames.mainWindow.browserHeight or minH)
        f.frame:SetWidth(w)
        f.frame:SetHeight(h)
    end

    self._suppressBrowserSize = false
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
    elseif group == "missing" then
        if addon.MissingRecipesTab then
            addon.MissingRecipesTab:Draw(container)
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

-- addon:OpenReagents() is defined in GUI/ReagentTracker.lua

-- ---------------------------------------------------------------------------
-- React to guild data updates from Scanner
-- ---------------------------------------------------------------------------

hooksecurefunc(Ace, "OnEnable", function(_self)
    addon:RegisterCallback("GUILD_DATA_UPDATED", function(_event, _charKey)
        MainWindow:QueueRefresh()
    end)
end)
