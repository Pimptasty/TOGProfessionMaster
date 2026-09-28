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
-- release would break the widget for whoever recycles it next.
--
-- Prefer widget:SetCallback("OnEnter", fn) when the widget supports it
-- (Button, Dropdown, EditBox, etc. all do — Control_OnEnter fires the
-- registry). Use this helper only for widgets without native dispatch
-- (e.g. SimpleGroup) or for events the widget doesn't expose (OnMouseDown).
--
-- Delegates to LibAceGUIWidgets' WidgetFrameScripts (MINOR 36, TOGPM's own
-- contract afb62bf8), which restores the EXACT prior script (a constructor's
-- dispatcher, or none) on Release. Unlike the hand-rolled version it replaced,
-- it chains through the widget's OnRelease METHOD, so the widget's single
-- SetCallback("OnRelease") slot stays free for the caller.
--
-- Usage:
--   addon.AceGUIFrameScripts(widget, {
--       OnMouseDown = function(f, button) ... end,
--   })
function addon.AceGUIFrameScripts(widget, scripts)
    if not (widget and widget.frame and scripts and addon.W) then return end
    addon.W:WidgetFrameScripts(widget, scripts)
end

MainWindow.frame     = nil   -- root AceGUI Frame
MainWindow.tabs      = nil   -- AceGUI TabGroup
MainWindow.activeTab = "browser"

-- The size profile the resizable tabs (Professions, Crafting) share; the
-- locked tabs each use their own tab key. See ApplyTabSize.
local RESIZABLE_PROFILE = "browse"

-- v0.7.0: function (not table) so the L["..."] reads happen at tab-build
-- time, after ApplyLocaleOverride has had a chance to mutate the AceLocale
-- table. A file-scope table would freeze the strings at module load.
local function getTabDefs()
    local defs = {
        { value = "browser",   text = L["TabProfessions"]    },
        { value = "cooldowns", text = L["TabCooldowns"]      },
        { value = "missing",   text = L["TabMissingRecipes"] },
        { value = "guild",     text = L["TabGuild"]          },
    }
    -- The Crafting tab is omitted entirely when the user opts out of TOGPM's
    -- crafting UI (profile.hideCraftingTab). Built per-open so toggling it +
    -- /reload reflects immediately.
    if not (Ace.db and Ace.db.profile and Ace.db.profile.hideCraftingTab) then
        defs[#defs + 1] = { value = "crafting", text = L["TabCrafting"] }
    end
    defs[#defs + 1] = { value = "ahprofit", text = L["TabProfitPlanner"] }
    return defs
end

-- ---------------------------------------------------------------------------
-- Escape: popups first, then the window
-- ---------------------------------------------------------------------------
-- LibAceGUIWidgets' EscapeLayer (MINOR 36, TOGPM contract d8f15682): the first
-- Escape closes the most recently shown popup the window owns, the next one
-- closes the window. The library read the client's CloseSpecialWindows
-- (UIParentPanelManager.lua:1041): it hides EVERY shown entry of
-- UISpecialFrames in `pairs` order, so the old proxy's premise -- that the walk
-- stops at the first entry -- was wrong, and one press could close a popup and
-- the window together. The layer ends on its own when the window is released.
--
-- The popups: the Cooldowns tab's group/transmute popup and the [Bank] request
-- dialog. Each registers itself when it opens (AddEscapeChild); ArmEscape
-- re-adds whichever already exist when the layer is rebuilt.
function MainWindow:AddEscapeChild(frame)
    if not (frame and self.frame and addon.W) then return end
    addon.W:EscapeLayer(self.frame, { frame })
end

function MainWindow:ArmEscape()
    if not (self.frame and addon.W) then return end
    local children = {}
    local ct = addon.CooldownsTab
    if ct and ct._groupPopup then children[#children + 1] = ct._groupPopup end
    local bd = _G["TOGPMBankRequestDialog"]
    if bd then children[#children + 1] = bd end
    addon.W:EscapeLayer(self.frame, children)
end

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
    -- Position and size persistence through LibAceGUIWidgets' PersistWindow
    -- (MINOR 36): the saved table is ours (db.char.frames.mainWindow) and is
    -- handed to AceGUI's SetStatusTable, and the restored window is clamped
    -- onto the screen -- the fix for a title bar left above the screen after a
    -- UI-scale change (Discord, 2026-08-30), which the hand-rolled version did
    -- with SetClampedToScreen on the pooled frame and never turned back off.
    -- Per-tab sizes are profiles (ApplyTabSize): the locked tabs snap, and the
    -- two resizable tabs (Professions, Crafting) share one remembered size.
    local frames = Ace.db.char.frames
    frames.mainWindow = frames.mainWindow or { width = 720, height = 500 }
    local saved = frames.mainWindow
    -- One-time move of the size the older builds kept in browserWidth /
    -- browserHeight into the shared resizable profile.
    if saved.browserWidth or saved.browserHeight then
        saved.profiles = saved.profiles or {}
        saved.profiles[RESIZABLE_PROFILE] = saved.profiles[RESIZABLE_PROFILE] or {
            width = saved.browserWidth, height = saved.browserHeight,
        }
        saved.browserWidth, saved.browserHeight = nil, nil
    end
    if addon.W then
        addon.W:PersistWindow(f, saved, { width = 720, height = 500 })
    else
        f:SetStatusTable(saved)
    end
    -- PersistWindow clamps only when it restores a position, so a title bar
    -- dragged past the top edge mid-session would stay there. Clamp for the
    -- life of the window, and put the pooled frame's own setting back in
    -- _ReleaseFrame so the flag never reaches the next addon.
    self._priorClamp = f.frame:IsClampedToScreen()
    f.frame:SetClampedToScreen(true)

    -- Fire a cross-tab WINDOW_RESIZED callback (debounced ~150ms) on every
    -- resize so tabs that compute responsive layouts can re-render. Set
    -- through the library's WidgetFrameScripts, which puts the frame's
    -- original script back on Release; the old HookScript could not be
    -- removed, so every open stacked another copy on the pooled frame and
    -- they kept firing inside whichever addon AceGUI gave that frame to next.
    -- AceGUI's own OnSizeChanged runs first.
    local origSizeChanged = f.frame:GetScript("OnSizeChanged")
    local _resizeTimer
    addon.AceGUIFrameScripts(f, {
        OnSizeChanged = function(frame, w, h, ...)
            if origSizeChanged then origSizeChanged(frame, w, h, ...) end
            if _resizeTimer then _resizeTimer:Cancel() end
            _resizeTimer = C_Timer.NewTimer(0.15, function()
                _resizeTimer = nil
                if addon.callbacks then
                    addon.callbacks:Fire("WINDOW_RESIZED", w, h)
                end
            end)
        end,
    })

    f:SetCallback("OnClose", function(widget)
        -- Browser's last user-chosen size is already persisted by the
        -- OnSizeChanged hook above, so no special-case capture needed
        -- on close. All chrome-detach + Release routing lives in the
        -- shared _ReleaseFrame helper below so the X-button path AND
        -- the programmatic Close() path use identical cleanup.
        self:_ReleaseFrame(widget)
    end)

    -- The help "i" and settings gear sit left of AceGUI's Close button, and the
    -- status bar is shortened to clear them: LibAceGUIWidgets' DressBottomRow,
    -- built below once the help text exists, and UndressBottomRow in
    -- _ReleaseFrame (both icons hidden and the status bar re-anchored, so the
    -- pooled frame reaches the next addon clean).
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

    -- Price-source legend, keyed by ItemDB's source ids (one per provider) and
    -- coloured from addon.PriceSourceColors so the tags match every tab.
    local srcCol = addon.PriceSourceColors or {}
    local srcLbl = addon.PriceSourceLabels or {}
    local function srcTag(id, fallbackColor, fallbackLabel)
        return "|c" .. (srcCol[id] or fallbackColor) .. "[" .. (srcLbl[id] or fallbackLabel) .. "]|r "
    end
    local sourceLegend = brand .. "Price sources:|r "
        .. srcTag("scan",        addon.BrandColor or "ffFF8000", "ItemDB Scan")
        .. srcTag("auctionator", "ff6da9ff", "Auctionator")
        .. srcTag("auctioneer",  "ff8fcf7f", "Auctioneer")
        .. srcTag("tsm",         "fff0c44f", "TSM")
        .. "(set in ItemDB: " .. brand .. "/itemdb|r)"

    -- Help text: one sentence per entry, as the player reads it. Wrapping these
    -- into concatenations would hide the prose behind string plumbing, so the
    -- line-length rule is set aside for this table only.
    -- luacheck: push ignore 631
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
                brand .. "Row actions:|r Hover the recipe name for an item tooltip, shift-click to link in chat. " .. brand .. "[Bank]|r requests the scroll from the guild bank when it has one; " .. brand .. "[AH]|r (after a Scan AH) jumps to its auction listing.",
                " ",
                brand .. "Sources:|r Each row tags how the recipe is obtained: " .. brand .. "Vendor|r, " .. brand .. "Drop|r, " .. brand .. "Quest|r, " .. brand .. "Crafted|r, " .. brand .. "Container|r, " .. brand .. "Fishing|r, or " .. brand .. "Trainer|r when shown.",
            },
        },
        crafting = {
            title = "Crafting",
            lines = {
                nameColorLegend,
                " ",
                "Craft your known recipes, queue batches, and compare cost vs sale value.",
                " ",
                brand .. "Cost rows:|r Reagent and output prices carry a source badge (e.g. [SCAN], [AUC], [TSM]); a vendor-sold reagent is costed at the vendor price.",
                " ",
                sourceLegend,
            },
        },
        ahprofit = {
            title = L["TabProfitPlanner"],
            lines = {
                nameColorLegend,
                " ",
                "Profit ranking across recipes your own characters can craft.",
                " ",
                brand .. "Live AH Profit:|r Uses the best current sale price from every price source you have turned on in ItemDB (Auctionator, Auctioneer, TSM, the ItemDB scan).",
                " ",
                brand .. "Historical Profit:|r Uses only sources that keep a history (Auctionator's 14-day mean, Auctioneer's cached stat, TSM's historical figure).",
                " ",
                sourceLegend,
            },
        },
        guild = {
            title = L["GuildHelpTitle"],
            lines = {
                nameColorLegend,
                " ",
                L["GuildHelpIntro"],
                " ",
                L["GuildHelpExpand"],
                " ",
                L["GuildHelpSpecs"],
                " ",
                L["GuildHelpCoverage"],
            },
        },

    }
    -- luacheck: pop

    -- The help tooltip follows the active tab, so its title and body are
    -- functions DressBottomRow reads at hover. tipMinWidth = 280 keeps the
    -- help readable as paragraphs; the library saves GameTooltip's minimum
    -- width (both halves GetMinimumWidth returns) and puts it back on hide,
    -- which the hand-rolled version had to do itself because nothing in the
    -- client resets it (GameTooltip_OnHide, Blizzard_GameTooltip/Classic/
    -- GameTooltip.lua:413, leaves it alone). The body is one string, so the
    -- old per-line grey is carried by a colour escape around each line.
    local function helpFor()
        return TAB_HELP[MainWindow.activeTab or "browser"] or TAB_HELP.browser
    end
    local function helpTitle()
        return "|c" .. (addon.BrandColor or "ffFF8000") .. helpFor().title .. "|r"
    end
    local function helpBody()
        local out = {}
        for _, line in ipairs(helpFor().lines) do
            out[#out + 1] = (line == " ") and " " or ("|cffe6e6e6" .. line .. "|r")
        end
        return out
    end

    if addon.W then
        local icons = addon.W:DressBottomRow(f, {
            { key = "help", texture = "Interface\\Common\\help-i",
              tipTitle = helpTitle, tipBody = helpBody, tipMinWidth = 280 },
            -- The settings gear opens the options panel (same target as
            -- /togpm settings and Shift+click on the minimap button). That
            -- panel is an AceConfigDialog window. The start of
            -- AceConfigDialog:Open (Ace3 AceConfigDialog-3.0.lua:1853-1860)
            -- wraps CloseSpecialWindows rather than calling it; the rest of
            -- Open was NOT read, and the gear has not been clicked in game
            -- since the old proxy-clearing workaround (written for the
            -- Blizzard Settings panel) was removed. If the window closes on a
            -- gear click, that assumption was wrong.
            { key = "gear", texture = "Interface\\Icons\\Trade_Engineering",
              texCoord = { 0.08, 0.92, 0.08, 0.92 },
              tipTitle = "|c" .. (addon.BrandColor or "ffFF8000") .. L["TooltipSettingsTitle"] .. "|r",
              tipBody = L["TooltipSettingsDesc"],
              onClick = function() if addon.OpenSettings then addon:OpenSettings() end end },
        })
        self._helpIcon = icons and icons.help
        self._gearIcon = icons and icons.gear
    end

    -- TabGroup
    local tg = AceGUI:Create("TabGroup")
    tg:SetTabs(getTabDefs())
    tg:SetLayout("Flow")
    tg:SetFullWidth(true)
    tg:SetFullHeight(true)

    tg:SetCallback("OnGroupSelected", function(widget, _event, group)
        -- The resizable tabs' size is saved by SetWindowProfile when the
        -- profile is left (ApplyTabSize), and by _ReleaseFrame on close.
        self.activeTab = group
        -- A tab SELECTION is a user navigation (hardware event), so it's the one
        -- safe moment to let the Crafting tab auto-cast/open the selected
        -- profession. Event-driven re-draws (FireUpdate → DrawTab) bypass this
        -- callback, so they can't trigger the protected CastSpellByName. The flag
        -- is consumed in CraftingTab:Draw.
        if group == "crafting" and addon.CraftingTab then
            addon.CraftingTab._autoOpenOnUserNav = true
        end
        -- Persist main tab selection so reopening the window returns to the last
        -- used tab (per-character), via the shared addon.GUI.PersistentChoice
        -- helper. Called at runtime (not file scope) because MainWindow loads
        -- before SharedWidgets in the TOC.
        local _, setLastTab = addon.GUI.PersistentChoice("char", "lastMainTab")
        setLastTab(group)
        self:ApplyTabSize(group)
        widget:ReleaseChildren()
        self:DrawTab(group, widget)
    end)

    f:AddChild(tg)

    self.frame = f
    self.tabs  = tg

    self:ApplyScale()
    self:ApplyOpacity()
    self:ArmEscape()
    -- Apply size BEFORE selecting the tab so the first Draw sees the
    -- correct frame dimensions (some tabs read frame width during Draw).
    -- Load saved tab from db.char, falling back to "browser" if none saved
    local getLastTab = addon.GUI.PersistentChoice("char", "lastMainTab")
    local initialTab = tabKey or getLastTab() or self.activeTab or "browser"
    -- Never select a tab that isn't in the current set (e.g. a saved/forced
    -- "crafting" when the Crafting tab is hidden) — that would render hidden-tab
    -- content with no tab to leave it. Fall back to Browser.
    local valid = false
    for _, def in ipairs(getTabDefs()) do
        if def.value == initialTab then valid = true; break end
    end
    if not valid then initialTab = "browser" end
    self:ApplyTabSize(initialTab)
    tg:SelectTab(initialTab)
end

-- Whole-window UI scale (Settings → Display → "Window scale"). Scaling the root
-- frame shrinks every element proportionally — text, recipe columns, the queue
-- panel — so the window (and the Crafting tab) can take far less screen space
-- than the resize floor allows without the layout overlapping. Independent of
-- size: SetResizeBounds / the persisted width/height are in the frame's own
-- coordinate space, so a scaled window still resizes and remembers its size; the
-- on-screen footprint is size × scale. Clamped 0.5–1.5 (50%–150%) by
-- LibAceGUIWidgets' SetWindowScale (MINOR 36, TOGPM contract e5e1586a), which
-- keeps the window's top-left on the same screen point, clamps it on screen
-- and puts the pooled frame's scale back to 1 on Release -- the hand-rolled
-- SetScale left the next addon given this frame at our scale.
function MainWindow:ApplyScale()
    if not (self.frame and self.frame.frame and addon.W) then return end
    addon.W:SetWindowScale(self.frame, tonumber(Ace.db.profile.windowScale) or 1)
end

-- Background opacity (Settings → Display → "Background opacity"). Fades the
-- background fills -- the window's backdrop and every pane backdrop inside it
-- -- and nothing else: text, borders, icons and rows keep full alpha, so the
-- window stays readable over the world behind it. LibAceGUIWidgets'
-- SetWindowOpacity (MINOR 36, TOGPM contract ae090bd5) fades from the stock
-- colour each time and restores every faded frame exactly when its widget is
-- released, so nothing faded reaches another addon through the pool. It only
-- reaches panes that exist when it runs, so DrawTab calls ApplyOpacity again
-- after each tab draw. Clamped 0.2-1.0: below 20% the pane reads as bare text
-- floating on the world.
function MainWindow:GetOpacity()
    local a = tonumber(Ace.db.profile.windowOpacity) or 1
    if a < 0.2 then a = 0.2 elseif a > 1 then a = 1 end
    return a
end

function MainWindow:ApplyOpacity()
    if not (self.frame and addon.W) then return end
    addon.W:SetWindowOpacity(self.frame, self:GetOpacity())
end

-- ---------------------------------------------------------------------------
-- Per-tab window sizing
-- ---------------------------------------------------------------------------
-- Each tab declares a WINDOW_SIZE table on its module:
--   { width=W, height=H, locked=true }       — resize disabled, snap to W×H
--   { minWidth=W, minHeight=H }              — resizable, with a floor
--
-- Locked tabs (Cooldowns, Missing) use IDENTICAL dimensions so switching
-- between them produces no visible jump. Each spec becomes a LibAceGUIWidgets
-- size profile (SetWindowProfile, MINOR 36, TOGPM contract 72e8dd4b): a locked
-- tab is its own profile, and the resizable tabs (Professions, Crafting)
-- share RESIZABLE_PROFILE, whose size the library saves when it is left and
-- restores when it comes back. A locked tab's snapped size can never be
-- written into that save, which is what the old _suppressBrowserSize flag was
-- for. Every switch ends clamped to the screen.
local _TAB_SIZE_LOOKUP = {
    browser   = function() return addon.BrowserTab        and addon.BrowserTab.WINDOW_SIZE        end,
    cooldowns = function() return addon.CooldownsTab      and addon.CooldownsTab.WINDOW_SIZE      end,
    missing   = function() return addon.MissingRecipesTab and addon.MissingRecipesTab.WINDOW_SIZE end,
    guild     = function() return addon.GuildTab          and addon.GuildTab.WINDOW_SIZE          end,
    crafting  = function() return addon.CraftingTab       and addon.CraftingTab.WINDOW_SIZE       end,
    ahprofit  = function() return addon.AHProfitTab       and addon.AHProfitTab.WINDOW_SIZE       end,
}

function MainWindow:ApplyTabSize(tabKey)
    if not (self.frame and self.frame.frame) then return end
    local lookup = _TAB_SIZE_LOOKUP[tabKey]
    local spec = lookup and lookup()
    if not (spec and addon.W) then return end

    if spec.locked then
        addon.W:SetWindowProfile(self.frame, tabKey, {
            width = spec.width, height = spec.height, resizable = false,
        })
    else
        addon.W:SetWindowProfile(self.frame, RESIZABLE_PROFILE, {
            width = 720, height = 500, resizable = true,
            minWidth = spec.minWidth or 600, minHeight = spec.minHeight or 350,
        })
    end
end

--- Shared release-and-cleanup path used by BOTH OnClose (X-button) and
--- the programmatic Close()/Toggle() path. AceGUI:Release does NOT fire
--- OnClose, so any escape route that ends in Release (ESC key, /togpm
--- toggle, etc.) MUST go through here or the help "i" + gear icons stay
--- parented to f.frame and ride the recycled widget into the next
--- AceGUI:Create("Frame") caller (TOGBank, PersonalShopper, Grouper).
function MainWindow:_ReleaseFrame(widget)
    -- The help and gear icons hidden and the status bar put back. Opacity,
    -- scale, persistence, the Escape layer and the resize hook are all undone
    -- by the library on Release -- which also saves the resizable profile's
    -- size when the window closes on it (MINOR 36, the floor addon.W requires).
    if widget and addon.W then addon.W:UndressBottomRow(widget) end
    if widget and widget.frame then
        widget.frame:SetClampedToScreen(self._priorClamp and true or false)
    end
    self._priorClamp = nil
    self._helpIcon, self._gearIcon = nil, nil
    self.frame = nil
    self.tabs  = nil
    if widget then AceGUI:Release(widget) end
end

function MainWindow:Close()
    if self.frame then
        self:_ReleaseFrame(self.frame)
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

-- Set the root frame's bottom-left status-bar text. Safe no-op when the window
-- isn't open. Used for the version string (default, reset on every tab switch
-- in DrawTab) and per-tab status lines such as the Profit Planner row count.
function MainWindow:SetStatusText(text)
    if self.frame and self.frame.SetStatusText then
        self.frame:SetStatusText(text or "")
    end
end

-- The canonical left-of-status-bar string: the version, plus a redraw counter to
-- its right that only appears when debug mode is on (`/togpm debug`). `_redrawCount`
-- bumps on every full tab redraw (MainWindow:Refresh — the guild-sync churn path),
-- so with debug on you can watch the rate live and confirm the "only redraw on real
-- data change" fix keeps it low. Hidden in normal play.
function MainWindow:StatusBase()
    local base = (addon.Version or "")
    if addon.debug then
        base = base .. "    |cff888888[redraws: " .. (self._redrawCount or 0) .. "]|r"
    end
    return base
end

-- The version string is canonical and always leads the status bar. Tabs append
-- their own info (e.g. Profit Planner's row count) as a suffix after it; pass
-- nil/empty to show just the version.
function MainWindow:SetStatusSuffix(suffix)
    local base = self:StatusBase()
    if suffix and suffix ~= "" then
        self:SetStatusText(base .. "    " .. suffix)
    else
        self:SetStatusText(base)
    end
end

function MainWindow:DrawTab(group, container)
    -- Clear any container.LayoutFinished override left over from the
    -- previously-active tab. Missing and Browser install their own
    -- overrides (AnchorAll / AnchorScrollToFill) for custom anchoring,
    -- and those overrides survive tab switches because the TabGroup
    -- widget stays alive across switches — only its children get
    -- released. Without this clear, switching Missing → Cooldowns
    -- leaves Missing's AnchorAll on the container; it fires during
    -- Cooldowns' layout pass, references Missing's stale widget refs,
    -- and silently anchors a recycled-from-Missing scroll frame to
    -- hidden/wrong frames — the scroll viewport collapses and the
    -- scrollbar disappears.
    --
    -- We set this to nil (not back to the class default). TabGroup's
    -- class LayoutFinished does `self:SetHeight((height + borderoffset
    -- + 23))` whose OnHeightSet shrinks `content:SetHeight(height -
    -- borderoffset - 23)` based on the partially-laid-out height —
    -- when fired during a tab's intermediate AddChild passes (e.g.
    -- when Missing has only its toolbar attached so far), it collapses
    -- the content frame to ~0px and squashes everything anchored
    -- inside. The TabGroup is sized by its parent Frame's fill anchors
    -- anyway, so the class auto-size is redundant; nil here is correct.
    -- Missing/Browser then re-set this to their own AnchorAll/etc. as
    -- part of their Draw, which is fine — only the inter-tab leftover
    -- needs to be wiped.
    container.LayoutFinished = nil

    -- Reset the status bar to the addon version on every tab switch. Tabs that
    -- want a custom status line (Profit Planner writes its row count here) over-
    -- write it during their own Draw; this guarantees it reverts when you leave.
    -- (StatusBase = version + the TEMP redraw counter.)
    self:SetStatusText(self:StatusBase())

    -- Timed (see addon.Perf): a tab draw is the whole of what a player waits
    -- for on open or on a tab click, so every one is a mark for /togpm perf.
    local t0 = addon.Perf.now()
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
    elseif group == "guild" then
        if addon.GuildTab then
            addon.GuildTab:Draw(container)
        end
    elseif group == "crafting" then
        if addon.CraftingTab then
            addon.CraftingTab:Draw(container)
        end
    elseif group == "ahprofit" then
        if addon.AHProfitTab then
            addon.AHProfitTab:Draw(container)
        end
    end
    addon.Perf.mark("Tab draw: " .. tostring(group), addon.Perf.now() - t0)
    -- The panes this draw just built are faded to the window's opacity too;
    -- SetWindowOpacity only reaches panes that exist when it runs.
    self:ApplyOpacity()
end

-- ---------------------------------------------------------------------------
-- Refresh current tab (called after GUILD_DATA_UPDATED)
-- ---------------------------------------------------------------------------

function MainWindow:Refresh()
    if not self.frame or not self.tabs then
        addon:DebugPrint("MainWindow:Refresh ABORT — frame=",
            self.frame and "set" or "nil", "tabs=", self.tabs and "set" or "nil")
        return
    end

    -- Defer the refresh while any toolbar dropdown's pullout is open.
    -- Releasing the tab's children tears down the Dropdown widget,
    -- which closes its pullout mid-interaction — annoying when a guild
    -- sync arrives every few seconds and the user is mid-pick. Re-queue
    -- and re-test on a longer cadence; the user closing the pullout
    -- (either by picking a value or clicking elsewhere) is the natural
    -- gating event. addon.GUI.IsAnyDropdownPulloutOpen lives in
    -- GUI/SharedWidgets.lua and walks AceGUI's global pullout pool.
    -- Defer ONLY while one of OUR OWN dropdown pullouts is open (releasing the
    -- tab's children would shut it mid-pick). Two guards against the bug that
    -- froze refreshes indefinitely — purge/sync never redrawing until a manual
    -- tab switch:
    --   1. Scope to our window frame. The AceGUI30PulloutN frames are GLOBAL,
    --      shared across every AceGUI-3.0 addon, so a foreign or leaked-shown
    --      pullout used to make the old global check return true forever.
    --   2. Cap the retries, so even our own open pullout can't hang us.
    local rootFrame = self.frame and self.frame.frame
    local pulloutOpen = rootFrame and addon.GUI and addon.GUI.IsAnyDropdownPulloutOpen
                        and addon.GUI.IsAnyDropdownPulloutOpen(rootFrame)
    local typing      = addon.GUI and addon.GUI.IsAnySearchFocused
                        and addon.GUI.IsAnySearchFocused()
    if (pulloutOpen or typing) and (self._refreshDeferrals or 0) < 8 then
        self._refreshDeferrals = (self._refreshDeferrals or 0) + 1
        addon:DebugPrint("MainWindow:Refresh DEFERRED —",
            typing and "search field focused" or "our dropdown pullout open",
            "(", self._refreshDeferrals, "/8); re-try in 0.25s")
        if self._refreshTimer then self._refreshTimer:Cancel() end
        self._refreshTimer = C_Timer.NewTimer(0.25, function()
            self._refreshTimer = nil
            self:Refresh()
        end)
        return
    end
    self._refreshDeferrals = 0

    self._redrawCount = (self._redrawCount or 0) + 1   -- perf-churn counter (shown in status bar when debug is on)
    addon:DebugPrint("MainWindow:Refresh — ReleaseChildren + DrawTab(", self.activeTab, ")")
    self.tabs:ReleaseChildren()
    self:DrawTab(self.activeTab, self.tabs)
end

-- Debounced refresh — defers the redraw out of the message-handler context
-- so AceGUI layout isn't called mid-callback.  Rapid back-to-back data
-- updates (multiple guild members syncing at once) collapse into one redraw.
function MainWindow:QueueRefresh()
    addon:DebugPrint("MainWindow:QueueRefresh — scheduling Refresh in 0.05s")
    if self._refreshTimer then
        self._refreshTimer:Cancel()
    end
    self._refreshTimer = C_Timer.NewTimer(0.05, function()
        self._refreshTimer = nil
        addon:DebugPrint("MainWindow:QueueRefresh — timer fired -> Refresh()")
        self:Refresh()
    end)
end

-- ---------------------------------------------------------------------------
-- Slash command stubs (override the ones created in TOGProfessionMaster.lua)
-- ---------------------------------------------------------------------------

function addon:OpenBrowser()
    -- Generic "open the addon" entry (minimap click, bare /togpm). Pass NO tab
    -- so Open() restores the last-used tab (db.char.lastMainTab); it falls back
    -- to "browser" only when nothing is saved. Passing "browser" here would
    -- override the saved tab and always force the Professions tab.
    MainWindow:Toggle()
end

-- addon:OpenReagents() is defined in GUI/ReagentTracker.lua

-- ---------------------------------------------------------------------------
-- React to guild data updates from Scanner
-- ---------------------------------------------------------------------------

-- Which change-scopes each tab actually renders. GUILD_DATA_UPDATED carries a
-- scope set describing WHICH kind of data changed (see Scanner's fire sites); a
-- refresh whose scope is disjoint from the active tab's interests is skipped —
-- e.g. a cooldown sync must not tear down and rebuild the 19k-crafter recipe
-- Browser, which renders no cooldown data. A nil/empty scope (legacy or unknown
-- caller) always refreshes, so this can only ever REDUCE redraws, never miss one
-- a tab genuinely needs.
-- `roster` belongs to every GUILD-SCOPED tab, not just the Guild tab. All four
-- of them filter what they render through IsVisibleCrafter / IsInCurrentGuildScope,
-- so a change in roster truth — most importantly the roster becoming ready after
-- login, which is when the "hide nothing yet" cold-start guard lifts — changes
-- what each of them should display. Leaving it only on `guild` is why a departed
-- member kept showing on the Professions and Cooldowns tabs after a reload.
-- crafting / ahprofit are excluded on purpose: they render YOUR OWN craftables
-- and aren't roster-filtered.
local TAB_SCOPES = {
    browser   = { recipes = true, altgroups = true, roster = true },
    cooldowns = { cooldowns = true, roster = true },
    missing   = { recipes = true, altgroups = true, roster = true },
    guild     = { skills = true, recipes = true, altgroups = true, roster = true },
    crafting  = { recipes = true },
    ahprofit  = { recipes = true },
}

local function activeTabCaresAbout(activeTab, scopes)
    if type(scopes) ~= "table" then return true end   -- unknown → refresh
    if not next(scopes) then return true end          -- empty → refresh
    local interests = TAB_SCOPES[activeTab]
    if not interests then return true end             -- unknown tab → refresh
    for scope in pairs(scopes) do
        if interests[scope] then return true end
    end
    return false
end

hooksecurefunc(Ace, "OnEnable", function(_self)
    addon:RegisterCallback("GUILD_DATA_UPDATED", function(_event, _charKey, scopes)
        if not activeTabCaresAbout(MainWindow.activeTab, scopes) then
            addon:DebugPrint("MainWindow: GUILD_DATA_UPDATED skipped — tab",
                MainWindow.activeTab, "renders none of the changed scope")
            return
        end
        MainWindow:QueueRefresh()
    end)
end)
